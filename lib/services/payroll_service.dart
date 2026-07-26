import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

class PayrollService {
  static final PayrollService _instance = PayrollService._();
  factory PayrollService() => _instance;
  PayrollService._();

  static List<Map<String, dynamic>> combinePayroll(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    DateTime? month,
    bool allowUndatedRecords = false,
  }) {
    final targetMonth = month ?? DateTime.now();
    final monthlyPayrollDocs = rawPayrollDocs.where((record) {
      return isRecordInMonth(
        record,
        targetMonth,
        allowUndated: allowUndatedRecords,
      );
    }).toList();
    if (workersList.isEmpty) return monthlyPayrollDocs;

    final combined = <Map<String, dynamic>>[];
    for (var worker in workersList) {
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();

      final payrollRecord = monthlyPayrollDocs.firstWhere((p) {
        final pEmail = (p['email'] ?? '').toString().trim().toLowerCase();
        final pName = (p['name'] ?? '').toString().trim().toLowerCase();
        return (email.isNotEmpty && pEmail == email) ||
            (name.isNotEmpty && pName == name);
      }, orElse: () => {});

      if (payrollRecord.isNotEmpty) {
        final currentSalary = currentSalaryDisplay(worker);
        combined.add({
          ...worker,
          ...payrollRecord,
          'hasPayrollRecord': true,
          // Worker compensation is the source of truth for the current
          // payroll form. The payroll record still keeps its historical
          // snapshot in [rawPayrollDocs], but must not mask a salary edited
          // from the Workers screen.
          'salaryAmount':
              worker['salaryAmount'] ?? payrollRecord['salaryAmount'],
          'currency': worker['currency'] ?? payrollRecord['currency'],
          'salaryType': worker['salaryType'] ?? payrollRecord['salaryType'],
          if (currentSalary.isNotEmpty) 'salary': currentSalary,
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

  static bool isRecordInMonth(
    Map<String, dynamic> record,
    DateTime month, {
    bool allowUndated = false,
  }) {
    final date = payrollRecordDate(record);
    if (date == null) return allowUndated;
    return date.year == month.year && date.month == month.month;
  }

  static DateTime? payrollRecordDate(Map<String, dynamic> record) {
    for (final key in [
      'createdAt',
      'timestamp',
      'payPeriod',
      'payrollDate',
      'date',
      'lastModified',
    ]) {
      final parsed = _parseDate(record[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final isoDate = DateTime.tryParse(text);
    if (isoDate != null) return isoDate.toLocal();

    final parts = text.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) return null;
    final year = parts[0].length == 4 ? first : third;
    final month = second;
    final day = parts[0].length == 4 ? third : first;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
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
        cleaned.contains(',')) {
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

  /// Returns the worker's current configured salary for payroll editing.
  /// `salaryAmount` is preferred over a saved payroll snapshot so a salary
  /// change made on the Workers screen is reflected immediately.
  static String currentSalaryDisplay(Map<String, dynamic> data) {
    final salaryAmount = (data['salaryAmount'] ?? '').toString().trim();
    if (salaryAmount.isNotEmpty) {
      final currency = (data['currency'] ?? 'USD').toString();
      final symbol = getCurrencySymbol(currency);
      return symbol.isEmpty ? salaryAmount : '$symbol $salaryAmount';
    }
    final salary = (data['salary'] ?? '').toString().trim();
    if (salary.isNotEmpty) return salary;
    return '\$ 0';
  }

  /// Payroll absences and leaves are attendance counts, not leave allowance.
  /// A new worker may have `annualLeaves: 100`, but until attendance is marked
  /// their payroll leave count must still be zero.
  static Map<String, int> attendanceCounts(
    Map<String, dynamic> payrollOrWorkerData,
  ) {
    final legacyLeaves = parseIntSafe(
      (payrollOrWorkerData['leaves'] ?? '').toString(),
    );
    final paidLeaves = parseIntSafe(
      (payrollOrWorkerData['paidLeaves'] ?? '').toString(),
    );
    final hasExplicitUnpaid = payrollOrWorkerData.containsKey('unpaidLeaves');
    final unpaidLeaves = hasExplicitUnpaid
        ? parseIntSafe((payrollOrWorkerData['unpaidLeaves'] ?? '').toString())
        : legacyLeaves;
    return {
      'absents': parseIntSafe(
        (payrollOrWorkerData['absents'] ?? '').toString(),
      ),
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'leaves': paidLeaves + unpaidLeaves,
    };
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

  static String getCurrencySymbol(String currency) {
    final key = currency.trim().toUpperCase();
    if (key == 'POUND') return '£';
    if (key == 'JAPANESE YEN') return '¥';
    return CurrencyUtils.symbolFor(key);
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

    // Worked Days is informational. Monthly gross remains the configured
    // salary, and absence/unpaid-leave deductions are applied exactly once.
    final workedDaysVal = daysWorked.isEmpty
        ? totalWorkDaysVal - absentDays - leaveDays
        : parseIntSafe(daysWorked);

    final grossSalary = rawSalaryVal;

    // Overtime Pay = Custom Amount (HR enters manually)
    final overtimePay = customOvertimeAmount;

    // Blank per-day fields use the calculated daily rate. Entered values are
    // treated as an explicit HR override, not an additional penalty.
    final absentRate = absentDeductionPerDay.trim().isNotEmpty
        ? customAbsentDeduction
        : dailyRate;
    final leaveRate = leaveDeductionPerDay.trim().isNotEmpty
        ? customLeaveDeduction
        : dailyRate;
    final absentDeduction = absentDays * absentRate;
    final leaveDeduction = leaveDays * leaveRate;

    final totalDeductions = absentDeduction + leaveDeduction;

    // Net Pay = Gross + OT - Deductions
    final netSalary = (grossSalary + overtimePay - totalDeductions).clamp(
      0.0,
      double.infinity,
    );

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
      'absentDeductionPerDayApplied': absentRate,
      'leaveDeductionPerDayApplied': leaveRate,
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
