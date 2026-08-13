import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/currency_utils.dart';

class PayrollReminderWindow {
  final DateTime payrollMonth;
  final DateTime dueDate;

  final int dayOffset;

  const PayrollReminderWindow({
    required this.payrollMonth,
    required this.dueDate,
    required this.dayOffset,
  });

  String get periodKey => PayrollService.payrollPeriodLabel(payrollMonth);
  String get suppressionKey =>
      '${periodKey}_${PayrollService.periodDateKey(dueDate)}';
}

class PayrollService {
  static final PayrollService _instance = PayrollService._();
  factory PayrollService() => _instance;
  PayrollService._();

  static DateTime currentPayrollMonth({DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();
    return DateTime(reference.year, reference.month, 1);
  }

  static DateTime payPeriodStart(DateTime month) =>
      DateTime(month.year, month.month, 1);

  static DateTime payPeriodEnd(DateTime month) =>
      DateTime(month.year, month.month + 1, 0);

  static String payrollPeriodLabel(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  static String formatPayPeriodRange(
    DateTime start,
    DateTime end, {
    String? locale,
  }) {
    String monthLabel(DateTime date) {
      try {
        return DateFormat('MMM', locale).format(date);
      } catch (_) {
        return const [
          '',
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ][date.month];
      }
    }

    final startLabel = '${monthLabel(start)} ${start.day}';
    final endLabel = '${monthLabel(end)} ${end.day}';
    if (start.year == end.year) {
      return '$startLabel – $endLabel, ${end.year}';
    }
    return '$startLabel, ${start.year} – $endLabel, ${end.year}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String periodDateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}';

  static String payrollKeyForPeriod(
    String identity,
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    final normalizedIdentity = identity.trim().toLowerCase();
    if (normalizedIdentity.isEmpty) return '';
    return '${normalizedIdentity}_${periodDateKey(periodStart)}_${periodDateKey(periodEnd)}';
  }

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

  static DateTime payrollDueDate(DateTime month, int payDay) {
    final normalizedDay = payDay.clamp(1, 31).toInt();
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(
      month.year,
      month.month,
      normalizedDay.clamp(1, lastDay).toInt(),
    );
  }

  static PayrollReminderWindow? reminderWindowForDate(
    DateTime date, {
    int? payDay,
    int leadDays = 3,
    int? overdueDays,
  }) {
    final today = DateTime(date.year, date.month, date.day);
    final currentMonth = DateTime(today.year, today.month, 1);
    final currentDueDate = payDay == null
        ? payPeriodEnd(today)
        : payrollDueDate(currentMonth, payDay);
    final daysUntilCurrentDue = currentDueDate.difference(today).inDays;
    if (daysUntilCurrentDue >= 0 && daysUntilCurrentDue <= leadDays) {
      return PayrollReminderWindow(
        payrollMonth: currentMonth,
        dueDate: currentDueDate,
        dayOffset: -daysUntilCurrentDue,
      );
    }

    final daysAfterCurrentDue = today.difference(currentDueDate).inDays;
    if (daysAfterCurrentDue > 0 &&
        (overdueDays == null || daysAfterCurrentDue <= overdueDays)) {
      return PayrollReminderWindow(
        payrollMonth: currentMonth,
        dueDate: currentDueDate,
        dayOffset: daysAfterCurrentDue,
      );
    }

    final previousMonth = DateTime(today.year, today.month - 1, 1);
    final previousDueDate = payDay == null
        ? payPeriodEnd(previousMonth)
        : payrollDueDate(previousMonth, payDay);
    final daysAfterPreviousDue = today.difference(previousDueDate).inDays;
    if (daysAfterPreviousDue > 0 &&
        (overdueDays == null || daysAfterPreviousDue <= overdueDays)) {
      return PayrollReminderWindow(
        payrollMonth: previousMonth,
        dueDate: previousDueDate,
        dayOffset: daysAfterPreviousDue,
      );
    }
    return null;
  }

  static Map<String, dynamic> editedNetSalaryFields(
    double amount, {
    required String currency,
  }) {
    final normalizedAmount = amount.clamp(0, double.infinity).toDouble();
    final formatted = formatAmountInCurrency(normalizedAmount, currency);
    return {
      'netSalaryAmount': normalizedAmount,
      'netSalary': formatted,
      'netSalaryFormatted': formatted,
      'salaryAfterDeduction': formatted,
      'amount': normalizedAmount,
    };
  }

  static Map<String, dynamic> reopenedPayrollFields() => const {
    'status': 'Unpaid',
    'isPaid': false,
    'paid': false,
    'paymentStatus': 'unpaid',
  };

  static bool workerJoinedBeforePeriodEnd(
    Map<String, dynamic> worker,
    DateTime month,
  ) {
    final joiningDate = _parseDate(
      worker['joiningDate'] ?? worker['dateOfJoining'],
    );
    if (joiningDate == null) return true;
    final periodEnd = payPeriodEnd(month);

    return !joiningDate.isAfter(periodEnd);
  }

  static bool allWorkersHavePayrollRecords(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month, {
    bool allowUndatedRecords = false,
  }) {
    final expectedWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .where((worker) => workerJoinedBeforePeriodEnd(worker, month))
        .toList();
    if (expectedWorkers.isEmpty) return true;

    final combined = combinePayroll(
      expectedWorkers,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
    );

    return combined.every((worker) => worker['hasPayrollRecord'] == true);
  }

  static bool hasUnpaidWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
    DateTime month,
  ) {
    final combined = combinePayroll(workersList, rawPayrollDocs, month: month);
    return combined.any((worker) => worker['isPaid'] != true);
  }

  static List<Map<String, dynamic>> unpaidWorkersForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
  }) {
    return combinePayroll(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
    ).where((worker) => worker['isPaid'] != true).toList();
  }

  static List<Map<String, dynamic>> payableWorkersForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
  }) {
    return unpaidWorkersForPeriod(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
    ).where((worker) {
      return extractSalary(
            currentSalaryDisplay(worker, companyCurrency: companyCurrency),
          ) >
          0;
    }).toList();
  }

  static bool allWorkersPaidForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
  }) {
    return unpaidWorkersForPeriod(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
    ).isEmpty;
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

  static String workerEmploymentType(Map<String, dynamic> worker) {
    for (final key in [
      'type1',
      'employmentType',
      'employment_type',
      'workType',
      'workerType',
      'contractType',
    ]) {
      final value = (worker[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool isPayrollRecordPaid(Map<String, dynamic> record) {
    final explicitSalaryValues = [
      record['salaryAmount'],
      record['salary'],
      record['baseSalary'],
      record['grossSalary'],
    ].where(_hasValue).toList();
    if (explicitSalaryValues.isNotEmpty &&
        explicitSalaryValues.every(
          (value) => extractSalary(value.toString()) <= 0,
        )) {
      return false;
    }

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

  static String? _companyCurrencyCode(String? companyCurrency) {
    final value = companyCurrency?.trim() ?? '';
    return value.isEmpty ? null : CurrencyUtils.normalize(value);
  }

  static String formatAmountInCurrency(dynamic value, String currency) {
    final rawValue = (value ?? '').toString().trim();
    if (rawValue.isEmpty) return '';
    final symbol = getCurrencySymbol(CurrencyUtils.normalize(currency));
    return '$symbol ${formatFullNumber(extractSalary(rawValue))}';
  }

  static String _salaryDisplayOrEmpty(
    Map<String, dynamic> data, {
    String? companyCurrency,
  }) {
    final companyCurrencyCode = _companyCurrencyCode(companyCurrency);
    final workerCurrency = CurrencyUtils.normalize(data['currency']);
    final salaryAmount = (data['salaryAmount'] ?? '').toString().trim();
    if (salaryAmount.isNotEmpty) {
      final currency = companyCurrencyCode ?? workerCurrency;
      final symbol = getCurrencySymbol(currency);
      return symbol.isEmpty ? salaryAmount : '$symbol $salaryAmount';
    }

    final salary = (data['salary'] ?? '').toString().trim();
    if (salary.isEmpty) return salary;
    final effectiveCurrency = companyCurrencyCode ?? workerCurrency;
    return formatAmountInCurrency(salary, effectiveCurrency);
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

    if ((workerId.isNotEmpty && recordWorkerId.isNotEmpty) ||
        recordEmail.isNotEmpty) {
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
    String? companyCurrency,
  }) {
    final targetMonth = month ?? DateTime.now();
    final companyCurrencyCode = _companyCurrencyCode(companyCurrency);
    final activeWorkers = workersList
        .where(isWorkerEligibleForPayroll)
        .where((worker) => workerJoinedBeforePeriodEnd(worker, targetMonth))
        .map(Map<String, dynamic>.from)
        .toList();

    if (activeWorkers.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final monthlyPayrollDocs = rawPayrollDocs
        .where(
          (record) => isRecordInMonth(
            record,
            targetMonth,
            allowUndated: allowUndatedRecords,
          ),
        )
        .map(Map<String, dynamic>.from)
        .toList();

    final combined = <Map<String, dynamic>>[];

    for (final worker in activeWorkers) {
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim();
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final identity = workerId.isNotEmpty ? workerId : email;
      final newPayrollKey = identity.isEmpty
          ? ''
          : payrollKeyForPeriod(
              identity,
              payPeriodStart(targetMonth),
              payPeriodEnd(targetMonth),
            );
      final legacyPayrollKey = identity.isEmpty
          ? ''
          : '${identity}_${payrollPeriodLabel(targetMonth)}'.toLowerCase();
      final canonicalKeys = <String>{newPayrollKey, legacyPayrollKey}
        ..remove('');

      final canonicalRecord = canonicalKeys.isEmpty
          ? null
          : rawPayrollDocs.cast<Map<String, dynamic>?>().firstWhere(
              (record) =>
                  record != null &&
                  canonicalKeys.contains(
                    (record['payrollKey'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase(),
                  ),
              orElse: () => null,
            );
      final canonicalRecordMovedOut =
          canonicalRecord != null &&
          !isRecordInMonth(
            canonicalRecord,
            targetMonth,
            allowUndated: allowUndatedRecords,
          );

      final matchingRecords = canonicalRecordMovedOut
          ? <Map<String, dynamic>>[]
          : monthlyPayrollDocs.where((record) {
              return _recordMatchesWorker(record, worker, activeWorkers);
            }).toList();

      matchingRecords.sort((a, b) {
        final aKey = (a['payrollKey'] ?? '').toString().trim().toLowerCase();
        final bKey = (b['payrollKey'] ?? '').toString().trim().toLowerCase();
        final aIsCanonical =
            canonicalKeys.isNotEmpty && canonicalKeys.contains(aKey);
        final bIsCanonical =
            canonicalKeys.isNotEmpty && canonicalKeys.contains(bKey);

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
        final currency =
            companyCurrencyCode ??
            CurrencyUtils.normalize(
              _preferNonEmpty(worker['currency'], payrollRecord['currency']),
            );
        final salaryType = _preferNonEmpty(
          worker['salaryType'],
          payrollRecord['salaryType'],
        );
        final profileImage = _preferNonEmpty(
          worker['profileImage'],
          payrollRecord['profileImage'],
        );
        final phone = _preferNonEmpty(
          worker['phone'],
          _preferNonEmpty(
            payrollRecord['phone'],
            _preferNonEmpty(worker['contact'], payrollRecord['contact']),
          ),
        );

        final currentSalary = _salaryDisplayOrEmpty(
          worker,
          companyCurrency: companyCurrencyCode,
        );
        final historicalSalary = (payrollRecord['salary'] ?? '')
            .toString()
            .trim();
        final mergedSalary = currentSalary.isNotEmpty
            ? currentSalary
            : companyCurrencyCode == null || historicalSalary.isEmpty
            ? historicalSalary
            : formatAmountInCurrency(historicalSalary, companyCurrencyCode);
        final historicalNetSalary = _preferNonEmpty(
          payrollRecord['netSalary'],
          payrollRecord['netSalaryFormatted'],
        ).toString().trim();
        final mergedNetSalary =
            companyCurrencyCode == null || historicalNetSalary.isEmpty
            ? historicalNetSalary
            : formatAmountInCurrency(historicalNetSalary, companyCurrencyCode);

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
          if (mergedNetSalary.isNotEmpty) ...{
            'netSalary': mergedNetSalary,
            'netSalaryFormatted': mergedNetSalary,
            'salaryAfterDeduction': mergedNetSalary,
          },
          'profileImage': profileImage,
          'phone': phone ?? '',
        });
      } else {
        final salary = _salaryDisplayOrEmpty(
          worker,
          companyCurrency: companyCurrencyCode,
        );
        final currency =
            companyCurrencyCode ?? CurrencyUtils.normalize(worker['currency']);

        combined.add({
          ...worker,
          'status': worker['status'] ?? 'Active',
          'workerId': workerId,
          'workerStatus': worker['employmentStatus'] ?? worker['status'],
          'hasPayrollRecord': false,
          'isPaid': false,
          'hasPaidPayrollRecord': false,
          'totalWorkDays': '',
          'absents': '',
          'leaves': '',
          'overtimeAmount': '',
          'currency': currency,
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

  static List<Map<String, dynamic>> paidPayrollRecordsForActiveWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> payrollRecords,
  ) {
    return payrollRecordsForActiveWorkers(
      workersList,
      payrollRecords,
    ).where(isPayrollRecordPaid).toList();
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

    final dateRangeMatch = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})_(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(payrollKey);
    if (dateRangeMatch != null) {
      final year = int.tryParse(dateRangeMatch.group(4)!);
      final month = int.tryParse(dateRangeMatch.group(5)!);
      final day = int.tryParse(dateRangeMatch.group(6)!);
      if (year != null &&
          month != null &&
          day != null &&
          month >= 1 &&
          month <= 12) {
        return DateTime(year, month, day);
      }
    }

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

  static DateTime? payrollPaymentDate(Map<String, dynamic> record) {
    for (final key in [
      'paidAt',
      'paidOn',
      'paymentDate',
      'payrollDate',
      'createdAt',
    ]) {
      final parsed = _parseDate(record[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static bool wasPaidOn(Map<String, dynamic> record, DateTime date) {
    if (!isPayrollRecordPaid(record)) return false;
    final paidAt = payrollPaymentDate(record);
    return paidAt != null &&
        paidAt.year == date.year &&
        paidAt.month == date.month &&
        paidAt.day == date.day;
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
    final trimmed = salaryStr.trim();
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    final numericPart = firstDigit == null
        ? trimmed
        : trimmed.substring(firstDigit.start);
    final suffix = RegExp(
      r'([KMBT])\s*$',
      caseSensitive: false,
    ).firstMatch(numericPart)?.group(1)?.toUpperCase();
    final multiplier = switch (suffix) {
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      'T' => 1e12,
      _ => 1.0,
    };
    String cleaned = numericPart.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return 0;

    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final commaCount = ','.allMatches(cleaned).length;
      final digitsAfterComma = cleaned.length - lastComma - 1;
      if (commaCount > 1 || digitsAfterComma == 3) {
        cleaned = cleaned.replaceAll(',', '');
      } else {
        cleaned = cleaned.replaceAll(',', '.');
      }
    } else if ('.'.allMatches(cleaned).length > 1) {
      cleaned = cleaned.replaceAll('.', '');
    }
    return (double.tryParse(cleaned) ?? 0) * multiplier;
  }

  static int parseIntSafe(String value) {
    if (value.isEmpty) return 0;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String currentSalaryDisplay(
    Map<String, dynamic> data, {
    String? companyCurrency,
  }) {
    final salary = _salaryDisplayOrEmpty(
      data,
      companyCurrency: companyCurrency,
    );
    if (salary.isNotEmpty) return salary;
    final currency =
        _companyCurrencyCode(companyCurrency) ??
        CurrencyUtils.normalize(data['currency']);
    return '${getCurrencySymbol(currency)} 0';
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

  static String formatNumber(num number, {String locale = 'en_US'}) {
    if (number.isNaN || number.isInfinite) return '0';
    final isNegative = number < 0;
    final absolute = isNegative ? -number : number;
    final abs = absolute;
    if (abs >= 1e3) {
      final compact = CurrencyUtils.formatCompactLocale(
        number.toDouble(),
        locale,
        symbol: '',
      );
      return isNegative ? '($compact)' : compact;
    }
    final roundedStr = absolute.toStringAsFixed(0);
    final formatted = roundedStr.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    if (isNegative) return '($formatted)';
    return formatted;
  }

  static String formatFullNumber(num number, {String locale = 'en_US'}) {
    if (number.isNaN || number.isInfinite) return '0';
    final hasDecimals = number != number.roundToDouble();
    try {
      final formatted = NumberFormat.currency(
        locale: locale,
        symbol: '',
        decimalDigits: hasDecimals ? 2 : 0,
      ).format(number);
      return formatted.trim();
    } catch (_) {
      final parts = number.toStringAsFixed(hasDecimals ? 2 : 0).split('.');
      final formattedInteger = parts.first.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match match) => '${match[1]},',
      );
      return parts.length == 1
          ? formattedInteger
          : '$formattedInteger.${parts[1]}';
    }
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
    return '$prefix${formatFullNumber(val)}';
  }

  static double calculateNetFromTotals({
    required String salary,
    String overtimeAmount = '',
    String absentDeduction = '',
    String leaveDeduction = '',
    String customDeduction = '',
    String salaryType = 'Monthly',
    double taxRatePercent = 0.0,
    double prorationFactor = 1.0,
  }) {
    final enteredSalary = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual'
        ? enteredSalary / 12
        : enteredSalary;
    final overtimeVal = extractSalary(overtimeAmount);
    final absentVal = extractSalary(absentDeduction);
    final leaveVal = extractSalary(leaveDeduction);
    final customVal = extractSalary(customDeduction);

    final subtotal =
        (periodSalary * prorationFactor +
                overtimeVal -
                absentVal -
                leaveVal -
                customVal)
            .clamp(0.0, double.infinity);
    final taxDeduction = taxRatePercent > 0
        ? (subtotal * (taxRatePercent / 100))
        : 0.0;
    final netSalary = subtotal - taxDeduction;
    return netSalary.clamp(0.0, double.infinity).toDouble();
  }

  static double maximumAbsentDeduction({
    required String salary,
    String overtimeAmount = '',
    String leaveDeduction = '',
    String customDeduction = '',
    String salaryType = 'Monthly',
    double prorationFactor = 1.0,
  }) {
    final enteredSalary = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual'
        ? enteredSalary / 12
        : enteredSalary;
    final availableEarnings =
        (periodSalary * prorationFactor) +
        extractSalary(overtimeAmount) -
        extractSalary(leaveDeduction) -
        extractSalary(customDeduction);
    return availableEarnings.clamp(0.0, double.infinity).toDouble();
  }

  static double cappedAbsentDeduction({
    required bool hasAbsences,
    required num requestedDeduction,
    required String salary,
    String overtimeAmount = '',
    String leaveDeduction = '',
    String customDeduction = '',
    String salaryType = 'Monthly',
    double prorationFactor = 1.0,
  }) {
    if (!hasAbsences || !requestedDeduction.isFinite) return 0.0;
    final maximum = maximumAbsentDeduction(
      salary: salary,
      overtimeAmount: overtimeAmount,
      leaveDeduction: leaveDeduction,
      customDeduction: customDeduction,
      salaryType: salaryType,
      prorationFactor: prorationFactor,
    );
    return requestedDeduction.clamp(0.0, maximum).toDouble();
  }

  static double prorationFactor({
    DateTime? joiningDate,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int totalWorkDays,
    Set<DateTime>? workingDates,
  }) {
    final join = joiningDate == null
        ? null
        : DateTime(joiningDate.year, joiningDate.month, joiningDate.day);
    final start = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    if (join == null || !join.isAfter(start)) return 1.0;
    if (!join.isBefore(end)) return 0.0;
    if (totalWorkDays <= 0) return 1.0;

    int availableDays;
    if (workingDates != null && workingDates.isNotEmpty) {
      availableDays = workingDates.where((date) => !date.isBefore(join)).length;
    } else {
      final totalDays = end.difference(start).inDays;
      final elapsedBeforeJoin = join.difference(start).inDays;
      availableDays = totalDays > 0
          ? (totalDays - elapsedBeforeJoin)
          : totalDays;
    }
    return (availableDays / totalWorkDays).clamp(0.0, 1.0).toDouble();
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
    double taxRatePercent = 0.0,
    double prorationFactor = 1.0,
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

    final grossSalary = periodSalary * prorationFactor;

    final overtimePay = customOvertimeAmount;

    final leaveDeduction = leaveDays > 0
        ? (customLeaveDeduction > 0
              ? customLeaveDeduction
              : leaveDays * dailyRate)
        : 0.0;
    final requestedAbsentDeduction = absentDays > 0
        ? (customAbsentDeduction > 0
              ? customAbsentDeduction
              : absentDays * dailyRate)
        : 0.0;
    final absentDeduction = cappedAbsentDeduction(
      hasAbsences: absentDays > 0,
      requestedDeduction: requestedAbsentDeduction,
      salary: salary,
      overtimeAmount: overtimeAmount,
      leaveDeduction: leaveDeduction.toString(),
      salaryType: salaryType,
      prorationFactor: prorationFactor,
    );

    final subtotalBeforeTax =
        (grossSalary + overtimePay - absentDeduction - leaveDeduction).clamp(
          0.0,
          double.infinity,
        );
    final taxDeduction = taxRatePercent > 0
        ? (subtotalBeforeTax * (taxRatePercent / 100))
        : 0.0;

    final totalDeductions = absentDeduction + leaveDeduction + taxDeduction;

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
      'absentDeductionPerDayApplied': absentDays > 0
          ? absentDeduction / absentDays
          : 0.0,
      'leaveDeductionPerDayApplied': leaveDays > 0
          ? leaveDeduction / leaveDays
          : 0.0,
      'absentDeduction': absentDeduction,
      'leaveDeduction': leaveDeduction,
      'taxRatePercent': taxRatePercent,
      'taxDeduction': taxDeduction,
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
      'formattedTaxDeduct': taxDeduction > 0
          ? '-${_fmt(taxDeduction, p)}'
          : _fmt(0.0, p),
      'formattedTotalDeductions': totalDeductions > 0
          ? '-${_fmt(totalDeductions, p)}'
          : _fmt(0.0, p),
      'formattedNetSalary': _fmt(netSalary, p),
      'formattedNet': _fmt(netSalary, p),
    };
  }
}
