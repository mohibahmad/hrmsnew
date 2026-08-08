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
