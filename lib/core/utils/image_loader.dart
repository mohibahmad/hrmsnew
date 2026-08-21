import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageLoader {
  const ImageLoader._();

  /// In-memory cache of resolved image bytes keyed by the original source
  /// string (URL, file path, or base64). Keeps images from being re-read from
  /// disk or re-downloaded across repeated operations (e.g. payroll runs).
  static final Map<String, Uint8List> _memoryCache = {};

  /// Caches up to this many resolved bytes to bound memory usage.
  static const int _memoryCacheLimit = 8;
  static final List<String> _memoryCacheKeys = [];

  static void _remember(String source, Uint8List bytes) {
    if (source.isEmpty) return;
    while (_memoryCache.length >= _memoryCacheLimit && _memoryCacheKeys.isNotEmpty) {
      _memoryCache.remove(_memoryCacheKeys.removeAt(0));
    }
    if (!_memoryCache.containsKey(source)) {
      _memoryCacheKeys.add(source);
    }
    _memoryCache[source] = bytes;
  }

  /// Clears the in-memory cache (used when company images change).
  static void clearMemoryCache() {
    _memoryCache.clear();
    _memoryCacheKeys.clear();
  }

  static Uint8List? memoryCached(String source) => _memoryCache[source];

  /// Stores resolved image bytes in the in-memory cache so they are reused
  /// without re-reading from disk or re-downloading.
  static void cacheBytes(String source, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _remember(source, bytes);
  }

      static Future<Uint8List?> load({
    required String? source,
    int maxSizeBytes = 5 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 15),
    bool convertToPng = false,
  }) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;

    final cached = _memoryCache[value];
    if (cached != null) return cached;

    try {
      Uint8List? bytes;
      if (value.startsWith('data:image/')) {
        bytes = _decodeDataImage(value, maxSizeBytes);
      } else {
        final uri = Uri.tryParse(value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          bytes = await _download(uri, maxSizeBytes, timeout);
        } else if (uri != null && uri.scheme == 'file') {
          bytes = await _readFile(File.fromUri(uri), maxSizeBytes, timeout);
        } else {
          bytes = await _readFile(File(value), maxSizeBytes, timeout);
          bytes ??= await _readAsset(value, maxSizeBytes, timeout);
        }
      }

      if (bytes == null || bytes.isEmpty || bytes.lengthInBytes > maxSizeBytes) {
        return null;
      }
      if (!isValidImageBytes(bytes)) return null;

      if (convertToPng) {
        bytes = _tryConvertToPng(bytes);
        if (bytes == null) return null;
      }
      _remember(value, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

    static bool isValidImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 4) return false;

        if (bytes.lengthInBytes >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
        bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A &&
        bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return true;
    }

        if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;

        if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;

        if (bytes.lengthInBytes >= 12) {
      final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
      final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (riff == 'RIFF' && webp == 'WEBP') return true;
    }

        if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;

    return false;
  }

  static Uint8List? _decodeDataImage(String value, int maxSizeBytes) {
    try {
      final separator = value.indexOf(',');
      if (separator <= 5) return null;

      final metadata = value.substring(5, separator).toLowerCase();
      if (!metadata.startsWith('image/') || !metadata.contains(';base64')) {
        return null;
      }

      final encoded = value.substring(separator + 1).replaceAll(RegExp(r'\s+'), '');
      if (encoded.isEmpty || encoded.length > ((maxSizeBytes * 4) ~/ 3) + 16) {
        return null;
      }

      final bytes = base64Decode(encoded);
      return bytes.lengthInBytes <= maxSizeBytes ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _download(Uri uri, int maxSizeBytes, Duration timeout) async {
    if (kIsWeb) {
      try {
        final data = await NetworkAssetBundle(uri).load(uri.toString()).timeout(timeout);
        if (data.lengthInBytes > maxSizeBytes) return null;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        return null;
      }
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType != null &&
          (contentType.startsWith('text/html') || contentType.startsWith('application/json'))) {
        return null;
      }

      if (response.contentLength > maxSizeBytes) return null;

      final bytes = BytesBuilder(copy: false);
      var total = 0;

      await for (final chunk in response.timeout(timeout)) {
        total += chunk.length;
        if (total > maxSizeBytes) return null;
        bytes.add(chunk);
      }

      return bytes.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _readFile(File file, int maxSizeBytes, Duration timeout) async {
    try {
      if (!await file.exists().timeout(timeout)) return null;
      final length = await file.length().timeout(timeout);
      if (length <= 0 || length > maxSizeBytes) return null;
      return await file.readAsBytes().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readAsset(String path, int maxSizeBytes, Duration timeout) async {
    try {
      final data = await rootBundle.load(path).timeout(timeout);
      if (data.lengthInBytes <= 0 || data.lengthInBytes > maxSizeBytes) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _tryConvertToPng(Uint8List bytes) {
    if (isValidImageBytes(bytes)) return bytes;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return Uint8List.fromList(img.encodePng(decoded));
    } catch (_) {}
    return null;
  }
}
