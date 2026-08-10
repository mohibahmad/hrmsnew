import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_utils.dart';

class DuplicateTimeOffDateException implements Exception {
  const DuplicateTimeOffDateException();
}

class PastTimeOffEditException implements Exception {
  const PastTimeOffEditException();
}

class TimeOffService {
  static const _workerLeaveFields =
      <({String balance, String total, String available, String used})>[
        (
          balance: 'annualLeave',
          total: 'annualLeaves',
          available: 'availableAnnualLeaves',
          used: 'annualLeavesUsed',
        ),
        (
          balance: 'sickLeave',
          total: 'sickLeaves',
          available: 'availableSickLeaves',
          used: 'sickLeavesUsed',
        ),
        (
          balance: 'casualLeave',
          total: 'casualLeaves',
          available: 'availableCasualLeaves',
          used: 'casualLeavesUsed',
        ),
        (
          balance: 'medicalLeave',
          total: 'medicalLeaves',
          available: 'availableMedicalLeaves',
          used: 'medicalLeavesUsed',
        ),
      ];

  static int _leaveInt(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse((value ?? '').toString().trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  /// Produces the single canonical Firestore representation for worker leave
  /// balances. All values are numeric and every used value is derived from
  /// `total - available`, so legacy counters cannot disagree with balances.
  static Map<String, dynamic> canonicalWorkerLeaveFields(
    Map<String, dynamic> worker, {
    Map<String, dynamic>? remainingBalances,
  }) {
    final storedBalances = worker['leaveBalances'] is Map
        ? Map<String, dynamic>.from(worker['leaveBalances'] as Map)
        : <String, dynamic>{};
    final explicitBalances = remainingBalances == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(remainingBalances);
    final canonicalBalances = <String, int>{};
    final result = <String, dynamic>{};
    var totalUsed = 0;

    for (final fields in _workerLeaveFields) {
      final hasOverride = explicitBalances.containsKey(fields.balance);
      final hasNestedBalance = storedBalances.containsKey(fields.balance);
      final hasTopLevelBalance = worker.containsKey(fields.available);
      final hasAvailable =
          hasOverride || hasNestedBalance || hasTopLevelBalance;

      final rawAvailable = hasOverride
          ? explicitBalances[fields.balance]
          : hasTopLevelBalance
          ? worker[fields.available]
          : storedBalances[fields.balance];
      final storedTotal = _leaveInt(worker[fields.total]);
      final storedUsed = _leaveInt(worker[fields.used]);
      var available = hasAvailable
          ? _leaveInt(rawAvailable)
          : (storedTotal - storedUsed).clamp(0, storedTotal).toInt();

      // Preserve the actual allowance when a legacy document contains a
      // partial/missing total but its remaining + used values prove a larger
      // value. Used is still recalculated below from the canonical balance.
      final inferredTotal = available + storedUsed;
      final total = storedTotal > 0 ? storedTotal : inferredTotal;
      available = available.clamp(0, total).toInt();
      final used = total - available;

      result[fields.total] = total;
      result[fields.available] = available;
      result[fields.used] = used;
      canonicalBalances[fields.balance] = available;
      totalUsed += used;
    }

    result['leavesUsed'] = totalUsed;
    result['leaveBalances'] = canonicalBalances;
    return result;
  }

  static bool hasCanonicalWorkerLeaveFields(Map<String, dynamic> worker) {
    final canonical = canonicalWorkerLeaveFields(worker);
    for (final entry in canonical.entries) {
      final current = worker[entry.key];
      if (entry.key == 'leaveBalances') {
        if (current is! Map) return false;
        final currentMap = Map<String, dynamic>.from(current);
        final expectedMap = entry.value as Map<String, int>;
        for (final balance in expectedMap.entries) {
          if (currentMap[balance.key] is! int ||
              currentMap[balance.key] != balance.value) {
            return false;
          }
        }
      } else if (current is! int || current != entry.value) {
        return false;
      }
    }
    return true;
  }

  static const Set<String> paidLeaveTypes = {
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
    'Maternity Leave',
    'Paternity Leave',
    'Hajj Leave',
    'Emergency Leave',
    'Study Leave',
    'Compensatory Leave',
  };

  static const Set<String> unpaidLeaveTypes = {'Unpaid Leave'};

  static String normalizeLeaveType(String type) {
    final normalized = type.trim();
    switch (normalized.toLowerCase()) {
      case 'annual leave':
      case 'annual':
        return 'Annual Leave';
      case 'sick leave':
      case 'sick':
        return 'Sick Leave';
      case 'casual leave':
      case 'casual':
        return 'Casual Leave';
      case 'medical leave':
      case 'medical':
        return 'Medical Leave';
      case 'maternity leave':
      case 'maternity':
        return 'Maternity Leave';
      case 'paternity leave':
        return 'Paternity Leave';
      case 'hajj leave':
        return 'Hajj Leave';
      case 'emergency leave':
        return 'Emergency Leave';
      case 'study leave':
        return 'Study Leave';
      case 'compensatory leave':
        return 'Compensatory Leave';
      case 'unpaid leave':
        return 'Unpaid Leave';
      case 'custom leave':
        return 'Custom Leave';
      default:
        return normalized.isNotEmpty ? normalized : 'Other Leave';
    }
  }

  static String leaveType(Map<String, dynamic> record) {
    return normalizeLeaveType(
      (record['action'] ?? record['type'] ?? record['leaveType'] ?? '')
          .toString(),
    );
  }

  static bool recordHasLeaveType(
    Map<String, dynamic> record,
    String expectedType,
  ) {
    return leaveType(record) == normalizeLeaveType(expectedType);
  }

  static bool isPaidLeaveType(String type) =>
      paidLeaveTypes.contains(normalizeLeaveType(type));

  static bool isUnpaidLeaveType(String type) =>
      unpaidLeaveTypes.contains(normalizeLeaveType(type));

  static bool isCancelledRecord(Map<String, dynamic> record) {
    final status = (record['status'] ?? '').toString().trim().toLowerCase();
    return const {
      'cancelled',
      'canceled',
      'rejected',
      'declined',
    }.contains(status);
  }

  static bool isActiveRecord(Map<String, dynamic> record) =>
      !isCancelledRecord(record);

  /// Time off that has already started is treated as used history. Today and
  /// future dates remain editable so a same-day correction can still keep an
  /// automatically created attendance record in sync.
  static bool isEditableRecord(
    Map<String, dynamic> record, {
    DateTime? referenceDate,
  }) {
    if (!isActiveRecord(record)) return false;
    final dates = selectedDatesForRecord(record);
    if (dates.isEmpty) return false;
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !dates.any((date) => date.isBefore(today));
  }

  static Set<String> activeLeaveAssignmentKeysForDate(
    List<Map<String, dynamic>> records,
    DateTime date,
  ) {
    final target = DateTime(date.year, date.month, date.day);
    final keys = <String>{};

    for (final record in records) {
      if (!isActiveRecord(record)) continue;
      if (!selectedDatesForRecord(record).contains(target)) continue;

      final recordId = (record['id'] ?? '').toString().trim();
      final workerId = (record['workerId'] ?? '').toString().trim();
      final email = (record['email'] ?? '').toString().trim().toLowerCase();
      final name = (record['name'] ?? record['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final workerKey = workerId.isNotEmpty
          ? 'id:$workerId'
          : email.isNotEmpty
          ? 'email:$email'
          : 'name:$name';
      keys.add('$recordId|$workerKey|${leaveType(record)}');
    }

    return keys;
  }

  static bool isPaidRecord(Map<String, dynamic> record) {
    final explicit = record['isPaidLeave'];
    if (explicit is bool) return explicit;
    return isPaidLeaveType(leaveType(record));
  }

  static bool isUnpaidRecord(Map<String, dynamic> record) {
    final explicit = record['isPaidLeave'];
    if (explicit is bool) return !explicit;
    return isUnpaidLeaveType(leaveType(record));
  }

  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is Timestamp) {
      final converted = value.toDate();
      return DateTime(converted.year, converted.month, converted.day);
    }

    final parsed = AppDateUtils.dateFromValue(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static List<DateTime> inclusiveDateRange(DateTime start, DateTime end) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    final step = normalizedEnd.isBefore(normalizedStart) ? -1 : 1;
    final dates = <DateTime>[];

    for (var date = normalizedStart; ; date = date.add(Duration(days: step))) {
      dates.add(date);
      if (date == normalizedEnd) break;
    }
    return dates;
  }

  static List<DateTime> selectedDatesForRecord(Map<String, dynamic> record) {
    final explicitDates = record['selectedDates'];
    if (explicitDates is Iterable) {
      final dates =
          explicitDates.map(parseDate).whereType<DateTime>().toSet().toList()
            ..sort();
      if (dates.isNotEmpty) return dates;
    }

    final start = parseDate(record['startDate']);
    final end = parseDate(record['endDate']);
    if (start == null || end == null || end.isBefore(start)) return const [];

    final dates = <DateTime>[];
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(date);
    }
    return dates;
  }

  static Map<String, dynamic>? activeLeaveForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    DateTime? onDate,
    String? excludingRecordId,
  }) {
    final date = onDate ?? DateTime.now();
    final target = DateTime(date.year, date.month, date.day);
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final leave in timeOffRecords) {
      if (!isActiveRecord(leave)) continue;
      if (excludingRecordId != null &&
          leave['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!_belongsToWorker(
        leave,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }

      final leaveDates = selectedDatesForRecord(leave);
      if (leaveDates.contains(target)) return leave;
    }
    return null;
  }

  static Set<DateTime> allLeaveDatesForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final dates = <DateTime>{};
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final leave in timeOffRecords) {
      if (!isActiveRecord(leave)) continue;
      if (!_belongsToWorker(
        leave,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }

      final leaveDates = selectedDatesForRecord(leave);
      dates.addAll(leaveDates);
    }
    return dates;
  }

  static bool isWorkerOnLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    DateTime? onDate,
  }) => activeLeaveForWorker(worker, timeOffRecords, onDate: onDate) != null;

  static bool _belongsToWorker(
    Map<String, dynamic> record, {
    required String workerId,
    required String workerEmail,
    required String workerName,
  }) {
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty && recordWorkerId.isNotEmpty) {
      return workerId == recordWorkerId;
    }
    final leaveEmail = (record['email'] ?? '').toString().trim().toLowerCase();
    final leaveName = (record['name'] ?? record['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return workerEmail.isNotEmpty && leaveEmail.isNotEmpty
        ? workerEmail == leaveEmail
        : workerName.isNotEmpty && workerName == leaveName;
  }

  static int paidDaysUsedForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    if (timeOffRecords.isEmpty) return 0;

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final usedDates = <DateTime>{};

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!isPaidRecord(record)) continue;
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      usedDates.addAll(selectedDatesForRecord(record));
    }
    return usedDates.length;
  }

  static int leaveDaysUsedForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    if (timeOffRecords.isEmpty) return 0;

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final usedDates = <DateTime>{};

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      usedDates.addAll(selectedDatesForRecord(record));
    }
    return usedDates.length;
  }

  static Map<String, int> paidDaysUsedForWorkerByType(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final result = <String, int>{
      'Sick Leave': 0,
      'Casual Leave': 0,
      'Medical Leave': 0,
      'Annual Leave': 0,
    };
    if (timeOffRecords.isEmpty) return result;

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!isPaidRecord(record)) continue;
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      final normType = normalizeLeaveType(record['action']?.toString() ?? '');
      final dates = selectedDatesForRecord(record);
      result[normType] = (result[normType] ?? 0) + dates.length;
    }
    return result;
  }

  static Map<String, List<DateTime>> leaveDatesByTypeForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final result = <String, Set<DateTime>>{
      'Annual Leave': <DateTime>{},
      'Sick Leave': <DateTime>{},
      'Casual Leave': <DateTime>{},
      'Medical Leave': <DateTime>{},
    };
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record) || !isPaidRecord(record)) continue;
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      final type = normalizeLeaveType(
        (record['action'] ?? record['type'] ?? '').toString(),
      );
      final dates = result[type];
      if (dates == null) continue;
      dates.addAll(selectedDatesForRecord(record));
    }

    return {
      for (final entry in result.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  /// Finds the worker's record for a dropdown leave type without converting
  /// the currently open record into that type. Editable records are preferred,
  /// then the most recent assigned dates are used.
  static Map<String, dynamic>? recordForWorkerLeaveType(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    String type, {
    DateTime? referenceDate,
  }) {
    final normalizedType = normalizeLeaveType(type);
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final matches = timeOffRecords
        .where((record) {
          return isActiveRecord(record) &&
              normalizeLeaveType(leaveType(record)) == normalizedType &&
              _belongsToWorker(
                record,
                workerId: workerId,
                workerEmail: workerEmail,
                workerName: workerName,
              );
        })
        .map(Map<String, dynamic>.from)
        .toList();

    if (matches.isEmpty) return null;

    DateTime recordDate(Map<String, dynamic> record) {
      final dates = selectedDatesForRecord(record);
      if (dates.isNotEmpty) return dates.last;
      for (final key in ['updatedAt', 'createdAt', 'startDate', 'endDate']) {
        final parsed = parseDate(record[key]);
        if (parsed != null) return parsed;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    matches.sort((a, b) {
      final aEditable = isEditableRecord(a, referenceDate: referenceDate);
      final bEditable = isEditableRecord(b, referenceDate: referenceDate);
      if (aEditable != bEditable) return aEditable ? -1 : 1;
      return recordDate(b).compareTo(recordDate(a));
    });
    return matches.first;
  }

  static int configuredPaidLeaveAllowance(Map<String, dynamic> worker) {
    final rawAnnual = worker['annualLeaves'];
    final annual = rawAnnual is num
        ? rawAnnual.toInt()
        : int.tryParse((rawAnnual ?? '').toString()) ?? 0;

    if (annual > 0) return annual;

    final sick = int.tryParse((worker['sickLeaves'] ?? '').toString()) ?? 5;
    final casual = int.tryParse((worker['casualLeaves'] ?? '').toString()) ?? 5;
    final medical =
        int.tryParse((worker['medicalLeaves'] ?? '').toString()) ?? 1;

    final total = sick + casual + medical;
    return total > 0 ? total : 25;
  }

  static int remainingPaidLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final total = configuredPaidLeaveAllowance(worker);
    if (timeOffRecords.isEmpty) return total;

    final used = paidDaysUsedForWorker(
      worker,
      timeOffRecords,
      excludingRecordId: excludingRecordId,
    );
    return (total - used).clamp(0, total).toInt();
  }

  static int getLeaveBalance(Map<String, dynamic> worker, String type) {
    final fieldName = switch (normalizeLeaveType(type)) {
      'Annual Leave' => 'annualLeave',
      'Sick Leave' => 'sickLeave',
      'Casual Leave' => 'casualLeave',
      'Medical Leave' => 'medicalLeave',
      _ => '',
    };
    if (fieldName.isEmpty) return 0;
    final balances =
        canonicalWorkerLeaveFields(worker)['leaveBalances'] as Map<String, int>;
    return balances[fieldName] ?? 0;
  }

  /// Returns the balance that can be used while editing an existing record.
  /// The record's already allocated days are temporarily available because an
  /// atomic save restores the old allocation before applying the new one.
  static int availableBalanceForEditingRecord(
    Map<String, dynamic> worker,
    String type,
    Map<String, dynamic>? editingRecord,
  ) {
    final storedBalance = getLeaveBalance(worker, type);
    if (editingRecord == null ||
        normalizeLeaveType(type) != leaveType(editingRecord)) {
      return storedBalance;
    }

    return (storedBalance + selectedDatesForRecord(editingRecord).length).clamp(
      0,
      9999,
    );
  }

  /// Projects the worker's total assigned days for one leave type while a
  /// single record is being edited. Firestore's stored used count already
  /// includes every record; replace only the open record's old allocation with
  /// its current draft selection.
  static int projectedAssignedDaysForEditingRecord(
    Map<String, dynamic> worker,
    String type,
    Map<String, dynamic>? editingRecord,
    int selectedDays,
  ) {
    final total = configuredLimitForType(worker, type);
    final available = getLeaveBalance(worker, type).clamp(0, total);
    final storedAssigned = total - available;
    final originalSelectedDays =
        editingRecord != null && recordHasLeaveType(editingRecord, type)
        ? selectedDatesForRecord(editingRecord).length
        : 0;
    return (storedAssigned - originalSelectedDays + selectedDays).clamp(
      0,
      total,
    );
  }

  static int configuredLimitForType(Map<String, dynamic> worker, String type) {
    final normType = normalizeLeaveType(type);
    switch (normType) {
      case 'Annual Leave':
        final annualLimit =
            int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        return annualLimit > 0
            ? annualLimit
            : configuredPaidLeaveAllowance(worker);
      case 'Sick Leave':
        return int.tryParse(worker['sickLeaves']?.toString() ?? '0') ?? 0;
      case 'Casual Leave':
        return int.tryParse(worker['casualLeaves']?.toString() ?? '0') ?? 0;
      case 'Medical Leave':
        return int.tryParse(worker['medicalLeaves']?.toString() ?? '0') ?? 0;
      default:
        return 0;
    }
  }

  static int remainingForType(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    String type, {
    String? excludingRecordId,
  }) {
    final normType = normalizeLeaveType(type);
    final limit = configuredLimitForType(worker, normType);
    if (limit <= 0) return 0;

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    int used = 0;
    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (normalizeLeaveType(
            record['action']?.toString() ?? record['type']?.toString() ?? '',
          ) !=
          normType) {
        continue;
      }
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      used += selectedDatesForRecord(record).length;
    }
    return (limit - used).clamp(0, limit).toInt();
  }

  static int totalAvailableLeaves(Map<String, dynamic> worker) {
    final balances =
        canonicalWorkerLeaveFields(worker)['leaveBalances'] as Map<String, int>;
    return balances.values.fold(0, (sum, value) => sum + value);
  }

  static bool isWorkerLimitReached(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    const types = [
      'Annual Leave',
      'Sick Leave',
      'Casual Leave',
      'Medical Leave',
    ];
    for (final type in types) {
      if (getLeaveBalance(worker, type) > 0) {
        return false;
      }
    }
    return true;
  }

  static bool hasOverlappingApprovedLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    Iterable<DateTime> requestedDates, {
    String? excludingRecordId,
  }) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final requested = requestedDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      if (selectedDatesForRecord(record).any(requested.contains)) return true;
    }
    return false;
  }

  static Map<String, int> monthlyLeaveCounts(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    required DateTime month,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final paidDates = <DateTime>{};
    final unpaidDates = <DateTime>{};

    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      if (!_belongsToWorker(
        record,
        workerId: workerId,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      final dates = selectedDatesForRecord(record).where(
        (date) =>
            date.year == month.year &&
            date.month == month.month &&
            !date.isAfter(today),
      );
      if (isPaidRecord(record)) {
        paidDates.addAll(dates);
      } else if (isUnpaidRecord(record)) {
        unpaidDates.addAll(dates);
      }
    }

    unpaidDates.removeAll(paidDates);
    return {
      'paidLeaves': paidDates.length,
      'unpaidLeaves': unpaidDates.length,
      'leaves': paidDates.length + unpaidDates.length,
    };
  }
}
