import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hrms/core/utils/image_loader.dart';
import 'package:hrms/core/utils/utils.dart';
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
    required String absents,
    required String leaves,
    String paidLeaves = '',
    String unpaidLeaves = '',
    required String overtimeAmount,
    required String salary,
    required String dailyRate,
    required String grossPay,
    required String overtimePay,
    required String absentDeduction,
    required String leaveDeduction,
    required String totalDeductions,
    required String netSalary,
    required String currency,
    String invoiceNo = '',
    String companyName = 'HRMS',
    String companyAddress = 'Human Resource Management System',
    String companyEmail = 'hr@company.com',
    String companyPhone = '',
    String companyId = '',
    String? companyStampImageUrl,
    String? companyLogoUrl,
    Uint8List? companyLogoBytes,
    Uint8List? companyStampBytes,
    Uint8List? fontBytes,
    String paymentMethod = 'Company Payroll',
    String workerId = '',
    Uint8List? employeeImageBytes,
  }) async {
    final detectedCurrency = _displayCurrency(currency.isEmpty ? _detectCurrency(salary) : currency);
    final pdf = pw.Document(deflate: (bytes) => bytes);

    final font = await _loadFont(fontBytes);
    final theme = _createTheme(font);

    final logoImage = await _loadLogo(companyLogoBytes, companyLogoUrl);
    final stampImage = await _loadStamp(companyStampBytes, companyStampImageUrl);
    final employeeImage = await _loadEmployeeImage(employeeImageBytes);

    final now = DateTime.now();
    final datePrefix = _periodDatePrefix(payPeriod);
    final invoiceNumber = _buildReadableInvoiceNumber(
      explicitInvoiceNumber: invoiceNo,
      datePrefix: datePrefix,
      workerId: workerId,
    );

    final invoiceLeaves = resolveInvoiceLeaveDays(leaves: leaves, paidLeaves: paidLeaves, unpaidLeaves: unpaidLeaves);
    final deductibleLeaveDays = _getDeductibleLeaveDays(unpaidLeaves, leaves);

    final hasOvertime = _parseValue(overtimePay) > 0;
    final hasAbsentDeduction = _parseValue(absentDeduction) > 0 && _parseValue(absents) > 0;
    final hasLeaveDeduction = _parseValue(leaveDeduction) > 0 && _parseValue(deductibleLeaveDays) > 0;
    final hasDeductions = _parseValue(totalDeductions) > 0;
    final isNegativeNet = _parseValue(netSalary) < 0;

    final sanitizedPayPeriod = cleanText(payPeriod);
    final sanitizedCompanyName = cleanText(companyName);
    final sanitizedCompanyAddress = cleanText(companyAddress);
    final sanitizedCompanyEmail = cleanText(companyEmail);
    final sanitizedCompanyPhone = cleanText(companyPhone);
    final sanitizedCompanyId = cleanText(companyId);
    final sanitizedEmployeeName = cleanText(employeeName);
    final sanitizedPosition = cleanText(position);
    final sanitizedEmail = cleanText(email);
    final sanitizedInvoiceNumber = cleanText(invoiceNumber);
    final sanitizedDetectedCurrency = cleanText(detectedCurrency);
    final sanitizedDailyRate = cleanText(dailyRate);
    final sanitizedTotalWorkDays = cleanText(totalWorkDays);
    final sanitizedGrossPay = cleanText(grossPay);
    final sanitizedOvertimeAmount = cleanText(overtimeAmount);
    final sanitizedOvertimePay = cleanText(overtimePay);
    final sanitizedAbsentDeduction = cleanText(absentDeduction);
    final sanitizedAbsents = cleanText(absents);
    final sanitizedLeaveDeduction = cleanText(leaveDeduction);
    final sanitizedDeductibleLeaveDays = cleanText(deductibleLeaveDays);
    final sanitizedTotalDeductions = cleanText(totalDeductions);
    final sanitizedNetSalary = cleanText(netSalary);
    final sanitizedSalary = cleanText(salary);
    final sanitizedInvoiceLeaves = cleanText(invoiceLeaves);
    final sanitizedPaymentMethod = cleanText(paymentMethod);

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            ..._buildContent(
              logoImage: logoImage,
              stampImage: stampImage,
              employeeImage: employeeImage,
              companyName: sanitizedCompanyName,
              companyAddress: sanitizedCompanyAddress,
              companyEmail: sanitizedCompanyEmail,
              companyPhone: sanitizedCompanyPhone,
              companyId: sanitizedCompanyId,
              employeeName: sanitizedEmployeeName,
              position: sanitizedPosition,
              email: sanitizedEmail,
              payPeriod: sanitizedPayPeriod,
              invoiceNumber: sanitizedInvoiceNumber,
              now: now,
              detectedCurrency: sanitizedDetectedCurrency,
              dailyRate: sanitizedDailyRate,
              totalWorkDays: sanitizedTotalWorkDays,
              grossPay: sanitizedGrossPay,
              hasOvertime: hasOvertime,
              overtimeAmount: sanitizedOvertimeAmount,
              overtimePay: sanitizedOvertimePay,
              hasAbsentDeduction: hasAbsentDeduction,
              absentDeduction: sanitizedAbsentDeduction,
              absents: sanitizedAbsents,
              hasLeaveDeduction: hasLeaveDeduction,
              leaveDeduction: sanitizedLeaveDeduction,
              deductibleLeaveDays: sanitizedDeductibleLeaveDays,
              hasDeductions: hasDeductions,
              totalDeductions: sanitizedTotalDeductions,
              netSalary: sanitizedNetSalary,
              isNegativeNet: isNegativeNet,
              salary: sanitizedSalary,
              invoiceLeaves: sanitizedInvoiceLeaves,
              paymentMethod: sanitizedPaymentMethod,
            ),
            pw.Spacer(),
            _buildFooter(),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static String cleanText(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAll('–', '-') // en-dash U+2013 -> ASCII hyphen
        .replaceAll('—', '-') // em-dash U+2014 -> ASCII hyphen
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll('×', 'x')
        .replaceAll('→', '->')
        .replaceAll('₹', 'Rs ')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('\u200B', '');
  }


  static Future<pw.MemoryImage?> _loadEmployeeImage(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _getDeductibleLeaveDays(String unpaidLeaves, String leaves) {
    return unpaidLeaves.trim().isNotEmpty ? unpaidLeaves.trim() : leaves;
  }

  static pw.Font? _cachedParsedFont;
  static pw.ThemeData? _cachedTheme;
  static pw.MemoryImage? _cachedLogoImage;
  static pw.MemoryImage? _cachedStampImage;

  static void warmupCache({
    Uint8List? fontBytes,
    Uint8List? logoBytes,
    Uint8List? stampBytes,
  }) {
    if (fontBytes != null && fontBytes.isNotEmpty && _cachedParsedFont == null) {
      try {
        final font = pw.Font.ttf(
          fontBytes.buffer.asByteData(fontBytes.offsetInBytes, fontBytes.lengthInBytes),
        );
        _cachedParsedFont = font;
        _cachedTheme = PdfHelpers.buildTheme(font);
      } catch (_) {}
    }
    if (logoBytes != null && logoBytes.isNotEmpty && _cachedLogoImage == null) {
      try {
        _cachedLogoImage = pw.MemoryImage(logoBytes);
      } catch (_) {}
    }
    if (stampBytes != null && stampBytes.isNotEmpty && _cachedStampImage == null) {
      try {
        _cachedStampImage = pw.MemoryImage(stampBytes);
      } catch (_) {}
    }
  }

  static Future<pw.Font?> _loadFont(Uint8List? fontBytes) async {
    if (_cachedParsedFont != null) return _cachedParsedFont;
    if (fontBytes != null && fontBytes.isNotEmpty) {
      try {
        final font = pw.Font.ttf(
          fontBytes.buffer.asByteData(fontBytes.offsetInBytes, fontBytes.lengthInBytes),
        );
        _cachedParsedFont = font;
        return font;
      } catch (_) {}
    }
    return null;
  }

  static pw.ThemeData _createTheme(pw.Font? font) {
    if (_cachedTheme != null) return _cachedTheme!;
    final theme = PdfHelpers.buildTheme(font);
    _cachedTheme = theme;
    return theme;
  }

  static Future<pw.MemoryImage?> _loadLogo(Uint8List? companyLogoBytes, String? companyLogoUrl) async {
    if (_cachedLogoImage != null) return _cachedLogoImage;
    if (companyLogoBytes != null && companyLogoBytes.isNotEmpty) {
      try {
        final image = pw.MemoryImage(companyLogoBytes);
        _cachedLogoImage = image;
        return image;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Future<pw.MemoryImage?> _loadStamp(Uint8List? companyStampBytes, String? companyStampImageUrl) async {
    if (_cachedStampImage != null) return _cachedStampImage;
    if (companyStampBytes != null && companyStampBytes.isNotEmpty) {
      try {
        final image = pw.MemoryImage(companyStampBytes);
        _cachedStampImage = image;
        return image;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<pw.Widget> _buildContent({
    required pw.MemoryImage? logoImage,
    required pw.MemoryImage? stampImage,
    required pw.MemoryImage? employeeImage,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required String companyId,
    required String employeeName,
    required String position,
    required String email,
    required String payPeriod,
    required String invoiceNumber,
    required DateTime now,
    required String detectedCurrency,
    required String dailyRate,
    required String totalWorkDays,
    required String grossPay,
    required bool hasOvertime,
    required String overtimeAmount,
    required String overtimePay,
    required bool hasAbsentDeduction,
    required String absentDeduction,
    required String absents,
    required bool hasLeaveDeduction,
    required String leaveDeduction,
    required String deductibleLeaveDays,
    required bool hasDeductions,
    required String totalDeductions,
    required String netSalary,
    required bool isNegativeNet,
    required String salary,
    required String invoiceLeaves,
    required String paymentMethod,
  }) {
    return [
      _buildHeader(logoImage, companyName, employeeImage),
      pw.SizedBox(height: 32),
      _buildInvoiceInfo(invoiceNumber, now),
      pw.SizedBox(height: 38),
      _buildCompanyEmployeeInfo(companyName, companyAddress, companyEmail, companyPhone, companyId, employeeName, position, email, payPeriod),
      pw.SizedBox(height: 28),
      _buildTable(detectedCurrency, dailyRate, totalWorkDays, grossPay, hasOvertime, overtimeAmount, overtimePay, hasAbsentDeduction, absentDeduction, absents, hasLeaveDeduction, leaveDeduction, deductibleLeaveDays),
      pw.SizedBox(height: 18),
      _buildPayrollSummary(detectedCurrency, paymentMethod, salary, absents, invoiceLeaves, grossPay, overtimePay, hasOvertime, hasDeductions, totalDeductions, netSalary, isNegativeNet),
      pw.SizedBox(height: 8),
      _buildAuthorization(companyName, companyId, stampImage),
    ];
  }

  static pw.Widget _buildHeader(pw.MemoryImage? logoImage, String companyName, pw.MemoryImage? employeeImage) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            logoImage != null
                ? pw.SizedBox(width: 32, height: 32, child: pw.Image(logoImage, fit: pw.BoxFit.contain))
                : pw.SizedBox(width: 32, height: 32),
            pw.SizedBox(width: 12),
            pw.Text(companyName.isEmpty ? 'HRMS' : companyName, style: pw.TextStyle(fontSize: 23, color: PdfColorPalette.navy)),
          ],
        ),
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(PdfHelpers.translate('payroll_invoice_title', 'PAYROLL INVOICE'), style: pw.TextStyle(fontSize: 21, color: PdfColorPalette.appBlue, fontWeight: pw.FontWeight.normal)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildInvoiceInfo(String invoiceNumber, DateTime now) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('${PdfHelpers.translate('invoice_no', 'Invoice No.')} $invoiceNumber', style: pw.TextStyle(fontSize: 9, color: PdfColorPalette.textColor)),
        pw.SizedBox(height: 7),
        pw.Text(_formatDate(now), style: pw.TextStyle(fontSize: 9, color: PdfColorPalette.textColor)),
      ],
    );
  }

  static pw.Widget _buildCompanyEmployeeInfo(
    String companyName,
    String companyAddress,
    String companyEmail,
    String companyPhone,
    String companyId,
    String employeeName,
    String position,
    String email,
    String payPeriod,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _informationBlock(
            title: PdfHelpers.translate('employer', 'Employer'),
            titleColor: PdfColorPalette.navy,
            titleTextColor: PdfColors.white,
            lines: [
              companyName,
              companyAddress,
              if (companyEmail.trim().isNotEmpty) companyEmail,
              if (companyPhone.trim().isNotEmpty) companyPhone,
              if (companyId.trim().isNotEmpty) '${PdfHelpers.translate('company_id_label', 'Company ID:')} $companyId',
            ],
            textColor: PdfColorPalette.textColor,
          ),
        ),
        pw.SizedBox(width: 54),
        pw.Expanded(
          child: _informationBlock(
            title: PdfHelpers.translate('employee', 'Employee'),
            titleColor: PdfColorPalette.navy,
            titleTextColor: PdfColors.white,
            lines: [
              employeeName,
              position,
              email,
              '${PdfHelpers.translate('pay_period', 'Pay period:')} $payPeriod',
            ],
            textColor: PdfColorPalette.textColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTable(
    String detectedCurrency,
    String dailyRate,
    String totalWorkDays,
    String grossPay,
    bool hasOvertime,
    String overtimeAmount,
    String overtimePay,
    bool hasAbsentDeduction,
    String absentDeduction,
    String absents,
    bool hasLeaveDeduction,
    String leaveDeduction,
    String deductibleLeaveDays,
  ) {
    final rows = <pw.Widget>[
      _tableHeader(PdfColorPalette.navy, PdfColors.white),
      _tableRow(
        description: PdfHelpers.translate('basic_salary', 'Basic Salary'),
        rate: _money(dailyRate, defaultCurrency: detectedCurrency),
        quantity: totalWorkDays,
        total: _money(grossPay, defaultCurrency: detectedCurrency),
        textColor: PdfColorPalette.textColor,
        lineColor: PdfColorPalette.lineColor,
      ),
    ];

    if (hasOvertime) {
      rows.add(_tableRow(
        description: PdfHelpers.translate('overtime_pay', 'Overtime Pay'),
        rate: _money(overtimeAmount, defaultCurrency: detectedCurrency),
        quantity: '1',
        total: _money(overtimePay, defaultCurrency: detectedCurrency),
        textColor: PdfColorPalette.textColor,
        lineColor: PdfColorPalette.lineColor,
      ));
    }

    if (hasAbsentDeduction) {
      rows.add(_tableRow(
        description: PdfHelpers.translate('unpaid_absence_deduction', 'Absent Deduction'),
        rate: _perDayRate(absentDeduction, absents, defaultCurrency: detectedCurrency),
        quantity: absents,
        total: '-${_money(absentDeduction, defaultCurrency: detectedCurrency)}',
        textColor: PdfColorPalette.textColor,
        lineColor: PdfColorPalette.lineColor,
      ));
    }

    if (hasLeaveDeduction) {
      rows.add(_tableRow(
        description: PdfHelpers.translate('unpaid_leave_deduction', 'Unpaid Leave Deduction'),
        rate: _perDayRate(leaveDeduction, deductibleLeaveDays, defaultCurrency: detectedCurrency),
        quantity: deductibleLeaveDays,
        total: '-${_money(leaveDeduction, defaultCurrency: detectedCurrency)}',
        textColor: PdfColorPalette.textColor,
        lineColor: PdfColorPalette.lineColor,
      ));
    }

    if (!hasOvertime) rows.add(_emptyTableRow(PdfColorPalette.textColor, PdfColorPalette.lineColor));
    if (!hasAbsentDeduction) rows.add(_emptyTableRow(PdfColorPalette.textColor, PdfColorPalette.lineColor));

    return pw.Column(children: rows);
  }

  static pw.Widget _buildPayrollSummary(
    String detectedCurrency,
    String paymentMethod,
    String salary,
    String absents,
    String invoiceLeaves,
    String grossPay,
    String overtimePay,
    bool hasOvertime,
    bool hasDeductions,
    String totalDeductions,
    String netSalary,
    bool isNegativeNet,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                color: PdfColorPalette.navy,
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: pw.Text(PdfHelpers.translate('payroll_information', 'Payroll Information'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
              ),
              pw.SizedBox(height: 8),
              _smallInfoLine(PdfHelpers.translate('payment_method', 'Payment Method'), paymentMethod, PdfColorPalette.textColor),
              _smallInfoLine(PdfHelpers.translate('basic_salary', 'Basic Salary'), _money(salary, defaultCurrency: detectedCurrency), PdfColorPalette.textColor),
              _smallInfoLine(PdfHelpers.translate('absents', 'Absents'), absents, PdfColorPalette.textColor),
              _smallInfoLine(PdfHelpers.translate('leaves', 'Leaves'), invoiceLeaves, PdfColorPalette.textColor),
            ],
          ),
        ),
        pw.SizedBox(width: 60),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _summaryLine(PdfHelpers.translate('gross_pay', 'Gross Pay'), _money(grossPay, defaultCurrency: detectedCurrency), PdfColorPalette.textColor),
              if (hasOvertime) _summaryLine(PdfHelpers.translate('overtime_pay', 'Overtime Pay'), _money(overtimePay, defaultCurrency: detectedCurrency), PdfColorPalette.textColor),
              _summaryLine(
                PdfHelpers.translate('deductions', 'Deductions'),
                hasDeductions ? '-${_money(totalDeductions, defaultCurrency: detectedCurrency)}' : _money('0', defaultCurrency: detectedCurrency),
                PdfColorPalette.textColor,
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                color: PdfColorPalette.navy,
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(PdfHelpers.translate('net_salary', 'Net Salary'), style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                    pw.Text(
                      isNegativeNet ? _money('0', defaultCurrency: detectedCurrency) : _money(netSalary, defaultCurrency: detectedCurrency),
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildAuthorization(String companyName, String companyId, pw.MemoryImage? stampImage) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: buildCompanyAuthorization(
        companyName: companyName,
        companyId: companyId,
        stampImage: stampImage,
        accentColor: PdfColorPalette.appBlue,
        mutedColor: PdfColorPalette.mutedText,
        authorizedSignatoryText: PdfHelpers.translate('authorized_signatory', 'Authorized Signatory'),
        companyIdLabel: PdfHelpers.translate('company_id_label', 'Company ID:'),
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColorPalette.lineColor, height: 1, thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(PdfHelpers.translate('thank_you_contribution', 'Thank you for your contribution!'), style: pw.TextStyle(fontSize: 14, color: PdfColorPalette.appBlue)),
        ),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(PdfHelpers.translate('generated_by_hrms', 'Generated by HRMS'), style: pw.TextStyle(fontSize: 7, color: PdfColorPalette.mutedText)),
        ),
      ],
    );
  }

  static String resolveInvoiceLeaveDays({required String leaves, String paidLeaves = '', String unpaidLeaves = ''}) {
    final total = _parseValue(leaves);
    final splitTotal = _parseValue(paidLeaves) + _parseValue(unpaidLeaves);
    final resolved = total > splitTotal ? total : splitTotal;
    return resolved == resolved.roundToDouble() ? resolved.toStringAsFixed(0) : resolved.toStringAsFixed(1);
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
          child: pw.Text(title, style: pw.TextStyle(fontSize: 8, color: titleTextColor)),
        ),
        pw.SizedBox(height: 7),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 13),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: lines.where((line) => line.trim().isNotEmpty).map((line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(line, style: pw.TextStyle(fontSize: 8.5, color: textColor)),
            )).toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(PdfColor navy, PdfColor white) {
    return pw.Container(
      color: navy,
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text(PdfHelpers.translate('description', 'Description'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(PdfHelpers.translate('rate', 'Rate'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(PdfHelpers.translate('qty', 'Qty'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(PdfHelpers.translate('total', 'Total'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)))),
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
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: lineColor, width: 0.6))),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5, child: pw.Text(description, style: pw.TextStyle(fontSize: 8.5, color: textColor))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(rate, style: pw.TextStyle(fontSize: 8, color: textColor)))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(quantity, style: pw.TextStyle(fontSize: 8, color: textColor)))),
          pw.Expanded(flex: 2, child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(total, style: pw.TextStyle(fontSize: 8, color: textColor)))),
        ],
      ),
    );
  }

  static pw.Widget _emptyTableRow(PdfColor textColor, PdfColor lineColor) {
    return _tableRow(description: '', rate: '', quantity: '', total: '', textColor: textColor, lineColor: lineColor);
  }

  static pw.Widget _smallInfoLine(String label, String value, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 6, bottom: 4),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(fontSize: 8, color: color),
          children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
    final months = LocalizationHelper.englishMonthNames.sublist(1);
    final monthKey = 'month_${months[date.month - 1].toLowerCase()}';
    final monthName = PdfHelpers.translate(monthKey, months[date.month - 1]);
    return '$monthName ${date.day}, ${date.year}';
  }

  static String _twoDigits(int value) => pad2(value);

  static String _money(String raw, {String? defaultCurrency}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '${defaultCurrency ?? 'Rs'} 0.00';

    String prefix = defaultCurrency ?? 'Rs';
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);

    if (firstDigit != null && firstDigit.start > 0) {
      final detected = trimmed.substring(0, firstDigit.start).trim().replaceAll('-', '').trim();
      if (detected.isNotEmpty) {
        final code = detected.toUpperCase();
        prefix = CurrencyUtils.isSupported(code) ? _displayCurrency(code) : _displayCurrency(detected);
      }
    }

    final value = _parseValue(trimmed).abs();
    final formatted = value.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '$prefix $formatted';
  }

  static String _perDayRate(String total, String quantity, {String? defaultCurrency}) {
    final amount = _parseValue(total);
    final cleaned = quantity.replaceAll(RegExp(r'[^0-9.]'), '');
    final days = double.tryParse(cleaned) ?? 0;
    if (days <= 0 || amount <= 0) return _money('0', defaultCurrency: defaultCurrency);
    final rate = amount / days;
    final roundedRate = ((rate * 100) + 1e-9).floorToDouble() / 100;
    return _money(roundedRate.toStringAsFixed(2), defaultCurrency: defaultCurrency);
  }

  static String _detectCurrency(String salary) {
    final trimmed = salary.trim();
    if (trimmed.isEmpty) return 'Rs';
    final match = RegExp(r'\d').firstMatch(trimmed);
    if (match == null || match.start == 0) return 'Rs';
    final prefix = trimmed.substring(0, match.start).trim();
    if (prefix.isEmpty) return 'Rs';
    final code = prefix.toUpperCase();
    return CurrencyUtils.isSupported(code) ? CurrencyUtils.symbolFor(code) : '${prefix[0].toUpperCase()}${prefix.substring(1)}';
  }

  static const Set<String> _arabicScriptCurrencies = {'AED', 'SAR', 'QAR', 'KWD', 'OMR'};
  static const Map<String, String> _arabicSymbolToCode = {'د.إ': 'AED', '﷼': 'SAR', 'ر.ق': 'QAR', 'د.ك': 'KWD', 'ر.ع.': 'OMR'};

  static String _displayCurrency(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Rs';
    final arabicCode = _arabicSymbolToCode[trimmed];
    if (arabicCode != null) return arabicCode;
    if (CurrencyUtils.isSupported(trimmed)) {
      final code = trimmed.toUpperCase();
      return _arabicScriptCurrencies.contains(code) ? code : CurrencyUtils.symbolFor(code);
    }
    return trimmed;
  }

  static double _parseValue(String formatted) {
    final trimmed = formatted.trim();
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    final numericPart = firstDigit == null ? trimmed : trimmed.substring(firstDigit.start);
    final cleaned = numericPart.replaceAll(RegExp(r'[^0-9.]'), '');
    final value = double.tryParse(cleaned) ?? 0;

    final suffixMatch = RegExp(r'[KMBTkmbt]').firstMatch(numericPart);
    if (suffixMatch == null) return value;

    switch (suffixMatch.group(0)!.toUpperCase()) {
      case 'K': return value * 1000;
      case 'M': return value * 1000000;
      case 'B': return value * 1000000000;
      case 'T': return value * 1000000000000;
      default: return value;
    }
  }

  static Future<Uint8List?> _loadCompanyLogoBytes(String? source) async {
    return await ImageLoader.load(
      source: source,
      maxSizeBytes: _maxCompanyStampBytes,
      timeout: _companyStampTimeout,
      convertToPng: true,
    );
  }

  static Future<Uint8List?> resolveCompanyLogoBytes(String? source) async {
    final customLogo = await _loadCompanyLogoBytes(source);
    if (customLogo != null) return customLogo;
    try {
      final byteData = await rootBundle.load('assets/app_icon.png');
      return byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> resolveCompanyStampBytes(String? source) async {
    return await _loadCompanyStampBytes(source) ?? await loadDefaultHrStampBytes();
  }

  static Future<Uint8List?> _loadCompanyStampBytes(String? source) async {
    return await ImageLoader.load(
      source: source,
      maxSizeBytes: _maxCompanyStampBytes,
      timeout: _companyStampTimeout,
      convertToPng: true,
    );
  }

  static String _periodDatePrefix(String payPeriod) {
    if (payPeriod.trim().isNotEmpty) {
      final yearMatch = RegExp(r'20\d\d').firstMatch(payPeriod);
      if (yearMatch != null) {
        final year = yearMatch.group(0)!;
        const monthMatches = {
          'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04', 'may': '05', 'jun': '06',
          'jul': '07', 'aug': '08', 'sep': '09', 'oct': '10', 'nov': '11', 'dec': '12',
        };
        final lower = payPeriod.toLowerCase();
        for (final entry in monthMatches.entries) {
          if (lower.contains(entry.key)) return '$year${entry.value}';
        }
        return year;
      }
    }
    final now = DateTime.now();
    return '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
  }

  static String _buildReadableInvoiceNumber({
    String explicitInvoiceNumber = '',
    required String datePrefix,
    required String workerId,
  }) {
    final trimmed = explicitInvoiceNumber.trim();
    if (trimmed.isNotEmpty) return trimmed;

    String suffix = '0001';
    final cleanWorkerId = workerId.trim();
    final numericOnly = cleanWorkerId.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.isNotEmpty) {
      final numVal = int.tryParse(numericOnly);
      suffix = numVal != null ? numVal.toString().padLeft(4, '0') : numericOnly;
    } else if (cleanWorkerId.isNotEmpty) {
      final hashHex = cleanWorkerId.hashCode.abs().toRadixString(16).toUpperCase();
      suffix = hashHex.padLeft(4, '0');
    }

    return 'PAY-$datePrefix-$suffix';
  }

  static Future<bool> shareInvoice(Uint8List bytes, String fileName) async {
    final result = await FilePicker.saveFile(
      dialogTitle: PdfHelpers.translate('save_payroll_invoice', 'Save Payroll Invoice'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
    if (result == null || result.trim().isEmpty) return false;

    var outputPath = result.trim();
    if (!outputPath.toLowerCase().endsWith('.pdf')) outputPath = '$outputPath.pdf';
    await File(outputPath).writeAsBytes(bytes, flush: true);
    await FileOpener.open(outputPath);
    return true;
  }
}
