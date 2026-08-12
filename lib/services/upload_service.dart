import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

import 'error_reporter.dart';

class CancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelCompleter.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelCompleter.complete();
  }
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

class _UploadCancelledException implements Exception {
  const _UploadCancelledException();
}

class UploadService {
  static const int _maxRetries = 3;
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const Duration _downloadTimeout = Duration(seconds: 30);
  static int _uploadSequence = 0;

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

    if (folder.trim().isEmpty) {
      throw const FormatException('An upload folder is required.');
    }

    final safeFallbackName = _safeFileName(fallbackFileName, 'file');
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
      final remoteName = _remoteFileName(uri);
      final requestedName = remoteName.isNotEmpty
          ? remoteName
          : safeFallbackName;
      final safeName = _safeFileName(requestedName, safeFallbackName);
      final responseMimeType = response.headers.contentType?.mimeType;
      final detectedMimeType = _mimeTypeFromBytes(downloadedData);
      final mimeType = _normalizedMimeType(
        detectedMimeType ??
            (responseMimeType == null ||
                    responseMimeType.isEmpty ||
                    responseMimeType == 'application/octet-stream'
                ? _mimeTypeFromFileName(safeName, fallbackMimeType)
                : responseMimeType),
        fileName: safeName,
        bytes: downloadedData,
      );

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

  static Future<List<UploadResult>> uploadFiles({
    required List<UploadFile> files,
    void Function(int completed, int total)? onProgress,
    CancellationToken? cancelToken,
    int maxConcurrent = 8,
  }) async {
    final total = files.length;
    if (total == 0) return [];

    var completed = 0;
    final placeholder = UploadFile(folder: '', fileName: '', bytes: Uint8List(0), mimeType: 'application/octet-stream');
    final results = List<UploadResult>.filled(total, UploadResult.cancelled(file: placeholder));

    Future<void> uploadSingle(int index) async {
      final file = files[index];
      UploadResult result;

      if (cancelToken?.isCancelled == true) {
        result = UploadResult.cancelled(file: file);
      } else {
        final validationError = _validationError(file);
        if (validationError != null) {
          result = UploadResult.failure(file: file, error: validationError);
        } else {
          try {
            final url = await _uploadToStorage(file, cancelToken: cancelToken);
            result = UploadResult.success(file: file, url: url);
          } on _UploadCancelledException {
            result = UploadResult.cancelled(file: file);
          } catch (e) {
            result = UploadResult.failure(file: file, error: e.toString());
          }
        }
      }

      results[index] = result;
      completed++;
      _notifyProgress(onProgress, completed, total);
    }

    final poolSize = maxConcurrent.clamp(1, 30);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (cancelToken?.isCancelled == true) break;
        final index = nextIndex++;
        if (index >= total) break;
        await uploadSingle(index);
      }
    }

    await Future.wait(List.generate(poolSize, (_) => worker()));
    return results;
  }

  static Future<String> _uploadToStorage(
    UploadFile file, {
    CancellationToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const _UploadCancelledException();
    }

    final safeFolder = _safeFolderPath(file.folder);
    final safeName = _safeFileName(file.fileName, 'file');
    final mimeType = _normalizedMimeType(
      file.mimeType,
      fileName: safeName,
      bytes: file.bytes,
    );
    final uploadId = _nextUploadId();
    final ref = FirebaseStorage.instance.ref().child(
      'hrms_documents/$safeFolder/${uploadId}_$safeName',
    );

    var uploadStarted = false;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      if (cancelToken?.isCancelled == true) {
        if (uploadStarted) {
          await _deleteQuietly(ref);
        }
        throw const _UploadCancelledException();
      }

      UploadTask? uploadTask;

      try {
        uploadTask = ref.putData(
          file.bytes,
          SettableMetadata(contentType: mimeType),
        );
        uploadStarted = true;

        if (cancelToken != null) {
          unawaited(
            cancelToken.whenCancelled.then((_) async {
              try {
                await uploadTask?.cancel();
              } catch (_) {}
            }),
          );
        }

        final snapshot = await uploadTask;

        if (cancelToken?.isCancelled == true) {
          await _deleteQuietly(ref);
          throw const _UploadCancelledException();
        }

        return await snapshot.ref.getDownloadURL();
      } on FirebaseException catch (e) {
        if (cancelToken?.isCancelled == true || e.code == 'canceled') {
          await _deleteQuietly(ref);
          throw const _UploadCancelledException();
        }

        final isLastAttempt = attempt == _maxRetries - 1;
        if (isLastAttempt || !_shouldRetry(e)) {
          await _deleteQuietly(ref);
          rethrow;
        }

        await _waitBeforeRetry(
          Duration(seconds: 2 * (attempt + 1)),
          cancelToken,
        );
      } on _UploadCancelledException {
        rethrow;
      } catch (_) {
        final isLastAttempt = attempt == _maxRetries - 1;
        if (isLastAttempt) {
          await _deleteQuietly(ref);
          rethrow;
        }

        await _waitBeforeRetry(
          Duration(seconds: 2 * (attempt + 1)),
          cancelToken,
        );
      }
    }

    await _deleteQuietly(ref);
    throw Exception('Upload failed after $_maxRetries retries');
  }

  static String? _validationError(UploadFile file) {
    if (file.folder.trim().isEmpty) {
      return 'Upload folder is required.';
    }

    if (file.fileName.trim().isEmpty) {
      return 'File name is required.';
    }

    if (file.bytes.isEmpty) {
      return 'File is empty.';
    }

    if (file.bytes.length > maxFileBytes) {
      return 'File is larger than the 10 MB limit.';
    }

    final mimeType = _normalizedMimeType(
      file.mimeType,
      fileName: file.fileName,
      bytes: file.bytes,
    );
    if (!mimeType.contains('/')) {
      return 'A valid MIME type is required.';
    }

    return null;
  }

  static bool _shouldRetry(FirebaseException error) {
    final code = error.code.trim().toLowerCase();
    return !{
      'unauthenticated',
      'unauthorized',
      'permission-denied',
      'quota-exceeded',
      'invalid-argument',
      'invalid-checksum',
      'object-not-found',
      'bucket-not-found',
      'project-not-found',
      'canceled',
    }.contains(code);
  }

  static Future<void> _waitBeforeRetry(
    Duration duration,
    CancellationToken? cancelToken,
  ) async {
    if (cancelToken == null) {
      await Future.delayed(duration);
      return;
    }

    if (cancelToken.isCancelled) {
      throw const _UploadCancelledException();
    }

    await Future.any([Future.delayed(duration), cancelToken.whenCancelled]);

    if (cancelToken.isCancelled) {
      throw const _UploadCancelledException();
    }
  }

  static Future<void> _deleteQuietly(Reference ref) async {
    try {
      await ref.delete();
    } catch (_) {}
  }

  static void _notifyProgress(
    void Function(int completed, int total)? callback,
    int completed,
    int total,
  ) {
    if (callback == null) return;
    try {
      callback(completed, total);
    } catch (_) {}
  }

  static String _nextUploadId() {
    _uploadSequence = (_uploadSequence + 1) & 0x7fffffff;
    return '${DateTime.now().microsecondsSinceEpoch}_$_uploadSequence';
  }

  static String _remoteFileName(Uri uri) {
    if (uri.pathSegments.isEmpty) return '';
    final raw = uri.pathSegments.last.trim();
    if (raw.isEmpty) return '';

    try {
      return Uri.decodeComponent(raw).trim();
    } on FormatException {
      return raw;
    }
  }

  static String _safeFolderPath(String value) {
    final parts = value
        .replaceAll('\\', '/')
        .split('/')
        .map((part) => _safePathSegment(part, ''))
        .where((part) => part.isNotEmpty)
        .toList();

    return parts.isEmpty ? 'uploads' : parts.join('/');
  }

  static String _safeFileName(String value, String fallback) {
    final safeFallback = _safePathSegment(fallback, 'file');
    final sanitized = _safePathSegment(value, safeFallback);
    final limited = sanitized.length > 180
        ? sanitized.substring(sanitized.length - 180)
        : sanitized;
    return limited.isEmpty ? safeFallback : limited;
  }

  static String _safePathSegment(String value, String fallback) {
    final sanitized = value
        .replaceAll(RegExp(r'[\x00-\x1F\x7F/\\?%*:|"<>]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return fallback;
    }

    return sanitized;
  }

  static String _normalizedMimeType(
    String value, {
    required String fileName,
    required Uint8List bytes,
  }) {
    final detected = _mimeTypeFromBytes(bytes);
    if (detected != null) return detected;

    final normalized = value.split(';').first.trim().toLowerCase();
    if (normalized.contains('/')) return normalized;

    return _mimeTypeFromFileName(fileName, 'application/octet-stream');
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
      _ =>
        fallback.trim().isEmpty
            ? 'application/octet-stream'
            : fallback.trim().toLowerCase(),
    };
  }

  static String? _mimeTypeFromBytes(Uint8List bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    if (startsWith(const [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }

    if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }

    if (startsWith(const [0x47, 0x49, 0x46, 0x38])) {
      return 'image/gif';
    }

    if (startsWith(const [0x42, 0x4D])) {
      return 'image/bmp';
    }

    if (bytes.length >= 12 &&
        startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    if (startsWith(const [0x25, 0x50, 0x44, 0x46])) {
      return 'application/pdf';
    }

    if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0])) {
      return 'application/msword';
    }

    if (startsWith(const [0x50, 0x4B, 0x03, 0x04]) &&
        _containsAscii(bytes, '[Content_Types].xml') &&
        _containsAscii(bytes, 'word/')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }

    return null;
  }

  static bool _containsAscii(Uint8List bytes, String value) {
    final pattern = ascii.encode(value);
    if (pattern.isEmpty || bytes.length < pattern.length) return false;

    for (var start = 0; start <= bytes.length - pattern.length; start++) {
      var matches = true;
      for (var offset = 0; offset < pattern.length; offset++) {
        if (bytes[start + offset] != pattern[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }

    return false;
  }

  
  
  
  static Future<void> deleteByUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.host.contains('firebasestorage.googleapis.com')) {
      return;
    }
    final segments = uri.pathSegments;
    final oIndex = segments.indexOf('o');
    if (oIndex == -1 || oIndex + 1 >= segments.length) return;
    final path = Uri.decodeComponent(segments[oIndex + 1]);
    if (path.trim().isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (error, stackTrace) {
      final message = error.toString().toLowerCase();
      
      
      
      if (message.contains('already running') ||
          message.contains('object-not-found') ||
          message.contains('not found') ||
          message.contains('not_found')) {
        return;
      }
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'UploadService.deleteByUrl',
      );
    }
  }

}
