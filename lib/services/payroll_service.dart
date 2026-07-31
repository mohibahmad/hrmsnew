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

  /// Reporting helper only. Do not use this value to disable, lock, or make
  /// the payroll screen read-only. Paid payroll records remain editable.
  static bool allWorkersPaidForMonth(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month,
  ) {
    final activeWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .toList();
    if (activeWorkers.isEmpty) return true;

    final combined = combinePayroll(
      activeWorkers,
      rawPayrollDocs,
      month: month,
    );

    return combined.length == activeWorkers.length &&
        combined.every((worker) => worker['isPaid'] == true);
  }

  static int unpaidWorkerCountForMonth(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month,
  ) {
    final activeWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .toList();
    if (activeWorkers.isEmpty) return 0;

    final combined = combinePayroll(
      activeWorkers,
      rawPayrollDocs,
      month: month,
    );

    return combined.where((worker) => worker['isPaid'] != true).length;
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

  static bool isWorkerEligibleForPayroll(Map<String, dynamic> worker) {
    if (_isTruthy(worker['isDeleted']) ||
        _isTruthy(worker['deleted']) ||
        _isTruthy(worker['isArchived'])) {
      return false;
    }

    final status = (worker['employmentStatus'] ?? worker['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return !const {
      'deleted',
      'inactive',
      'terminated',
      'archived',
    }.contains(status);
  }

  static bool isPayrollRecordPaid(Map<String, dynamic> record) {
    if (_isTruthy(record['isPaid']) || _isTruthy(record['paid'])) {
      return true;
    }

    final paymentStatus = (record['paymentStatus'] ?? record['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (const {
      'paid',
      'completed',
      'processed',
      'successful',
      'success',
    }.contains(paymentStatus)) {
      return true;
    }

    return _parseDate(record['paidAt']) != null ||
        _parseDate(record['paidOn']) != null ||
        _parseDate(record['paymentDate']) != null;
  }

  /// Payroll is intentionally never locked after payment.
  /// `isPaid` is only a status used for display, filtering and reporting.
  static bool canEditPayrollRecord(Map<String, dynamic>? record) => true;

  /// Backward-compatible helper for screens/controllers that previously
  /// expected a lock decision from the service. Always returns false.
  static bool shouldLockPayrollScreen({
    Map<String, dynamic>? payrollRecord,
    DateTime? month,
  }) => false;

  static bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = (value ?? '').toString().trim().toLowerCase();
    return const {'true', '1', 'yes', 'y'}.contains(normalized);
  }

  static bool _hasValue(dynamic value) {
    return value != null && value.toString().trim().isNotEmpty;
  }

  static dynamic _preferNonEmpty(dynamic primary, dynamic fallback) {
    return _hasValue(primary) ? primary : fallback;
  }

  static String _salaryDisplayOrEmpty(Map<String, dynamic> data) {
    final salaryAmount = (data['salaryAmount'] ?? '').toString().trim();
    if (salaryAmount.isNotEmpty) {
      final currency = (data['currency'] ?? 'USD').toString();
      final symbol = getCurrencySymbol(currency);
      return symbol.isEmpty ? salaryAmount : '$symbol $salaryAmount';
    }

    return (data['salary'] ?? '').toString().trim();
  }

  static DateTime _recordSortDate(Map<String, dynamic> record) {
    for (final key in [
      'lastModified',
      'updatedAt',
      'paidAt',
      'paidOn',
      'paymentDate',
      'createdAt',
      'timestamp',
      'payrollDate',
      'date',
    ]) {
      final parsed = _parseDate(record[key]);
      if (parsed != null) return parsed;
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _recordMatchesWorker(
    Map<String, dynamic> record,
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> activeWorkers,
  ) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();

    if (workerId.isNotEmpty && recordWorkerId.isNotEmpty) {
      return workerId == recordWorkerId;
    }

    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final recordEmail = (record['email'] ?? '').toString().trim().toLowerCase();

    if (workerEmail.isNotEmpty && recordEmail.isNotEmpty) {
      return workerEmail == recordEmail;
    }

    // Name matching is only allowed for legacy records that contain neither
    // workerId nor email, and only when that name is unique in the active
    // roster. This prevents two same-name workers sharing one payroll record.
    if (recordWorkerId.isNotEmpty || recordEmail.isNotEmpty) {
      return false;
    }

    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final recordName = (record['name'] ?? record['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (workerName.isEmpty || recordName.isEmpty || workerName != recordName) {
      return false;
    }

    final sameNameWorkers = activeWorkers.where((candidate) {
      return (candidate['name'] ?? '').toString().trim().toLowerCase() ==
          workerName;
    }).length;

    return sameNameWorkers == 1;
  }

  static List<Map<String, dynamic>> combinePayroll(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    DateTime? month,
    bool allowUndatedRecords = false,
  }) {
    final targetMonth = month ?? DateTime.now();
    final activeWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .map(Map<String, dynamic>.from)
        .toList();

    if (activeWorkers.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final monthlyPayrollDocs = rawPayrollDocs
        .where((record) {
          final status = (record['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (status == 'cancelled' || status == 'canceled') {
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

    final combined = <Map<String, dynamic>>[];

    for (final worker in activeWorkers) {
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim();
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final identity = workerId.isNotEmpty ? workerId : email;
      final canonicalPayrollKey = identity.isEmpty
          ? ''
          : '${identity}_${payrollPeriodLabel(targetMonth)}'.toLowerCase();

      final matchingRecords = monthlyPayrollDocs.where((record) {
        return _recordMatchesWorker(record, worker, activeWorkers);
      }).toList();

      matchingRecords.sort((a, b) {
        final aKey = (a['payrollKey'] ?? '').toString().trim().toLowerCase();
        final bKey = (b['payrollKey'] ?? '').toString().trim().toLowerCase();
        final aIsCanonical =
            canonicalPayrollKey.isNotEmpty && aKey == canonicalPayrollKey;
        final bIsCanonical =
            canonicalPayrollKey.isNotEmpty && bKey == canonicalPayrollKey;

        if (aIsCanonical != bIsCanonical) {
          return bIsCanonical ? 1 : -1;
        }

        return _recordSortDate(b).compareTo(_recordSortDate(a));
      });

      final payrollRecord = matchingRecords.isEmpty
          ? <String, dynamic>{}
          : matchingRecords.first;

      if (payrollRecord.isNotEmpty) {
        final salaryAmount = _preferNonEmpty(
          worker['salaryAmount'],
          payrollRecord['salaryAmount'],
        );
        final currency = _preferNonEmpty(
          worker['currency'],
          payrollRecord['currency'],
        );
        final salaryType = _preferNonEmpty(
          worker['salaryType'],
          payrollRecord['salaryType'],
        );
        final profileImage = _preferNonEmpty(
          worker['profileImage'],
          payrollRecord['profileImage'],
        );
        final phone = _preferNonEmpty(worker['phone'], payrollRecord['phone']);

        final currentSalary = _salaryDisplayOrEmpty(worker);
        final historicalSalary = (payrollRecord['salary'] ?? '')
            .toString()
            .trim();
        final mergedSalary = currentSalary.isNotEmpty
            ? currentSalary
            : historicalSalary;
        // Status only: a paid record is still fully editable and saveable.
        final paid = isPayrollRecordPaid(payrollRecord);

        combined.add({
          ...worker,
          ...payrollRecord,
          'workerId': workerId,
          'workerStatus': worker['employmentStatus'] ?? worker['status'],
          'hasPayrollRecord': true,
          'isPaid': paid,
          'hasPaidPayrollRecord': paid,
          'salaryAmount': salaryAmount,
          'currency': currency,
          'salaryType': salaryType,
          if (mergedSalary.isNotEmpty) 'salary': mergedSalary,
          'profileImage': profileImage,
          'phone': phone ?? '',
        });
      } else {
        final salary = _salaryDisplayOrEmpty(worker);

        combined.add({
          ...worker,
          'workerId': workerId,
          'workerStatus': worker['employmentStatus'] ?? worker['status'],
          'hasPayrollRecord': false,
          'isPaid': false,
          'hasPaidPayrollRecord': false,
          'totalWorkDays': '',
          'absents': '',
          'leaves': '',
          'overtimeAmount': '',
          'salary': salary,
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
    final activeWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .map(Map<String, dynamic>.from)
        .toList();

    if (activeWorkers.isEmpty || payrollRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    return payrollRecords.where((record) {
      return activeWorkers.any((worker) {
        return _recordMatchesWorker(record, worker, activeWorkers);
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

    final calculatedWorkedDays = daysWorked.isEmpty
        ? totalWorkDaysVal - absentDays - leaveDays
        : parseIntSafe(daysWorked);
    final workedDaysVal = calculatedWorkedDays
        .clamp(0, totalWorkDaysVal)
        .toInt();

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
          : _fmt(0.0, p),
      'formattedLeaveDeduct': leaveDeduction > 0
          ? '-${_fmt(leaveDeduction, p)}'
          : _fmt(0.0, p),
      'formattedTotalDeductions': totalDeductions > 0
          ? '-${_fmt(totalDeductions, p)}'
          : _fmt(0.0, p),
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
