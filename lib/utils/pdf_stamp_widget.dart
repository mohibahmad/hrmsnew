import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String _companyInitials(String companyName) {
  final words = companyName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'HR';
  if (words.length == 1) {
    final word = words.first.toUpperCase();
    return word.substring(0, math.min(2, word.length));
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}

void _drawSealStar(
  PdfGraphics canvas,
  double centerX,
  double centerY,
  PdfColor color,
) {
  const outerRadius = 3.2;
  const innerRadius = 1.35;
  canvas.setFillColor(color);
  for (var index = 0; index < 10; index++) {
    final radius = index.isEven ? outerRadius : innerRadius;
    final angle = -math.pi / 2 + index * math.pi / 5;
    final x = centerX + math.cos(angle) * radius;
    final y = centerY + math.sin(angle) * radius;
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

pw.Widget _buildDefaultCompanySeal({
  required String companyName,
  required PdfColor color,
}) {
  final initials = _companyInitials(companyName);
  return pw.CustomPaint(
    size: const PdfPoint(66, 66),
    painter: (canvas, size) {
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(1.4)
        ..drawEllipse(centerX, centerY, 31, 31)
        ..strokePath()
        ..setLineWidth(0.7)
        ..drawEllipse(centerX, centerY, 26.5, 26.5)
        ..strokePath();
      _drawSealStar(canvas, 10.5, centerY, color);
      _drawSealStar(canvas, 55.5, centerY, color);
    },
    child: pw.Container(
      width: 66,
      height: 66,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            initials,
            style: pw.TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'OFFICIAL SEAL',
            style: pw.TextStyle(
              color: color,
              fontSize: 4.2,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.45,
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
  double width = 180,
}) {
  final cleanName = companyName.trim().isEmpty
      ? 'HRMS Company'
      : companyName.trim();

  return pw.SizedBox(
    width: width,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 66,
          height: 66,
          alignment: pw.Alignment.center,
          child: stampImage != null
              ? pw.Image(stampImage, fit: pw.BoxFit.contain)
              : _buildDefaultCompanySeal(
                  companyName: cleanName,
                  color: accentColor,
                ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                cleanName,
                style: pw.TextStyle(
                  color: accentColor,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Container(height: 0.7, color: accentColor),
              pw.SizedBox(height: 3),
              pw.Text(
                authorizedSignatoryText,
                style: pw.TextStyle(color: mutedColor, fontSize: 6),
              ),
              if (companyId.trim().isNotEmpty)
                pw.Text(
                  '${companyIdLabel.isNotEmpty ? '$companyIdLabel ' : ''}${companyId.trim()}',
                  style: pw.TextStyle(color: mutedColor, fontSize: 6),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
