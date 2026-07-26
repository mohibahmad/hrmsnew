import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class WorkerProfileService {
  static Future<Uint8List> generateWorkerProfile({
    required String name,
    required String email,
    required String phone,
    required String fatherHusbandName,
    required String position,
    required String nationalId,
    required String attendanceType,
    required String workType,
    required String experienceLevel,
    required String gender,
    required String joiningDate,
    required String salary,
    required String education,
    required String salaryType,
    required String religion,
    required String dateOfBirth,
    required String relationshipStatus,
    required String address,
    String? profileImageUrl,
  }) async {
    final pdf = pw.Document();

    final primaryBlue = PdfColor.fromHex('#0247C4');
    final darkBlue = PdfColor.fromHex('#004FDE');
    final white = PdfColors.white;
    final lightIconBg = PdfColor.fromHex('#E5EEFC');
    final cardBorder = PdfColor.fromHex('#E8E8E8');
    final textDark = PdfColor.fromHex('#111827');
    final textGrey = PdfColor.fromHex('#6B7280');

    // Download profile image
    Uint8List? imageBytes;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      imageBytes = await _downloadImage(profileImageUrl);
    }

    final details = <Map<String, String>>[
      {'label': 'Father/Husband Name', 'value': fatherHusbandName, 'icon': 'F'},
      {'label': 'Position', 'value': position, 'icon': 'P'},
      {'label': 'National ID', 'value': nationalId, 'icon': 'N'},
      {'label': 'Attendance Type', 'value': attendanceType, 'icon': 'A'},
      {'label': 'Work Type', 'value': workType, 'icon': 'W'},
      {'label': 'Experience Level', 'value': experienceLevel, 'icon': 'E'},
      {'label': 'Gender', 'value': gender, 'icon': 'G'},
      {'label': 'Joining Date', 'value': joiningDate, 'icon': 'J'},
      {'label': 'Salary', 'value': salary.isNotEmpty ? salary : '-', 'icon': 'S'},
      {'label': 'Education', 'value': education, 'icon': 'E'},
      {'label': 'Salary Type', 'value': salaryType, 'icon': 'T'},
      {'label': 'Religion', 'value': religion, 'icon': 'R'},
      {'label': 'Date of Birth', 'value': dateOfBirth, 'icon': 'D'},
      {'label': 'Relationship Status', 'value': relationshipStatus, 'icon': 'R'},
      {'label': 'Address', 'value': address, 'icon': 'A'},
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 0),
        build: (context) => [
          // ── Header (matches WorkerProfilePreviewDialog) ──
          _buildHeader(primaryBlue, darkBlue, white, name, email, phone, imageBytes, lightIconBg),

          pw.SizedBox(height: 24),

          // ── Details cards in 2-column grid ──
          _buildDetailsSection(details, primaryBlue, lightIconBg, cardBorder, textDark, textGrey),

          pw.SizedBox(height: 24),

          // ── Footer ──
          _buildFooter(textGrey),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List?> _downloadImage(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final List<int> allBytes = [];
        await for (final chunk in response) {
          allBytes.addAll(chunk);
        }
        return Uint8List.fromList(allBytes);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Header — matches WorkerProfilePreviewDialog layout
  // ─────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader(
    PdfColor primaryBlue,
    PdfColor darkBlue,
    PdfColor white,
    String name,
    String email,
    String phone,
    Uint8List? imageBytes,
    PdfColor lightIconBg,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [primaryBlue, darkBlue],
          begin: pw.Alignment.centerLeft,
          end: pw.Alignment.centerRight,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Title bar ──
          pw.Container(
            height: 32,
            color: darkBlue,
            alignment: pw.Alignment.center,
            child: pw.Text(
              'Worker Profile',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: white,
              ),
            ),
          ),

          // ── Profile info row ──
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(32, 16, 32, 20),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Profile image
                pw.Container(
                  width: 100,
                  height: 100,
                  decoration: pw.BoxDecoration(
                    color: white,
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: white, width: 3),
                  ),
                  child: imageBytes != null
                      ? pw.ClipOval(
                          child: pw.Image(
                            pw.MemoryImage(imageBytes),
                            width: 100,
                            height: 100,
                            fit: pw.BoxFit.cover,
                          ),
                        )
                      : pw.Center(
                          child: pw.Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: pw.TextStyle(
                              fontSize: 32,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryBlue,
                            ),
                          ),
                        ),
                ),
                pw.SizedBox(width: 20),

                // Name + contact info
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        name.isNotEmpty ? name : '-',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: white,
                        ),
                      ),
                      pw.SizedBox(height: 8),

                      // Email
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          _buildIconBox(lightIconBg, 'E', primaryBlue, 14),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Text(
                              email.isNotEmpty ? email : '-',
                              style: pw.TextStyle(
                                fontSize: 11,
                                color: white,
                                fontWeight: pw.FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),

                      // Phone
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          _buildIconBox(lightIconBg, 'P', primaryBlue, 14),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Text(
                              phone.isNotEmpty ? phone : '-',
                              style: pw.TextStyle(
                                fontSize: 11,
                                color: white,
                                fontWeight: pw.FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Icon box helper (small colored box with letter)
  // ─────────────────────────────────────────────────────────────
  static pw.Widget _buildIconBox(
    PdfColor bgColor,
    String letter,
    PdfColor iconColor,
    double size,
  ) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        letter,
        style: pw.TextStyle(
          fontSize: size * 0.55,
          fontWeight: pw.FontWeight.bold,
          color: iconColor,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Info card widget (matches preview dialog card style)
  // ─────────────────────────────────────────────────────────────
  static pw.Widget _buildInfoCard(
    String iconLetter,
    String label,
    String value,
    PdfColor primaryBlue,
    PdfColor lightIconBg,
    PdfColor cardBorder,
    PdfColor textDark,
    PdfColor textGrey,
  ) {
    final displayValue = value.isNotEmpty ? value : '-';
    return pw.Container(
      height: 56,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: cardBorder, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Icon box
          pw.Container(
            width: 32,
            height: 32,
            decoration: pw.BoxDecoration(
              color: lightIconBg,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              iconLetter,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: primaryBlue,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          // Label + value
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textGrey,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  displayValue,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: textDark,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Details section — 2-column card grid (like preview dialog)
  // ─────────────────────────────────────────────────────────────
  static pw.Widget _buildDetailsSection(
    List<Map<String, String>> details,
    PdfColor primaryBlue,
    PdfColor lightIconBg,
    PdfColor cardBorder,
    PdfColor textDark,
    PdfColor textGrey,
  ) {
    final rows = <pw.Widget>[];

    for (int i = 0; i < details.length; i += 2) {
      final left = _buildInfoCard(
        details[i]['icon'] ?? '?',
        details[i]['label']!,
        details[i]['value']!,
        primaryBlue,
        lightIconBg,
        cardBorder,
        textDark,
        textGrey,
      );

      pw.Widget right;
      if (i + 1 < details.length) {
        right = _buildInfoCard(
          details[i + 1]['icon'] ?? '?',
          details[i + 1]['label']!,
          details[i + 1]['value']!,
          primaryBlue,
          lightIconBg,
          cardBorder,
          textDark,
          textGrey,
        );
      } else {
        right = pw.SizedBox.shrink();
      }

      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: left),
              pw.SizedBox(width: 10),
              pw.Expanded(child: right),
            ],
          ),
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Footer
  // ─────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter(PdfColor greyColor) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 32),
      child: pw.Column(
        children: [
          pw.Divider(color: PdfColor.fromHex('#DEE2E6'), thickness: 0.5),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by HRMS',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: greyColor,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.Text(
                'Generated on ${DateTime.now().toString().substring(0, 10)}',
                style: pw.TextStyle(fontSize: 9, color: greyColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> shareWorkerProfile(Uint8List bytes, String fileName) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName)],
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Returns `true` if the file was saved, `false` if the user cancelled.
  static Future<bool> downloadWorkerProfile(Uint8List bytes, String fileName) async {
    try {
      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Worker Profile',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(bytes);
        return true;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }
}
