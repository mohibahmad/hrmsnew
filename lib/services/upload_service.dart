import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class UploadFile {
  final String folder;
  final String fileName;
  final Uint8List bytes;
  final String mimeType;

  UploadFile({
    required this.folder,
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });
}

class UploadResult {
  final UploadFile file;
  final String? url;
  final String? error;
  final bool isSuccess;
  final bool isCancelled;

  UploadResult._({
    required this.file,
    this.url,
    this.error,
    required this.isSuccess,
    this.isCancelled = false,
  });

  factory UploadResult.success({
    required UploadFile file,
    required String url,
  }) {
    return UploadResult._(file: file, url: url, isSuccess: true);
  }

  factory UploadResult.failure({
    required UploadFile file,
    required String error,
  }) {
    return UploadResult._(file: file, error: error, isSuccess: false);
  }

  factory UploadResult.cancelled({required UploadFile file}) {
    return UploadResult._(file: file, isSuccess: false, isCancelled: true);
  }
}

class UploadService {
  static const int _maxRetries = 3;
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const Duration _downloadTimeout = Duration(seconds: 30);

  static Future<UploadFile> downloadRemoteFile({
    required String url,
    required String folder,
    required String fallbackFileName,
    required String fallbackMimeType,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'A valid HTTP or HTTPS file URL is required.',
      );
    }

    final client = HttpClient()..connectionTimeout = _downloadTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_downloadTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'HRMS/1.0');
      final response = await request.close().timeout(_downloadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'File download failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      if (response.contentLength > maxFileBytes) {
        throw const FileSystemException(
          'Remote file is larger than the 10 MB limit.',
        );
      }

      final bytesBuilder = BytesBuilder(copy: false);
      var downloadedBytes = 0;
      await for (final chunk in response.timeout(_downloadTimeout)) {
        downloadedBytes += chunk.length;
        if (downloadedBytes > maxFileBytes) {
          throw const FileSystemException(
            'Remote file is larger than the 10 MB limit.',
          );
        }
        bytesBuilder.add(chunk);
      }
      if (downloadedBytes == 0) {
        throw const FileSystemException('Remote file is empty.');
      }
      final downloadedData = bytesBuilder.takeBytes();

      final remoteName = uri.pathSegments.isEmpty
          ? ''
          : Uri.decodeComponent(uri.pathSegments.last);
      final requestedName = remoteName.trim().isNotEmpty
          ? remoteName.trim()
          : fallbackFileName;
      final safeName = _safeFileName(requestedName, fallbackFileName);
      final responseMimeType = response.headers.contentType?.mimeType;
      final detectedMimeType = _mimeTypeFromBytes(downloadedData);
      final mimeType =
          detectedMimeType ??
          (responseMimeType == null ||
                  responseMimeType.isEmpty ||
                  responseMimeType == 'application/octet-stream'
              ? _mimeTypeFromFileName(safeName, fallbackMimeType)
              : responseMimeType);

      return UploadFile(
        folder: folder,
        fileName: safeName,
        bytes: downloadedData,
        mimeType: mimeType,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _safeFileName(String value, String fallback) {
    final sanitized = value.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_').trim();
    return sanitized.isEmpty ? fallback : sanitized;
  }

  static String _mimeTypeFromFileName(String fileName, String fallback) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => fallback,
    };
  }

  static String? _mimeTypeFromBytes(Uint8List bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (startsWith(const [0x25, 0x50, 0x44, 0x46])) {
      return 'application/pdf';
    }
    if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0])) {
      return 'application/msword';
    }
    if (startsWith(const [0x50, 0x4B, 0x03, 0x04])) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return null;
  }

  static Future<List<UploadResult>> uploadFiles({
    required List<UploadFile> files,
    void Function(int completed, int total)? onProgress,
    CancellationToken? cancelToken,
  }) async {
    final total = files.length;
    if (total == 0) return [];

    final futures = files.map((file) async {
      if (cancelToken?.isCancelled == true) {
        return UploadResult.cancelled(file: file);
      }
      try {
        final url = await _uploadToStorage(file);
        return UploadResult.success(file: file, url: url);
      } catch (e) {
        return UploadResult.failure(file: file, error: e.toString());
      }
    }).toList();

    final results = await Future.wait(futures);
    onProgress?.call(total, total);
    return results;
  }

  static Future<String> _uploadToStorage(UploadFile file) async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ref = FirebaseStorage.instance.ref().child(
          'hrms_documents/${file.folder}/${timestamp}_${file.fileName}',
        );
        final uploadTask = ref.putData(
          file.bytes,
          SettableMetadata(contentType: file.mimeType),
        );
        final snapshot = await uploadTask;
        return await snapshot.ref.getDownloadURL();
      } catch (e) {
        if (i == _maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw Exception('Upload failed after $_maxRetries retries');
  }

  static String base64EncodeFallback(Uint8List bytes, String mime) {
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
