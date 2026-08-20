import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/services/time_off/time_off_service.dart';
import 'package:hrms/services/payroll/invoice_service.dart';

class TimeOffExportService {
  TimeOffExportService._();

  static String _formatDate(dynamic value) {
    final date = AppDateUtils.dateFromValue(value);
    return date == null ? '' : DateFormat('yyyy-MM-dd').format(date);
  }

  static String _extractDays(Map<String, dynamic> record) {
    final explicitDays = record['requestedDays'] ?? record['durationDays'];
    if (explicitDays != null && explicitDays.toString().trim().isNotEmpty) {
      return explicitDays.toString().trim();
    }

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

  static String _escapeCsvCell(dynamic value) {
    if (value == null) return '""';

    var text = value.toString().trim();
    if (text.isEmpty) return '""';

    if (text.startsWith('=') || text.startsWith('+') || text.startsWith('-') ||
        text.startsWith('@') || text.startsWith('\t') || text.startsWith('\r')) {
      text = "'$text";
    }

    final escaped = text.replaceAll('"', '""').replaceAll('\n', ' ');
    return '"$escaped"';
  }

  static String generateCsvContent(List<Map<String, dynamic>> records) {
    final activeRecords = records.where(TimeOffService.isActiveRecord).toList();
    final buffer = StringBuffer();

    buffer.writeln('Worker Name,Leave Type,From Date,To Date,Days,Status,Reason');

    for (final record in activeRecords) {
      final name = (record['workerName'] ?? record['name'] ?? record['email'] ?? '').toString();
      final type = TimeOffService.leaveType(record);
      final from = _formatDate(record['startDate'] ?? record['date']);
      final to = _formatDate(record['endDate'] ?? record['startDate'] ?? record['date']);
      final days = _extractDays(record);
      final status = (record['status'] ?? 'Approved').toString().trim();
      final reason = (record['notes'] ?? record['reason'] ?? record['description'] ?? '').toString();

      buffer.writeln(
        '${_escapeCsvCell(name)},${_escapeCsvCell(type)},${_escapeCsvCell(from)},'
        '${_escapeCsvCell(to)},${_escapeCsvCell(days)},${_escapeCsvCell(status)},'
        '${_escapeCsvCell(reason)}',
      );
    }

    return buffer.toString();
  }

  static Future<String?> exportCsv({
    required List<Map<String, dynamic>> records,
    String fileName = 'time_off_records.csv',
  }) async {
    final content = generateCsvContent(records);
    final bytes = Uint8List.fromList(utf8.encode(content));

    final result = await FilePicker.saveFile(
      dialogTitle: PdfHelpers.translate('export_time_off_records', 'Export Time Off Records'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );

    if (result == null || result.toString().trim().isEmpty) return null;

    var outputPath = result.toString().trim();
    if (!outputPath.toLowerCase().endsWith('.csv')) {
      outputPath = '$outputPath.csv';
    }

    await File(outputPath).writeAsString(content, flush: true);
    await FileOpener.open(outputPath);
    return outputPath;
  }

  static Future<Uint8List> generatePdfReport({
    required List<Map<String, dynamic>> records,
    required String periodLabel,
    required String leaveTypeFilter,
    String companyName = 'HRMS',
    String? companyStampImageUrl,
    Uint8List? companyStampBytes,
  }) async {
    final activeRecords = records.where(TimeOffService.isActiveRecord).toList();
    final pdf = pw.Document();
    final theme = await PdfHelpers.loadTheme();

    final navy = PdfColorPalette.navy;
    final appBlue = PdfColorPalette.appBlue;
    final textColor = PdfColorPalette.textColor;
    final mutedText = PdfColorPalette.mutedText;

    Uint8List? stampBytes = companyStampBytes;
    if (stampBytes == null && (companyStampImageUrl ?? '').trim().isNotEmpty) {
      try {
        stampBytes = await InvoiceService.resolveCompanyStampBytes(companyStampImageUrl);
      } catch (_) {}
    }
    stampBytes ??= await loadDefaultHrStampBytes();
    final stampImage = stampBytes != null ? pw.MemoryImage(stampBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 40),
        build: (context) {
          return [
            _buildHeader(companyName, navy, appBlue),
            _buildSubHeader(periodLabel, leaveTypeFilter, mutedText),
            _buildTable(context, activeRecords, navy, textColor),
            _buildFooter(activeRecords.length, companyName, stampImage, navy, mutedText),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(String companyName, PdfColor navy, PdfColor appBlue) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          companyName.isEmpty ? 'HRMS' : companyName,
          style: pw.TextStyle(fontSize: 20, color: navy, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          PdfHelpers.translate('time_off_report_title', 'TIME OFF RECORDS REPORT'),
          style: pw.TextStyle(fontSize: 16, color: appBlue, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _buildSubHeader(String periodLabel, String leaveTypeFilter, PdfColor mutedText) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${PdfHelpers.translate('period', 'Period')}: $periodLabel | ${PdfHelpers.translate('type', 'Type')}: $leaveTypeFilter',
              style: pw.TextStyle(fontSize: 10, color: mutedText),
            ),
            pw.Text(
              '${PdfHelpers.translate('date', 'Date')}: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 10, color: mutedText),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTable(
    pw.Context context,
    List<Map<String, dynamic>> records,
    PdfColor navy,
    PdfColor textColor,
  ) {
    return pw.Column(
      children: [
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
            PdfHelpers.translate('worker_name', 'Worker Name'),
            PdfHelpers.translate('leave_type', 'Leave Type'),
            PdfHelpers.translate('from', 'From'),
            PdfHelpers.translate('to', 'To'),
            PdfHelpers.translate('days', 'Days'),
            PdfHelpers.translate('status', 'Status'),
          ],
          data: records.map((r) {
            final name = (r['workerName'] ?? r['name'] ?? r['email'] ?? '').toString();
            final type = TimeOffService.leaveType(r);
            final from = _formatDate(r['startDate'] ?? r['date']);
            final to = _formatDate(r['endDate'] ?? r['startDate'] ?? r['date']);
            final days = _extractDays(r);
            final status = (r['status'] ?? 'Approved').toString();
            return [name, type, from, to, days, status];
          }).toList(),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(
    int recordCount,
    String companyName,
    pw.MemoryImage? stampImage,
    PdfColor navy,
    PdfColor mutedText,
  ) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '${PdfHelpers.translate('total_records', 'Total Records')}: $recordCount',
              style: pw.TextStyle(fontSize: 10, color: navy, fontWeight: pw.FontWeight.bold),
            ),
            buildCompanyAuthorization(
              companyName: companyName,
              companyId: '',
              stampImage: stampImage,
              accentColor: navy,
              mutedColor: mutedText,
              authorizedSignatoryText: PdfHelpers.translate('authorized_signatory', 'Authorized Signatory'),
            ),
          ],
        ),
      ],
    );
  }
}