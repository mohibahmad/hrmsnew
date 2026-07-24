import 'dart:typed_data';
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
  }) async {
    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('#0247C4');
    final darkBlue = PdfColor.fromHex('#004FDE');
    final accentColor = PdfColor.fromHex('#0953D4');
    final greyColor = PdfColor.fromHex('#6B7280');
    final lightBg = PdfColor.fromHex('#F8F9FA');
    final borderColor = PdfColor.fromHex('#DEE2E6');
    final white = PdfColors.white;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 0),
        build: (context) => [
          _buildHeader(primaryColor, darkBlue, white, name),
          pw.SizedBox(height: 24),
          _buildContactSection(accentColor, lightBg, borderColor, email, phone),
          pw.SizedBox(height: 20),
          _buildDetailsSection(primaryColor, lightBg, borderColor, greyColor, fatherHusbandName, position, nationalId, attendanceType, workType, experienceLevel, gender, joiningDate, salary, education, salaryType, religion, dateOfBirth, relationshipStatus, address),
          pw.SizedBox(height: 20),
          _buildFooter(greyColor),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(PdfColor primaryColor, PdfColor darkBlue, PdfColor white, String name) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(40, 32, 40, 32),
      decoration: pw.BoxDecoration(
        color: primaryColor,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 10,
            height: 40,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'Worker Profile',
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: white,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  name.isNotEmpty ? name : '-',
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildContactSection(PdfColor accentColor, PdfColor lightBg, PdfColor borderColor, String email, String phone) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 40),
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: lightBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Email',
                  style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#6B7280'), fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  email.isNotEmpty ? email : '-',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1F2937')),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 20),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Phone',
                  style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#6B7280'), fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  phone.isNotEmpty ? phone : '-',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1F2937')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDetailsSection(PdfColor primaryColor, PdfColor lightBg, PdfColor borderColor, PdfColor greyColor, String fatherHusbandName, String position, String nationalId, String attendanceType, String workType, String experienceLevel, String gender, String joiningDate, String salary, String education, String salaryType, String religion, String dateOfBirth, String relationshipStatus, String address) {
    final details = [
      {'label': 'Father/Husband Name', 'value': fatherHusbandName},
      {'label': 'Position', 'value': position},
      {'label': 'National ID', 'value': nationalId},
      {'label': 'Attendance Type', 'value': attendanceType},
      {'label': 'Work Type', 'value': workType},
      {'label': 'Experience Level', 'value': experienceLevel},
      {'label': 'Gender', 'value': gender},
      {'label': 'Joining Date', 'value': joiningDate},
      {'label': 'Salary', 'value': salary},
      {'label': 'Education', 'value': education},
      {'label': 'Salary Type', 'value': salaryType},
      {'label': 'Religion', 'value': religion},
      {'label': 'Date of Birth', 'value': dateOfBirth},
      {'label': 'Relationship Status', 'value': relationshipStatus},
      {'label': 'Address', 'value': address},
    ];

    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 40),
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'Profile Details',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
                letterSpacing: 1,
              ),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: borderColor, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4FF')),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: pw.Text(
                      'Field',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0247C4')),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: pw.Text(
                      'Value',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0247C4')),
                    ),
                  ),
                ],
              ),
              for (int i = 0; i < details.length; i++) ...[
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: i % 2 == 0 ? PdfColors.white : lightBg,
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: pw.Text(
                        details[i]['label']!,
                        style: pw.TextStyle(fontSize: 12, color: PdfColor.fromHex('#374151')),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: pw.Text(
                        (details[i]['value'] as String).isNotEmpty ? details[i]['value'] as String : '-',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1F2937')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(PdfColor greyColor) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 40),
      child: pw.Column(
        children: [
          pw.Divider(color: PdfColor.fromHex('#DEE2E6'), thickness: 0.5),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by HRMS',
                style: pw.TextStyle(fontSize: 10, color: greyColor, fontStyle: pw.FontStyle.italic),
              ),
              pw.Text(
                'Generated on ${DateTime.now().toString().substring(0, 10)}',
                style: pw.TextStyle(fontSize: 10, color: greyColor),
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
}
