import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared company "authorization" block used by every PDF generator
/// (payroll invoice, worker profile, policies, leave policy) so the stamp and
/// signature always sit in the same position and look identical across
/// documents.
///
/// This mirrors the payroll invoice layout: the stamp image (or the fallback
/// company seal) on the left, and the company name / "Authorized Signatory"
/// line on the right. Callers should wrap it in a right-aligned `Align` at the
/// bottom of the page content, exactly like the payroll invoice does.
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
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        if (stampImage != null)
          pw.Container(
            width: 66,
            height: 54,
            alignment: pw.Alignment.center,
            child: pw.Image(stampImage, fit: pw.BoxFit.contain),
          )
        else
          // Fallback company seal (double circle + VERIFIED). The VERIFIED
          // text is intentionally drawn without a surrounding border box.
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
                    border: pw.Border.all(color: stampBlue, width: 2.5),
                  ),
                ),
                pw.Container(
                  width: 58,
                  height: 58,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: stampBlue, width: 1.2),
                  ),
                ),
                pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'VERIFIED',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: stampBlue,
                        letterSpacing: 1.2,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      cleanName.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                        fontSize: 4.5,
                        fontWeight: pw.FontWeight.bold,
                        color: stampBlue,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (companyId.trim().isNotEmpty)
                      pw.Text(
                        companyId.trim(),
                        style: pw.TextStyle(fontSize: 3.5, color: stampBlue),
                      ),
                  ],
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
