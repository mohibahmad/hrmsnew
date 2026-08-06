import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'auth_service.dart';
import 'preferences_service.dart';
import '../utils/file_opener.dart';
import '../utils/pdf_stamp_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const int _maxPdfImageDimension = 400;

class WorkerProfileService {
  static const int _maxProfileImageBytes = 10 * 1024 * 1024;
  static const Duration _imageLoadTimeout = Duration(seconds: 8);

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
    String companyName = 'HRMS Company',
    String companyId = '',
    String? companyStampImageUrl,
  }) async {
    Uint8List? regularFontData;
    try {
      final fontData = await rootBundle.load('assets/fonts/SF-Pro.ttf');
      regularFontData = fontData.buffer.asUint8List();
    } catch (_) {}

    // Load images concurrently. Fix: .then() was returning another Future<Uint8List?>
    // which caused "type 'Future<Uint8List?>' is not a subtype of type 'Uint8List?'" cast error.
    final rawProfileBytes = await _loadImageBytes(profileImageUrl);

    // Load stamp/signature: user uploaded stamp -> cached notifier -> preferences -> guest profile
    Uint8List? rawStampBytes;
    final stampSource = (companyStampImageUrl ?? '').trim();
    if (stampSource.isNotEmpty) {
      rawStampBytes = await _loadImageBytes(stampSource);
    }
    if (rawStampBytes == null || rawStampBytes.isEmpty) {
      final notifierUrl = AuthService.companyStampNotifier.value?.trim() ?? '';
      if (notifierUrl.isNotEmpty) {
        rawStampBytes = await _loadImageBytes(notifierUrl);
      }
    }
    if (rawStampBytes == null || rawStampBytes.isEmpty) {
      try {
        final prefUrl = await PreferencesService.getCompanyStampUrl();
        if (prefUrl != null && prefUrl.trim().isNotEmpty) {
          rawStampBytes = await _loadImageBytes(prefUrl.trim());
        }
      } catch (_) {}
    }
    if (rawStampBytes == null || rawStampBytes.isEmpty) {
      try {
        final guest = await PreferencesService.getGuestProfileData();
        final guestStamp = (guest?['companyStampUrl'] ??
                guest?['stampUrl'] ??
                guest?['companyStamp'] ??
                guest?['companySignature'] ??
                guest?['signatureUrl'] ??
                guest?['signature'] ??
                '')
            .toString()
            .trim();
        if (guestStamp.isNotEmpty) {
          rawStampBytes = await _loadImageBytes(guestStamp);
        }
      } catch (_) {}
    }

    final profileBytes = _compressImageForPdf(rawProfileBytes);
    final stampBytes = _compressImageForPdf(rawStampBytes);

    final strings = _collectStrings();

    return compute(_buildPdf, _PdfArgs(
      name: name,
      email: email,
      phone: phone,
      fatherHusbandName: fatherHusbandName,
      position: position,
      nationalId: nationalId,
      attendanceType: attendanceType,
      workType: workType,
      experienceLevel: experienceLevel,
      gender: gender,
      joiningDate: joiningDate,
      salary: salary,
      education: education,
      salaryType: salaryType,
      religion: religion,
      dateOfBirth: dateOfBirth,
      relationshipStatus: relationshipStatus,
      address: address,
      profileImageBytes: profileBytes,
      stampImageBytes: stampBytes,
      generatedOnText: generatedOnText,
      companyName: companyName,
      companyId: companyId,
      fontBytes: regularFontData,
      strings: strings,
    ));
  }

  static Uint8List? _compressImageForPdf(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final needsResize = decoded.width > _maxPdfImageDimension ||
          decoded.height > _maxPdfImageDimension;
      if (!needsResize) return bytes;
      final resized = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? _maxPdfImageDimension : null,
        height: decoded.height > decoded.width ? _maxPdfImageDimension : null,
        interpolation: img.Interpolation.linear,
      );
      if (decoded.hasAlpha) {
        return Uint8List.fromList(img.encodePng(resized));
      }
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (_) {
      return bytes;
    }
  }

  static Map<String, String> _collectStrings() {
    return {
      'worker_profile': _localized('worker_profile', 'Worker Profile'),
      'worker_detail': _localized('worker_detail', 'Employee Details'),
      'contact_no_label': _localized('contact_no_label', 'Contact'),
      'work_type': _localized('work_type', 'Work'),
      'personal_information': _localized('personal_information', 'Personal Information'),
      'experience': _localized('experience', 'Work Summary'),
      'worker_name_label': _localized('worker_name_label', 'Name'),
      'father_husband_name': _localized('father_husband_name', 'Father/Husband Name'),
      'position': _localized('position', 'Position'),
      'national_id': _localized('national_id', 'National ID'),
      'gender': _localized('gender', 'Gender'),
      'date_of_birth': _localized('date_of_birth', 'Date of Birth'),
      'worker_email': _localized('worker_email', 'Email'),
      'joining_date': _localized('joining_date', 'Joining Date'),
      'attendance_type': _localized('attendance_type', 'Attendance Type'),
      'experience_level': _localized('experience_level', 'Experience Level'),
      'religion_title': _localized('religion_title', 'Religion'),
      'education_title': _localized('education_title', 'Education'),
      'relationship_status': _localized('relationship_status', 'Relationship'),
      'salary_type': _localized('salary_type', 'Salary Type'),
      'address': _localized('address', 'Address'),
      'salary': _localized('salary', 'Salary'),
      'field': _localized('field', 'Field'),
      'details': _localized('details', 'Details'),
      'authorized_signatory': _localized('authorized_signatory', 'Authorized Signatory'),
      'generated_on': _localized('generated_on', 'Generated on'),
    };
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
      if (contentType != null &&
          (contentType.startsWith('text/html') ||
              contentType.startsWith('application/json'))) {
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

String _profileInitial(String name) {
  final value = name.trim();
  if (value.isEmpty) return '?';
  return String.fromCharCode(value.runes.first).toUpperCase();
}

(String, String) _titleLines(String title) {
  final words = title.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return ('WORK', 'PROFILE');
  if (words.length == 1) return (words.first, '');
  return (words.first, words.skip(1).join(' '));
}

String _localized(String key, String fallback) {
  final translated = key.tr().trim();
  return translated.isEmpty || translated == key ? fallback : translated;
}

pw.Widget _label(String text) {
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

pw.Widget _detailRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
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

pw.TableRow _tableRow(
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
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
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

class _PdfArgs {
  final String name;
  final String email;
  final String phone;
  final String fatherHusbandName;
  final String position;
  final String nationalId;
  final String attendanceType;
  final String workType;
  final String experienceLevel;
  final String gender;
  final String joiningDate;
  final String salary;
  final String education;
  final String salaryType;
  final String religion;
  final String dateOfBirth;
  final String relationshipStatus;
  final String address;
  final Uint8List? profileImageBytes;
  final Uint8List? stampImageBytes;
  final String? generatedOnText;
  final String companyName;
  final String companyId;
  final Uint8List? fontBytes;
  final Map<String, String> strings;

  const _PdfArgs({
    required this.name,
    required this.email,
    required this.phone,
    required this.fatherHusbandName,
    required this.position,
    required this.nationalId,
    required this.attendanceType,
    required this.workType,
    required this.experienceLevel,
    required this.gender,
    required this.joiningDate,
    required this.salary,
    required this.education,
    required this.salaryType,
    required this.religion,
    required this.dateOfBirth,
    required this.relationshipStatus,
    required this.address,
    this.profileImageBytes,
    this.stampImageBytes,
    this.generatedOnText,
    required this.companyName,
    required this.companyId,
    this.fontBytes,
    required this.strings,
  });
}

Future<Uint8List> _buildPdf(_PdfArgs args) async {
  final pdf = pw.Document();

  pw.Font? regularFont;
  pw.Font? boldFont;
  if (args.fontBytes != null) {
    final byteData = ByteData.view(args.fontBytes!.buffer);
    regularFont = pw.Font.ttf(byteData);
    boldFont = pw.Font.ttf(byteData);
  }

  final theme = pw.ThemeData.withFont(
    base: regularFont ?? pw.Font.helvetica(),
    bold: boldFont ?? pw.Font.helveticaBold(),
  );

  final navy = PdfColor.fromHex('#162036');
  final black = PdfColors.black;
  final lightGrey = PdfColor.fromHex('#F3F4F6');
  final border = PdfColor.fromHex('#D1D5DB');

  final s = args.strings;
  final profileImage = args.profileImageBytes == null
      ? null
      : pw.MemoryImage(args.profileImageBytes!);
  final stampImage = args.stampImageBytes == null
      ? null
      : pw.MemoryImage(args.stampImageBytes!);

  final profileTitle = s['worker_profile']!;
  final titleLines = _titleLines(profileTitle);
  final employeeDetails = s['worker_detail']!;
  final contactAndWork = '${s['contact_no_label']!} & ${s['work_type']!}';
  final personalInformation = s['personal_information']!;
  final workSummary = s['experience']!;
  final nameLabel = s['worker_name_label']!;
  final fatherHusbandLabel = s['father_husband_name']!;
  final positionLabel = s['position']!;
  final nationalIdLabel = s['national_id']!;
  final genderLabel = s['gender']!;
  final dateOfBirthLabel = s['date_of_birth']!;
  final phoneLabel = s['contact_no_label']!;
  final emailLabel = s['worker_email']!;
  final joiningDateLabel = s['joining_date']!;
  final workTypeLabel = s['work_type']!;
  final attendanceTypeLabel = s['attendance_type']!;
  final experienceLevelLabel = s['experience_level']!;
  final religionLabel = s['religion_title']!;
  final educationLabel = s['education_title']!;
  final relationshipLabel = s['relationship_status']!;
  final salaryTypeLabel = s['salary_type']!;
  final addressLabel = s['address']!;
  final salaryLabel = s['salary']!;
  final fieldLabel = s['field']!;
  final detailsLabel = s['details']!;

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
                      fontSize: 36,
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
                        fontSize: 36,
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
              width: 84,
              height: 84,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border, width: 1.5),
              ),
              child: profileImage != null
                  ? pw.Image(
                      profileImage,
                      width: 84,
                      height: 84,
                      fit: pw.BoxFit.cover,
                    )
                  : pw.Container(
                      color: lightGrey,
                      child: pw.Center(
                        child: pw.Text(
                          _profileInitial(args.name),
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
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _label(employeeDetails.toUpperCase()),
                  pw.SizedBox(height: 8),
                  _detailRow(nameLabel, args.name),
                  _detailRow(fatherHusbandLabel, args.fatherHusbandName),
                  _detailRow(positionLabel, args.position),
                  _detailRow(nationalIdLabel, args.nationalId),
                  _detailRow(genderLabel, args.gender),
                  _detailRow(dateOfBirthLabel, args.dateOfBirth),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _label(contactAndWork.toUpperCase()),
                  pw.SizedBox(height: 8),
                  _detailRow(phoneLabel, args.phone),
                  _detailRow(emailLabel, args.email),
                  _detailRow(joiningDateLabel, args.joiningDate),
                  _detailRow(workTypeLabel, args.workType),
                  _detailRow(attendanceTypeLabel, args.attendanceType),
                  _detailRow(experienceLevelLabel, args.experienceLevel),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Container(height: 1, color: black),
        pw.SizedBox(height: 2),
        pw.Container(height: 1, color: black),
        pw.SizedBox(height: 14),
        _label(personalInformation.toUpperCase()),
        pw.SizedBox(height: 8),
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
              [religionLabel, args.religion, educationLabel, args.education],
              navy,
              isHeader: true,
            ),
            _tableRow(
              [relationshipLabel, args.relationshipStatus, salaryTypeLabel, args.salaryType],
              navy,
              isHeader: true,
            ),
            _tableRow(
              [addressLabel, args.address, salaryLabel, args.salary.isNotEmpty ? args.salary : '-'],
              navy,
              isHeader: true,
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        _label(workSummary.toUpperCase()),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(6),
          },
          border: pw.TableBorder.all(color: border, width: 0.5),
          children: [
            _tableRow([fieldLabel, detailsLabel], navy, isHeader: true),
            _tableRow([workTypeLabel, args.workType], navy),
            _tableRow([attendanceTypeLabel, args.attendanceType], navy),
            _tableRow([experienceLevelLabel, args.experienceLevel], navy),
            _tableRow([joiningDateLabel, args.joiningDate], navy),
            _tableRow([salaryLabel, args.salary.isNotEmpty ? args.salary : '-'], navy),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Container(height: 0.5, color: PdfColor.fromHex('#D1D5DB')),
        pw.SizedBox(height: 8),
        // RIGHT: Company stamp + signature block, same position as the
        // payroll invoice PDF.
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              buildCompanyAuthorization(
                companyName: args.companyName,
                companyId: args.companyId,
                stampImage: stampImage,
                accentColor: navy,
                mutedColor: PdfColor.fromHex('#6B7280'),
                authorizedSignatoryText: s['authorized_signatory']!,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                args.generatedOnText ??
                    '${s['generated_on']!} ${DateTime.now().toString().substring(0, 10)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromHex('#6B7280'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}
