import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:pdfx/pdfx.dart';

class DocPreview extends StatefulWidget {
  final Uint8List? docBytes;
  final String? docName;
  final String? docUrl;

  const DocPreview({super.key, this.docBytes, this.docName, this.docUrl});

  @override
  State<DocPreview> createState() => _DocPreviewState();
}

class _DocPreviewState extends State<DocPreview> {
  String _content = '';
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _extractContent();
  }

  @override
  void didUpdateWidget(covariant DocPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.docBytes != oldWidget.docBytes ||
        widget.docUrl != oldWidget.docUrl) {
      _extractContent();
    }
  }

  Future<void> _extractContent() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _content = '';
    });

    final isDocx = (widget.docName ?? '').toLowerCase().endsWith('.docx');
    var bytes = widget.docBytes;

    if (bytes == null && widget.docUrl != null && widget.docUrl!.isNotEmpty) {
      try {
        final url = widget.docUrl!;
        if (url.startsWith('data:')) {
          if (url.contains(',')) {
            bytes = base64Decode(url.split(',').last);
          }
        } else if (isHttpUrl(url)) {
          final client = io.HttpClient()
            ..connectionTimeout = const Duration(seconds: 15);
          try {
            final request = await client
                .getUrl(Uri.parse(url))
                .timeout(const Duration(seconds: 15));
            final response = await request.close().timeout(
              const Duration(seconds: 20),
            );
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw io.HttpException(
                'HTTP ${response.statusCode}',
                uri: Uri.parse(url),
              );
            }
            const maxPreviewBytes = 20 * 1024 * 1024;
            if (response.contentLength > maxPreviewBytes) {
              throw const FormatException('DOC preview file is too large.');
            }
            final bytesBuilder = BytesBuilder();
            var receivedBytes = 0;
            await for (final chunk in response) {
              receivedBytes += chunk.length;
              if (receivedBytes > maxPreviewBytes) {
                throw const FormatException('DOC preview file is too large.');
              }
              bytesBuilder.add(chunk);
            }
            bytes = bytesBuilder.takeBytes();
          } finally {
            client.close();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = e.toString();
          });
        }
        return;
      }
    }

    if (bytes == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'documentation'.tr();
        });
      }
      return;
    }

    try {
      String text = '';
      if (isDocx) {
        try {
          final archive = ZipDecoder().decodeBytes(bytes);
          final docFile = archive.files.firstWhere(
            (file) => file.name == 'word/document.xml',
            orElse: () => throw StateError('no_document_xml'.tr()),
          );
          final xmlString = utf8.decode(docFile.content as List<int>);

          final textRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
          final paragraphs = xmlString.split('</w:p>');
          final lines = <String>[];
          for (final paragraph in paragraphs) {
            final matches = textRegex
                .allMatches(paragraph)
                .map((m) => m.group(1) ?? '')
                .join();
            if (matches.trim().isNotEmpty) lines.add(matches);
          }
          text = lines.join('\n');
        } catch (e) {
          rethrow;
        }
      }

      if (text.trim().isEmpty) {
        setState(() {
          _isLoading = false;
          _content = '';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _content = text;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
            const SizedBox(height: 8),
            Text(
              'documentation'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null || _content.trim().isEmpty) {
      final isDocx = (widget.docName ?? '').toLowerCase().endsWith('.docx');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDocx ? Icons.article_outlined : Icons.description_outlined,
              size: 64,
              color: const Color(0xFF0B50C3),
            ),
            const SizedBox(height: 8),
            Text(
              widget.docName ?? 'documentation'.tr(),
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Text(
          _content,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}

class PdfPagePreview extends StatefulWidget {
  final Uint8List? cvBytes;
  final String? existingCvUrl;
  final BoxFit fit;

  const PdfPagePreview({
    super.key,
    this.cvBytes,
    this.existingCvUrl,
    this.fit = BoxFit.contain,
  });

  @override
  State<PdfPagePreview> createState() => _PdfPagePreviewState();
}

class _PdfPagePreviewState extends State<PdfPagePreview> {
  final ScrollController _scrollController = ScrollController();
  List<Uint8List> _pageImages = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renderPdfPages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cvBytes != oldWidget.cvBytes ||
        widget.existingCvUrl != oldWidget.existingCvUrl) {
      _renderPdfPages();
    }
  }

  Future<void> _renderPdfPages() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _pageImages = [];
    });

    PdfDocument? document;
    io.HttpClient? client;

    try {
      if (widget.cvBytes != null) {
        document = await PdfDocument.openData(widget.cvBytes!);
      } else if (widget.existingCvUrl != null &&
          widget.existingCvUrl!.isNotEmpty) {
        if (widget.existingCvUrl!.startsWith('http')) {
          client = io.HttpClient()
            ..connectionTimeout = const Duration(seconds: 15);
          final request = await client
              .getUrl(Uri.parse(widget.existingCvUrl!))
              .timeout(const Duration(seconds: 15));
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );

          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw io.HttpException(
              'HTTP ${response.statusCode}',
              uri: Uri.parse(widget.existingCvUrl!),
            );
          }

          const maxPreviewBytes = 20 * 1024 * 1024;
          if (response.contentLength > maxPreviewBytes) {
            throw const FormatException('PDF preview file is too large.');
          }

          final bytesBuilder = BytesBuilder();
          var receivedBytes = 0;
          await for (final chunk in response) {
            receivedBytes += chunk.length;
            if (receivedBytes > maxPreviewBytes) {
              throw const FormatException('PDF preview file is too large.');
            }
            bytesBuilder.add(chunk);
          }

          document = await PdfDocument.openData(bytesBuilder.takeBytes());
        } else if (widget.existingCvUrl!.startsWith('data:application/pdf')) {
          final base64Content = widget.existingCvUrl!.split(',').last;
          document = await PdfDocument.openData(base64Decode(base64Content));
        }
      }

      if (document == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final pages = <Uint8List>[];
      for (int pageNum = 1; pageNum <= document.pagesCount; pageNum++) {
        final page = await document.getPage(pageNum);
        try {
          final pageImage = await page.render(
            width: (page.width * 2.0).toDouble(),
            height: (page.height * 2.0).toDouble(),
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
          if (pageImage != null) {
            pages.add(pageImage.bytes);
          }
        } finally {
          await page.close();
        }
      }

      if (mounted) {
        setState(() {
          _pageImages = pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      if (document != null) {
        try {
          await document.close();
        } catch (_) {}
      }
      client?.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
            const SizedBox(height: 8),
            Text(
              'documentation'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return const SizedBox.shrink();
    }
    if (_pageImages.isNotEmpty) {
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            ui.PointerDeviceKind.touch,
            ui.PointerDeviceKind.mouse,
            ui.PointerDeviceKind.trackpad,
            ui.PointerDeviceKind.stylus,
          },
        ),
        child: Scrollbar(
          controller: _scrollController,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(4),
            itemCount: _pageImages.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Image.memory(
                  _pageImages[index],
                  fit: widget.fit,
                  filterQuality: FilterQuality.high,
                  width: double.infinity,
                ),
              );
            },
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
