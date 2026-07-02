import 'dart:async';
import 'dart:convert';
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

  factory UploadResult.success({required UploadFile file, required String url}) {
    return UploadResult._(file: file, url: url, isSuccess: true);
  }

  factory UploadResult.failure({required UploadFile file, required String error}) {
    return UploadResult._(file: file, error: error, isSuccess: false);
  }

  factory UploadResult.cancelled({required UploadFile file}) {
    return UploadResult._(file: file, isSuccess: false, isCancelled: true);
  }
}

class UploadService {
  static const int _maxRetries = 3;

  static Future<List<UploadResult>> uploadFiles({
    required List<UploadFile> files,
    void Function(int completed, int total)? onProgress,
    CancellationToken? cancelToken,
  }) async {
    final results = <UploadResult>[];
    int completed = 0;
    final total = files.length;

    for (final file in files) {
      if (cancelToken?.isCancelled == true) {
        results.add(UploadResult.cancelled(file: file));
        completed++;
        onProgress?.call(completed, total);
        continue;
      }
      try {
        final url = await _uploadToStorage(file);
        completed++;
        onProgress?.call(completed, total);
        results.add(UploadResult.success(file: file, url: url));
      } catch (e) {
        completed++;
        onProgress?.call(completed, total);
        results.add(UploadResult.failure(file: file, error: e.toString()));
      }
    }

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
