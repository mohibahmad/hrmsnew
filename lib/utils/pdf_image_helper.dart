import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class PdfImageHelper {
  static Future<Uint8List?> getImageBytes(String? imageSource) async {
    if (imageSource == null || imageSource.trim().isEmpty) return null;
    final source = imageSource.trim();
    try {
      if (source.startsWith('data:')) {
        final commaIndex = source.indexOf(',');
        if (commaIndex < 0 || commaIndex == source.length - 1) return null;
        final base64Data = source.substring(commaIndex + 1).replaceAll(RegExp(r'\s+'), '');
        return base64Decode(base64Data);
      } else if (source.startsWith('http://') || source.startsWith('https://')) {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        final request = await client.getUrl(Uri.parse(source)).timeout(const Duration(seconds: 15));
        final response = await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final builder = BytesBuilder();
          await for (var chunk in response) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        }
      } else if (source.startsWith('assets/')) {
        final data = await rootBundle.load(source);
        return data.buffer.asUint8List();
      } else if (source.startsWith('file://')) {
        final file = File.fromUri(Uri.parse(source));
        if (file.existsSync()) {
          return await file.readAsBytes();
        }
      } else if (File(source).existsSync()) {
        return await File(source).readAsBytes();
      } else {
        try {
          return base64Decode(source);
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }
}
