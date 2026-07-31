import 'dart:io';
import 'package:open_file/open_file.dart';

class FileOpener {
  static Future<void> open(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      await OpenFile.open(filePath);
    } catch (_) {}
  }
}
