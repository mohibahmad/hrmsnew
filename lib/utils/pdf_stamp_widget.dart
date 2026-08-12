import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final PdfColor _hrStampColor = PdfColor.fromHex('#0B2A6F');
const String defaultHrStampAssetPath = 'assets/default_hr_stamp.png';

Future<Uint8List?> loadDefaultHrStampBytes() async {
  try {
    final data = await rootBundle.load(defaultHrStampAssetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

void _drawHrStampStar(
  PdfGraphics canvas,
  double centerX,
  double centerY,
  double size,
  PdfColor color,
) {
  final outerRadius = size;
  final innerRadius = size * 0.42;
  canvas.setFillColor(color);
  for (var index = 0; index < 10; index++) {
    final r = index.isEven ? outerRadius : innerRadius;
    final angle = (index * math.pi / 5) - (math.pi / 2);
    final x = centerX + r * math.cos(angle);
    final y = centerY + r * math.sin(angle);
    if (index == 0) {
      canvas.moveTo(x, y);
    } else {
      canvas.lineTo(x, y);
    }
  }
  canvas
    ..closePath()
    ..fillPath();
}

pw.Widget _buildDefaultHrStamp() {
  return pw.CustomPaint(
    size: const PdfPoint(66, 66),
    painter: (canvas, size) {
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      final radius = size.x / 2;
      final color = _hrStampColor;

      canvas.setStrokeColor(color);
      canvas.setFillColor(color);

      canvas
        ..setLineWidth(radius * 0.009)
        ..drawEllipse(centerX, centerY, radius * 0.95, radius * 0.95)
        ..strokePath()
        ..setLineWidth(radius * 0.022)
        ..drawEllipse(centerX, centerY, radius * 0.92, radius * 0.92)
        ..strokePath()
        ..setLineWidth(radius * 0.018)
        ..drawEllipse(centerX, centerY, radius * 0.59, radius * 0.59)
        ..strokePath();

      _drawHrStampStar(
        canvas,
        centerX - radius * 0.76,
        centerY,
        radius * 0.065,
        color,
      );
      _drawHrStampStar(
        canvas,
        centerX + radius * 0.76,
        centerY,
        radius * 0.065,
        color,
      );
    },
    child: pw.Container(
      width: 66,
      height: 66,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'HR',
            style: pw.TextStyle(
              color: _hrStampColor,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'HUMAN RESOURCES',
            style: pw.TextStyle(
              color: _hrStampColor,
              fontSize: 3.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget buildCompanyAuthorization({
  required String companyName,
  required String companyId,
  pw.MemoryImage? stampImage,
  required PdfColor accentColor,
  required PdfColor mutedColor,
  String authorizedSignatoryText = 'Authorized Signatory',
  String companyIdLabel = '',
  double width = 150,
}) {
  final cleanName = companyName.trim().isEmpty
      ? 'HRMS'
      : companyName.trim();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      // Stamp
      pw.SizedBox(
        width: 60,
        height: 60,
        child: stampImage != null
            ? pw.Image(stampImage, fit: pw.BoxFit.contain)
            : _buildDefaultHrStamp(),
      ),
      pw.SizedBox(height: 6),
      // Company name
      pw.Text(
        cleanName,
        style: pw.TextStyle(
          color: accentColor,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 2),
      // Underline — short, centered
      pw.Container(
        width: 60,
        height: 0.6,
        color: accentColor,
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        authorizedSignatoryText,
        style: pw.TextStyle(color: mutedColor, fontSize: 6.5),
      ),
      if (companyId.trim().isNotEmpty)
        pw.Text(
          '${companyIdLabel.isNotEmpty ? '$companyIdLabel ' : ''}${companyId.trim()}',
          style: pw.TextStyle(color: mutedColor, fontSize: 6),
        ),
    ],
  );
}
