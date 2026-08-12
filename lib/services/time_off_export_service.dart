import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/date_utils.dart';
import '../utils/file_opener.dart';
import '../utils/pdf_stamp_widget.dart';

class TimeOffExportService {
  TimeOffExportService._();

  static String _l(String key, String fallback) {
    final translated = key.tr().trim();
    return translated.isEmpty || translated == key ? fallback : translated;
  }

  static String _formatDate(dynamic value) {
    final dt = AppDateUtils.dateFromValue(value);
    if (dt == null) return (value ?? '').toString();
    return DateFormat('dd MMM yyyy').format(dt);
  }

  static String _extractDays(Map<String, dynamic> record) {
    final rawDays = record['days'] ?? record['numberOfDays'] ?? record['totalDays'];
    if (rawDays != null && rawDays.toString().trim().isNotEmpty) {
      return rawDays.toString().trim();
    }
    final dates = record['selectedDates'];
    if (dates is List && dates.isNotEmpty) {
      return dates.length.toString();
    }
    return '1';
  }

  static String generateCsvContent(List<Map<String, dynamic>> records) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Worker Name,Leave Type,From Date,To Date,Days,Status,Reason',
    );

    for (final record in records) {
      final name = (record['workerName'] ?? record['name'] ?? record['email'] ?? '').toString().replaceAll(',', ' ');
      final type = (record['leaveType'] ?? record['type'] ?? 'Leave').toString().replaceAll(',', ' ');
      final from = _formatDate(record['startDate'] ?? record['date']);
      final to = _formatDate(record['endDate'] ?? record['startDate'] ?? record['date']);
      final days = _extractDays(record);
      final status = (record['status'] ?? 'Approved').toString().replaceAll(',', ' ');
      final reason = (record['reason'] ?? record['description'] ?? '').toString().replaceAll(',', ' ').replaceAll('\n', ' ');

      buffer.writeln('"$name","$type","$from","$to","$days","$status","$reason"');
    }

    return buffer.toString();
  }

  static Future<bool> exportCsv({
    required List<Map<String, dynamic>> records,
    String fileName = 'time_off_records.csv',
  }) async {
    final content = generateCsvContent(records);
    final bytes = Uint8List.fromList(content.codeUnits);

    final result = await FilePicker.saveFile(
      dialogTitle: _l('export_time_off_records', 'Export Time Off Records'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );

    if (result == null || result.trim().isEmpty) return false;

    var outputPath = result.trim();
    if (!outputPath.toLowerCase().endsWith('.csv')) {
      outputPath = '$outputPath.csv';
    }

    await File(outputPath).writeAsString(content, flush: true);
    await FileOpener.open(outputPath);
    return true;
  }

  static Future<Uint8List> generatePdfReport({
    required List<Map<String, dynamic>> records,
    required String periodLabel,
    required String leaveTypeFilter,
    String companyName = 'HRMS Company',
  }) async {
    final pdf = pw.Document();

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

    final navy = PdfColor.fromHex('#111B4F');
    final appBlue = PdfColor.fromHex('#0247C4');
    final textColor = PdfColor.fromHex('#111B4F');
    final mutedText = PdfColor.fromHex('#586080');

    Uint8List? stampBytes = await loadDefaultHrStampBytes();
    final stampImage = stampBytes != null ? pw.MemoryImage(stampBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 40),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  companyName.isEmpty ? 'HRMS Company' : companyName,
                  style: pw.TextStyle(fontSize: 20, color: navy, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  _l('time_off_report_title', 'TIME OFF RECORDS REPORT'),
                  style: pw.TextStyle(
                    fontSize: 16,
                    color: appBlue,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_l('period', 'Period')}: $periodLabel | ${_l('type', 'Type')}: $leaveTypeFilter',
                  style: pw.TextStyle(fontSize: 10, color: mutedText),
                ),
                pw.Text(
                  '${_l('date', 'Date')}: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10, color: mutedText),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              context: context,
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              headerDecoration: pw.BoxDecoration(color: navy),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: pw.TextStyle(fontSize: 9, color: textColor),
              headers: [
                _l('worker_name', 'Worker Name'),
                _l('leave_type', 'Leave Type'),
                _l('from', 'From'),
                _l('to', 'To'),
                _l('days', 'Days'),
                _l('status', 'Status'),
              ],
              data: records.map((r) {
                final name = (r['workerName'] ?? r['name'] ?? r['email'] ?? '').toString();
                final type = (r['leaveType'] ?? r['type'] ?? 'Leave').toString();
                final from = _formatDate(r['startDate'] ?? r['date']);
                final to = _formatDate(r['endDate'] ?? r['startDate'] ?? r['date']);
                final days = _extractDays(r);
                final status = (r['status'] ?? 'Approved').toString();
                return [name, type, from, to, days, status];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  '${_l('total_records', 'Total Records')}: ${records.length}',
                  style: pw.TextStyle(fontSize: 10, color: navy, fontWeight: pw.FontWeight.bold),
                ),
                buildCompanyAuthorization(
                  companyName: companyName,
                  companyId: '',
                  stampImage: stampImage,
                  accentColor: navy,
                  mutedColor: mutedText,
                  authorizedSignatoryText: _l('authorized_signatory', 'Authorized Signatory'),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<bool> exportPdf({
    required List<Map<String, dynamic>> records,
    required String periodLabel,
    required String leaveTypeFilter,
    String companyName = 'HRMS Company',
    String fileName = 'time_off_records.pdf',
  }) async {
    final pdfBytes = await generatePdfReport(
      records: records,
      periodLabel: periodLabel,
      leaveTypeFilter: leaveTypeFilter,
      companyName: companyName,
    );

    final result = await FilePicker.saveFile(
      dialogTitle: _l('export_time_off_records', 'Export Time Off Records'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: pdfBytes,
    );

    if (result == null || result.trim().isEmpty) return false;

    var outputPath = result.trim();
    if (!outputPath.toLowerCase().endsWith('.pdf')) {
      outputPath = '$outputPath.pdf';
    }

    await File(outputPath).writeAsBytes(pdfBytes, flush: true);
    await FileOpener.open(outputPath);
    return true;
  }
}
