import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../services/upload_service.dart';

String mediaFieldName(String field) {
  return switch (field) {
    'profileImage' => 'media_field_profile_image'.tr(),
    'frontId' => 'media_field_front_id'.tr(),
    'backId' => 'media_field_back_id'.tr(),
    'cv' => 'media_field_cv'.tr(),
    _ => field,
  };
}

bool isSupportedMediaType(String field, String mimeType) {
  final raw = mimeType.toLowerCase().split(';').first.trim();
  final normalized = switch (raw) {
    'image/jpg' => 'image/jpeg',
    'application/doc' => 'application/msword',
    'application/docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => raw,
  };

  const supportedImages = {'image/jpeg', 'image/png'};

  if (field != 'cv') return supportedImages.contains(normalized);

  return supportedImages.contains(normalized) ||
      normalized == 'application/pdf' ||
      normalized == 'application/msword' ||
      normalized == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
}

String supportedMediaMessage(String field, [String? received]) {
  if (field == 'cv') return 'bulk_media_cv_format_error'.tr();
  return 'bulk_media_image_format_error'.tr(namedArgs: {'received': received ?? ''});
}

String readableSaveError(Object error) {
  if (error is TimeoutException) return error.message ?? 'bulk_media_download_timeout'.tr();
  if (error is io.HttpException) return error.message;
  if (error is io.SocketException) return error.message;
  if (error is io.FileSystemException) return error.message;
  if (error is FormatException) return error.message;

  var message = error.toString().trim();
  for (final prefix in ['Bad state: ', 'Exception: ', 'FirebaseException: ']) {
    if (message.startsWith(prefix)) message = message.substring(prefix.length).trim();
  }

  if (message.isEmpty) return 'bulk_media_unknown_error'.tr();
  return message;
}

Future<String?> validateRemoteWorkerMediaLink({
  required String field,
  required String url,
}) async {
  final value = url.trim();

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return 'bulk_media_invalid_url'.tr();
  }

  final folder = field == 'profileImage'
      ? 'profile_images'
      : field == 'cv'
      ? 'worker_cvs'
      : 'identity_documents';
  final fallbackName = field == 'cv' ? 'document.pdf' : '$field.jpg';
  final fallbackMime = field == 'cv' ? 'application/pdf' : 'image/jpeg';

  try {
    final file = await UploadService.downloadRemoteFile(
      url: value,
      folder: folder,
      fallbackFileName: fallbackName,
      fallbackMimeType: fallbackMime,
    );

    if (!isSupportedMediaType(field, file.mimeType)) {
      return supportedMediaMessage(field, file.mimeType);
    }
    return null;
  } catch (error) {
    return 'bulk_media_broken_link_error'.tr(namedArgs: {'error': readableSaveError(error)});
  }
}

Future<List<Map<String, dynamic>>> uploadEmbeddedWorkerMedia(
  List<Map<String, dynamic>> workers, {
  required List<String> uploadedMediaUrls,
  required Map<String, List<String>> uploadedMediaByRowId,
  void Function(int completed, int total, String currentFile)? onProgress,
}) async {
  final prepared = workers.map((worker) => Map<String, dynamic>.from(worker)).toList();

  const mediaFields = <({String key, String field})>[
    (key: 'profileImage', field: 'profileImage'),
    (key: 'frontId', field: 'idFront'),
    (key: 'idFront', field: 'idFront'),
    (key: 'backId', field: 'idBack'),
    (key: 'idBack', field: 'idBack'),
    (key: 'cv', field: 'cv'),
  ];
  const uploadBatchSize = 20;

  final embeddedSources = <({
    int workerIndex,
    String key,
    String field,
    String mimeType,
    Uint8List bytes,
    String folder,
    String fileName,
  })>[];

  for (var workerIndex = 0; workerIndex < prepared.length; workerIndex++) {
    final worker = prepared[workerIndex];

    for (final m in mediaFields) {
      final field = m.field;
      final key = m.key;
      final value = (worker[key] ?? worker[field] ?? '').toString().trim();
      final storedName = (worker['${key}_name'] ?? worker['${field}_name'] ?? '').toString().trim();

      final folder = field == 'profileImage'
          ? 'profile_images'
          : field == 'cv'
          ? 'worker_cvs'
          : 'identity_documents';

      final isEmbeddedFile = value.startsWith('data:') && value.contains(';base64,');

      if (isEmbeddedFile) {
        final separator = value.indexOf(';base64,');
        final mimeType = value.substring(5, separator);
        final bytes = base64Decode(value.substring(separator + 8));

        if (!isSupportedMediaType(field, mimeType)) {
          final workerName = (worker['name'] ?? 'Worker').toString();
          throw StateError('$workerName — ${mediaFieldName(field)}: ${supportedMediaMessage(field, mimeType)}');
        }

        final fallbackExtension = switch (mimeType) {
          'application/pdf' => 'pdf',
          'application/msword' || 'application/doc' => 'doc',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || 'application/docx' => 'docx',
          'image/png' => 'png',
          _ => 'jpg',
        };

        embeddedSources.add((
          workerIndex: workerIndex,
          key: key,
          field: field,
          mimeType: mimeType,
          bytes: bytes,
          folder: folder,
          fileName: storedName.isNotEmpty
              ? storedName
              : '${field}_$workerIndex.$fallbackExtension',
        ));
      } else {
        prepared[workerIndex][key] = value;
      }
    }
  }

  var completedCount = 0;
  final totalMedia = embeddedSources.length;

  Future<List<UploadResult>> uploadBatch(List<UploadFile> batchFiles) async {
    if (batchFiles.isEmpty) return [];

    final batchResults = await UploadService.uploadFiles(
      files: batchFiles,
      maxConcurrent: uploadBatchSize,
      onProgress: (completed, total) {
        final idx = completed - 1;
        final name = idx >= 0 && idx < batchFiles.length ? batchFiles[idx].fileName : '';
        onProgress?.call(completedCount + completed, totalMedia, name);
      },
    );

    final failed = batchResults.indexWhere((r) => !r.isSuccess || r.url == null);
    if (failed != -1) {
      throw StateError('${batchFiles[failed].fileName} upload: ${readableSaveError(batchResults[failed].error ?? 'bulk_media_upload_failed'.tr())}');
    }

    for (final result in batchResults) {
      if (result.isSuccess && result.url != null) uploadedMediaUrls.add(result.url!);
    }

    completedCount += batchFiles.length;
    return batchResults;
  }

  if (embeddedSources.isNotEmpty) {
    onProgress?.call(0, totalMedia, 'uploading_embedded');

    final embeddedFiles = await _prepareUploadFiles(embeddedSources);

    final embedResults = await uploadBatch(embeddedFiles);

    for (var i = 0; i < embedResults.length; i++) {
      final t = embeddedSources[i];
      prepared[t.workerIndex][t.key] = embedResults[i].url;
      prepared[t.workerIndex][t.field] = embedResults[i].url;
    }
  }

  uploadedMediaByRowId.clear();
  for (final worker in prepared) {
    final clientRowId = (worker['clientRowId'] ?? worker['client_row_id'] ?? '').toString().trim();
    if (clientRowId.isEmpty) continue;
    final rowUrls = <String>[];
    for (final m in mediaFields) {
      final val = (worker[m.key] ?? worker[m.field] ?? '').toString().trim();
      if (val.isNotEmpty && (val.startsWith('http://') || val.startsWith('https://'))) {
        rowUrls.add(val);
      }
    }
    if (rowUrls.isNotEmpty) {
      uploadedMediaByRowId[clientRowId] = rowUrls;
    }
  }

  return prepared;
}

Future<List<UploadFile>> _prepareUploadFiles(
  List<({
    int workerIndex,
    String key,
    String field,
    String mimeType,
    Uint8List bytes,
    String folder,
    String fileName,
  })> sources,
) async {
  const maxConcurrent = 4;
  final results = List<UploadFile?>.filled(sources.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final idx = nextIndex++;
      if (idx >= sources.length) return;
      final s = sources[idx];
      final compressed = await _compressForUpload(s.bytes, s.mimeType, s.field);
      results[idx] = UploadFile(
        folder: s.folder,
        fileName: s.fileName,
        bytes: compressed ?? s.bytes,
        mimeType: s.mimeType,
      );
    }
  }

  await Future.wait(List.generate(maxConcurrent, (_) => worker()));
  return results.cast<UploadFile>();
}

Future<Uint8List?> _compressForUpload(
  Uint8List bytes,
  String mimeType,
  String field,
) async {
  final normalizedMime = mimeType.toLowerCase().split(';').first.trim();
  if (normalizedMime != 'image/jpeg' &&
      normalizedMime != 'image/jpg' &&
      normalizedMime != 'image/png') {
    return null;
  }
      if (bytes.length > 8 * 1024 * 1024) return null;

  try {
    return await compute(
      _compressWorkerImageInIsolate,
      (bytes, normalizedMime, _maxDimensionFor(field), _qualityFor(field)),
    );
  } catch (_) {
    return null;
  }
}

Uint8List? _compressWorkerImageInIsolate(
  (Uint8List, String, int, int) args,
) {
  return _compressWorkerImage(args.$1, args.$2, args.$3, args.$4);
}

Uint8List? _compressWorkerImage(
  Uint8List bytes,
  String mimeType,
  int maxDimension,
  int quality,
) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final longestSide =
        decoded.width > decoded.height ? decoded.width : decoded.height;

        if (longestSide <= maxDimension && bytes.length <= 350 * 1024) return null;

    final scale = longestSide > maxDimension
        ? maxDimension / longestSide
        : 1.0;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.average,
    );

    if (mimeType == 'image/png') {
      return Uint8List.fromList(img.encodePng(resized));
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return null;
  }
}

int _maxDimensionFor(String field) =>
    field == 'profileImage' ? 1024 : 1400;

int _qualityFor(String field) => field == 'profileImage' ? 80 : 85;