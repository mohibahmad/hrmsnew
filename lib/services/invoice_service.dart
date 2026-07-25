import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
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

    final PdfColor primaryBlue = PdfColor.fromHex('#172052');
    final PdfColor primaryRed = PdfColor.fromHex('#D7232B');
    final PdfColor textColor = PdfColor.fromHex('#172052');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(45, 50, 45, 50),
        build: (context) => [
          // 1. Header (Logo & INVOICE)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    width: 28,
                    height: 28,
                    color: primaryRed,
                  ),
                  pw.SizedBox(width: 15),
                  pw.Text(
                    'logo',
                    style: pw.TextStyle(
                      fontSize: 32,
                      color: primaryBlue,
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
              pw.Text(
                'INVOICE',
                style: pw.TextStyle(
                  fontSize: 26,
                  color: primaryRed,
                  fontWeight: pw.FontWeight.normal,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 35),

          // 2. Invoice Details (Number & Date)
          pw.Text(
            'Invoice N $payPeriod',
            style: pw.TextStyle(color: textColor, fontSize: 11),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _formatDate(DateTime.now()),
            style: pw.TextStyle(color: textColor, fontSize: 11),
          ),
          pw.SizedBox(height: 40),

          // 3. Billing Addresses (Bill From & Bill To)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _buildAddressBlock(
                  primaryBlue,
                  textColor,
                  'Bill From',
                  'HRMS Company',
                  '123 Street, City, State',
                  '23123',
                  '+00 000 000 000',
                ),
              ),
              pw.SizedBox(width: 60),
              pw.Expanded(
                child: _buildAddressBlock(
                  primaryBlue,
                  textColor,
                  'Bill To',
                  employeeName,
                  email,
                  'Position: $position',
                  '',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // Employee Info Detail Row (attendance data)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: primaryBlue, width: 0.5),
            ),
            child: pw.Row(
              children: [
                _infoCell('Work Days', totalWorkDays),
                _infoCell('Days Worked', daysWorked),
                _infoCell('Absents', absents),
                _infoCell('Leaves', leaves),
                _infoCell('Overtime', overtimeAmount),
                pw.Expanded(child: _infoCell('Salary', salary)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // 4. Table Header
          pw.Container(
            color: primaryBlue,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.Text('Description', style: _headerStyle())),
                pw.Expanded(flex: 2, child: pw.Center(child: pw.Text('Rate', style: _headerStyle()))),
                pw.Expanded(flex: 2, child: pw.Center(child: pw.Text('Qty', style: _headerStyle()))),
                pw.Expanded(flex: 2, child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('Total', style: _headerStyle()),
                )),
              ],
            ),
          ),

          // 5. Table Rows
          _buildTableRow(primaryBlue, textColor, 'Basic Salary', dailyRate, daysWorked, grossPay),
          _buildTableRow(primaryBlue, textColor, 'Overtime', overtimePay, '1', overtimePay),
          _buildTableRow(primaryBlue, textColor, 'Absent Deduction', absentDeduction, absents, absentDeduction),
          _buildTableRow(primaryBlue, textColor, 'Leave Deduction', leaveDeduction, leaves, leaveDeduction),
          _buildTableRow(primaryBlue, textColor, 'Total Deductions', '', '', totalDeductions),

          pw.SizedBox(height: 20),

          // 6. Payment Info & Totals
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Payment Info Left Side
              pw.Expanded(
                flex: 10,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      color: primaryBlue,
                      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                      child: pw.Text(
                        'Payment Info',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Bank Account', style: pw.TextStyle(color: textColor, fontSize: 11)),
                          pw.SizedBox(height: 5),
                          pw.Text('ER73829 27382 28338', style: pw.TextStyle(color: textColor, fontSize: 11)),
                          pw.SizedBox(height: 5),
                          pw.Text('Pay Period', style: pw.TextStyle(color: textColor, fontSize: 11)),
                          pw.SizedBox(height: 5),
                          pw.Text(payPeriod, style: pw.TextStyle(color: textColor, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Expanded(flex: 3, child: pw.SizedBox()),
              // Totals Right Side
              pw.Expanded(
                flex: 9,
                child: pw.Column(
                  children: [
                    _buildTotalRow(textColor, 'Subtotal', _extractNumeric(grossPay)),
                    pw.SizedBox(height: 8),
                    _buildTotalRow(textColor, 'Tax', '\$0.00'),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      color: primaryBlue,
                      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total',
                            style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
                          ),
                          pw.Text(
                            _extractNumeric(netSalary),
                            style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
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

          // 7. Thank You text
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 35),
            child: pw.Text(
              'Thank you!',
              style: pw.TextStyle(
                fontSize: 28,
                color: primaryRed,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
          pw.SizedBox(height: 25),

          // 8. Terms and Conditions
          pw.Text(
            'Terms and conditions',
            style: pw.TextStyle(color: textColor, fontSize: 11),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'This invoice is for payroll services rendered for the period of $payPeriod. '
            'Payment is due immediately upon receipt. Please contact HR for any discrepancies.',
            style: pw.TextStyle(color: textColor, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildAddressBlock(
    PdfColor primaryBlue,
    PdfColor textColor,
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
          color: primaryBlue,
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          child: pw.Text(
            title,
            style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: pw.TextStyle(color: textColor, fontSize: 11)),
              if (address.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(address, style: pw.TextStyle(color: textColor, fontSize: 11)),
              ],
              if (zip.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(zip, style: pw.TextStyle(color: textColor, fontSize: 11)),
              ],
              if (phone.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(phone, style: pw.TextStyle(color: textColor, fontSize: 11)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static pw.TextStyle _headerStyle() {
    return pw.TextStyle(
      color: PdfColors.white,
      fontSize: 11,
      fontWeight: pw.FontWeight.normal,
    );
  }

  static pw.TextStyle _cellStyle(PdfColor textColor) {
    return pw.TextStyle(color: textColor, fontSize: 11);
  }

  static pw.Widget _buildTableRow(
    PdfColor primaryBlue,
    PdfColor textColor,
    String desc,
    String rate,
    String qty,
    String total,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: primaryBlue, width: 0.8)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text(desc, style: _cellStyle(textColor))),
          pw.Expanded(flex: 2, child: pw.Center(child: pw.Text(rate.isNotEmpty ? rate : '-', style: _cellStyle(textColor)))),
          pw.Expanded(flex: 2, child: pw.Center(child: pw.Text(qty.isNotEmpty ? qty : '-', style: _cellStyle(textColor)))),
          pw.Expanded(flex: 2, child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(total.isNotEmpty ? total : '-', style: _cellStyle(textColor)),
          )),
        ],
      ),
    );
  }

  static pw.Widget _infoCell(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#6B7280'),
              fontWeight: pw.FontWeight.normal,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value.isNotEmpty ? value : '-',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#172052'),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTotalRow(PdfColor textColor, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(color: textColor, fontSize: 11)),
          pw.Text(value, style: pw.TextStyle(color: textColor, fontSize: 11)),
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
    // Determine currency symbol from original string
    String currency = r'$';
    if (formatted.startsWith('Rs') || formatted.startsWith('rs') || formatted.startsWith('RS')) {
      currency = 'Rs ';
    } else if (formatted.startsWith(r'$')) {
      currency = r'$';
    }
    // Remove currency symbols and commas, keep the number
    final cleaned = formatted.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return '${currency}0.00';
    final value = double.tryParse(cleaned);
    if (value == null) return '${currency}0.00';
    if (value == value.roundToDouble()) {
      return '$currency${value.round()}';
    }
    return '$currency${value.toStringAsFixed(2)}';
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
