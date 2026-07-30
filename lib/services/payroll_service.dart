import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/currency_utils.dart';

class PayrollService {
  static final PayrollService _instance = PayrollService._();
  factory PayrollService() => _instance;
  PayrollService._();

  static DateTime currentPayrollMonth({DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();
    return DateTime(reference.year, reference.month, 1);
  }

  /// Kept for older callers and stored data that explicitly need the last
  /// fully completed calendar month.
  static DateTime completedPayrollMonth({DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();
    return DateTime(reference.year, reference.month - 1, 1);
  }

  static String payrollPeriodLabel(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  static DateTime? parsePayrollPeriodLabel(dynamic value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})(?:-\d{2})?$',
    ).firstMatch((value ?? '').toString().trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return DateTime(year, month, 1);
  }

  static DateTime nextPayrollMonth(DateTime month) =>
      DateTime(month.year, month.month + 1, 1);

  static bool isMonthBefore(DateTime month, DateTime other) {
    final normalizedMonth = DateTime(month.year, month.month, 1);
    final normalizedOther = DateTime(other.year, other.month, 1);
    return normalizedMonth.isBefore(normalizedOther);
  }

  static bool isMonthEnding(DateTime date, {int reminderDays = 3}) {
    if (reminderDays < 1) return false;
    final lastDay = DateTime(date.year, date.month + 1, 0).day;
    return date.day > lastDay - reminderDays;
  }

  static bool allWorkersPaidForMonth(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month,
  ) {
    if (workersList.isEmpty) return true;
    final combined = combinePayroll(workersList, rawPayrollDocs, month: month);
    return combined.length == workersList.length &&
        combined.every((worker) => worker['hasPayrollRecord'] == true);
  }

  static int unpaidWorkerCountForMonth(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month,
  ) {
    if (workersList.isEmpty) return 0;
    final combined = combinePayroll(workersList, rawPayrollDocs, month: month);
    return combined
        .where((worker) => worker['hasPayrollRecord'] != true)
        .length;
  }

  static int effectiveSalaryDay(DateTime month, int configuredDay) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return configuredDay.clamp(1, lastDay);
  }

  static bool isPayrollDue(DateTime date, int? configuredDay) {
    if (configuredDay == null || configuredDay < 1 || configuredDay > 31) {
      return false;
    }
    return date.day == effectiveSalaryDay(date, configuredDay);
  }

  static List<Map<String, dynamic>> combinePayroll(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    DateTime? month,
    bool allowUndatedRecords = false,
  }) {
    final targetMonth = month ?? DateTime.now();
    final monthlyPayrollDocs = rawPayrollDocs
        .where((record) {
          if ((record['status'] ?? '').toString().trim().toLowerCase() ==
              'cancelled') {
            return false;
          }
          return isRecordInMonth(
            record,
            targetMonth,
            allowUndated: allowUndatedRecords,
          );
        })
        .map(Map<String, dynamic>.from)
        .toList();
    // The workers collection is the source of truth for the active payroll
    // roster. Historical payroll documents must not recreate workers that
    // have since been deleted.
    if (workersList.isEmpty) return const <Map<String, dynamic>>[];

    final combined = <Map<String, dynamic>>[];
    for (var worker in workersList) {
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim();
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final name = (worker['name'] ?? '').toString().trim().toLowerCase();
      final identity = workerId.isNotEmpty ? workerId : email;
      final canonicalPayrollKey =
          '${identity}_${payrollPeriodLabel(targetMonth)}'.toLowerCase();
      final canonicalRecord = identity.isEmpty
          ? null
          : rawPayrollDocs.cast<Map<String, dynamic>?>().firstWhere(
              (record) =>
                  (record?['payrollKey'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase() ==
                  canonicalPayrollKey,
              orElse: () => null,
            );
      final workerPayrollDocs = canonicalRecord == null
          ? monthlyPayrollDocs
          : ((canonicalRecord['status'] ?? '')
                            .toString()
                            .trim()
                            .toLowerCase() !=
                        'cancelled' &&
                    isRecordInMonth(
                      canonicalRecord,
                      targetMonth,
                      allowUndated: allowUndatedRecords,
                    )
                ? <Map<String, dynamic>>[canonicalRecord]
                : const <Map<String, dynamic>>[]);

      final payrollRecord = workerPayrollDocs.firstWhere((p) {
        final payrollWorkerId = (p['workerId'] ?? '').toString().trim();
        final pEmail = (p['email'] ?? '').toString().trim().toLowerCase();
        final pName = (p['name'] ?? p['workerName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return (workerId.isNotEmpty &&
                payrollWorkerId.isNotEmpty &&
                workerId == payrollWorkerId) ||
            (payrollWorkerId.isEmpty && email.isNotEmpty && pEmail == email) ||
            (payrollWorkerId.isEmpty &&
                pEmail.isEmpty &&
                name.isNotEmpty &&
                pName == name);
      }, orElse: () => {});

      if (payrollRecord.isNotEmpty) {
        final currentSalary = currentSalaryDisplay(worker);
        combined.add({
          ...worker,
          ...payrollRecord,
          'workerId': workerId,
          'hasPayrollRecord': true,

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
          'workerId': workerId,
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

  static List<Map<String, dynamic>> payrollRecordsForActiveWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> payrollRecords,
  ) {
    if (workersList.isEmpty || payrollRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    return payrollRecords.where((record) {
      final payrollWorkerId = (record['workerId'] ?? '').toString().trim();
      final payrollEmail = (record['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final payrollName = (record['name'] ?? record['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      return workersList.any((worker) {
        final workerId = (worker['workerId'] ?? worker['id'] ?? '')
            .toString()
            .trim();
        if (payrollWorkerId.isNotEmpty && workerId.isNotEmpty) {
          return payrollWorkerId == workerId;
        }

        final email = (worker['email'] ?? '').toString().trim().toLowerCase();
        if (payrollEmail.isNotEmpty && email.isNotEmpty) {
          return payrollEmail == email;
        }

        final name = (worker['name'] ?? '').toString().trim().toLowerCase();
        return payrollEmail.isEmpty &&
            payrollName.isNotEmpty &&
            name.isNotEmpty &&
            payrollName == name;
      });
    }).toList();
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
    final createdAt = _parseDate(record['createdAt']);
    final payrollDate = _parseDate(record['payrollDate']);
    if (payrollDate != null &&
        createdAt != null &&
        (payrollDate.year != createdAt.year ||
            payrollDate.month != createdAt.month)) {
      return payrollDate;
    }

    for (final key in [
      'payrollMonth',
      'period',
      'payPeriod',
      'createdAt',
      'timestamp',
      'payrollDate',
      'date',
      'lastModified',
    ]) {
      final parsed = _parseDate(record[key]);
      if (parsed != null) return parsed;
    }
    final payrollKey = (record['payrollKey'] ?? '').toString();
    final periodMatch = RegExp(r'(\d{4})-(\d{2})$').firstMatch(payrollKey);
    if (periodMatch != null) {
      final year = int.tryParse(periodMatch.group(1)!);
      final month = int.tryParse(periodMatch.group(2)!);
      if (year != null && month != null && month >= 1 && month <= 12) {
        return DateTime(year, month, 1);
      }
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
    final suffix = RegExp(
      r'([KMBT])\s*$',
      caseSensitive: false,
    ).firstMatch(salaryStr.trim())?.group(1)?.toUpperCase();
    final multiplier = switch (suffix) {
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      'T' => 1e12,
      _ => 1.0,
    };
    String cleaned = salaryStr.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return 0;

    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        // European format: 1.234,56
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // US format: 1,234.56
        cleaned = cleaned.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final commaCount = ','.allMatches(cleaned).length;
      final digitsAfterComma = cleaned.length - lastComma - 1;
      if (commaCount > 1 || digitsAfterComma == 3) {
        // Thousands grouping: 1,234 or 1,234,567
        cleaned = cleaned.replaceAll(',', '');
      } else {
        // Decimal comma: 123,45
        cleaned = cleaned.replaceAll(',', '.');
      }
    } else if ('.'.allMatches(cleaned).length > 1) {
      // European thousands grouping without a decimal part: 1.234.567
      cleaned = cleaned.replaceAll('.', '');
    }
    return (double.tryParse(cleaned) ?? 0) * multiplier;
  }

  static int parseIntSafe(String value) {
    if (value.isEmpty) return 0;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

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
        : (legacyLeaves - paidLeaves).clamp(0, legacyLeaves);
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

  static String formatFullNumber(num number) {
    if (number.isNaN || number.isInfinite) return '0';
    final hasDecimals = number != number.roundToDouble();
    final parts = number.toStringAsFixed(hasDecimals ? 2 : 0).split('.');
    final formattedInteger = parts.first.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match match) => '${match[1]},',
    );
    return parts.length == 1
        ? formattedInteger
        : '$formattedInteger.${parts[1]}';
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

  static double calculateNetFromTotals({
    required String salary,
    String overtimeAmount = '',
    String absentDeduction = '',
    String leaveDeduction = '',
    String customDeduction = '',
    String salaryType = 'Monthly',
  }) {
    final enteredSalary = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual'
        ? enteredSalary / 12
        : enteredSalary;
    final netSalary =
        periodSalary +
        extractSalary(overtimeAmount) -
        extractSalary(absentDeduction) -
        extractSalary(leaveDeduction) -
        extractSalary(customDeduction);
    return netSalary.clamp(0.0, double.infinity).toDouble();
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
    final periodSalary = salaryType.trim().toLowerCase() == 'annual'
        ? rawSalaryVal / 12
        : rawSalaryVal;
    final totalWorkDaysVal = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final leaveDays = parseIntSafe(leaves);
    final customOvertimeAmount = extractSalary(overtimeAmount);
    final customAbsentDeduction = extractSalary(absentDeductionPerDay);
    final customLeaveDeduction = extractSalary(leaveDeductionPerDay);
    final currency = getCurrencyPrefix(salary);
    final p = currency.isNotEmpty ? '$currency ' : '';

    final dailyRate = totalWorkDaysVal > 0
        ? periodSalary / totalWorkDaysVal
        : 0.0;

    final workedDaysVal = daysWorked.isEmpty
        ? totalWorkDaysVal - absentDays - leaveDays
        : parseIntSafe(daysWorked);

    final grossSalary = periodSalary;

    final overtimePay = customOvertimeAmount;

    final absentRate = absentDeductionPerDay.trim().isNotEmpty
        ? customAbsentDeduction
        : 0.0;
    final leaveRate = leaveDeductionPerDay.trim().isNotEmpty
        ? customLeaveDeduction
        : 0.0;
    final absentDeduction = absentDays * absentRate;
    final leaveDeduction = leaveDays * leaveRate;

    final totalDeductions = absentDeduction + leaveDeduction;

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
    final enteredSalary = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual'
        ? enteredSalary / 12
        : enteredSalary;
    final overtime = extractSalary(overtimeAmount);
    final currency = getCurrencyPrefix(salary);
    final prefix = currency.isNotEmpty ? '$currency ' : '';

    // Attendance is detected and displayed separately. It must not reduce net
    // salary automatically; HR applies any deduction explicitly in payroll.
    final netSalary = periodSalary + overtime;

    return '$prefix${formatNumber(netSalary)}';
  }
}
