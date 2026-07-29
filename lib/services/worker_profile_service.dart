import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

    final navy = PdfColor.fromHex('#162036');
    final black = PdfColors.black;
    final lightGrey = PdfColor.fromHex('#F3F4F6');
    final border = PdfColor.fromHex('#D1D5DB');

    Uint8List? imageBytes;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      imageBytes = await _downloadImage(profileImageUrl);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
        build: (context) => [
          // ═══════════════════════════════════════════
          //  HEADER — Title + Profile Image
          // ═══════════════════════════════════════════
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'WORK',
                    style: pw.TextStyle(
                      fontSize: 42,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                      height: 1.0,
                      letterSpacing: 1,
                    ),
                  ),
                  pw.Text(
                    'PROFILE',
                    style: pw.TextStyle(
                      fontSize: 42,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                      height: 1.0,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              pw.Container(
                width: 90,
                height: 90,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: border, width: 1.5),
                ),
                child: imageBytes != null
                    ? pw.Image(
                        pw.MemoryImage(imageBytes),
                        width: 90,
                        height: 90,
                        fit: pw.BoxFit.cover,
                      )
                    : pw.Container(
                        color: lightGrey,
                        child: pw.Center(
                          child: pw.Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: pw.TextStyle(
                              fontSize: 36,
                              fontWeight: pw.FontWeight.bold,
                              color: navy,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),

          pw.SizedBox(height: 30),

          // ═══════════════════════════════════════════
          //  WORKER INFO — Two columns
          // ═══════════════════════════════════════════
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left column
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label('EMPLOYEE DETAILS'),
                    pw.SizedBox(height: 10),
                    _detailRow('Name', name),
                    _detailRow('Father/Husband Name', fatherHusbandName),
                    _detailRow('Position', position),
                    _detailRow('National ID', nationalId),
                    _detailRow('Gender', gender),
                    _detailRow('Date of Birth', dateOfBirth),
                  ],
                ),
              ),
              pw.SizedBox(width: 30),
              // Right column
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label('CONTACT & WORK'),
                    pw.SizedBox(height: 10),
                    _detailRow('Phone', phone),
                    _detailRow('Email', email),
                    _detailRow('Joining Date', joiningDate),
                    _detailRow('Work Type', workType),
                    _detailRow('Attendance Type', attendanceType),
                    _detailRow('Experience Level', experienceLevel),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 25),

          // ═══════════════════════════════════════════
          //  DOUBLE LINE SEPARATOR
          // ═══════════════════════════════════════════
          pw.Container(height: 1, color: black),
          pw.SizedBox(height: 2),
          pw.Container(height: 1, color: black),

          pw.SizedBox(height: 20),

          // ═══════════════════════════════════════════
          //  PERSONAL DETAILS TABLE
          // ═══════════════════════════════════════════
          _label('PERSONAL INFORMATION'),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(3),
            },
            border: pw.TableBorder.all(color: border, width: 0.5),
            children: [
              _tableRow(['Religion', religion, 'Education', education], navy, isHeader: true),
              _tableRow(['Relationship', relationshipStatus, 'Salary Type', salaryType], navy, isHeader: true),
              _tableRow(['Address', address, 'Salary', salary.isNotEmpty ? salary : '-'], navy, isHeader: true),
            ],
          ),

          pw.SizedBox(height: 25),

          // ═══════════════════════════════════════════
          //  WORK SUMMARY TABLE
          // ═══════════════════════════════════════════
          _label('WORK SUMMARY'),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FlexColumnWidth(6),
            },
            border: pw.TableBorder.all(color: border, width: 0.5),
            children: [
              _tableRow(['Field', 'Details'], navy, isHeader: true),
              _tableRow(['Work Type', workType], navy),
              _tableRow(['Attendance Type', attendanceType], navy),
              _tableRow(['Experience Level', experienceLevel], navy),
              _tableRow(['Joining Date', joiningDate], navy),
              _tableRow(['Salary', salary.isNotEmpty ? salary : '-'], navy),
            ],
          ),

          pw.SizedBox(height: 40),
          pw.Container(height: 0.5, color: PdfColor.fromHex('#D1D5DB')),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'Generated on ${DateTime.now().toString().substring(0, 10)}',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromHex('#6B7280'),
              ),
            ),
          ),
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

  // ─── Section Label ──────────────────────────────────────────
  static pw.Widget _label(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromHex('#162036'), width: 1.5),
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#162036'),
          letterSpacing: 1,
        ),
      ),
    );
  }

  // ─── Detail Row (Label: Value) ──────────────────────────────
  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColor.fromHex('#6B7280'),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : '-',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Table Row ──────────────────────────────────────────────
  static pw.TableRow _tableRow(List<String> cells, PdfColor navyColor, {bool isHeader = false}) {
    return pw.TableRow(
      decoration: isHeader
          ? pw.BoxDecoration(color: PdfColor.fromHex('#F3F4F6'))
          : null,
      children: cells.map((cell) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: pw.Text(
            cell,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isHeader ? navyColor : PdfColors.black,
            ),
          ),
        );
      }).toList(),
    );
  }

  static Future<void> shareWorkerProfile(Uint8List bytes, String fileName) async {
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
    }
  }

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
