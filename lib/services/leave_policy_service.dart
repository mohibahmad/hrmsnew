import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/file_opener.dart';

class LeavePolicyService {
  static String formattedText(
    Map<String, dynamic> policy, {
    String? companyName,
  }) {
    final title = _title(policy, companyName: companyName);
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln();

    for (final row in _leaveRows(policy)) {
      buffer.writeln('${row.$1}: ${row.$2}');
    }

    final applicableTo = _value(policy['applicableTo']);
    if (applicableTo.isNotEmpty) {
      buffer.writeln('Applicable To: $applicableTo');
    }

    final startDate = _humanDate(policy['startDate']);
    if (startDate.isNotEmpty) {
      buffer.writeln('Effective From: $startDate');
    }

    final leaveYear = _value(policy['leaveYear']);
    if (leaveYear.isNotEmpty) {
      buffer.writeln('Leave Year: $leaveYear');
    }

    final annual = _value(policy['annualLeaveDays']);
    if (annual.isNotEmpty) {
      buffer.writeln('Total Annual Leaves: $annual days');
    }

    final description = _value(policy['description']);
    if (description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }

    return buffer.toString().trim();
  }

  static Future<Uint8List> generatePdf(
    Map<String, dynamic> policy, {
    String? companyName,
    String? companyId,
  }) async {
    final document = pw.Document();
    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/SF-Pro.ttf');
      regularFont = pw.Font.ttf(fontData);
      boldFont = pw.Font.ttf(fontData);
    } catch (_) {}

    final theme = pw.ThemeData.withFont(
      base: regularFont ?? pw.Font.helvetica(),
      bold: boldFont ?? pw.Font.helveticaBold(),
    );

    final primaryBlue = PdfColor.fromHex('#0F52FA');
    final orange = PdfColor.fromHex('#FF451A');
    final dark = PdfColor.fromHex('#1E1E1E');
    final grey = PdfColor.fromHex('#424242');
    final black = PdfColors.black;

    final organization = _value(companyName).isEmpty
        ? 'Company'
        : _value(companyName);
    final policyName = _value(policy['policyName']).isEmpty
        ? 'Leave Policy'
        : _value(policy['policyName']);
    final effectiveDate = _humanDate(policy['startDate']);
    final annualDays = _value(policy['annualLeaveDays']);
    final companyIdText = _value(companyId);

    pw.MemoryImage? appIconImage;
    try {
      final iconData = await rootBundle.load('assets/app_icon.png');
      appIconImage = pw.MemoryImage(iconData.buffer.asUint8List(
        iconData.offsetInBytes,
        iconData.lengthInBytes,
      ));
    } catch (_) {}

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 32, 40, 40),
        footer: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Authorized by HR',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: black,
                  ),
                ),
                pw.Text(
                  'Company ID: ${companyIdText.isEmpty ? '—' : companyIdText}',
                  style: pw.TextStyle(fontSize: 9, color: grey),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              height: 20,
              width: double.infinity,
              color: primaryBlue,
            ),
          ],
        ),
        build: (context) => [
          
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.ClipOval(
                child: appIconImage != null
                    ? pw.Image(
                        appIconImage,
                        width: 46,
                        height: 46,
                        fit: pw.BoxFit.cover,
                      )
                    : pw.Container(
                        width: 46,
                        height: 46,
                        decoration: pw.BoxDecoration(
                          color: primaryBlue,
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.CustomPaint(painter: _personIconPainter),
                      ),
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'HRMS',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: dark,
                      height: 1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  pw.Text(
                    'HR Solution for Growth',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: grey,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 26),

          
          pw.Text(
            policyName,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: black,
            ),
          ),
          pw.SizedBox(height: 14),
          _richLine('Company: ', organization),
          pw.SizedBox(height: 10),
          _richLine(
            'Effective Date: ',
            effectiveDate.isEmpty ? '—' : effectiveDate,
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Policy Owner: HR',
            style: pw.TextStyle(
              fontSize: 11,
              color: black,
              height: 1.5,
            ),
          ),
          pw.SizedBox(height: 18),

          
          _sectionHeader('Purpose'),
          _body(
            "This policy defines the company's leave rules and annual leave "
            'entitlement for workers.',
          ),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Eligibility and Scope'),
          _body('This policy applies to all active workers of the company.'),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Annual Leave Entitlement'),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(
                  fontSize: 11,
                  color: black,
                  height: 1.5,
                ),
                children: [
                  const pw.TextSpan(
                    text:
                        'Each worker is entitled to ',
                  ),
                  pw.TextSpan(
                    text:
                        '[${annualDays.isEmpty ? '0' : annualDays}]',
                    style: pw.TextStyle(color: orange),
                  ),
                  const pw.TextSpan(
                    text:
                        ' annual leave days during the leave year.',
                  ),
                ],
              ),
            ),
          ),
          _body(
            "All supported paid leave types are deducted from the worker's "
            'total annual leave balance.',
          ),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Supported Leave Types'),
          ..._leaveRows(policy).map((row) => _bullet(row.$1, '')),
          _body(
            'These leave types are used for categorization and reporting. '
            "All paid leave types are deducted from the worker's total "
            'annual leave balance.',
          ),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Leave Counting Rules'),
          ..._countingRules(),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Leave Recording and Review'),
          _body(
            "Workers communicate their leave request through the company's "
            'defined process.',
          ),
          _body(
            "HR records the worker's leave directly in the system after "
            'checking the available leave balance.',
          ),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Unpaid Leave'),
          ..._unpaidLeaveRule(),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Leave Balance'),
          _body('The system automatically calculates:'),
          _bullet('', 'Total annual leave allowance'),
          _bullet('', 'Used leave days'),
          _bullet('', 'Remaining leave balance'),
          pw.SizedBox(height: 14),

          
          _sectionHeader('Policy Changes'),
          _body(
            'HR may update this policy according to company requirements. '
            'Any updated policy will apply from its stated effective date.',
          ),
          pw.SizedBox(height: 24),
        ],
      ),
    );

    return document.save();
  }

  static Future<bool> downloadPdf(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) throw StateError('Unable to generate leave policy PDF');
    final safeName = safeFileName(fileName);
    final result = await FilePicker.saveFile(
      dialogTitle: 'Download Leave Policy PDF',
      fileName: safeName,
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

  static String safeFileName(String title) {
    var source = title.trim();
    if (source.toLowerCase().endsWith('.pdf')) {
      source = source.substring(0, source.length - 4);
    }
    var name = source
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (name.isEmpty) name = 'company_leave_policy';
    if (name.toLowerCase().endsWith('_leave_policy')) return '$name.pdf';
    return '${name}_leave_policy.pdf';
  }

  static pw.Widget _sectionHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _body(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          color: PdfColors.black,
          height: 1.5,
        ),
      ),
    );
  }

  static pw.Widget _richLine(String blackText, String orangeText) {
    return pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 11,
          height: 1.5,
        ),
        children: [
          pw.TextSpan(text: blackText),
          pw.TextSpan(
            text: orangeText,
            style: pw.TextStyle(color: PdfColor.fromHex('#FF451A')),
          ),
        ],
      ),
    );
  }

  static pw.Widget _bullet(String boldText, String normalText) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 1, right: 6, left: 2),
            child: pw.Text(
              '•',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: pw.TextStyle(
                  color: PdfColors.black,
                  fontSize: 11,
                  height: 1.45,
                ),
                children: [
                  if (boldText.isNotEmpty)
                    pw.TextSpan(
                      text: boldText,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.TextSpan(text: normalText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _personIconPainter(PdfGraphics canvas, PdfPoint size) {
    final w = size.x;
    final h = size.y;
    canvas
      ..setFillColor(PdfColors.white)
      ..drawEllipse(w * 0.5, h * 0.28, w * 0.073, h * 0.073)
      ..fillPath();
    canvas
      ..setStrokeColor(PdfColors.white)
      ..setLineWidth(w * 0.055)
      ..moveTo(w * 0.25, h * 0.45)
      ..curveTo(w * 0.5, h * 0.35, w * 0.5, h * 0.35, w * 0.75, h * 0.45)
      ..strokePath();
    canvas
      ..moveTo(w * 0.5, h * 0.4)
      ..lineTo(w * 0.5, h * 0.75)
      ..strokePath();
  }

  static List<pw.Widget> _countingRules() {
    return [
      _bullet('', 'Leave is counted on working days only.'),
      _bullet('', 'Company holidays and weekly off days are excluded.'),
      _bullet(
        '',
        'Leave exceeding the available annual balance may be treated as '
        'unpaid leave.',
      ),
    ];
  }

  static List<pw.Widget> _unpaidLeaveRule() {
    return [
      _body(
        'When a worker has insufficient annual leave balance, HR may '
        'record the additional days as unpaid leave.',
      ),
      _body(
        'Unpaid leave may result in a salary deduction according to the '
        "company's payroll rules.",
      ),
    ];
  }

  static List<(String, String)> _leaveRows(Map<String, dynamic> policy) {
    final rows = <(String, String)>[];

    void add(String type, dynamic value) {
      final text = _value(value);
      if (text.isEmpty || text == '0') return;
      final lower = text.toLowerCase();
      if (lower.endsWith('days') ||
          lower.endsWith('day') ||
          lower.endsWith('(paid)') ||
          lower.endsWith('(unpaid)')) {
        rows.add((type, text));
      } else {
        rows.add((type, '$text days'));
      }
    }

    add('Sick Leave', policy['sickLeaves']);
    add('Casual Leave', policy['casualLeaves']);
    add('Medical Leave', policy['medicalLeaves']);

    final multiple = policy['leaveTypes'];
    if (multiple is List) {
      for (final entry in multiple.whereType<Map>()) {
        final item = Map<String, dynamic>.from(entry);
        final type = _leaveLabel(item['leaveType'] ?? item['type']);
        if (type == 'Leave') continue;
        if (rows.any((row) => row.$1 == type)) continue;
        rows.add((type, _allowance(item)));
      }
    }

    if (rows.isEmpty) {
      final annual = _value(policy['annualLeaveDays']);
      if (annual.isNotEmpty && annual != '0') {
        rows.add(('Total Annual Leave', '$annual days'));
      }
    }

    return rows;
  }

  static String _allowance(Map<String, dynamic> item) {
    final allowed = _value(item['allowedLeaves'] ?? item['days']);
    final paidStatus = _value(item['paidUnpaid']);
    final type = _value(item['leaveType'] ?? item['type']).toLowerCase();
    if (allowed.isEmpty || (type == 'unpaid' && allowed == '0')) {
      return type == 'unpaid' ? 'As required' : '-';
    }
    final suffix = allowed == '1' ? 'day' : 'days';
    return paidStatus.isEmpty || paidStatus.toLowerCase() == 'paid'
        ? '$allowed $suffix'
        : '$allowed $suffix ($paidStatus)';
  }

  static String _leaveLabel(dynamic value) {
    final type = _value(value);
    if (type.isEmpty) return 'Leave';
    return type.toLowerCase().endsWith('leave') ? type : '$type Leave';
  }

  static String _title(Map<String, dynamic> policy, {String? companyName}) {
    final savedTitle = _value(policy['policyName']);
    if (savedTitle.isNotEmpty) return savedTitle;
    final organization = _value(companyName);
    final year = _policyYear(policy);
    return '${organization.isEmpty ? 'Company' : organization} Leave Policy $year';
  }

  static int _policyYear(Map<String, dynamic> policy) {
    final parsed = DateTime.tryParse(_value(policy['startDate']));
    return parsed?.year ?? DateTime.now().year;
  }

  static String _humanDate(dynamic value) {
    final text = _value(value);
    if (text.isEmpty) return '';
    final parsed = DateTime.tryParse(text);
    return parsed == null ? text : DateFormat('d MMMM yyyy').format(parsed);
  }

  static String _value(dynamic value) => value?.toString().trim() ?? '';
}
