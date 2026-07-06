import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
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
    required String overtimeDays,
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

    final greenColor = PdfColor.fromHex('#27AE60');
    final blueColor = PdfColor.fromHex('#0247C4');
    final greyColor = PdfColor.fromHex('#6B7280');
    final lightGrey = PdfColor.fromHex('#F3F4F6');
    final borderColor = PdfColor.fromHex('#E5E7EB');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PAYROLL INVOICE',
                    style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                      color: blueColor,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Pay Period: $payPeriod',
                    style: pw.TextStyle(fontSize: 12, color: greyColor),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: greenColor,
                  borderRadius: pw.BorderRadius.circular(20),
                ),
                child: pw.Text(
                  'PAID',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: lightGrey,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: borderColor),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Employee Details',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: blueColor,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      _infoRow('Name', employeeName),
                      _infoRow('Email', email),
                      _infoRow('Position', position),
                    ],
                  ),
                ),
                pw.SizedBox(width: 30),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Attendance',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: blueColor,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      _infoRow('Total Work Days', totalWorkDays),
                      _infoRow('Days Worked', daysWorked),
                      _infoRow('Absents', absents),
                      _infoRow('Leaves', leaves),
                      _infoRow('Overtime Days', overtimeDays),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          pw.Text(
            'Salary Breakdown',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: blueColor,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: borderColor),
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
          pw.SizedBox(height: 20),

          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: pw.BoxDecoration(
              color: blueColor,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'NET SALARY',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  netSalary,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),

          pw.Center(
            child: pw.Text(
              'Generated on ${DateTime.now().toString().substring(0, 10)}',
              style: pw.TextStyle(fontSize: 10, color: greyColor),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#6B7280')),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : '-',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.TableRow _tableHeaderRow(String col1, String col2) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F3F4F6')),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(
            col1,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(
            col2,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
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
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Text(
            value.isNotEmpty ? value : r'$0',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  static Future<File> saveInvoice(Uint8List bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<void> shareInvoice(Uint8List bytes, String fileName) async {
    final file = await saveInvoice(bytes, fileName);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Payroll Invoice - $fileName',
      ),
    );
  }
}
