import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;










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
  final cleanName =
      companyName.trim().isEmpty ? 'HRMS Company' : companyName.trim();
  final stampBlue = PdfColor.fromHex('#1A3FA3');

  return pw.SizedBox(
    width: width,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (stampImage != null)
          pw.Container(
            width: 66,
            height: 66,
            alignment: pw.Alignment.center,
            child: pw.Image(stampImage, fit: pw.BoxFit.contain),
          )
        else
          
          pw.SizedBox(
            width: 72,
            height: 72,
            child: pw.Stack(
              alignment: pw.Alignment.center,
              children: [
                pw.Container(
                  width: 72,
                  height: 72,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: stampBlue, width: 2.2),
                  ),
                ),
                pw.Container(
                  width: 60,
                  height: 60,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: stampBlue, width: 1.0),
                  ),
                ),
                pw.Container(
                  width: 52,
                  alignment: pw.Alignment.center,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'HRMS OFFICIAL',
                        style: pw.TextStyle(
                          fontSize: 4.8,
                          fontWeight: pw.FontWeight.bold,
                          color: stampBlue,
                          letterSpacing: 0.6,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          _drawStar(stampBlue, size: 6),
                          pw.SizedBox(width: 2),
                          pw.Text(
                            'VERIFIED',
                            style: pw.TextStyle(
                              fontSize: 5.2,
                              fontWeight: pw.FontWeight.bold,
                              color: stampBlue,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.SizedBox(width: 2),
                          _drawStar(stampBlue, size: 6),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        cleanName.toUpperCase(),
                        maxLines: 2,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 4.2,
                          fontWeight: pw.FontWeight.bold,
                          color: stampBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (companyId.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          companyId.trim(),
                          maxLines: 1,
                          style: pw.TextStyle(
                            fontSize: 3.5,
                            color: stampBlue,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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




pw.Widget _drawStar(PdfColor color, {double size = 6}) {
  return pw.CustomPaint(
    size: PdfPoint(size, size),
    painter: (canvas, bounds) {
      canvas.setColor(color);
      final centerX = bounds.x / 2;
      final centerY = bounds.y / 2;
      final outer = bounds.x / 2;
      final inner = outer * 0.45;
      for (var i = 0; i < 10; i++) {
        final radius = i.isEven ? outer : inner;
        final angle = -math.pi / 2 + i * math.pi / 5;
        final pointX = centerX + radius * math.cos(angle);
        final pointY = centerY + radius * math.sin(angle);
        if (i == 0) {
          canvas.moveTo(pointX, pointY);
        } else {
          canvas.lineTo(pointX, pointY);
        }
      }
      canvas.closePath();
      canvas.fillPath();
    },
  );
}
