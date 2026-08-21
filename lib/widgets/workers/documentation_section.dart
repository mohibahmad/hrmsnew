import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hrms/widgets/common/clickable_gesture_detector.dart';
import 'package:hrms/widgets/workers/document_preview.dart';
import 'package:shimmer/shimmer.dart';

class DocumentationSection extends StatelessWidget {
  final Uint8List? frontIdBytes;
  final String? frontIdName;
  final String? existingFrontIdUrl;
  final VoidCallback? onUploadFrontTap;

  final Uint8List? backIdBytes;
  final String? backIdName;
  final String? existingBackIdUrl;
  final VoidCallback? onUploadBackTap;

  final Uint8List? cvBytes;
  final String? cvName;
  final String? existingCvUrl;
  final bool isCvUploaded;
  final VoidCallback? onUploadCvTap;
  final VoidCallback? onDeleteCvTap;
  final VoidCallback? onPrevStep;

  const DocumentationSection({
    super.key,
    this.frontIdBytes,
    this.frontIdName,
    this.existingFrontIdUrl,
    this.onUploadFrontTap,
    this.backIdBytes,
    this.backIdName,
    this.existingBackIdUrl,
    this.onUploadBackTap,
    this.cvBytes,
    this.cvName,
    this.existingCvUrl,
    this.isCvUploaded = false,
    this.onUploadCvTap,
    this.onDeleteCvTap,
    this.onPrevStep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'personal_documentation'.tr(),
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onPrevStep != null)
              GestureDetector(
                onTap: onPrevStep,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9FD),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: Color(0xFF000000),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'previous_step'.tr(),
                        style: const TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'id_card_label'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final h = (constraints.maxWidth * 1.8).clamp(
                        360.0,
                        700.0,
                      );
                      return Container(
                        height: h,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F3F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap:
                                      (frontIdBytes != null ||
                                          (existingFrontIdUrl != null &&
                                              existingFrontIdUrl!.isNotEmpty))
                                      ? null
                                      : onUploadFrontTap,
                                  child: Text(
                                    'upload_front_side'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Color(0xFF000000),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (frontIdBytes != null ||
                                    (existingFrontIdUrl != null &&
                                        existingFrontIdUrl!.isNotEmpty))
                                  GestureDetector(
                                    onTap: onUploadFrontTap,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF000000),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'edit'.tr(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SvgPicture.asset(
                                            'assets/edit_icon.svg',
                                            height: 14,
                                            width: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildIdUploadBox(
                              label: 'upload_front_id_hint'.tr(),
                              bytes: frontIdBytes,
                              fileName: frontIdName,
                              existingUrl: existingFrontIdUrl,
                              onTap: onUploadFrontTap,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: onUploadBackTap,
                                  child: Text(
                                    'upload_back_side'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (backIdBytes != null ||
                                    (existingBackIdUrl != null &&
                                        existingBackIdUrl!.isNotEmpty))
                                  GestureDetector(
                                    onTap: onUploadBackTap,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF000000),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'edit'.tr(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SvgPicture.asset(
                                            'assets/edit_icon.svg',
                                            height: 14,
                                            width: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildIdUploadBox(
                              label: 'upload_back_id_hint'.tr(),
                              bytes: backIdBytes,
                              fileName: backIdName,
                              existingUrl: existingBackIdUrl,
                              onTap: onUploadBackTap,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'upload_cv_label'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (isCvUploaded) ...[
                          GestureDetector(
                            onTap: onUploadCvTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'edit'.tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SvgPicture.asset(
                                    'assets/edit_icon.svg',
                                    height: 14,
                                    width: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  isCvUploaded ? _buildCvPreview(context) : _buildCvUpload(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final bool hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);
    var sourceName = fileName?.trim() ?? '';
    if (sourceName.isEmpty && existingUrl != null && existingUrl.isNotEmpty) {
      try {
        final decodedPath = Uri.decodeComponent(Uri.parse(existingUrl).path);
        sourceName = decodedPath.split('/').last;
      } catch (_) {
        sourceName = existingUrl.split('?').first.split('/').last;
      }

      sourceName = sourceName.replaceFirst(RegExp(r'^\d+_\d+_'), '');
    }
    final lowerSourceName = sourceName.toLowerCase();
    final cleanUrl = (existingUrl ?? '').split('?').first.toLowerCase();
    final bool isPdf =
        lowerSourceName.endsWith('.pdf') ||
        cleanUrl.endsWith('.pdf') ||
        (existingUrl?.startsWith('data:application/pdf') ?? false);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasFile ? null : onTap,
      child: Container(
        height: 280,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF0B50C3).withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: hasFile
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (isPdf)
                    PdfPagePreview(cvBytes: bytes, existingCvUrl: existingUrl)
                  else if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(
                          color: Colors.grey.shade300,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('data:'))
                    Image.memory(
                      base64Decode(existingUrl.split(',').last),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else
                    _buildIdPlaceholder(label, hasFile),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black.withValues(alpha: 0.54),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              fileName ?? 'file_uploaded'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildIdPlaceholder(label, false),
      ),
    );
  }

  Widget _buildIdPlaceholder(String label, bool hasFile) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/Id card.png',
          width: 50,
          height: 50,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tap_to_select_file'.tr(),
          style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    return _buildCvContainer(
      overlay: GestureDetector(
        onTap: onUploadCvTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'upload'.tr(),
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/Upload_profile.svg',
                height: 18,
                width: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCvPreview(BuildContext buildContext) {
    final lowerName = (cvName ?? '').toLowerCase();
    final isImage =
        cvName != null &&
        (lowerName.endsWith('.png') ||
            lowerName.endsWith('.jpg') ||
            lowerName.endsWith('.jpeg') ||
            lowerName.endsWith('.gif') ||
            lowerName.endsWith('.bmp') ||
            lowerName.endsWith('.webp'));
    final isPdf = cvName != null && lowerName.endsWith('.pdf');
    final isDoc =
        cvName != null &&
        (lowerName.endsWith('.doc') || lowerName.endsWith('.docx'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final containerHeight = (availableWidth * 1.8).clamp(360.0, 700.0);
        return Container(
          height: containerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: isImage
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 1 / 1.414,
                        child: Container(
                          color: Colors.white,
                          child: cvBytes != null
                              ? Image.memory(
                                  cvBytes!,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                )
                              : (existingCvUrl != null &&
                                        existingCvUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: existingCvUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Shimmer.fromColors(
                                              baseColor: Colors.grey.shade300,
                                              highlightColor:
                                                  Colors.grey.shade100,
                                              child: Container(
                                                color: Colors.grey.shade300,
                                                width: double.infinity,
                                                height: double.infinity,
                                              ),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            const Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                size: 48,
                                              ),
                                            ),
                                      )
                                    : const SizedBox.shrink()),
                        ),
                      ),
                    )
                  : (isPdf || isDoc)
                  ? Stack(
                      children: [
                        if (cvBytes == null &&
                            (existingCvUrl == null || existingCvUrl!.isEmpty))
                          Container(
                            height: double.infinity,
                            width: double.infinity,
                            color: Colors.grey.shade200,
                          ),
                        if (isPdf &&
                            (cvBytes != null ||
                                (existingCvUrl != null &&
                                    existingCvUrl!.isNotEmpty)))
                          Positioned.fill(
                            child: IgnorePointer(
                              child: PdfPagePreview(
                                cvBytes: cvBytes,
                                existingCvUrl: existingCvUrl,
                              ),
                            ),
                          ),
                        if (isDoc &&
                            (cvBytes != null ||
                                (existingCvUrl != null &&
                                    existingCvUrl!.isNotEmpty)))
                          Center(
                            child: AspectRatio(
                              aspectRatio: 1 / 1.414,
                              child: IgnorePointer(
                                child: DocPreview(
                                  docBytes: cvBytes,
                                  docName: cvName,
                                  docUrl: existingCvUrl,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            cvName ?? 'upload_cv_label'.tr(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCvContainer({required Widget overlay}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final containerHeight = (availableWidth * 1.8).clamp(360.0, 700.0);
        return Container(
          height: containerHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Center(child: overlay),
        );
      },
    );
  }
}
