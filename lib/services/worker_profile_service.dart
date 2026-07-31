import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../utils/file_opener.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WorkerProfileService {
  static const int _maxProfileImageBytes = 10 * 1024 * 1024;
  static const Duration _imageLoadTimeout = Duration(seconds: 15);

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
    String? generatedOnText,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/SF-Pro.ttf',
      );
      regularFont = pw.Font.ttf(fontData);
      boldFont = pw.Font.ttf(fontData);
    } catch (_) {}

    final theme = pw.ThemeData.withFont(
      base: regularFont ?? pw.Font.helvetica(),
      bold: boldFont ?? pw.Font.helveticaBold(),
    );

    final navy = PdfColor.fromHex('#162036');
    final black = PdfColors.black;
    final lightGrey = PdfColor.fromHex('#F3F4F6');
    final border = PdfColor.fromHex('#D1D5DB');

    final imageBytes = await _loadImageBytes(profileImageUrl);
    final profileTitle = _localized('worker_profile', 'Worker Profile');
    final titleLines = _titleLines(profileTitle);
    final employeeDetails = _localized('worker_detail', 'Employee Details');
    final contactAndWork =
        '${_localized('contact_no_label', 'Contact')} & '
        '${_localized('work_type', 'Work')}';
    final personalInformation = _localized(
      'personal_information',
      'Personal Information',
    );
    final workSummary = _localized('experience', 'Work Summary');
    final nameLabel = _localized('worker_name_label', 'Name');
    final fatherHusbandLabel = _localized(
      'father_husband_name',
      'Father/Husband Name',
    );
    final positionLabel = _localized('position', 'Position');
    final nationalIdLabel = _localized('national_id', 'National ID');
    final genderLabel = _localized('gender', 'Gender');
    final dateOfBirthLabel = _localized('date_of_birth', 'Date of Birth');
    final phoneLabel = _localized('contact_no_label', 'Phone');
    final emailLabel = _localized('worker_email', 'Email');
    final joiningDateLabel = _localized('joining_date', 'Joining Date');
    final workTypeLabel = _localized('work_type', 'Work Type');
    final attendanceTypeLabel = _localized(
      'attendance_type',
      'Attendance Type',
    );
    final experienceLevelLabel = _localized(
      'experience_level',
      'Experience Level',
    );
    final religionLabel = _localized('religion_title', 'Religion');
    final educationLabel = _localized('education_title', 'Education');
    final relationshipLabel = _localized('relationship_status', 'Relationship');
    final salaryTypeLabel = _localized('salary_type', 'Salary Type');
    final addressLabel = _localized('address', 'Address');
    final salaryLabel = _localized('salary', 'Salary');
    final fieldLabel = _localized('field', 'Field');
    final detailsLabel = _localized('details', 'Details');

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      titleLines.$1.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 42,
                        fontWeight: pw.FontWeight.bold,
                        color: navy,
                        height: 1,
                        letterSpacing: 1,
                      ),
                    ),
                    if (titleLines.$2.isNotEmpty)
                      pw.Text(
                        titleLines.$2.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 42,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                          height: 1,
                          letterSpacing: 1,
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
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
                            _profileInitial(name),
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
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label(employeeDetails.toUpperCase()),
                    pw.SizedBox(height: 10),
                    _detailRow(nameLabel, name),
                    _detailRow(fatherHusbandLabel, fatherHusbandName),
                    _detailRow(positionLabel, position),
                    _detailRow(nationalIdLabel, nationalId),
                    _detailRow(genderLabel, gender),
                    _detailRow(dateOfBirthLabel, dateOfBirth),
                  ],
                ),
              ),
              pw.SizedBox(width: 30),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label(contactAndWork.toUpperCase()),
                    pw.SizedBox(height: 10),
                    _detailRow(phoneLabel, phone),
                    _detailRow(emailLabel, email),
                    _detailRow(joiningDateLabel, joiningDate),
                    _detailRow(workTypeLabel, workType),
                    _detailRow(attendanceTypeLabel, attendanceType),
                    _detailRow(experienceLevelLabel, experienceLevel),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 25),
          pw.Container(height: 1, color: black),
          pw.SizedBox(height: 2),
          pw.Container(height: 1, color: black),
          pw.SizedBox(height: 20),
          _label(personalInformation.toUpperCase()),
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
              _tableRow(
                [religionLabel, religion, educationLabel, education],
                navy,
                isHeader: true,
              ),
              _tableRow(
                [
                  relationshipLabel,
                  relationshipStatus,
                  salaryTypeLabel,
                  salaryType,
                ],
                navy,
                isHeader: true,
              ),
              _tableRow(
                [
                  addressLabel,
                  address,
                  salaryLabel,
                  salary.isNotEmpty ? salary : '-',
                ],
                navy,
                isHeader: true,
              ),
            ],
          ),
          pw.SizedBox(height: 25),
          _label(workSummary.toUpperCase()),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FlexColumnWidth(6),
            },
            border: pw.TableBorder.all(color: border, width: 0.5),
            children: [
              _tableRow([fieldLabel, detailsLabel], navy, isHeader: true),
              _tableRow([workTypeLabel, workType], navy),
              _tableRow([attendanceTypeLabel, attendanceType], navy),
              _tableRow([experienceLevelLabel, experienceLevel], navy),
              _tableRow([joiningDateLabel, joiningDate], navy),
              _tableRow([salaryLabel, salary.isNotEmpty ? salary : '-'], navy),
            ],
          ),
          pw.SizedBox(height: 40),
          pw.Container(height: 0.5, color: PdfColor.fromHex('#D1D5DB')),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              generatedOnText ??
                  '${_localized('generated_on', 'Generated on')} '
                      '${DateTime.now().toString().substring(0, 10)}',
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

  static Future<Uint8List?> _loadImageBytes(String? source) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;

    Uint8List? bytes;
    if (value.startsWith('data:image/')) {
      bytes = _decodeDataImage(value);
    } else {
      final uri = Uri.tryParse(value);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        bytes = await _downloadImage(uri);
      } else if (uri != null && uri.scheme == 'file') {
        bytes = await _readImageFile(File.fromUri(uri));
      } else {
        bytes = await _readImageFile(File(value));
        bytes ??= await _readAssetImage(value);
      }
    }

    if (bytes == null ||
        bytes.isEmpty ||
        bytes.lengthInBytes > _maxProfileImageBytes) {
      return null;
    }
    return _isSupportedImageBytes(bytes) ? bytes : null;
  }

  static Uint8List? _decodeDataImage(String value) {
    try {
      final separator = value.indexOf(',');
      if (separator <= 5) return null;
      final metadata = value.substring(5, separator).toLowerCase();
      if (!metadata.startsWith('image/') || !metadata.contains(';base64')) {
        return null;
      }
      final encoded = value
          .substring(separator + 1)
          .replaceAll(RegExp(r'\s+'), '');
      if (encoded.isEmpty ||
          encoded.length > ((_maxProfileImageBytes * 4) ~/ 3) + 16) {
        return null;
      }
      final bytes = base64Decode(encoded);
      return bytes.lengthInBytes <= _maxProfileImageBytes ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _downloadImage(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _imageLoadTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_imageLoadTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(_imageLoadTimeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) {
        return null;
      }

      final contentLength = response.contentLength;
      if (contentLength > _maxProfileImageBytes) return null;

      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(_imageLoadTimeout)) {
        total += chunk.length;
        if (total > _maxProfileImageBytes) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _readImageFile(File file) async {
    try {
      if (!await file.exists().timeout(_imageLoadTimeout)) return null;
      final length = await file.length().timeout(_imageLoadTimeout);
      if (length <= 0 || length > _maxProfileImageBytes) return null;
      return await file.readAsBytes().timeout(_imageLoadTimeout);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readAssetImage(String path) async {
    try {
      final data = await rootBundle.load(path).timeout(_imageLoadTimeout);
      if (data.lengthInBytes <= 0 ||
          data.lengthInBytes > _maxProfileImageBytes) {
        return null;
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static bool _isSupportedImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    if (bytes.lengthInBytes >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.lengthInBytes >= 6) {
      final header = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
      if (header == 'GIF87a' || header == 'GIF89a') return true;
    }
    if (bytes.lengthInBytes >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true;
    }
    if (bytes.lengthInBytes >= 12) {
      final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
      final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (riff == 'RIFF' && webp == 'WEBP') return true;
    }
    return false;
  }

  static String _profileInitial(String name) {
    final value = name.trim();
    if (value.isEmpty) return '?';
    return String.fromCharCode(value.runes.first).toUpperCase();
  }

  static (String, String) _titleLines(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return ('WORK', 'PROFILE');
    if (words.length == 1) return (words.first, '');
    return (words.first, words.skip(1).join(' '));
  }

  static String _localized(String key, String fallback) {
    final translated = key.tr().trim();
    return translated.isEmpty || translated == key ? fallback : translated;
  }

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
              value.trim().isNotEmpty ? value : '-',
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

  static pw.TableRow _tableRow(
    List<String> cells,
    PdfColor navyColor, {
    bool isHeader = false,
  }) {
    return pw.TableRow(
      decoration: isHeader
          ? pw.BoxDecoration(color: PdfColor.fromHex('#F3F4F6'))
          : null,
      children: cells.map((cell) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: pw.Text(
            cell.trim().isNotEmpty ? cell : '-',
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

  static Future<bool> shareWorkerProfile(
    Uint8List bytes,
    String fileName, {
    String? dialogTitle,
  }) {
    return _saveWorkerProfile(bytes, fileName, dialogTitle: dialogTitle);
  }

  static Future<bool> downloadWorkerProfile(
    Uint8List bytes,
    String fileName, {
    String? dialogTitle,
  }) {
    return _saveWorkerProfile(bytes, fileName, dialogTitle: dialogTitle);
  }

  static Future<bool> _saveWorkerProfile(
    Uint8List bytes,
    String fileName, {
    String? dialogTitle,
  }) async {
    if (bytes.isEmpty) {
      throw StateError(
        _localized('unexpected_error', 'Unable to save worker profile'),
      );
    }

    final result = await FilePicker.saveFile(
      dialogTitle: dialogTitle?.trim().isNotEmpty == true
          ? dialogTitle!.trim()
          : '${_localized('save', 'Save')} '
                '${_localized('worker_profile', 'Worker Profile')}',
      fileName: _safePdfFileName(fileName),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (result == null || result.trim().isEmpty) return false;

    var outputPath = result.trim();
    if (!outputPath.toLowerCase().endsWith('.pdf')) {
      outputPath = '$outputPath.pdf';
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
    await FileOpener.open(outputPath);
    return true;
  }

  static String _safePdfFileName(String fileName) {
    final segments = fileName.trim().split(RegExp(r'[\\/]'));
    var name = segments.isEmpty ? '' : segments.last.trim();
    name = name.replaceAll(RegExp(r'[:*?"<>|]'), '_');
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'worker_profile.pdf';
    }
    if (!name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    }
    return name;
  }
}
