import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfHelpers {
  PdfHelpers._();

  static Future<ByteData?>? _fontDataFuture;

  static Future<ByteData?> _loadFontData() async {
    try {
      return await rootBundle.load('assets/fonts/SF-Pro.ttf');
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font?> loadFont() async {
    try {
      final fontData = await (_fontDataFuture ??= _loadFontData());
      return fontData != null ? pw.Font.ttf(fontData) : null;
    } catch (_) {
      return null;
    }
  }

  static pw.ThemeData buildTheme(pw.Font? font) {
    return pw.ThemeData.withFont(
      base: font ?? pw.Font.helvetica(),
      bold: font ?? pw.Font.helveticaBold(),
    );
  }

  static Future<pw.ThemeData> loadTheme() async {
    final font = await loadFont();
    return buildTheme(font);
  }

  static String translate(String key, String fallback, {Map<String, String>? namedArgs}) {
    final translated = key.tr(namedArgs: namedArgs).trim();
    return translated.isEmpty || translated == key ? fallback : translated;
  }
}

class PdfColorPalette {
  PdfColorPalette._();

  static final navy = PdfColor.fromHex('#111B4F');
  static final appBlue = PdfColor.fromHex('#0247C4');
  static final textColor = PdfColor.fromHex('#111B4F');
  static final mutedText = PdfColor.fromHex('#586080');
  static final lineColor = PdfColor.fromHex('#6B7398');
  static final lightGrey = PdfColor.fromHex('#F3F4F6');
  static final border = PdfColor.fromHex('#D1D5DB');
  static final darkNavy = PdfColor.fromHex('#162036');
  static final mutedGrey = PdfColor.fromHex('#6B7280');
  static final tableBorder = PdfColor.fromHex('#E2E8F0');
}
