import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';

class InvoiceService {
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
  }) async {
    final pdf = pw.Document();

    final PdfColor primaryNavy = PdfColor.fromHex('#16215B');
    final PdfColor appBlue = PdfColor.fromHex('#0247C4');
    final PdfColor textColor = PdfColor.fromHex('#16215B');
    final PdfColor lineColor = PdfColor.fromHex('#8B93B8');
    const double fontSize = 10;

    // Load app logo
    pw.Image? appLogo;
    try {
      final byteData = await rootBundle.load('assets/app_icon.png');
      final bytes = byteData.buffer.asUint8List();
      final image = pw.MemoryImage(bytes);
      appLogo = pw.Image(image, width: 40, height: 40);
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(45, 50, 45, 50),
        build: (context) => [
          // ── 1. HEADER ROW (Logo & INVOICE) ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  if (appLogo != null) appLogo,
                  pw.SizedBox(width: 12),
                  pw.Text(
                    'HRMS',
                    style: pw.TextStyle(
                      fontSize: 28,
                      color: primaryNavy,
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
              pw.Text(
                'INVOICE',
                style: pw.TextStyle(
                  fontSize: 24,
                  color: appBlue,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 40),

          // ── 2. INVOICE DETAILS ──
          pw.Text(
            'Invoice N $payPeriod',
            style: pw.TextStyle(color: textColor, fontSize: fontSize),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _formatDate(DateTime.now()),
            style: pw.TextStyle(color: textColor, fontSize: fontSize),
          ),
          pw.SizedBox(height: 40),

          // ── 3. ADDRESS BLOCKS ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _buildAddressBlock(
                  primaryNavy,
                  textColor,
                  fontSize,
                  'Bill From',
                  'HRMS Company',
                  '123 Street, City, State',
                  '23123',
                  '+00 000 000 000',
                ),
              ),
              pw.SizedBox(width: 40),
              pw.Expanded(
                child: _buildAddressBlock(
                  primaryNavy,
                  textColor,
                  fontSize,
                  'Bill To',
                  employeeName,
                  email,
                  'Position: $position',
                  '',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 35),

          // ── 4. ITEMS TABLE ──
          // Table Header
          pw.Container(
            color: primaryNavy,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.Text('Description', style: _headerStyle(fontSize))),
                pw.Expanded(flex: 2, child: pw.Center(child: pw.Text('Rate', style: _headerStyle(fontSize)))),
                pw.Expanded(flex: 2, child: pw.Center(child: pw.Text('Qty', style: _headerStyle(fontSize)))),
                pw.Expanded(flex: 2, child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('Total', style: _headerStyle(fontSize)),
                )),
              ],
            ),
          ),
          // Table Rows
          _buildTableRow(lineColor, textColor, fontSize, 'Basic Salary', dailyRate, daysWorked, grossPay),
          _buildTableRow(lineColor, textColor, fontSize, 'Overtime', overtimePay, '1', overtimePay),
          _buildTableRow(lineColor, textColor, fontSize, 'Absent Deduction', absentDeduction, absents, absentDeduction),
          _buildTableRow(lineColor, textColor, fontSize, 'Leave Deduction', leaveDeduction, leaves, leaveDeduction),
          _buildTableRow(lineColor, textColor, fontSize, 'Total Deductions', '', '', totalDeductions),
          pw.SizedBox(height: 20),

          // ── 5. PAYMENT & TOTALS ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Payment Info (Left)
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      color: primaryNavy,
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: pw.Text(
                        'Payment Info',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: fontSize, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Bank Account', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                          pw.SizedBox(height: 4),
                          pw.Text('ER73829 27382 28338', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                          pw.SizedBox(height: 4),
                          pw.Text('Pay Period', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                          pw.Text(payPeriod, style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 40),
              // Totals (Right)
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Subtotal', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                          pw.Text(_extractNumeric(grossPay), style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Tax', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                          pw.Text(r'$0.00', style: pw.TextStyle(color: textColor, fontSize: fontSize)),
                        ],
                      ),
                    ),
                    pw.Container(
                      width: double.infinity,
                      color: primaryNavy,
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total',
                            style: pw.TextStyle(color: PdfColors.white, fontSize: fontSize, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            _extractNumeric(netSalary),
                            style: pw.TextStyle(color: PdfColors.white, fontSize: fontSize, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 50),

          // ── 6. FOOTER (Thank you) ──
          pw.SizedBox(height: 40),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10),
            child: pw.Text(
              'Thank you!',
              style: pw.TextStyle(
                fontSize: 26,
                color: appBlue,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildAddressBlock(
    PdfColor primaryNavy,
    PdfColor textColor,
    double fontSize,
    String title,
    String name,
    String address,
    String zip,
    String phone,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: primaryNavy,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Text(
            title,
            style: pw.TextStyle(color: PdfColors.white, fontSize: fontSize, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: pw.TextStyle(color: textColor, fontSize: fontSize)),
              pw.Text(address, style: pw.TextStyle(color: textColor, fontSize: fontSize)),
              pw.Text(zip, style: pw.TextStyle(color: textColor, fontSize: fontSize)),
              if (phone.isNotEmpty) pw.Text(phone, style: pw.TextStyle(color: textColor, fontSize: fontSize)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.TextStyle _headerStyle(double fontSize) {
    return pw.TextStyle(
      color: PdfColors.white,
      fontSize: fontSize,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static pw.TextStyle _cellStyle(PdfColor textColor, double fontSize) {
    return pw.TextStyle(color: textColor, fontSize: fontSize);
  }

  static pw.Widget _buildTableRow(
    PdfColor lineColor,
    PdfColor textColor,
    double fontSize,
    String desc,
    String rate,
    String qty,
    String total,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: lineColor, width: 0.8)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text(desc, style: _cellStyle(textColor, fontSize))),
          pw.Expanded(flex: 2, child: pw.Center(child: pw.Text(rate.isNotEmpty ? rate : '-', style: _cellStyle(textColor, fontSize)))),
          pw.Expanded(flex: 2, child: pw.Center(child: pw.Text(qty.isNotEmpty ? qty : '-', style: _cellStyle(textColor, fontSize)))),
          pw.Expanded(flex: 2, child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(total.isNotEmpty ? total : '-', style: _cellStyle(textColor, fontSize)),
          )),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final day = date.day;
    final suffix = day >= 11 && day <= 13 ? 'th'
        : day % 10 == 1 ? 'st'
        : day % 10 == 2 ? 'nd'
        : day % 10 == 3 ? 'rd'
        : 'th';
    return '${months[date.month - 1]}. $day$suffix, ${date.year}';
  }

  /// Extracts numeric portion preserving the original currency symbol.
  static String _extractNumeric(String formatted) {
    if (formatted.isEmpty) return r'$0.00';
    // Detect currency symbol: everything before the first digit
    String currency = r'$';
    final digitMatch = RegExp(r'\d').firstMatch(formatted);
    if (digitMatch != null && digitMatch.start > 0) {
      currency = formatted.substring(0, digitMatch.start).trim();
      if (currency.isEmpty) currency = r'$';
    }
    // Remove currency symbols and commas, keep the number
    final cleaned = formatted.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return '$currency 0.00';
    final value = double.tryParse(cleaned);
    if (value == null) return '$currency 0.00';
    if (value == value.roundToDouble()) {
      return '$currency ${value.round()}';
    }
    return '$currency ${value.toStringAsFixed(2)}';
  }

  static Future<void> shareInvoice(Uint8List bytes, String fileName) async {
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save Invoice',
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
}
