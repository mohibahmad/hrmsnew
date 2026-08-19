import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/helpers.dart';
import '../utils/image_loader.dart';
import '../utils/pdf_helpers.dart';

const int _maxPdfImageDimension = 400;

class WorkerProfileService {
  static const int _maxProfileImageBytes = 10 * 1024 * 1024;
  static const Duration _imageLoadTimeout = Duration(seconds: 3);
  static const int _maxCacheSize = 20;
  static final Map<String, Uint8List?> _imageCache = {};
  static final List<String> _cacheKeys = [];

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
    required String religion,
    required String dateOfBirth,
    required String relationshipStatus,
    required String address,
    String? profileImageUrl,
    String? generatedOnText,
    String companyName = 'HRMS',
    String companyId = '',
    String? companyStampImageUrl,
  }) async {
    Uint8List? regularFontData;
    try {
      final fontData = await rootBundle.load('assets/fonts/SF-Pro.ttf');
      regularFontData = fontData.buffer.asUint8List();
    } catch (_) {}

    final rawProfileBytes = await _loadImageBytes(profileImageUrl);
    Uint8List? rawStampBytes;
    final stampSource = (companyStampImageUrl ?? '').trim();
    if (stampSource.isNotEmpty) {
      rawStampBytes = await _loadImageBytes(stampSource);
    }
    rawStampBytes ??= await loadDefaultHrStampBytes();

    final profileBytes = _compressImageForPdf(rawProfileBytes);
    final stampBytes = _compressImageForPdf(rawStampBytes);

    final strings = _collectStrings();

    return compute(
      _buildPdf,
      _PdfArgs(
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
      ),
    );
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
      'worker_profile': PdfHelpers.translate('worker_profile', 'Worker Profile'),
      'worker_detail': PdfHelpers.translate('worker_detail', 'Employee Details'),
      'contact_no_label': PdfHelpers.translate('contact_no_label', 'Contact'),
      'work_type': PdfHelpers.translate('work_type', 'Employment Type'),
      'personal_information': PdfHelpers.translate('personal_information', 'Personal Information'),
      'experience': PdfHelpers.translate('experience', 'Work Summary'),
      'worker_name_label': PdfHelpers.translate('worker_name_label', 'Name'),
      'father_husband_name': PdfHelpers.translate('father_husband_name', 'Father / Husband Name'),
      'position': PdfHelpers.translate('position', 'Position'),
      'national_id': PdfHelpers.translate('national_id', 'National ID'),
      'gender': PdfHelpers.translate('gender', 'Gender'),
      'date_of_birth': PdfHelpers.translate('date_of_birth', 'Date of Birth'),
      'worker_email': PdfHelpers.translate('worker_email', 'Email'),
      'joining_date': PdfHelpers.translate('joining_date', 'Joining Date'),
      'attendance_type': PdfHelpers.translate('attendance_type', 'Work Model'),
      'experience_level': PdfHelpers.translate('experience_level', 'Experience Level'),
      'religion_title': PdfHelpers.translate('religion_title', 'Religion'),
      'education_title': PdfHelpers.translate('education_title', 'Education'),
      'relationship_status': PdfHelpers.translate('relationship_status', 'Relationship'),
      'address': PdfHelpers.translate('address', 'Address'),
      'salary': PdfHelpers.translate('salary', 'Salary'),
      'field': PdfHelpers.translate('field', 'Field'),
      'details': PdfHelpers.translate('details', 'Details'),
      'authorized_signatory': PdfHelpers.translate('authorized_signatory', 'Authorized Signatory'),
      'generated_on': PdfHelpers.translate('generated_on', 'Generated on'),
    };
  }

  static Future<Uint8List?> _loadImageBytes(String? source) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;
    if (_imageCache.containsKey(value)) {
      _cacheKeys.remove(value);
      _cacheKeys.add(value);
      return _imageCache[value];
    }

    final bytes = await ImageLoader.load(
      source: source,
      maxSizeBytes: _maxProfileImageBytes,
      timeout: _imageLoadTimeout,
    );

    if (bytes == null) return null;

    if (_cacheKeys.length >= _maxCacheSize) {
      final oldest = _cacheKeys.removeAt(0);
      _imageCache.remove(oldest);
    }
    _imageCache[value] = bytes;
    _cacheKeys.add(value);
    return bytes;
  }

  static Future<bool> shareWorkerProfile(Uint8List bytes, String fileName, {String? dialogTitle}) {
    return _saveWorkerProfile(bytes, fileName, dialogTitle: dialogTitle);
  }

  static Future<bool> downloadWorkerProfile(Uint8List bytes, String fileName, {String? dialogTitle}) {
    return _saveWorkerProfile(bytes, fileName, dialogTitle: dialogTitle);
  }

  static Future<bool> _saveWorkerProfile(Uint8List bytes, String fileName, {String? dialogTitle}) async {
    if (bytes.isEmpty) {
      throw StateError(PdfHelpers.translate('unexpected_error', 'Unable to save worker profile'));
    }

    final result = await FilePicker.saveFile(
      dialogTitle: dialogTitle?.trim().isNotEmpty == true
          ? dialogTitle!.trim()
          : '${PdfHelpers.translate('save', 'Save')} ${PdfHelpers.translate('worker_profile', 'Worker Profile')}',
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
  final displayVal = value.trim().isNotEmpty ? value : '-';
  final isLong = displayVal.length > 22;
  final valFontSize = isLong ? (displayVal.length > 30 ? 8.0 : 8.5) : 10.0;

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 95,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#6B7280')),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            displayVal,
            style: pw.TextStyle(
              fontSize: valFontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.TableRow _tableRow(List<String> cells, PdfColor navyColor, {bool isHeader = false}) {
  return pw.TableRow(
    decoration: isHeader ? pw.BoxDecoration(color: PdfColor.fromHex('#F3F4F6')) : null,
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

  pw.Font? font;
  if (args.fontBytes != null) {
    final byteData = ByteData.view(args.fontBytes!.buffer);
    font = pw.Font.ttf(byteData);
  }

  final theme = PdfHelpers.buildTheme(font);

  final navy = PdfColorPalette.darkNavy;
  final border = PdfColorPalette.border;
  final lightGrey = PdfColorPalette.lightGrey;

  final s = args.strings;
  final profileImage = args.profileImageBytes == null ? null : pw.MemoryImage(args.profileImageBytes!);
  final stampImage = args.stampImageBytes == null ? null : pw.MemoryImage(args.stampImageBytes!);

  final profileTitle = s['worker_profile']!;
  final titleLines = _titleLines(profileTitle);
  final employeeDetails = s['worker_detail']!;
  final contactAndWork = '${s['contact_no_label']!} & ${s['work_type']!}';
  final personalInformation = s['personal_information']!;
  final workSummary = s['experience']!;

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
                  ? pw.Image(profileImage, width: 84, height: 84, fit: pw.BoxFit.cover)
                  : pw.Container(
                      color: lightGrey,
                      child: pw.Center(
                        child: pw.Text(
                          _profileInitial(args.name),
                          style: pw.TextStyle(fontSize: 36, fontWeight: pw.FontWeight.bold, color: navy),
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
                  _detailRow(s['worker_name_label']!, args.name),
                  _detailRow(s['father_husband_name']!, args.fatherHusbandName),
                  _detailRow(s['position']!, args.position),
                  _detailRow(s['national_id']!, args.nationalId),
                  _detailRow(s['gender']!, args.gender),
                  _detailRow(s['date_of_birth']!, args.dateOfBirth),
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
                  _detailRow(s['contact_no_label']!, args.phone),
                  _detailRow(s['worker_email']!, args.email),
                  _detailRow(s['joining_date']!, args.joiningDate),
                  _detailRow(s['work_type']!, args.workType),
                  _detailRow(s['attendance_type']!, args.attendanceType),
                  _detailRow(s['experience_level']!, args.experienceLevel),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Container(height: 1, color: PdfColors.black),
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
              [s['religion_title']!, args.religion, s['education_title']!, args.education],
              navy,
              isHeader: true,
            ),
            _tableRow(
              [s['relationship_status']!, args.relationshipStatus, s['salary']!, args.salary.isNotEmpty ? args.salary : '-'],
              navy,
              isHeader: true,
            ),
            _tableRow(
              [s['address']!, args.address, '', ''],
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
            _tableRow([s['field']!, s['details']!], navy, isHeader: true),
            _tableRow([s['work_type']!, args.workType], navy),
            _tableRow([s['attendance_type']!, args.attendanceType], navy),
            _tableRow([s['experience_level']!, args.experienceLevel], navy),
            _tableRow([s['joining_date']!, args.joiningDate], navy),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 0.5, color: PdfColor.fromHex('#D1D5DB')),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: buildCompanyAuthorization(
            companyName: args.companyName,
            companyId: args.companyId,
            stampImage: stampImage,
            accentColor: navy,
            mutedColor: PdfColor.fromHex('#6B7280'),
            authorizedSignatoryText: s['authorized_signatory']!,
            generatedOnText: args.generatedOnText ?? 
                '${s['generated_on']!} ${DateTime.now().toString().substring(0, 10)}',
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}