import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:easy_localization/easy_localization.dart';
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
    'application/docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => raw,
  };
  const supportedImages = {'image/jpeg', 'image/png'};
  if (field != 'cv') return supportedImages.contains(normalized);
  return supportedImages.contains(normalized) ||
      normalized == 'application/pdf' ||
      normalized == 'application/msword' ||
      normalized ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
}

String supportedMediaMessage(String field, [String? received]) {
  if (field == 'cv') {
    return 'bulk_media_cv_format_error'.tr();
  }
  return 'bulk_media_image_format_error'.tr(
    namedArgs: {'received': received ?? ''},
  );
}

String readableSaveError(Object error) {
  if (error is TimeoutException) {
    return error.message ?? 'bulk_media_download_timeout'.tr();
  }
  if (error is io.HttpException) return error.message;
  if (error is io.SocketException) return error.message;
  if (error is io.FileSystemException) return error.message;
  if (error is FormatException) return error.message;

  var message = error.toString().trim();
  for (final prefix in [
    'Bad state: ',
    'Exception: ',
    'FirebaseException: ',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
    }
  }
  if (message.isEmpty) return 'bulk_media_unknown_error'.tr();
  return message.length > 220 ? '${message.substring(0, 220)}…' : message;
}

Future<List<Map<String, dynamic>>> uploadEmbeddedWorkerMedia(
  List<Map<String, dynamic>> workers, {
  required List<String> uploadedMediaUrls,
  required Map<String, List<String>> uploadedMediaByRowId,
  void Function(int completed, int total, String currentFile)? onProgress,
}) async {
  final prepared = workers
      .map((worker) => Map<String, dynamic>.from(worker))
      .toList();
  const mediaFields = ['profileImage', 'frontId', 'backId', 'cv'];
  const uploadBatchSize = 8;

  var totalMedia = 0;
  for (final worker in workers) {
    for (final field in mediaFields) {
      final value = (worker[field] ?? '').toString().trim();
      if (value.isNotEmpty) totalMedia++;
    }
  }

  final embeddedFiles = <UploadFile>[];
  final embeddedTargets = <({int workerIndex, String field})>[];
  final remoteItems =
      <
        int,
        ({
          int workerIndex,
          String field,
          String url,
          String folder,
          String fallbackName,
          String fallbackMime,
        })
      >{};

  for (var workerIndex = 0; workerIndex < prepared.length; workerIndex++) {
    final worker = prepared[workerIndex];
    for (final field in mediaFields) {
      final value = (worker[field] ?? '').toString().trim();
      final isEmbeddedFile =
          value.startsWith('data:') && value.contains(';base64,');
      final uri = Uri.tryParse(value);
      final isRemoteFile =
          uri != null &&
          uri.hasAuthority &&
          (uri.scheme == 'http' || uri.scheme == 'https');
      if (!isEmbeddedFile && !isRemoteFile) {
        if (value.isNotEmpty) {
          final workerName = (worker['name'] ?? 'Worker').toString();
          throw StateError(
            '$workerName — ${mediaFieldName(field)}: '
            '${'bulk_media_invalid_url'.tr()}',
          );
        }
        continue;
      }

      final storedName = (worker['${field}_name'] ?? '').toString().trim();
      final folder = field == 'profileImage'
          ? 'profile_images'
          : field == 'cv'
          ? 'worker_cvs'
          : 'identity_documents';

      if (isEmbeddedFile) {
        final separator = value.indexOf(';base64,');
        final mimeType = value.substring(5, separator);
        final bytes = base64Decode(value.substring(separator + 8));
        if (!isSupportedMediaType(field, mimeType)) {
          final workerName = (worker['name'] ?? 'Worker').toString();
          throw StateError(
            '$workerName — ${mediaFieldName(field)}: '
            '${supportedMediaMessage(field, mimeType)}',
          );
        }
        final fallbackExtension = switch (mimeType) {
          'application/pdf' => 'pdf',
          'application/msword' || 'application/doc' => 'doc',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
          'application/docx' => 'docx',
          'image/png' => 'png',
          'image/webp' => 'webp',
          _ => 'jpg',
        };
        embeddedFiles.add(
          UploadFile(
            folder: folder,
            fileName: storedName.isNotEmpty
                ? storedName
                : '${field}_$workerIndex.$fallbackExtension',
            bytes: bytes,
            mimeType: mimeType,
          ),
        );
        embeddedTargets.add((workerIndex: workerIndex, field: field));
      } else {
        final key =
            workerIndex * mediaFields.length + mediaFields.indexOf(field);
        remoteItems[key] = (
          workerIndex: workerIndex,
          field: field,
          url: value,
          folder: folder,
          fallbackName: storedName.isNotEmpty
              ? storedName
              : '${field}_$workerIndex.${field == 'cv' ? 'pdf' : 'jpg'}',
          fallbackMime: field == 'cv' ? 'application/pdf' : 'image/jpeg',
        );
      }
    }
  }

  var completedCount = 0;

  Future<List<UploadResult>> uploadBatch(List<UploadFile> batchFiles) async {
    if (batchFiles.isEmpty) return [];
    final batchResults = await UploadService.uploadFiles(
      files: batchFiles,
      maxConcurrent: uploadBatchSize,
      onProgress: (completed, total) {
        final idx = completed - 1;
        final name = idx >= 0 && idx < batchFiles.length
            ? batchFiles[idx].fileName
            : '';
        onProgress?.call(completedCount + completed, totalMedia, name);
      },
    );
    final failed = batchResults.indexWhere(
      (r) => !r.isSuccess || r.url == null,
    );
    if (failed != -1) {
      throw StateError(
        '${batchFiles[failed].fileName} upload: '
        '${readableSaveError(batchResults[failed].error ?? 'bulk_media_upload_failed'.tr())}',
      );
    }
    for (final result in batchResults) {
      if (result.isSuccess && result.url != null) {
        uploadedMediaUrls.add(result.url!);
      }
    }
    completedCount += batchFiles.length;
    return batchResults;
  }

  if (embeddedFiles.isNotEmpty) {
    onProgress?.call(0, totalMedia, 'uploading_embedded');
    final embedResults = await uploadBatch(embeddedFiles);
    for (var i = 0; i < embedResults.length; i++) {
      final t = embeddedTargets[i];
      prepared[t.workerIndex][t.field] = embedResults[i].url;
    }
  }

  final remoteKeys = remoteItems.keys.toList();

  if (remoteKeys.isNotEmpty) {
    const maxConcurrent = 4;
    var nextIndex = 0;
    Object? firstError;

    Future<void> processItem(int key) async {
      final item = remoteItems[key]!;
      UploadFile? downloaded;
      try {
        downloaded = await UploadService.downloadRemoteFile(
          url: item.url,
          folder: item.folder,
          fallbackFileName: item.fallbackName,
          fallbackMimeType: item.fallbackMime,
        );
      } catch (e) {
        final workerName = (prepared[item.workerIndex]['name'] ?? 'Worker')
            .toString();
        final errorText = 'bulk_media_broken_link_error'.tr(
          namedArgs: {'error': readableSaveError(e)},
        );
        throw StateError(
          '$workerName — ${mediaFieldName(item.field)} link: $errorText',
        );
      }
      final file = downloaded;
      if (!isSupportedMediaType(item.field, file.mimeType)) {
        final workerName = (prepared[item.workerIndex]['name'] ?? 'Worker')
            .toString();
        throw StateError(
          '$workerName — ${mediaFieldName(item.field)} link: '
          '${supportedMediaMessage(item.field, file.mimeType)}',
        );
      }
      final results = await uploadBatch([file]);
      final result = results.first;
      prepared[item.workerIndex][item.field] = result.url!;
    }

    Future<void> worker() async {
      while (true) {
        if (firstError != null) return;
        final index = nextIndex++;
        if (index >= remoteKeys.length) return;
        try {
          await processItem(remoteKeys[index]);
        } catch (e) {
          firstError ??= e;
          return;
        }
      }
    }

    await Future.wait(List.generate(maxConcurrent, (_) => worker()));
    if (firstError != null) {
      throw firstError!;
    }
  }

  uploadedMediaByRowId.clear();
  for (final worker in prepared) {
    final rowId = (worker['clientRowId'] ?? '').toString().trim();
    if (rowId.isEmpty) continue;
    final urls = <String>[];
    for (final field in mediaFields) {
      final value = (worker[field] ?? '').toString().trim();
      if (value.isNotEmpty && value.startsWith('http')) {
        urls.add(value);
      }
    }
    if (urls.isNotEmpty) {
      uploadedMediaByRowId[rowId] = urls;
    }
  }

  return prepared;
}
