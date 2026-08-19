import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/helpers.dart';
import '../utils/utils.dart';

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
  String get suppressionKey => '${periodKey}_${PayrollService.periodDateKey(dueDate)}';
}

class PayrollPeriod {
  final DateTime start;
  final DateTime end;

  const PayrollPeriod({required this.start, required this.end});
}

class PayrollService {
  static DateTime currentPayrollMonth({DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();
    return DateTime(reference.year, reference.month, 1);
  }

  static DateTime payPeriodStart(DateTime month) => DateTime(month.year, month.month, 1);
  static DateTime payPeriodEnd(DateTime month) => DateTime(month.year, month.month + 1, 0);

  static DateTime _payDayInMonth(DateTime month, int payDay) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final clampedPayDay = payDay.clamp(1, lastDay);
    return DateTime(month.year, month.month, clampedPayDay);
  }

  static PayrollPeriod payDayPeriodContaining(DateTime date, int payDay) {
    final month = DateTime(date.year, date.month, 1);
    final payDayThisMonth = _payDayInMonth(month, payDay);
    final today = DateTime(date.year, date.month, date.day);

    return today.isAfter(payDayThisMonth)
        ? PayrollPeriod(
            start: payDayThisMonth,
            end: _payDayInMonth(DateTime(month.year, month.month + 1, 1), payDay),
          )
        : PayrollPeriod(
            start: _payDayInMonth(DateTime(month.year, month.month - 1, 1), payDay),
            end: payDayThisMonth,
          );
  }

  static PayrollPeriod payDayPeriod(DateTime dueMonth, int payDay) {
    final prevMonthPayDay = _payDayInMonth(DateTime(dueMonth.year, dueMonth.month - 1, 1), payDay);
    return PayrollPeriod(
      start: prevMonthPayDay,
      end: _payDayInMonth(dueMonth, payDay),
    );
  }

  static PayrollPeriod nextPayDayPeriod(PayrollPeriod current, int payDay) {
    final currentEndMonth = DateTime(current.end.year, current.end.month, 1);
    final currentEndPayDay = _payDayInMonth(currentEndMonth, payDay);
    final nextEnd = _payDayInMonth(DateTime(currentEndMonth.year, currentEndMonth.month + 1, 1), payDay);
    return PayrollPeriod(
      start: currentEndPayDay,
      end: nextEnd,
    );
  }

  static bool payrollPeriodsEqual(PayrollPeriod a, PayrollPeriod b) =>
      periodDateKey(a.start) == periodDateKey(b.start) &&
      periodDateKey(a.end) == periodDateKey(b.end);

  static PayrollPeriod getNextFullMonthlyCycleAfter(DateTime anchor, int payDay) {
    final normalizedPayDay = payDay.clamp(1, 28);
    var candidateStart = DateTime(anchor.year, anchor.month, normalizedPayDay);
    if (candidateStart.isBefore(anchor)) {
      candidateStart = DateTime(anchor.year, anchor.month + 1, normalizedPayDay);
    }
    final candidateEnd = DateTime(candidateStart.year, candidateStart.month + 1, normalizedPayDay);
    return PayrollPeriod(start: candidateStart, end: candidateEnd);
  }

  /// Returns the first occurrence of [payDay] strictly after [anchor].
  static DateTime getNextPayDayAfter(DateTime anchor, int payDay) {
    final normalizedPayDay = payDay.clamp(1, 28);
    var candidate = DateTime(anchor.year, anchor.month, normalizedPayDay);
    if (!candidate.isAfter(anchor)) {
      candidate = DateTime(anchor.year, anchor.month + 1, normalizedPayDay);
    }
    return candidate;
  }

  /// Returns the latest SETTLED (fully paid) payroll cycle from records.
  static PayrollPeriod? latestSettledPayrollCycle(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    String? companyCurrency,
  }) {
    final candidatePeriods = <String, PayrollPeriod>{};
    for (final record in rawPayrollDocs) {
      if (!isPayrollRecordPaid(record)) continue;
      final start = _parseDate(record['payPeriodStart']);
      final end = _parseDate(record['payPeriodEnd']);
      if (start != null && end != null && start.isBefore(end)) {
        final period = PayrollPeriod(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day),
        );
        final key = '${periodDateKey(period.start)}_${periodDateKey(period.end)}';
        candidatePeriods[key] = period;
      }
    }

    if (candidatePeriods.isEmpty) return null;

    PayrollPeriod? latestSettled;
    for (final period in candidatePeriods.values) {
      final unpaid = unpaidWorkersForPeriod(
        workersList,
        rawPayrollDocs,
        month: DateTime(period.end.year, period.end.month, 1),
        allowUndatedRecords: true,
        companyCurrency: companyCurrency,
        periodStart: period.start,
        periodEnd: period.end,
      );
      final hasUnpaid = unpaid.any((worker) =>
          extractSalary(currentSalaryDisplay(worker, companyCurrency: companyCurrency)) > 0);

      if (!hasUnpaid) {
        if (latestSettled == null || period.end.isAfter(latestSettled.end)) {
          latestSettled = period;
        }
      }
    }
    return latestSettled;
  }

  static PayrollPeriod resolveCurrentPayrollPeriod({
    required List<Map<String, dynamic>> workersList,
    required List<Map<String, dynamic>> payrollRecords,
    required int payDay,
    String? companyCurrency,
    DateTime? referenceDate,
    PayrollPeriod? persistedCycle,
    bool advanceIfFullyPaid = true,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedPayDay = payDay.clamp(1, 28);

    final lastPaid = latestSettledPayrollCycle(
      workersList,
      payrollRecords,
      companyCurrency: companyCurrency,
    );

    if (lastPaid != null && !today.isBefore(lastPaid.start)) {
      if (today.isBefore(lastPaid.end)) {
        return lastPaid;
      }
      final nextCycle = getNextFullMonthlyCycleAfter(lastPaid.end, normalizedPayDay);

      final nextUnpaid = unpaidWorkersForPeriod(
        workersList,
        payrollRecords,
        month: DateTime(nextCycle.end.year, nextCycle.end.month, 1),
        allowUndatedRecords: true,
        companyCurrency: companyCurrency,
        periodStart: nextCycle.start,
        periodEnd: nextCycle.end,
      );

      final hasPayableNext = nextUnpaid.any((worker) =>
          extractSalary(currentSalaryDisplay(worker, companyCurrency: companyCurrency)) > 0);

      if (hasPayableNext || !advanceIfFullyPaid) {
        if (persistedCycle != null &&
            persistedCycle.end.isAfter(persistedCycle.start) &&
            persistedCycle.end.difference(lastPaid.end).inDays >= 20) {
          final persistedUnpaid = unpaidWorkersForPeriod(
            workersList,
            payrollRecords,
            month: DateTime(persistedCycle.end.year, persistedCycle.end.month, 1),
            allowUndatedRecords: true,
            companyCurrency: companyCurrency,
            periodStart: persistedCycle.start,
            periodEnd: persistedCycle.end,
          );
          if (persistedUnpaid.any((w) => extractSalary(currentSalaryDisplay(w, companyCurrency: companyCurrency)) > 0)) {
            return persistedCycle;
          }
        }
        return nextCycle;
      } else {
        final followingCycle = getNextFullMonthlyCycleAfter(nextCycle.end, normalizedPayDay);
        if (persistedCycle != null &&
            periodDateKey(persistedCycle.start) == periodDateKey(followingCycle.start) &&
            periodDateKey(persistedCycle.end) == periodDateKey(followingCycle.end)) {
          return persistedCycle;
        }
        return followingCycle;
      }
    }

    final base = normalizedPayDay <= 0
        ? PayrollPeriod(start: payPeriodStart(today), end: payPeriodEnd(today))
        : payDayPeriodContaining(today, normalizedPayDay);
    final next = nextPayDayPeriod(base, normalizedPayDay);

    PayrollPeriod? anchor;
    if (persistedCycle != null) {
      if (payrollPeriodsEqual(persistedCycle, base)) {
        anchor = base;
      } else if (payrollPeriodsEqual(persistedCycle, next)) {
        anchor = next;
      }
    }

    final currentMonthPayday = _payDayInMonth(
      DateTime(today.year, today.month, 1), normalizedPayDay);

    if (anchor == null && today.isAfter(currentMonthPayday)) {
      final prevCycleEnd = base.start;
      final prevCycleStart = _payDayInMonth(
        DateTime(prevCycleEnd.year, prevCycleEnd.month - 1, 1),
        normalizedPayDay,
      );

      final allRecordsAfterPrevCycle = payrollRecords.isNotEmpty &&
          payrollRecords.every((record) {
        final savedEnd = _parseDate(record['payPeriodEnd']);
        return savedEnd != null && savedEnd.isAfter(prevCycleEnd);
      });

      if (!allRecordsAfterPrevCycle) {
        final prevPayable = payableWorkersForPeriod(
          workersList,
          payrollRecords,
          month: DateTime(prevCycleEnd.year, prevCycleEnd.month, 1),
          allowUndatedRecords: true,
          companyCurrency: companyCurrency,
          periodStart: prevCycleStart,
          periodEnd: prevCycleEnd,
        );

        if (prevPayable.isNotEmpty) {
          if (anchor != null && payrollPeriodsEqual(anchor, next)) {
            return anchor;
          }
          return PayrollPeriod(start: prevCycleStart, end: prevCycleEnd);
        }
      }
    }

    final payable = payableWorkersForPeriod(
      workersList,
      payrollRecords,
      month: DateTime(base.end.year, base.end.month, 1),
      allowUndatedRecords: true,
      companyCurrency: companyCurrency,
      periodStart: base.start,
      periodEnd: base.end,
    );

    if (today.isBefore(base.end)) return anchor ?? base;

    if (payable.isNotEmpty) return base;

    if (!advanceIfFullyPaid) {
      return anchor ?? base;
    }

    return next;
  }

  static String payrollPeriodLabel(DateTime month) => '${month.year}-${pad2(month.month)}';

  static String formatPayPeriodRange(DateTime start, DateTime end, {String? locale}) {
    final startLabel = '${_monthLabel(start, locale)} ${start.day}';
    final endLabel = '${_monthLabel(end, locale)} ${end.day}';
    return start.year == end.year
        ? '$startLabel – $endLabel, ${end.year}'
        : '$startLabel, ${start.year} – $endLabel, ${end.year}';
  }

  static String _monthLabel(DateTime date, String? locale) {
    try {
      return DateFormat('MMM', locale).format(date);
    } catch (_) {
      return const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month];
    }
  }

  static String periodDateKey(DateTime d) => '${pad4(d.year)}-${pad2(d.month)}-${pad2(d.day)}';

  static String payrollKeyForPeriod(String identity, DateTime periodStart, DateTime periodEnd) {
    final normalizedIdentity = identity.trim().toLowerCase();
    return normalizedIdentity.isEmpty
        ? ''
        : '${normalizedIdentity}_${periodDateKey(periodStart)}_${periodDateKey(periodEnd)}';
  }

  static bool workerEmployedDuringPeriod(Map<String, dynamic> worker, DateTime periodEnd) {
    final joiningDate = _parseDate(worker['joiningDate'] ?? worker['dateOfJoining']);
    return joiningDate == null || !joiningDate.isAfter(periodEnd);
  }

  static List<Map<String, dynamic>> unpaidWorkersForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final effectivePeriodEnd = periodEnd ?? payPeriodEnd(month);
    return combinePayroll(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ).where((worker) =>
        worker['isPaid'] != true &&
        workerEmployedDuringPeriod(worker, effectivePeriodEnd)
    ).toList();
  }  static List<Map<String, dynamic>> payableWorkersForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    return unpaidWorkersForPeriod(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ).where((worker) =>
        extractSalary(currentSalaryDisplay(worker, companyCurrency: companyCurrency)) > 0
    ).toList();

  }

          static List<Map<String, dynamic>> excludedLateJoinersForPeriod(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    required DateTime month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final effectivePeriodEnd = periodEnd ?? payPeriodEnd(month);
    return combinePayroll(
      workersList,
      rawPayrollDocs,
      month: month,
      allowUndatedRecords: allowUndatedRecords,
      companyCurrency: companyCurrency,
      periodStart: periodStart,
      periodEnd: periodEnd,
    ).where((worker) =>
        worker['isPaid'] != true &&
        !workerEmployedDuringPeriod(worker, effectivePeriodEnd) &&
        extractSalary(currentSalaryDisplay(worker, companyCurrency: companyCurrency)) > 0
    ).toList();
  }

  static String canonicalWorkerStatus(Map<String, dynamic> worker) {
    if (_isTruthy(worker['isDeleted']) || _isTruthy(worker['deleted']) || _isTruthy(worker['isArchived'])) {
      return 'Terminated';
    }
    for (final key in ['employmentStatus', 'workerStatus', 'status']) {
      final value = (worker[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'Active';
  }

  static bool isWorkerEligibleForPayroll(Map<String, dynamic> worker) {
    final status = canonicalWorkerStatus(worker).trim().toLowerCase();
    return !const {'deleted', 'inactive', 'terminated', 'archived'}.contains(status);
  }

  static String workerEmploymentType(Map<String, dynamic> worker) {
    for (final key in ['type1', 'employmentType', 'employment_type', 'workType', 'workerType', 'contractType']) {
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

    if (explicitSalaryValues.isNotEmpty && explicitSalaryValues.every((v) => extractSalary(v.toString()) <= 0)) {
      return false;
    }

    if (_isTruthy(record['isPaid']) || _isTruthy(record['paid'])) return true;

    final paymentStatus = (record['paymentStatus'] ?? record['status'] ?? '').toString().trim().toLowerCase();
    if (const {'paid', 'completed', 'processed', 'successful', 'success'}.contains(paymentStatus)) {
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

  static bool _hasValue(dynamic value) => value != null && value.toString().trim().isNotEmpty;
  static dynamic _preferNonEmpty(dynamic primary, dynamic fallback) => _hasValue(primary) ? primary : fallback;

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

  static String _salaryDisplayOrEmpty(Map<String, dynamic> data, {String? companyCurrency}) {
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
    for (final key in ['lastModified', 'updatedAt', 'paidAt', 'paidOn', 'paymentDate', 'createdAt', 'timestamp', 'payrollDate', 'date']) {
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
    if (WorkerIdentity.matchesByIdOrEmail(record, worker)) return true;

    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    final workerId = WorkerIdentity.normalizeId(worker);
    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
    if ((workerId.isNotEmpty && recordWorkerId.isNotEmpty) ||
        recordEmail.isNotEmpty) {
      return false;
    }

    return WorkerIdentity.recordsMatchByUniqueName(
      record,
      worker,
      activeWorkers,
    );
  }

  static List<Map<String, dynamic>> combinePayroll(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs, {
    DateTime? month,
    bool allowUndatedRecords = false,
    String? companyCurrency,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final targetMonth = month ?? DateTime.now();
    final effectivePeriodStart = periodStart ?? payPeriodStart(targetMonth);
    final effectivePeriodEnd = periodEnd ?? payPeriodEnd(targetMonth);
    final companyCurrencyCode = _companyCurrencyCode(companyCurrency);

    final activeWorkers = _filterActiveWorkers(workersList, rawPayrollDocs).map(Map<String, dynamic>.from).toList();
    if (activeWorkers.isEmpty) return const <Map<String, dynamic>>[];

    final monthlyPayrollDocs = rawPayrollDocs
        .where((record) => isRecordInPayPeriod(record, effectivePeriodStart, effectivePeriodEnd, allowUndated: allowUndatedRecords))
        .map(Map<String, dynamic>.from)
        .toList();

    return _combineWorkerRecords(
      activeWorkers,
      monthlyPayrollDocs,
      rawPayrollDocs,
      effectivePeriodStart,
      effectivePeriodEnd,
      targetMonth,
      companyCurrencyCode,
    );
  }

  static List<Map<String, dynamic>> _filterActiveWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> rawPayrollDocs,
  ) {
    return workersList.where((worker) {
      if (isWorkerEligibleForPayroll(worker)) return true;
      return rawPayrollDocs
          .any((doc) => WorkerIdentity.matchesByIdOrEmail(doc, worker));
    }).toList();
  }

  static List<Map<String, dynamic>> _combineWorkerRecords(
    List<Map<String, dynamic>> activeWorkers,
    List<Map<String, dynamic>> monthlyPayrollDocs,
    List<Map<String, dynamic>> allPayrollDocs,
    DateTime effectivePeriodStart,
    DateTime effectivePeriodEnd,
    DateTime targetMonth,
    String? companyCurrencyCode,
  ) {
    final combined = <Map<String, dynamic>>[];

    for (final worker in activeWorkers) {
      final workerId = (worker['workerId'] ?? worker['id'] ?? '').toString().trim();
      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      final identity = workerId.isNotEmpty ? workerId : email;

      final canonicalKeys = _getCanonicalKeys(identity, effectivePeriodStart, effectivePeriodEnd, targetMonth);
      final canonicalRecord = _findCanonicalRecord(allPayrollDocs, canonicalKeys, effectivePeriodStart, effectivePeriodEnd, allowUndated: false);
      final matchingRecords = _getMatchingRecords(worker, activeWorkers, monthlyPayrollDocs, canonicalKeys, canonicalRecord, effectivePeriodStart, effectivePeriodEnd);

      final payrollRecord = matchingRecords.isEmpty ? <String, dynamic>{} : matchingRecords.first;

      if (payrollRecord.isNotEmpty) {
        combined.add(_buildMergedWorkerRecord(worker, payrollRecord, workerId, companyCurrencyCode));
      } else {
        combined.add(_buildUnpaidWorkerRecord(worker, workerId, companyCurrencyCode));
      }
    }

    return combined;
  }

  static Set<String> _getCanonicalKeys(String identity, DateTime periodStart, DateTime periodEnd, DateTime targetMonth) {
    if (identity.isEmpty) return <String>{};
    final newKey = payrollKeyForPeriod(identity, periodStart, periodEnd);
    final legacyKey = '${identity}_${payrollPeriodLabel(targetMonth)}'.toLowerCase();
    return {newKey, legacyKey}..remove('');
  }

  static Map<String, dynamic>? _findCanonicalRecord(
    List<Map<String, dynamic>> docs,
    Set<String> canonicalKeys,
    DateTime periodStart,
    DateTime periodEnd, {
    required bool allowUndated,
  }) {
    if (canonicalKeys.isEmpty) return null;

    final record = docs.cast<Map<String, dynamic>?>().firstWhere(
      (record) => record != null && canonicalKeys.contains((record['payrollKey'] ?? '').toString().trim().toLowerCase()),
      orElse: () => null,
    );

    if (record == null) return null;
    return isRecordInPayPeriod(record, periodStart, periodEnd, allowUndated: allowUndated) ? record : null;
  }

  static List<Map<String, dynamic>> _getMatchingRecords(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> activeWorkers,
    List<Map<String, dynamic>> monthlyPayrollDocs,
    Set<String> canonicalKeys,
    Map<String, dynamic>? canonicalRecord,
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    if (canonicalRecord != null && !isRecordInPayPeriod(canonicalRecord, periodStart, periodEnd, allowUndated: false)) {
      return <Map<String, dynamic>>[];
    }

    final matches = monthlyPayrollDocs.where((record) =>
        _recordMatchesWorker(record, worker, activeWorkers)
    ).toList();

    matches.sort((a, b) {
      final aKey = (a['payrollKey'] ?? '').toString().trim().toLowerCase();
      final bKey = (b['payrollKey'] ?? '').toString().trim().toLowerCase();
      final aIsCanonical = canonicalKeys.isNotEmpty && canonicalKeys.contains(aKey);
      final bIsCanonical = canonicalKeys.isNotEmpty && canonicalKeys.contains(bKey);

      if (aIsCanonical != bIsCanonical) {
        return bIsCanonical ? 1 : -1;
      }
      return _recordSortDate(b).compareTo(_recordSortDate(a));
    });

    return matches;
  }

  static Map<String, dynamic> _buildMergedWorkerRecord(
    Map<String, dynamic> worker,
    Map<String, dynamic> payrollRecord,
    String workerId,
    String? companyCurrencyCode,
  ) {
    final salaryAmount = _preferNonEmpty(worker['salaryAmount'], payrollRecord['salaryAmount']);
    final currency = companyCurrencyCode ?? CurrencyUtils.normalize(_preferNonEmpty(worker['currency'], payrollRecord['currency']));
    final salaryType = _preferNonEmpty(worker['salaryType'], payrollRecord['salaryType']);
    final profileImage = _preferNonEmpty(worker['profileImage'], payrollRecord['profileImage']);
    final phone = _preferNonEmpty(worker['phone'], _preferNonEmpty(payrollRecord['phone'], _preferNonEmpty(worker['contact'], payrollRecord['contact'])));

    final currentSalary = _salaryDisplayOrEmpty(worker, companyCurrency: companyCurrencyCode);
    final historicalSalary = (payrollRecord['salary'] ?? '').toString().trim();
    final mergedSalary = historicalSalary.isNotEmpty
        ? (companyCurrencyCode == null ? historicalSalary : formatAmountInCurrency(historicalSalary, companyCurrencyCode))
        : currentSalary;

    final historicalNetSalary = _preferNonEmpty(payrollRecord['netSalary'], payrollRecord['netSalaryFormatted']).toString().trim();
    final mergedNetSalary = companyCurrencyCode == null || historicalNetSalary.isEmpty
        ? historicalNetSalary
        : formatAmountInCurrency(historicalNetSalary, companyCurrencyCode);

    final paid = isPayrollRecordPaid(payrollRecord);

    return {
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
    };
  }

  static Map<String, dynamic> _buildUnpaidWorkerRecord(
    Map<String, dynamic> worker,
    String workerId,
    String? companyCurrencyCode,
  ) {
    final salary = _salaryDisplayOrEmpty(worker, companyCurrency: companyCurrencyCode);
    final currency = companyCurrencyCode ?? CurrencyUtils.normalize(worker['currency']);

    return {
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
    };
  }

  static List<Map<String, dynamic>> payrollRecordsForActiveWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> payrollRecords,
  ) {
    final activeWorkers = workersList.where(isWorkerEligibleForPayroll).map(Map<String, dynamic>.from).toList();
    if (activeWorkers.isEmpty || payrollRecords.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    return payrollRecords.where((record) =>
        activeWorkers.any((worker) => _recordMatchesWorker(record, worker, activeWorkers))
    ).toList();
  }

  static List<Map<String, dynamic>> paidPayrollRecordsForActiveWorkers(
    List<Map<String, dynamic>> workersList,
    List<Map<String, dynamic>> payrollRecords,
  ) {
    return payrollRecordsForActiveWorkers(workersList, payrollRecords).where(isPayrollRecordPaid).toList();
  }

  static bool isRecordInMonth(Map<String, dynamic> record, DateTime month, {bool allowUndated = false}) {
    final date = payrollRecordDate(record);
    if (date == null) return allowUndated;
    return date.year == month.year && date.month == month.month;
  }

  static bool isRecordInPayPeriod(
    Map<String, dynamic> record,
    DateTime periodStart,
    DateTime periodEnd, {
    bool allowUndated = false,
  }) {
    final savedStart = _parseDate(record['payPeriodStart']);
    final savedEnd = _parseDate(record['payPeriodEnd']);

    if (savedStart != null || savedEnd != null) {
      return savedStart != null &&
          savedEnd != null &&
          periodDateKey(savedStart) == periodDateKey(periodStart) &&
          periodDateKey(savedEnd) == periodDateKey(periodEnd);
    }
    return isRecordInMonth(record, periodEnd, allowUndated: allowUndated);
  }

  static DateTime? payrollRecordDate(Map<String, dynamic> record) {
    final createdAt = _parseDate(record['createdAt']);
    final payrollDate = _parseDate(record['payrollDate']);

    if (payrollDate != null && createdAt != null &&
        (payrollDate.year != createdAt.year || payrollDate.month != createdAt.month)) {
      return payrollDate;
    }

    for (final key in ['payrollMonth', 'period', 'payPeriod', 'createdAt', 'timestamp', 'payrollDate', 'date', 'lastModified']) {
      final parsed = _parseDate(record[key]);
      if (parsed != null) return parsed;
    }

    return _parseDateFromPayrollKey((record['payrollKey'] ?? '').toString());
  }

  static DateTime? _parseDateFromPayrollKey(String payrollKey) {
    final dateRangeMatch = RegExp(r'(\d{4})-(\d{2})-(\d{2})_(\d{4})-(\d{2})-(\d{2})$').firstMatch(payrollKey);

    if (dateRangeMatch != null) {
      final year = int.tryParse(dateRangeMatch.group(4)!);
      final month = int.tryParse(dateRangeMatch.group(5)!);
      final day = int.tryParse(dateRangeMatch.group(6)!);
      if (year != null && month != null && day != null && month >= 1 && month <= 12) {
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
    for (final key in ['paidAt', 'paidOn', 'paymentDate', 'payrollDate', 'createdAt']) {
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
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value).toLocal();

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

    return (date.year == year && date.month == month && date.day == day) ? date : null;
  }

  static double extractSalary(String salaryStr) {
    if (salaryStr.isEmpty) return 0;
    final trimmed = salaryStr.trim();
    final firstDigit = RegExp(r'\d').firstMatch(trimmed);
    final numericPart = firstDigit == null ? trimmed : trimmed.substring(firstDigit.start);

    final suffix = RegExp(r'([KMBT])\s*$', caseSensitive: false).firstMatch(numericPart)?.group(1)?.toUpperCase();

    final multiplier = switch (suffix) {
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      'T' => 1e12,
      _ => 1.0,
    };

    String cleaned = numericPart.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return 0;

    cleaned = _normalizeDecimalSeparator(cleaned);
    return (double.tryParse(cleaned) ?? 0) * multiplier;
  }

  static String _normalizeDecimalSeparator(String cleaned) {
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');

    if (lastDot >= 0 && lastComma >= 0) {
      return lastComma > lastDot ? cleaned.replaceAll('.', '').replaceAll(',', '.') : cleaned.replaceAll(',', '');
    }

    if (lastComma >= 0) {
      final commaCount = ','.allMatches(cleaned).length;
      final digitsAfterComma = cleaned.length - lastComma - 1;
      return commaCount > 1 || digitsAfterComma == 3 ? cleaned.replaceAll(',', '') : cleaned.replaceAll(',', '.');
    }

    if ('.'.allMatches(cleaned).length > 1) {
      return cleaned.replaceAll('.', '');
    }

    return cleaned;
  }

  static int parseIntSafe(String value) {
    if (value.isEmpty) return 0;
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String currentSalaryDisplay(Map<String, dynamic> data, {String? companyCurrency}) {
    final salary = _salaryDisplayOrEmpty(data, companyCurrency: companyCurrency);
    if (salary.isNotEmpty) return salary;

    final currency = _companyCurrencyCode(companyCurrency) ?? CurrencyUtils.normalize(data['currency']);
    return '${getCurrencySymbol(currency)} 0';
  }

  static Map<String, int> attendanceCounts(Map<String, dynamic> payrollOrWorkerData) {
    final legacyLeaves = parseIntSafe((payrollOrWorkerData['leaves'] ?? '').toString());
    final paidLeaves = parseIntSafe((payrollOrWorkerData['paidLeaves'] ?? '').toString());
    final hasExplicitUnpaid = payrollOrWorkerData.containsKey('unpaidLeaves');
    final unpaidLeaves = hasExplicitUnpaid
        ? parseIntSafe((payrollOrWorkerData['unpaidLeaves'] ?? '').toString())
        : (legacyLeaves - paidLeaves).clamp(0, legacyLeaves);

    return {
      'absents': parseIntSafe((payrollOrWorkerData['absents'] ?? '').toString()),
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'leaves': paidLeaves + unpaidLeaves,
    };
  }

  static String formatNumber(num number, {String locale = 'en_US'}) {
    if (number.isNaN || number.isInfinite) return '0';
    final isNegative = number < 0;
    final absolute = isNegative ? -number : number;

    if (absolute >= 1e3) {
      final compact = CurrencyUtils.formatCompactLocale(number.toDouble(), locale, symbol: '');
      return isNegative ? '($compact)' : compact;
    }

    final roundedStr = absolute.toStringAsFixed(0);
    final formatted = roundedStr.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return isNegative ? '($formatted)' : formatted;
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
      return parts.length == 1 ? formattedInteger : '$formattedInteger.${parts[1]}';
    }
  }

  static String getCurrencyPrefix(String salaryStr) {
    if (salaryStr.isEmpty) return '';
    final match = RegExp(r'\d').firstMatch(salaryStr);
    return match == null ? salaryStr.trim() : salaryStr.substring(0, match.start).trim();
  }

  static String getCurrencySymbol(String currency) {
    final key = currency.trim().toUpperCase();
    if (key == 'POUND') return '£';
    if (key == 'JAPANESE YEN') return '¥';
    return CurrencyUtils.symbolFor(key);
  }

  static String _formatCurrency(num value, String prefix) => '$prefix${formatFullNumber(value)}';

  static double calculateNetFromTotals({
    required String salary,
    String overtimeAmount = '',
    String absentDeduction = '',
    String leaveDeduction = '',
    String customDeduction = '',
    String salaryType = 'Monthly',
    double prorationFactor = 1.0,
  }) {
    final enteredSalary = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual' ? enteredSalary / 12 : enteredSalary;

    final overtimeVal = extractSalary(overtimeAmount);
    final absentVal = extractSalary(absentDeduction);
    final leaveVal = extractSalary(leaveDeduction);
    final customVal = extractSalary(customDeduction);

    return (periodSalary * prorationFactor + overtimeVal - absentVal - leaveVal - customVal)
        .clamp(0.0, double.infinity)
        .toDouble();
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
    final periodSalary = salaryType.trim().toLowerCase() == 'annual' ? enteredSalary / 12 : enteredSalary;

    final availableEarnings = (periodSalary * prorationFactor) +
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
    double prorationFactor = 1.0,
  }) {
    final rawSalaryVal = extractSalary(salary);
    final periodSalary = salaryType.trim().toLowerCase() == 'annual' ? rawSalaryVal / 12 : rawSalaryVal;
    final totalWorkDaysVal = parseIntSafe(totalWorkDays);
    final absentDays = parseIntSafe(absents);
    final leaveDays = parseIntSafe(leaves);
    final customOvertimeAmount = extractSalary(overtimeAmount);
    final customAbsentDeduction = extractSalary(absentDeductionPerDay);
    final customLeaveDeduction = extractSalary(leaveDeductionPerDay);
    final currency = getCurrencyPrefix(salary);
    final p = currency.isNotEmpty ? '$currency ' : '';

    final dailyRate = totalWorkDaysVal > 0 ? periodSalary / totalWorkDaysVal : 0.0;

    final calculatedWorkedDays = daysWorked.isEmpty ? totalWorkDaysVal - absentDays - leaveDays : parseIntSafe(daysWorked);
    final workedDaysVal = calculatedWorkedDays.clamp(0, totalWorkDaysVal).toInt();

    final grossSalary = periodSalary * prorationFactor;
    final overtimePay = customOvertimeAmount;

    final leaveDeduction = leaveDays > 0 ? leaveDays * customLeaveDeduction : 0.0;
    final requestedAbsentDeduction = absentDays > 0 ? absentDays * customAbsentDeduction : 0.0;
    final absentDeduction = cappedAbsentDeduction(
      hasAbsences: absentDays > 0,
      requestedDeduction: requestedAbsentDeduction,
      salary: salary,
      overtimeAmount: overtimeAmount,
      leaveDeduction: leaveDeduction.toString(),
      salaryType: salaryType,
      prorationFactor: prorationFactor,
    );

    final totalDeductions = absentDeduction + leaveDeduction;
    final netSalary = (grossSalary + overtimePay - totalDeductions).clamp(0.0, double.infinity);

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
      'absentDeductionPerDayApplied': absentDays > 0 ? absentDeduction / absentDays : 0.0,
      'leaveDeductionPerDayApplied': leaveDays > 0 ? leaveDeduction / leaveDays : 0.0,
      'absentDeduction': absentDeduction,
      'leaveDeduction': leaveDeduction,
      'totalDeductions': totalDeductions,
      'netSalary': netSalary,
      'formattedDailyRate': _formatCurrency(dailyRate, p),
      'formattedOvertimeRate': _formatCurrency(dailyRate * 1.5, p),
      'formattedGross': _formatCurrency(grossSalary, p),
      'formattedOvertime': _formatCurrency(overtimePay, p),
      'formattedAbsentDeduct': absentDeduction > 0 ? '-${_formatCurrency(absentDeduction, p)}' : _formatCurrency(0.0, p),
      'formattedLeaveDeduct': leaveDeduction > 0 ? '-${_formatCurrency(leaveDeduction, p)}' : _formatCurrency(0.0, p),
      'formattedTotalDeductions': totalDeductions > 0 ? '-${_formatCurrency(totalDeductions, p)}' : _formatCurrency(0.0, p),
      'formattedNetSalary': _formatCurrency(netSalary, p),
      'formattedNet': _formatCurrency(netSalary, p),
    };
  }
}