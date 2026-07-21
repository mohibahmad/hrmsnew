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

    final primaryColor = PdfColor.fromHex('#0247C4');
    final accentColor = PdfColor.fromHex('#27AE60');
    final greyColor = PdfColor.fromHex('#6B7280');
    final lightBg = PdfColor.fromHex('#F8F9FA');
    final borderColor = PdfColor.fromHex('#DEE2E6');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        build: (context) => [
          _buildHeader(primaryColor, accentColor, greyColor, payPeriod),
          pw.SizedBox(height: 24),
          _buildEmployeeSection(primaryColor, lightBg, borderColor, employeeName, email, position, totalWorkDays, daysWorked, absents, leaves, overtimeAmount),
          pw.SizedBox(height: 24),
          _buildSalarySection(primaryColor, lightBg, borderColor, dailyRate, grossPay, overtimePay, absentDeduction, leaveDeduction, totalDeductions),
          pw.SizedBox(height: 20),
          _buildNetSalary(netSalary, primaryColor),
          pw.SizedBox(height: 24),
          _buildFooter(greyColor),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(PdfColor primaryColor, PdfColor accentColor, PdfColor greyColor, String payPeriod) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 10,
                  height: 36,
                  decoration: pw.BoxDecoration(
                    color: primaryColor,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Pay Period: $payPeriod',
              style: pw.TextStyle(fontSize: 12, color: greyColor, letterSpacing: 0.5),
            ),
          ],
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: pw.BoxDecoration(
            color: accentColor,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            'PAID',
            style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildEmployeeSection(PdfColor primaryColor, PdfColor lightBg, PdfColor borderColor, String name, String email, String position, String totalWorkDays, String daysWorked, String absents, String leaves, String overtimeAmount) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: lightBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Text(
              'Employee Information',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
                letterSpacing: 1,
              ),
            ),
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _infoRow('Employee Name', name),
                    _infoRow('Email Address', email),
                    _infoRow('Position', position),
                  ],
                ),
              ),
              pw.SizedBox(width: 30),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _infoRow('Total Work Days', totalWorkDays),
                    _infoRow('Days Worked', daysWorked),
                    _infoRow('Absents', absents),
                    _infoRow('Leaves', leaves),
                    _infoRow('Overtime Amount', overtimeAmount),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 12, color: PdfColor.fromHex('#6B7280')),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : '-',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1F2937')),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSalarySection(PdfColor primaryColor, PdfColor lightBg, PdfColor borderColor, String dailyRate, String grossPay, String overtimePay, String absentDeduction, String leaveDeduction, String totalDeductions) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Text(
              'Salary Breakdown',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
                letterSpacing: 1,
              ),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: borderColor, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
            },
            children: [
              _tableHeaderRow('Description', 'Amount'),
              _tableRow('Daily Rate', dailyRate),
              _tableRow('Gross Pay', grossPay),
              _tableRow('Overtime Pay', overtimePay),
              _tableRow('Absent Deduction', absentDeduction),
              _tableRow('Leave Deduction', leaveDeduction),
              _tableRow('Total Deductions', totalDeductions),
            ],
          ),
        ],
      ),
    );
  }

  static pw.TableRow _tableHeaderRow(String col1, String col2) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F0F4FF'),
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(
            col1,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0247C4')),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(
            col2,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0247C4')),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  static pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: pw.Text(label, style: pw.TextStyle(fontSize: 13, color: PdfColor.fromHex('#374151'))),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: pw.Text(
            value.isNotEmpty ? value : r'$0',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1F2937')),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildNetSalary(String netSalary, PdfColor primaryColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: pw.BoxDecoration(
        color: primaryColor,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'NET SALARY',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Total amount payable',
                style: pw.TextStyle(fontSize: 12, color: PdfColor.fromHex('#BBDEFB')),
              ),
            ],
          ),
          pw.Text(
            netSalary,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(PdfColor greyColor) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColor.fromHex('#DEE2E6'), thickness: 0.5),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Thank you for your business',
              style: pw.TextStyle(fontSize: 11, color: greyColor, fontStyle: pw.FontStyle.italic),
            ),
            pw.Text(
              'Generated on ${DateTime.now().toString().substring(0, 10)}',
              style: pw.TextStyle(fontSize: 11, color: greyColor),
            ),
          ],
        ),
      ],
    );
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
