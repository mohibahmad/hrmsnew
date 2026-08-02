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

    final endDate = _humanDate(policy['endDate']);
    if (endDate.isNotEmpty) {
      buffer.writeln('Effective Until: $endDate');
    }

    if (policy['carryForward'] == true) {
      final days = _value(policy['carryForwardDays']);
      buffer.writeln(
        days.isEmpty || days == '0'
            ? 'Carry Forward: Allowed'
            : 'Carry Forward: Up to $days days',
      );
    }

    if (policy['approvalRequired'] == true) {
      buffer.writeln('Approval Required: Yes');
    }

    final notice = _value(policy['noticePeriod']);
    if (notice.isNotEmpty) buffer.writeln('Notice Period: $notice');

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
    final navy = PdfColor.fromHex('#162036');
    final indigo = PdfColor.fromHex('#4F46E5');
    final muted = PdfColor.fromHex('#64748B');
    final border = PdfColor.fromHex('#E2E8F0');
    final surface = PdfColor.fromHex('#F8FAFC');
    final title = _title(policy, companyName: companyName);
    final organization = _value(companyName).isEmpty
        ? 'HRMS Company'
        : _value(companyName);

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                organization,
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(
              color: navy,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  organization.toUpperCase(),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 25,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (_value(companyId).isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Company ID: ${_value(companyId)}',
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Text(
            'LEAVE ENTITLEMENTS',
            style: pw.TextStyle(
              color: indigo,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: border),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: _leaveRows(policy)
                .map(
                  (row) => pw.TableRow(
                    children: [_cell(row.$1, bold: true), _cell(row.$2)],
                  ),
                )
                .toList(),
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: surface,
              border: pw.Border.all(color: border),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Column(
              children: _detailRows(policy)
                  .map(
                    (row) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 9),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: 120,
                            child: pw.Text(
                              row.$1,
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: muted,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              row.$2,
                              style: pw.TextStyle(fontSize: 10, color: navy),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_value(policy['description']).isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'POLICY NOTES',
              style: pw.TextStyle(
                color: indigo,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              _value(policy['description']),
              style: pw.TextStyle(fontSize: 10, color: navy, lineSpacing: 3),
            ),
          ],
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

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static List<(String, String)> _leaveRows(Map<String, dynamic> policy) {
    final multiple = policy['leaveTypes'];
    if (multiple is List) {
      final rows = multiple
          .whereType<Map>()
          .map((entry) {
            final item = Map<String, dynamic>.from(entry);
            final type = _leaveLabel(item['leaveType'] ?? item['type']);
            return (type, _allowance(item));
          })
          .where((row) => row.$1.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) return rows;
    }

    return [(_leaveLabel(policy['leaveType']), _allowance(policy))];
  }

  static List<(String, String)> _detailRows(Map<String, dynamic> policy) {
    final rows = <(String, String)>[];
    void add(String label, dynamic value) {
      final text = _value(value);
      if (text.isNotEmpty) rows.add((label, text));
    }

    add('Applicable To', policy['applicableTo']);
    add('Effective From', _humanDate(policy['startDate']));
    add('Effective Until', _humanDate(policy['endDate']));
    if (policy['carryForward'] == true) {
      final days = _value(policy['carryForwardDays']);
      add(
        'Carry Forward',
        days.isEmpty || days == '0' ? 'Allowed' : '$days days',
      );
    }
    add('Approval Required', policy['approvalRequired'] == true ? 'Yes' : 'No');
    add('Notice Period', policy['noticePeriod']);
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
    return paidStatus.isEmpty
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
