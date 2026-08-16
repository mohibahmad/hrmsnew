import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../utils/helpers.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import '../utils/utils.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceService {
  static const int _maxCompanyStampBytes = 5 * 1024 * 1024;
  static const Duration _companyStampTimeout = Duration(seconds: 15);
  static Future<ByteData?>? _payrollFontDataFuture;

  static Future<ByteData?> _loadPayrollFontData() async {
    try {
      return await rootBundle.load('assets/fonts/SF-Pro.ttf');
    } catch (_) {
      return null;
    }
  }

  static String _l(String key, String fallback) {
    final translated = key.tr().trim();
    return translated.isEmpty || translated == key ? fallback : translated;
  }

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
    String paymentMethod = 'Company Payroll',
    String workerId = '',
  }) async {
    final detectedCurrency = _displayCurrency(
      currency.isEmpty ? _detectCurrency(salary) : currency,
    );
    final pdf = pw.Document();

    final font = await _loadFont();
    final theme = _createTheme(font);

    final colors = _PdfColors(
      navy: PdfColor.fromHex('#111B4F'),
      appBlue: PdfColor.fromHex('#0247C4'),
      textColor: PdfColor.fromHex('#111B4F'),
      mutedText: PdfColor.fromHex('#586080'),
      lineColor: PdfColor.fromHex('#6B7398'),
      white: PdfColors.white,
    );

    final logoImage = await _loadLogo(companyLogoBytes, companyLogoUrl);
    final stampImage = await _loadStamp(companyStampBytes, companyStampImageUrl);

    final now = DateTime.now();
    final datePrefix = _periodDatePrefix(payPeriod);
    final invoiceNumber = _buildReadableInvoiceNumber(
      explicitInvoiceNumber: invoiceNo,
      datePrefix: datePrefix,
      workerId: workerId,
    );

    final invoiceLeaves = resolveInvoiceLeaveDays(
      leaves: leaves,
      paidLeaves: paidLeaves,
      unpaidLeaves: unpaidLeaves,
    );
    final deductibleLeaveDays = _getDeductibleLeaveDays(unpaidLeaves, leaves);

    final hasOvertime = _parseValue(overtimePay) > 0;
    final hasAbsentDeduction = _parseValue(absentDeduction) > 0 && _parseValue(absents) > 0;
    final hasLeaveDeduction = _parseValue(leaveDeduction) > 0 && _parseValue(deductibleLeaveDays) > 0;
    final hasDeductions = _parseValue(totalDeductions) > 0;
    final isNegativeNet = _parseValue(netSalary) < 0;

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 40),
        build: (context) => _buildContent(
          colors: colors,
          logoImage: logoImage,
          stampImage: stampImage,
          companyName: companyName,
          companyAddress: companyAddress,
          companyEmail: companyEmail,
          companyPhone: companyPhone,
          companyId: companyId,
          employeeName: employeeName,
          position: position,
          email: email,
          payPeriod: payPeriod,
          invoiceNumber: invoiceNumber,
          now: now,
          detectedCurrency: detectedCurrency,
          dailyRate: dailyRate,
          totalWorkDays: totalWorkDays,
          grossPay: grossPay,
          hasOvertime: hasOvertime,
          overtimeAmount: overtimeAmount,
          overtimePay: overtimePay,
          hasAbsentDeduction: hasAbsentDeduction,
          absentDeduction: absentDeduction,
          absents: absents,
          hasLeaveDeduction: hasLeaveDeduction,
          leaveDeduction: leaveDeduction,
          deductibleLeaveDays: deductibleLeaveDays,
          hasDeductions: hasDeductions,
          totalDeductions: totalDeductions,
          netSalary: netSalary,
          isNegativeNet: isNegativeNet,
          salary: salary,
          invoiceLeaves: invoiceLeaves,
          paymentMethod: paymentMethod,
        ),
        footer: (context) => _buildFooter(colors),
      ),
    );

    return pdf.save();
  }

  static String _getDeductibleLeaveDays(String unpaidLeaves, String leaves) {
    return unpaidLeaves.trim().isNotEmpty ? unpaidLeaves.trim() : leaves;
  }

  static Future<pw.Font?> _loadFont() async {
    try {
      final fontData = await (_payrollFontDataFuture ??= _loadPayrollFontData());
      return fontData != null ? pw.Font.ttf(fontData) : null;
    } catch (e) {
      debugPrint('InvoiceService: could not load fonts (falling back to Helvetica): $e');
      return null;
    }
  }

  static pw.ThemeData _createTheme(pw.Font? font) {
    return pw.ThemeData.withFont(
      base: font ?? pw.Font.helvetica(),
      bold: font ?? pw.Font.helveticaBold(),
    );
  }

  static Future<pw.MemoryImage?> _loadLogo(Uint8List? companyLogoBytes, String? companyLogoUrl) async {
    try {
      final bytes = companyLogoBytes ?? await resolveCompanyLogoBytes(companyLogoUrl);
      return bytes != null ? pw.MemoryImage(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<pw.MemoryImage?> _loadStamp(Uint8List? companyStampBytes, String? companyStampImageUrl) async {
    final bytes = companyStampBytes ?? await resolveCompanyStampBytes(companyStampImageUrl);
    return bytes != null ? pw.MemoryImage(bytes) : null;
  }

  static List<pw.Widget> _buildContent({
    required _PdfColors colors,
    required pw.MemoryImage? logoImage,
    required pw.MemoryImage? stampImage,
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
      _buildHeader(colors, logoImage, companyName),
      pw.SizedBox(height: 32),
      _buildInvoiceInfo(colors, invoiceNumber, now),
      pw.SizedBox(height: 38),
      _buildCompanyEmployeeInfo(colors, companyName, companyAddress, companyEmail, companyPhone, companyId, employeeName, position, email, payPeriod),
      pw.SizedBox(height: 28),
      _buildTable(colors, detectedCurrency, dailyRate, totalWorkDays, grossPay, hasOvertime, overtimeAmount, overtimePay, hasAbsentDeduction, absentDeduction, absents, hasLeaveDeduction, leaveDeduction, deductibleLeaveDays),
      pw.SizedBox(height: 18),
      _buildPayrollSummary(colors, detectedCurrency, paymentMethod, salary, absents, invoiceLeaves, grossPay, overtimePay, hasOvertime, hasDeductions, totalDeductions, netSalary, isNegativeNet),
      pw.SizedBox(height: 8),
      _buildAuthorization(colors, companyName, companyId, stampImage),
    ];
  }

  static pw.Widget _buildHeader(_PdfColors colors, pw.MemoryImage? logoImage, String companyName) {
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
            pw.Text(companyName.isEmpty ? 'HRMS' : companyName, style: pw.TextStyle(fontSize: 23, color: colors.navy)),
          ],
        ),
        pw.Text(
          _l('payroll_invoice_title', 'PAYROLL INVOICE'),
          style: pw.TextStyle(fontSize: 21, color: colors.appBlue, fontWeight: pw.FontWeight.normal),
        ),
      ],
    );
  }

  static pw.Widget _buildInvoiceInfo(_PdfColors colors, String invoiceNumber, DateTime now) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('${_l('invoice_no', 'Invoice No.')} $invoiceNumber', style: pw.TextStyle(fontSize: 9, color: colors.textColor)),
        pw.SizedBox(height: 7),
        pw.Text(_formatDate(now), style: pw.TextStyle(fontSize: 9, color: colors.textColor)),
      ],
    );
  }

  static pw.Widget _buildCompanyEmployeeInfo(
    _PdfColors colors,
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
            title: _l('employer', 'Employer'),
            titleColor: colors.navy,
            titleTextColor: colors.white,
            lines: [
              companyName,
              companyAddress,
              if (companyEmail.trim().isNotEmpty) companyEmail,
              if (companyPhone.trim().isNotEmpty) companyPhone,
              if (companyId.trim().isNotEmpty) '${_l('company_id_label', 'Company ID:')} $companyId',
            ],
            textColor: colors.textColor,
          ),
        ),
        pw.SizedBox(width: 54),
        pw.Expanded(
          child: _informationBlock(
            title: _l('employee', 'Employee'),
            titleColor: colors.navy,
            titleTextColor: colors.white,
            lines: [
              employeeName,
              position,
              email,
              '${_l('pay_period', 'Pay period:')} $payPeriod',
            ],
            textColor: colors.textColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTable(
    _PdfColors colors,
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
      _tableHeader(colors.navy, colors.white),
      _tableRow(
        description: _l('basic_salary', 'Basic Salary'),
        rate: _money(dailyRate, defaultCurrency: detectedCurrency),
        quantity: totalWorkDays,
        total: _money(grossPay, defaultCurrency: detectedCurrency),
        textColor: colors.textColor,
        lineColor: colors.lineColor,
      ),
    ];

    if (hasOvertime) {
      rows.add(_tableRow(
        description: _l('overtime_pay', 'Overtime Pay'),
        rate: _money(overtimeAmount, defaultCurrency: detectedCurrency),
        quantity: '1',
        total: _money(overtimePay, defaultCurrency: detectedCurrency),
        textColor: colors.textColor,
        lineColor: colors.lineColor,
      ));
    }

    if (hasAbsentDeduction) {
      rows.add(_tableRow(
        description: _l('unpaid_absence_deduction', 'Absent Deduction'),
        rate: _perDayRate(absentDeduction, absents, defaultCurrency: detectedCurrency),
        quantity: absents,
        total: '-${_money(absentDeduction, defaultCurrency: detectedCurrency)}',
        textColor: colors.textColor,
        lineColor: colors.lineColor,
      ));
    }

    if (hasLeaveDeduction) {
      rows.add(_tableRow(
        description: _l('unpaid_leave_deduction', 'Unpaid Leave Deduction'),
        rate: _perDayRate(leaveDeduction, deductibleLeaveDays, defaultCurrency: detectedCurrency),
        quantity: deductibleLeaveDays,
        total: '-${_money(leaveDeduction, defaultCurrency: detectedCurrency)}',
        textColor: colors.textColor,
        lineColor: colors.lineColor,
      ));
    }

    if (!hasOvertime) rows.add(_emptyTableRow(colors.textColor, colors.lineColor));
    if (!hasAbsentDeduction) rows.add(_emptyTableRow(colors.textColor, colors.lineColor));
    if (!hasLeaveDeduction) rows.add(_emptyTableRow(colors.textColor, colors.lineColor));

    rows.add(_emptyTableRow(colors.textColor, colors.lineColor));

    return pw.Column(children: rows);
  }

  static pw.Widget _buildPayrollSummary(
    _PdfColors colors,
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
                color: colors.navy,
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: pw.Text(
                  _l('payroll_information', 'Payroll Information'),
                  style: pw.TextStyle(fontSize: 8, color: colors.white),
                ),
              ),
              pw.SizedBox(height: 8),
              _smallInfoLine(_l('payment_method', 'Payment Method'), paymentMethod, colors.textColor),
              _smallInfoLine(_l('basic_salary', 'Basic Salary'), _money(salary, defaultCurrency: detectedCurrency), colors.textColor),
              _smallInfoLine(_l('absents', 'Absents'), absents, colors.textColor),
              _smallInfoLine(_l('leaves', 'Leaves'), invoiceLeaves, colors.textColor),
            ],
          ),
        ),
        pw.SizedBox(width: 60),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _summaryLine(_l('gross_pay', 'Gross Pay'), _money(grossPay, defaultCurrency: detectedCurrency), colors.textColor),
              if (hasOvertime) _summaryLine(_l('overtime_pay', 'Overtime Pay'), _money(overtimePay, defaultCurrency: detectedCurrency), colors.textColor),
              _summaryLine(
                _l('deductions', 'Deductions'),
                hasDeductions
                    ? '-${_money(totalDeductions, defaultCurrency: detectedCurrency)}'
                    : _money('0', defaultCurrency: detectedCurrency),
                colors.textColor,
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                color: colors.navy,
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(_l('net_salary', 'Net Salary'), style: pw.TextStyle(fontSize: 10, color: colors.white)),
                    pw.Text(
                      isNegativeNet
                          ? _money('0', defaultCurrency: detectedCurrency)
                          : _money(netSalary, defaultCurrency: detectedCurrency),
                      style: pw.TextStyle(fontSize: 10, color: colors.white, fontWeight: pw.FontWeight.bold),
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

  static pw.Widget _buildAuthorization(_PdfColors colors, String companyName, String companyId, pw.MemoryImage? stampImage) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: buildCompanyAuthorization(
        companyName: companyName,
        companyId: companyId,
        stampImage: stampImage,
        accentColor: colors.appBlue,
        mutedColor: colors.mutedText,
        authorizedSignatoryText: _l('authorized_signatory', 'Authorized Signatory'),
        companyIdLabel: _l('company_id_label', 'Company ID:'),
      ),
    );
  }

  static pw.Widget _buildFooter(_PdfColors colors) {
    return pw.Column(
      children: [
        pw.Divider(color: colors.lineColor, height: 1, thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(_l('thank_you_contribution', 'Thank you for your contribution!'), style: pw.TextStyle(fontSize: 14, color: colors.appBlue)),
        ),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(_l('generated_by_hrms', 'Generated by HRMS'), style: pw.TextStyle(fontSize: 7, color: colors.mutedText)),
        ),
      ],
    );
  }

  static String resolveInvoiceLeaveDays({
    required String leaves,
    String paidLeaves = '',
    String unpaidLeaves = '',
  }) {
    final total = _parseValue(leaves);
    final splitTotal = _parseValue(paidLeaves) + _parseValue(unpaidLeaves);
    final resolved = total > splitTotal ? total : splitTotal;
    return resolved == resolved.roundToDouble()
        ? resolved.toStringAsFixed(0)
        : resolved.toStringAsFixed(1);
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
            children: lines
                .where((line) => line.trim().isNotEmpty)
                .map((line) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Text(line, style: pw.TextStyle(fontSize: 8.5, color: textColor)),
                    ))
                .toList(),
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
          pw.Expanded(
            flex: 5,
            child: pw.Text(_l('description', 'Description'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_l('rate', 'Rate'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_l('qty', 'Qty'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_l('total', 'Total'), style: pw.TextStyle(fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)),
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
            child: pw.Text(description, style: pw.TextStyle(fontSize: 8.5, color: textColor)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(rate, style: pw.TextStyle(fontSize: 8, color: textColor)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(quantity, style: pw.TextStyle(fontSize: 8, color: textColor)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(total, style: pw.TextStyle(fontSize: 8, color: textColor)),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyTableRow(PdfColor textColor, PdfColor lineColor) {
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
    final monthName = _l(monthKey, months[date.month - 1]);
    return '$monthName ${date.day}, ${date.year}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
    final formatted = value
        .toStringAsFixed(2)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
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

  static bool _isValidPdfImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 4) return false;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    if (bytes.lengthInBytes >= 12) {
      final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
      final webp = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
      if (riff == 'RIFF' && webp == 'WEBP') return true;
    }
    return bytes[0] == 0x42 && bytes[1] == 0x4D;
  }

  static Future<Uint8List?> _loadCompanyLogoBytes(String? source) async {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      Uint8List? bytes;
      if (value.startsWith('data:')) {
        final separator = value.indexOf(',');
        if (separator > 0) {
          final encoded = value.substring(separator + 1).replaceAll(RegExp(r'\s+'), '');
          if (encoded.isNotEmpty) bytes = base64Decode(encoded);
        }
      } else {
        final uri = Uri.tryParse(value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          bytes = await _downloadCompanyStamp(uri);
        } else if (uri != null && uri.scheme == 'file') {
          bytes = await _readCompanyStampFile(File.fromUri(uri));
        } else {
          bytes = await _readCompanyStampFile(File(value));
        }
      }
      if (bytes == null || bytes.isEmpty) return null;
      if (_isValidPdfImageBytes(bytes)) return bytes;
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return Uint8List.fromList(img.encodePng(decoded));
    } catch (_) {}
    return null;
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
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;

    Uint8List? bytes;
    try {
      if (value.startsWith('data:')) {
        final separator = value.indexOf(',');
        if (separator > 0) {
          final encoded = value.substring(separator + 1).replaceAll(RegExp(r'\s+'), '');
          if (encoded.isNotEmpty && encoded.length <= ((_maxCompanyStampBytes * 4) ~/ 3) + 16) {
            bytes = base64Decode(encoded);
          }
        }
      } else {
        final uri = Uri.tryParse(value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          bytes = await _downloadCompanyStamp(uri);
        } else if (uri != null && uri.scheme == 'file') {
          bytes = await _readCompanyStampFile(File.fromUri(uri));
        } else {
          bytes = await _readCompanyStampFile(File(value));
          if (bytes == null) {
            final data = await rootBundle.load(value).timeout(_companyStampTimeout);
            bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          }
        }
      }
    } catch (_) {
      return null;
    }

    if (bytes == null || bytes.isEmpty || bytes.lengthInBytes > _maxCompanyStampBytes) return null;
    if (_isValidPdfImageBytes(bytes)) return bytes;

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return Uint8List.fromList(img.encodePng(decoded));
    } catch (_) {}
    return null;
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
      if (contentType != null && (contentType.startsWith('text/html') || contentType.startsWith('application/json'))) return null;
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
      dialogTitle: _l('save_payroll_invoice', 'Save Payroll Invoice'),
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

class _PdfColors {
  final PdfColor navy;
  final PdfColor appBlue;
  final PdfColor textColor;
  final PdfColor mutedText;
  final PdfColor lineColor;
  final PdfColor white;

  const _PdfColors({
    required this.navy,
    required this.appBlue,
    required this.textColor,
    required this.mutedText,
    required this.lineColor,
    required this.white,
  });
}