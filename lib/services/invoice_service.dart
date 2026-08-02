import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../utils/file_opener.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceService {
  static const int _maxCompanyStampBytes = 5 * 1024 * 1024;
  static const Duration _companyStampTimeout = Duration(seconds: 15);

  static Future<Uint8List> generatePayrollInvoice({
    required String employeeName,
    required String email,
    required String position,
    required String payPeriod,
    required String totalWorkDays,
    required String daysWorked,
    required String absents,
    required String leaves,
    required String overtimeAmount,
    required String salary,
    required String dailyRate,
    required String grossPay,
    required String overtimePay,
    required String absentDeduction,
    required String leaveDeduction,
    required String totalDeductions,
    required String netSalary,

    String companyName = 'HRMS Company',
    String companyAddress = 'Human Resource Management System',
    String companyEmail = 'hr@company.com',
    String companyPhone = '',
    String companyId = '',
    String? companyStampImageUrl,
    String paymentMethod = 'Company Payroll',
    String terms = 'Standard payroll terms apply.',
  }) async {
    final detectedCurrency = _detectCurrency(salary);
    final pdf = pw.Document();

    // ✅ Use BUILT-IN fonts - no external files needed
    final regularFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();

    final theme = pw.ThemeData.withFont(base: regularFont, bold: boldFont);

    final navy = PdfColor.fromHex('#111B4F');
    final appBlue = PdfColor.fromHex('#0247C4');
    final textColor = PdfColor.fromHex('#111B4F');
    final mutedText = PdfColor.fromHex('#586080');
    final lineColor = PdfColor.fromHex('#6B7398');
    final white = PdfColors.white;

    // ✅ Load & resize logo image for PDF
    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/app_icon.png');
      final rawBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final resized = img.copyResize(decoded, width: 56, height: 56);
        final pngBytes = Uint8List.fromList(img.encodePng(resized));
        logoImage = pw.MemoryImage(pngBytes);
      }
    } catch (_) {
      logoImage = null;
    }
    final companyStampBytes = await _loadCompanyStampBytes(
      companyStampImageUrl,
    );
    final companyStampImage = companyStampBytes == null
        ? null
        : pw.MemoryImage(companyStampBytes);

    final now = DateTime.now();

    final invoiceNumber =
        'PAY-${now.year}'
        '${_twoDigits(now.month)}'
        '${_twoDigits(now.day)}-'
        '${payPeriod.replaceAll(RegExp(r'[^0-9]'), '')}';

    final hasOvertime = _parseValue(overtimePay) > 0;
    final hasAbsentDeduction = _parseValue(absentDeduction) > 0;
    final hasLeaveDeduction = _parseValue(leaveDeduction) > 0;
    final hasDeductions = _parseValue(totalDeductions) > 0;

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 40),
        build: (context) {
          return [
            // ✅ Header with actual logo
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    logoImage != null
                        ? pw.SizedBox(
                            width: 32,
                            height: 32,
                            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                          )
                        : pw.Container(
                            width: 32,
                            height: 32,
                            decoration: pw.BoxDecoration(
                              color: appBlue,
                              borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(6),
                              ),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'H',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  color: white,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                    pw.SizedBox(width: 12),
                    pw.Text(
                      'HRMS',
                      style: pw.TextStyle(fontSize: 23, color: navy),
                    ),
                  ],
                ),
                pw.Text(
                  'PAYROLL INVOICE',
                  style: pw.TextStyle(
                    fontSize: 21,
                    color: appBlue,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 32),

            pw.Text(
              'Invoice No. $invoiceNumber',
              style: pw.TextStyle(fontSize: 9, color: textColor),
            ),

            pw.SizedBox(height: 7),

            pw.Text(
              _formatDate(now),
              style: pw.TextStyle(fontSize: 9, color: textColor),
            ),

            pw.SizedBox(height: 38),

            // Employer and Employee Info
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _informationBlock(
                    title: 'Employer',
                    titleColor: navy,
                    titleTextColor: white,
                    lines: [
                      companyName,
                      companyAddress,
                      if (companyEmail.trim().isNotEmpty) companyEmail,
                      if (companyPhone.trim().isNotEmpty) companyPhone,
                      if (companyId.trim().isNotEmpty) 'Company ID: $companyId',
                    ],
                    textColor: textColor,
                  ),
                ),

                pw.SizedBox(width: 54),

                pw.Expanded(
                  child: _informationBlock(
                    title: 'Employee',
                    titleColor: navy,
                    titleTextColor: white,
                    lines: [
                      employeeName,
                      position,
                      email,
                      'Pay period: $payPeriod',
                    ],
                    textColor: textColor,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 28),

            // ── Table ────────────────────────────────────────────────
            _tableHeader(navy: navy, white: white),

            _tableRow(
              description: 'Basic Salary - $daysWorked Payable Days',
              rate: _money(dailyRate, defaultCurrency: detectedCurrency),
              quantity: daysWorked,
              total: _money(grossPay, defaultCurrency: detectedCurrency),
              textColor: textColor,
              lineColor: lineColor,
            ),

            if (hasOvertime)
              _tableRow(
                description: 'Overtime Pay',
                rate: _money(overtimeAmount, defaultCurrency: detectedCurrency),
                quantity: '1',
                total: _money(overtimePay, defaultCurrency: detectedCurrency),
                textColor: textColor,
                lineColor: lineColor,
              ),

            if (hasAbsentDeduction)
              _tableRow(
                description: 'Absent Deduction',
                rate: _money(dailyRate, defaultCurrency: detectedCurrency),
                quantity: absents,
                total: '-${_money(absentDeduction, defaultCurrency: detectedCurrency)}',
                textColor: textColor,
                lineColor: lineColor,
              ),

            if (hasLeaveDeduction)
              _tableRow(
                description: 'Unpaid Leave Deduction',
                rate: _money(dailyRate, defaultCurrency: detectedCurrency),
                quantity: leaves,
                total: '-${_money(leaveDeduction, defaultCurrency: detectedCurrency)}',
                textColor: textColor,
                lineColor: lineColor,
              ),

            // Fill remaining rows so the table always has the same height
            if (!hasOvertime)
              _emptyTableRow(textColor: textColor, lineColor: lineColor),
            if (!hasAbsentDeduction)
              _emptyTableRow(textColor: textColor, lineColor: lineColor),
            if (!hasLeaveDeduction)
              _emptyTableRow(textColor: textColor, lineColor: lineColor),

            _emptyTableRow(textColor: textColor, lineColor: lineColor),

            pw.SizedBox(height: 18),

            // ── Summary Section ──────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        color: navy,
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: pw.Text(
                          'Payroll Information',
                          style: pw.TextStyle(fontSize: 8, color: white),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      _smallInfoLine(
                        'Payment Method',
                        paymentMethod,
                        textColor,
                      ),
                      _smallInfoLine(
                        'Contract Salary',
                        _money(salary, defaultCurrency: detectedCurrency),
                        textColor,
                      ),
                      _smallInfoLine(
                        'Payable Days',
                        daysWorked,
                        textColor,
                      ),
                      _smallInfoLine('Working Days', totalWorkDays, textColor),
                      _smallInfoLine('Absents', absents, textColor),
                      _smallInfoLine('Leaves', leaves, textColor),
                    ],
                  ),
                ),

                pw.SizedBox(width: 60),

                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _summaryLine('Gross Pay', _money(grossPay, defaultCurrency: detectedCurrency), textColor),
                      if (hasOvertime)
                        _summaryLine(
                          'Overtime Pay',
                          _money(overtimePay, defaultCurrency: detectedCurrency),
                          textColor,
                        ),
                      _summaryLine(
                        'Deductions',
                        hasDeductions
                            ? '-${_money(totalDeductions, defaultCurrency: detectedCurrency)}'
                            : _money('0', defaultCurrency: detectedCurrency),
                        textColor,
                      ),
                      pw.SizedBox(height: 8),

                      // Net Salary — navy highlight box
                      pw.Container(
                        color: navy,
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Net Salary',
                              style: pw.TextStyle(fontSize: 10, color: white),
                            ),
                            pw.Text(
                              _money(netSalary, defaultCurrency: detectedCurrency),
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: white,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: _companyAuthorization(
                companyName: companyName,
                companyId: companyId,
                stampImage: companyStampImage,
                color: appBlue,
                mutedColor: mutedText,
              ),
            ),
          ];
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: lineColor, height: 1, thickness: 0.5),
              pw.SizedBox(height: 8),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Thank you for your contribution!',
                  style: pw.TextStyle(fontSize: 14, color: appBlue),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Generated by HRMS',
                  style: pw.TextStyle(fontSize: 7, color: mutedText),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _informationBlock({
    required String title,
    required PdfColor titleColor,
    required PdfColor titleTextColor,
    required List<String> lines,
    required PdfColor textColor,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: titleColor,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: pw.Text(
            title,
            style: pw.TextStyle(fontSize: 8, color: titleTextColor),
          ),
        ),

        pw.SizedBox(height: 7),

        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 13),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: lines
                .where((line) => line.trim().isNotEmpty)
                .map(
                  (line) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Text(
                      line,
                      style: pw.TextStyle(fontSize: 8.5, color: textColor),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader({
    required PdfColor navy,
    required PdfColor white,
  }) {
    return pw.Container(
      color: navy,
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              'Description',
              style: pw.TextStyle(
                fontSize: 8.5,
                color: white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Rate',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Payable Days',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableRow({
    required String description,
    required String rate,
    required String quantity,
    required String total,
    required PdfColor textColor,
    required PdfColor lineColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: lineColor, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              description,
              style: pw.TextStyle(fontSize: 8.5, color: textColor),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                rate,
                style: pw.TextStyle(fontSize: 8, color: textColor),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                quantity,
                style: pw.TextStyle(fontSize: 8, color: textColor),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                total,
                style: pw.TextStyle(fontSize: 8, color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyTableRow({
    required PdfColor textColor,
    required PdfColor lineColor,
  }) {
    return _tableRow(
      description: '',
      rate: '',
      quantity: '',
      total: '',
      textColor: textColor,
      lineColor: lineColor,
    );
  }

  static pw.Widget _smallInfoLine(String label, String value, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 6, bottom: 4),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: 8, color: color),
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  static pw.Widget _summaryLine(String label, String value, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: color)),
          pw.Text(value, style: pw.TextStyle(fontSize: 8, color: color)),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  static String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  static String _money(String raw, {String? defaultCurrency}) {
    final trimmed = raw.trim();

    if (trimmed.isEmpty) {
      return '${defaultCurrency ?? 'Rs'} 0.00';
    }

    String prefix = defaultCurrency ?? 'Rs';

    final firstDigit = RegExp(r'\d').firstMatch(trimmed);

    if (firstDigit != null && firstDigit.start > 0) {
      final detected = trimmed
          .substring(0, firstDigit.start)
          .trim()
          .replaceAll('-', '')
          .trim();

      if (detected.isNotEmpty) {
        prefix = detected[0].toUpperCase() + detected.substring(1);
      }
    }

    final value = _parseValue(trimmed).abs();

    return '$prefix ${value.toStringAsFixed(2)}';
  }

  static String _detectCurrency(String salary) {
    final trimmed = salary.trim();
    if (trimmed.isEmpty) return 'Rs';
    final match = RegExp(r'\d').firstMatch(trimmed);
    if (match == null || match.start == 0) return 'Rs';
    final prefix = trimmed.substring(0, match.start).trim();
    if (prefix.isEmpty) return 'Rs';
    return prefix[0].toUpperCase() + prefix.substring(1);
  }

  static double _parseValue(String formatted) {
    final cleaned = formatted.replaceAll(RegExp(r'[^0-9.]'), '');

    final value = double.tryParse(cleaned) ?? 0;

    final suffixMatch = RegExp(r'[KMBTkmbt]').firstMatch(formatted);

    if (suffixMatch == null) {
      return value;
    }

    switch (suffixMatch.group(0)!.toUpperCase()) {
      case 'K':
        return value * 1000;

      case 'M':
        return value * 1000000;

      case 'B':
        return value * 1000000000;

      case 'T':
        return value * 1000000000000;

      default:
        return value;
    }
  }

  static pw.Widget _companyAuthorization({
    required String companyName,
    required String companyId,
    pw.MemoryImage? stampImage,
    required PdfColor color,
    required PdfColor mutedColor,
  }) {
    final cleanName = companyName.trim().isEmpty
        ? 'HRMS Company'
        : companyName.trim();
    final initials = cleanName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(3)
        .map((word) => word.substring(0, 1).toUpperCase())
        .join();

    return pw.SizedBox(
      width: 180,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (stampImage != null)
            pw.Container(
              width: 66,
              height: 54,
              alignment: pw.Alignment.center,
              child: pw.Image(stampImage, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(
              width: 54,
              height: 54,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: color, width: 1.5),
              ),
              child: pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      initials.isEmpty ? 'HRMS' : initials,
                      style: pw.TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'APPROVED',
                      style: pw.TextStyle(color: color, fontSize: 5),
                    ),
                  ],
                ),
              ),
            ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  cleanName,
                  style: pw.TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Container(height: 0.7, color: color),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Authorized Signatory',
                  style: pw.TextStyle(color: mutedColor, fontSize: 6),
                ),
                if (companyId.trim().isNotEmpty)
                  pw.Text(
                    'Company ID: ${companyId.trim()}',
                    style: pw.TextStyle(color: mutedColor, fontSize: 6),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List?> _loadCompanyStampBytes(String? source) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;

    Uint8List? bytes;
    try {
      if (value.startsWith('data:image/')) {
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
            encoded.length > ((_maxCompanyStampBytes * 4) ~/ 3) + 16) {
          return null;
        }
        bytes = base64Decode(encoded);
      } else {
        final uri = Uri.tryParse(value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          bytes = await _downloadCompanyStamp(uri);
        } else if (uri != null && uri.scheme == 'file') {
          bytes = await _readCompanyStampFile(File.fromUri(uri));
        } else {
          bytes = await _readCompanyStampFile(File(value));
          if (bytes == null) {
            final data = await rootBundle
                .load(value)
                .timeout(_companyStampTimeout);
            bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          }
        }
      }
    } catch (_) {
      return null;
    }

    if (bytes == null ||
        bytes.isEmpty ||
        bytes.lengthInBytes > _maxCompanyStampBytes) {
      return null;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return Uint8List.fromList(img.encodePng(decoded));
  }

  static Future<Uint8List?> _downloadCompanyStamp(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _companyStampTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_companyStampTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(_companyStampTimeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) return null;
      if (response.contentLength > _maxCompanyStampBytes) return null;

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(_companyStampTimeout)) {
        total += chunk.length;
        if (total > _maxCompanyStampBytes) return null;
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _readCompanyStampFile(File file) async {
    try {
      if (!await file.exists().timeout(_companyStampTimeout)) return null;
      final length = await file.length().timeout(_companyStampTimeout);
      if (length <= 0 || length > _maxCompanyStampBytes) return null;
      return await file.readAsBytes().timeout(_companyStampTimeout);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> shareInvoice(Uint8List bytes, String fileName) async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save Payroll Invoice',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
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
}
