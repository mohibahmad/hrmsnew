class PayrollService {
  static final PayrollService _instance = PayrollService._();
  factory PayrollService() => _instance;
  PayrollService._();

  static List<Map<String, dynamic>> combinePayroll(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
  ) {
    if (workersList.isEmpty) return rawPayrollDocs;

    final combined = <Map<String, dynamic>>[];
    for (var worker in workersList) {
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();

      final payrollRecord = rawPayrollDocs.firstWhere((p) {
        final pEmail = (p['email'] ?? '').toString().trim().toLowerCase();
        final pName = (p['name'] ?? '').toString().trim().toLowerCase();
        return (email.isNotEmpty && pEmail == email) ||
            (name.isNotEmpty && pName == name);
      }, orElse: () => {});

      if (payrollRecord.isNotEmpty) {
        combined.add({
          ...worker,
          ...payrollRecord,
          'hasPayrollRecord': true,
          'profileImage':
              worker['profileImage'] ?? payrollRecord['profileImage'],
          'phone': worker['phone'] ?? payrollRecord['phone'] ?? '',
        });
      } else {
        final currency = worker['currency']?.toString() ?? 'USD';
        final currencySymbol = PayrollService.getCurrencySymbol(currency);
        final salaryAmount = worker['salaryAmount']?.toString() ?? '';
        combined.add({
          ...worker,
          'hasPayrollRecord': false,
          'status': 'Active',
          'totalWorkDays': '',
          'absents': '',
          'leaves': '',
          'overtimeAmount': '',
          'salary': salaryAmount.isNotEmpty
              ? '$currencySymbol $salaryAmount'
              : '',
          'netSalary': '',
        });
      }
    }

    return combined;
  }

  static double extractSalary(String salaryStr) {
    if (salaryStr.isEmpty) return 0;
    String cleaned = salaryStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return 0;
    // Detect European format: last . is followed by exactly 3 digits.
    // e.g. 1.234,56 -> treat as European; 1,234.56 -> treat as US
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    bool isEuropean = false;
    if (lastComma > lastDot) {
      isEuropean = true;
    } else if (lastDot > lastComma &&
        cleaned.length - lastDot == 4 &&
        cleaned.indexOf(',') >= 0) {
      isEuropean = true;
    }
    if (isEuropean) {
      cleaned = cleaned.replaceAll('.', '').replaceFirst(',', '.');
    } else {
      cleaned = cleaned.replaceAll(',', '');
    }
    return double.tryParse(cleaned) ?? 0;
  }

  static int parseIntSafe(String value) {
    if (value.isEmpty) return 0;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String formatNumber(num number) {
    if (number.isNaN || number.isInfinite) return '0';
    final isNegative = number < 0;
    final absolute = isNegative ? -number : number;
    final abs = absolute;
    if (abs >= 1e12) return '${(number / 1e12).toStringAsFixed(1)}T';
    if (abs >= 1e9) return '${(number / 1e9).toStringAsFixed(1)}B';
    if (abs >= 1e6) return '${(number / 1e6).toStringAsFixed(1)}M';
    if (abs >= 1e3) return '${(number / 1e3).toStringAsFixed(1)}K';
    final roundedStr = absolute.toStringAsFixed(0);
    final formatted = roundedStr.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    if (isNegative) return '($formatted)';
    return formatted;
  }

  static String getCurrencyPrefix(String salaryStr) {
    if (salaryStr.isEmpty) return '';
    final match = RegExp(r'\d').firstMatch(salaryStr);
    if (match == null) return salaryStr.trim();
    return salaryStr.substring(0, match.start).trim();
  }

  static const Map<String, String> _currencySymbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'POUND': '£',
    'JPY': '¥',
    'JAPANESE YEN': '¥',
    'INR': '₹',
    'RUB': '₽',
    'BRL': r'R$',
    'SAR': '﷼',
    'PKR': 'Rs',
  };

  static String getCurrencySymbol(String currency) {
    final key = currency.trim().toUpperCase();
    return _currencySymbols[key] ?? currency;
  }

  static String _fmt(num val, String prefix) {
    return '$prefix${formatNumber(val)}';
  }

  static Map<String, dynamic> calculatePayroll({
    required String salary,
    required String totalWorkDays,
    String daysWorked = '',
    required String absents,
    required String leaves,
    String overtimeAmount = '',
    String absentDeductionPerDay = '',
    String leaveDeductionPerDay = '',
    String salaryType = 'Monthly',
  }) {
    final rawSalaryVal = extractSalary(salary);
    final totalWorkDaysVal = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final leaveDays = parseIntSafe(leaves);
    final customOvertimeAmount = extractSalary(overtimeAmount);
    final customAbsentDeduction = extractSalary(absentDeductionPerDay);
    final customLeaveDeduction = extractSalary(leaveDeductionPerDay);
    final currency = getCurrencyPrefix(salary);
    final p = currency.isNotEmpty ? '$currency ' : '';

    // Daily Rate = Monthly Salary / Total Work Days
    final dailyRate = totalWorkDaysVal > 0
        ? rawSalaryVal / totalWorkDaysVal
        : 0.0;

    // Worked Days = Total Work Days - Absents (if daysWorked not provided)
    final workedDaysVal = daysWorked.isEmpty
        ? totalWorkDaysVal - absentDays
        : parseIntSafe(daysWorked);

    // Gross Pay = Daily Rate × Worked Days
    final grossSalary = workedDaysVal * dailyRate;

    // Overtime Pay = Custom Amount (HR enters manually)
    final overtimePay = customOvertimeAmount;

    // Deductions
    final absentDeduction = absentDays * dailyRate;
    final leaveDeduction = leaveDays * dailyRate;

    final totalDeductions = absentDeduction + leaveDeduction;

    // Net Pay = Gross + OT - Deductions
    final netSalary = grossSalary + overtimePay - totalDeductions;

    return {
      'annualSalary': rawSalaryVal,
      'totalWorkDaysPerYear': totalWorkDaysVal,
      'dailyRate': dailyRate,
      'overtimeRate': dailyRate * 1.5,
      'workedDays': workedDaysVal,
      'absentDays': absentDays,
      'leaveDays': leaveDays,
      'overtimeDays': 0,
      'grossSalary': grossSalary,
      'overtimePay': overtimePay,
      'absentDeduction': absentDeduction,
      'leaveDeduction': leaveDeduction,
      'totalDeductions': totalDeductions,
      'netSalary': netSalary,
      'formattedDailyRate': _fmt(dailyRate, p),
      'formattedOvertimeRate': _fmt(dailyRate * 1.5, p),
      'formattedGross': _fmt(grossSalary, p),
      'formattedOvertime': _fmt(overtimePay, p),
      'formattedAbsentDeduct': absentDeduction > 0
          ? '-${_fmt(absentDeduction, p)}'
          : '-${_fmt(0.0, p)}',
      'formattedLeaveDeduct': leaveDeduction > 0
          ? '-${_fmt(leaveDeduction, p)}'
          : '-${_fmt(0.0, p)}',
      'formattedTotalDeductions': totalDeductions > 0
          ? '-${_fmt(totalDeductions, p)}'
          : '-${_fmt(0.0, p)}',
      'formattedNet': _fmt(netSalary, p),
    };
  }

  static String getNetSalaryDisplay({
    required String salary,
    required String totalWorkDays,
    required String absents,
    String overtimeAmount = '',
    String salaryType = 'Monthly',
  }) {
    final rawSalary = extractSalary(salary);
    final workDays = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final overtime = extractSalary(overtimeAmount);
    final currency = getCurrencyPrefix(salary);
    final prefix = currency.isNotEmpty ? '$currency ' : '';

    // Daily Rate = Monthly Salary / Total Work Days
    final dailyRate = workDays > 0 ? rawSalary / workDays : 0.0;

    // Worked Days = Total Work Days - Absents
    final effectiveWorkDays = workDays - absentDays;

    // Gross Pay = Daily Rate × Worked Days
    final grossSalary = effectiveWorkDays * dailyRate;

    // Overtime Pay = Custom Amount
    final overtimePay = overtime;

    // Net Pay = Gross + OT
    final netSalary = grossSalary + overtimePay;

    return '$prefix${formatNumber(netSalary)}';
  }
}
