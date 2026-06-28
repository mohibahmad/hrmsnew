class PayrollService {
  static final PayrollService _instance = PayrollService._();
  factory PayrollService() => _instance;
  PayrollService._();

  static double extractSalary(String salaryStr) {
    if (salaryStr.isEmpty) return 0;
    final cleaned = salaryStr.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return 0;
    return double.tryParse(cleaned) ?? 0;
  }

  static int parseIntSafe(String value) {
    if (value.isEmpty) return 0;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String formatNumber(num number) {
    if (number.isNaN || number.isInfinite) return '0';
    final roundedStr = number.toStringAsFixed(0);
    return roundedStr.replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  static String getCurrencyPrefix(String salaryStr) {
    if (salaryStr.isEmpty) return '';
    final prefix = salaryStr.replaceAll(RegExp(r'[0-9,\s]'), '').trim();
    return prefix;
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
    required String overtimeDays,
  }) {
    final rawSalaryVal = extractSalary(salary);
    final totalWorkDaysVal = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final leaveDays = parseIntSafe(leaves);
    final overtime = parseIntSafe(overtimeDays);
    final currency = getCurrencyPrefix(salary);
    final p = currency.isNotEmpty ? '$currency ' : '';

    final isAnnualPeriod = totalWorkDaysVal > 100;
    double periodBaseSalary;
    if (isAnnualPeriod) {
      periodBaseSalary = rawSalaryVal;
    } else {
      final isAnnualSalary = rawSalaryVal >= 15000;
      periodBaseSalary = isAnnualSalary ? rawSalaryVal / 12 : rawSalaryVal;
    }

    final dailyRate = totalWorkDaysVal > 0 ? periodBaseSalary / totalWorkDaysVal : 0.0;
    final workedDaysVal = daysWorked.isEmpty ? (totalWorkDaysVal - absentDays) : parseIntSafe(daysWorked);
    final overtimeRate = dailyRate * 1.5;

    final grossSalary = workedDaysVal * dailyRate;
    final overtimePay = overtime * overtimeRate;
    final absentDeduction = absentDays * dailyRate;
    final leaveDeduction = leaveDays * dailyRate;
    final totalDeductions = absentDeduction + leaveDeduction;
    final netSalary = grossSalary + overtimePay - totalDeductions;

    return {
      'annualSalary': rawSalaryVal,
      'totalWorkDaysPerYear': totalWorkDaysVal,
      'dailyRate': dailyRate,
      'overtimeRate': overtimeRate,
      'workedDays': workedDaysVal,
      'absentDays': absentDays,
      'leaveDays': leaveDays,
      'overtimeDays': overtime,
      'grossSalary': grossSalary,
      'overtimePay': overtimePay,
      'absentDeduction': absentDeduction,
      'leaveDeduction': leaveDeduction,
      'totalDeductions': totalDeductions,
      'netSalary': netSalary,
      'formattedDailyRate': _fmt(dailyRate, p),
      'formattedOvertimeRate': _fmt(overtimeRate, p),
      'formattedGross': _fmt(grossSalary, p),
      'formattedOvertime': _fmt(overtimePay, p),
      'formattedAbsentDeduct': absentDeduction > 0 ? '-${_fmt(absentDeduction, p)}' : '0',
      'formattedLeaveDeduct': leaveDeduction > 0 ? '-${_fmt(leaveDeduction, p)}' : '0',
      'formattedTotalDeductions': totalDeductions > 0 ? '-${_fmt(totalDeductions, p)}' : '0',
      'formattedNet': _fmt(netSalary, p),
    };
  }

  static String getNetSalaryDisplay({
    required String salary,
    required String totalWorkDays,
    required String absents,
    required String overtimeDays,
  }) {
    final annualSalary = extractSalary(salary);
    final workDays = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final overtime = parseIntSafe(overtimeDays);
    final currency = getCurrencyPrefix(salary);
    final prefix = currency.isNotEmpty ? '$currency ' : '';

    final isAnnualPeriod = workDays > 100;
    double periodBaseSalary;
    if (isAnnualPeriod) {
      periodBaseSalary = annualSalary;
    } else {
      final isAnnualSalary = annualSalary >= 15000;
      periodBaseSalary = isAnnualSalary ? annualSalary / 12 : annualSalary;
    }

    final dailyRate = workDays > 0 ? periodBaseSalary / workDays : 0.0;
    final effectiveWorkDays = workDays - absentDays;
    final grossSalary = effectiveWorkDays * dailyRate;
    final overtimePay = overtime * dailyRate * 1.5;
    final netSalary = grossSalary + overtimePay;

    return '$prefix${formatNumber(netSalary)}';
  }
}
