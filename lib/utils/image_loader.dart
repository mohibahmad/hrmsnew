import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageLoader {
  const ImageLoader._();

  /// Loads image bytes from any source (data URI, HTTP URL, file path, or asset).
  /// Returns null if loading fails or bytes are invalid.
  static Future<Uint8List?> load({
    required String? source,
    int maxSizeBytes = 5 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 15),
    bool convertToPng = false,
  }) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;

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
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Validates image bytes by checking magic bytes (PNG, JPEG, GIF, WEBP, BMP).
  static bool isValidImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 4) return false;

    // PNG (8-byte header)
    if (bytes.lengthInBytes >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
        bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A &&
        bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return true;
    }

    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;

    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;

    // WEBP (RIFF....WEBP)
    if (bytes.lengthInBytes >= 12) {
      final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
      final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (riff == 'RIFF' && webp == 'WEBP') return true;
    }

    // BMP
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
