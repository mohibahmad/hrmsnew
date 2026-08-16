import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/utils.dart';

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

  static bool hasPastDateModification({
    required Iterable<DateTime> oldDates,
    required Iterable<DateTime> newDates,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final newSet = newDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    return oldDates.any(
      (d) =>
          d.isBefore(today) &&
          !newSet.contains(DateTime(d.year, d.month, d.day)),
    );
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

    final excludeId = (excludingRecordId ?? '').trim();
    for (final leave in timeOffRecords) {
      if (!isActiveRecord(leave)) continue;
      final leaveId = (leave['id'] ?? '').toString().trim();
      if (excludeId.isNotEmpty && leaveId.isNotEmpty && leaveId == excludeId) {
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

  static List<Map<String, dynamic>> combineTimeOffAndAttendanceRecords({
    required List<Map<String, dynamic>> timeOffRecords,
    required List<Map<String, dynamic>> attendanceRecords,
  }) {
    final combined = List<Map<String, dynamic>>.from(timeOffRecords);
    final existingDates = <DateTime>{};
    for (final record in timeOffRecords) {
      if (!isActiveRecord(record)) continue;
      existingDates.addAll(selectedDatesForRecord(record));
    }

    for (final att in attendanceRecords) {
      final status = (att['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'leave' &&
          status != 'onleave' &&
          status != 'on leave' &&
          status != 'l') {
        continue;
      }
      final date = AppDateUtils.attendanceRecordDate(att);
      if (date == null) continue;
      final dateOnly = DateTime(date.year, date.month, date.day);
      if (existingDates.contains(dateOnly)) continue;

      final dateStr = AppDateUtils.formatDate(dateOnly);
      final workerId = (att['workerId'] ?? '').toString().trim();
      final workerName = (att['name'] ?? att['workerName'] ?? '')
          .toString()
          .trim();
      final workerEmail = (att['email'] ?? '').toString().trim();
      final lType = (att['leaveType'] ?? att['type'] ?? 'Annual Leave')
          .toString();

      combined.add({
        'id': 'att_leave_${att['id'] ?? workerId}_$dateStr',
        'workerId': workerId,
        'name': workerName,
        'workerName': workerName,
        'email': workerEmail,
        'type': lType,
        'startDate': dateStr,
        'endDate': dateStr,
        'selectedDates': [dateStr],
        'status': 'Approved',
        'source': 'attendance',
      });
      existingDates.add(dateOnly);
    }
    return combined;
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
    bool isUniqueName = true,
  }) {
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty && recordWorkerId.isNotEmpty) {
      return workerId == recordWorkerId;
    }
    final leaveEmail = (record['email'] ?? '').toString().trim().toLowerCase();
    if (workerEmail.isNotEmpty && leaveEmail.isNotEmpty) {
      return workerEmail == leaveEmail;
    }
    final leaveName = (record['name'] ?? record['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return isUniqueName && workerName.isNotEmpty && workerName == leaveName;
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

  static Map<String, int> paidDaysUsedForWorkerByType(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final datesByType = assignedLeaveDatesForWorkerByType(
      worker,
      timeOffRecords,
      excludingRecordId: excludingRecordId,
    );
    return {
      for (final entry in datesByType.entries) entry.key: entry.value.length,
    };
  }

  static Map<String, Set<DateTime>> assignedLeaveDatesForWorkerByType(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final datesByType = <String, Set<DateTime>>{
      'Annual Leave': <DateTime>{},
      'Sick Leave': <DateTime>{},
      'Casual Leave': <DateTime>{},
      'Medical Leave': <DateTime>{},
    };
    if (timeOffRecords.isEmpty) return datesByType;

    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    final matchingRecords =
        timeOffRecords.where((record) {
          if (!isActiveRecord(record) || !isPaidRecord(record)) return false;
          if (excludingRecordId != null &&
              record['id']?.toString() == excludingRecordId) {
            return false;
          }
          return _belongsToWorker(
            record,
            workerId: workerId,
            workerEmail: workerEmail,
            workerName: workerName,
          );
        }).toList()..sort((a, b) {
          final aFromAttendance =
              (a['source'] ?? '').toString().trim().toLowerCase() ==
              'attendance';
          final bFromAttendance =
              (b['source'] ?? '').toString().trim().toLowerCase() ==
              'attendance';
          if (aFromAttendance != bFromAttendance) {
            return aFromAttendance ? 1 : -1;
          }
          return (a['id'] ?? '').toString().compareTo(
            (b['id'] ?? '').toString(),
          );
        });

    final claimedDates = <DateTime>{};
    for (final record in matchingRecords) {
      final normType = leaveType(record);
      final dates = datesByType[normType];
      if (dates == null) continue;
      for (final date in selectedDatesForRecord(record)) {
        if (claimedDates.add(date)) dates.add(date);
      }
    }
    return datesByType;
  }

  static Map<String, int> remainingBalancesFromAssignedRecords(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    const balanceFields = <String, String>{
      'Annual Leave': 'annualLeave',
      'Sick Leave': 'sickLeave',
      'Casual Leave': 'casualLeave',
      'Medical Leave': 'medicalLeave',
    };
    final assigned = paidDaysUsedForWorkerByType(worker, timeOffRecords);
    return {
      for (final entry in balanceFields.entries)
        entry.value:
            (configuredLimitForType(worker, entry.key) -
                    (assigned[entry.key] ?? 0))
                .clamp(0, configuredLimitForType(worker, entry.key))
                .toInt(),
    };
  }

  static Map<String, List<DateTime>> leaveDatesByTypeForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final result = assignedLeaveDatesForWorkerByType(worker, timeOffRecords);

    return {
      for (final entry in result.entries)
        entry.key: entry.value.toList()..sort(),
    };
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

  static int availableBalanceForEditingRecord(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    String type,
    Map<String, dynamic>? editingRecord,
  ) {
    return remainingForType(
      worker,
      timeOffRecords,
      type,
      excludingRecordId:
          editingRecord != null && recordHasLeaveType(editingRecord, type)
          ? editingRecord['id']?.toString()
          : null,
    );
  }

  static int projectedAssignedDaysForEditingRecord(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    String type,
    Map<String, dynamic>? editingRecord,
    int selectedDays,
  ) {
    final total = configuredLimitForType(worker, type);
    final excludingRecordId =
        editingRecord != null && recordHasLeaveType(editingRecord, type)
        ? editingRecord['id']?.toString()
        : null;
    final assigned = assignedLeaveDatesForWorkerByType(
      worker,
      timeOffRecords,
      excludingRecordId: excludingRecordId,
    );
    final otherAssigned = assigned[normalizeLeaveType(type)]?.length ?? 0;
    return (otherAssigned + selectedDays).clamp(0, total);
  }

  static int configuredLimitForType(Map<String, dynamic> worker, String type) {
    final normType = normalizeLeaveType(type);
    switch (normType) {
      case 'Annual Leave':
        return int.tryParse(
              worker['annualLeaves']?.toString() ?? '0',
            ) ??
            0;
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

    final used =
        assignedLeaveDatesForWorkerByType(
          worker,
          timeOffRecords,
          excludingRecordId: excludingRecordId,
        )[normType]?.length ??
        0;
    return (limit - used).clamp(0, limit).toInt();
  }

  static int totalAvailableLeaves(Map<String, dynamic> worker) {
    final balances =
        canonicalWorkerLeaveFields(worker)['leaveBalances'] as Map<String, int>;
    return balances.values.fold(0, (total, value) => total + value);
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
      if (remainingForType(worker, timeOffRecords, type) > 0) {
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
    DateTime? startDate,
    DateTime? endDate,
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

    final normStart = startDate == null
        ? null
        : DateTime(startDate.year, startDate.month, startDate.day);
    final normEnd = endDate == null
        ? null
        : DateTime(endDate.year, endDate.month, endDate.day);

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
      final dates = selectedDatesForRecord(record).where((date) {
        if (date.isAfter(today)) return false;
        if (normStart != null && normEnd != null) {
          return !date.isBefore(normStart) && !date.isAfter(normEnd);
        }
        return date.year == month.year && date.month == month.month;
      });
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
