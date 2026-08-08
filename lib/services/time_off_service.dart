import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_utils.dart';

class TimeOffService {
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
      if (excludingRecordId != null && leave['id']?.toString() == excludingRecordId) {
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

  static int configuredPaidLeaveAllowance(Map<String, dynamic> worker) {
    final rawAnnual = worker['annualLeaves'];
    final annual = rawAnnual is num
        ? rawAnnual.toInt()
        : int.tryParse((rawAnnual ?? '').toString()) ?? 0;

    if (annual > 0) return annual;

    final sick = int.tryParse((worker['sickLeaves'] ?? '').toString()) ?? 5;
    final casual = int.tryParse((worker['casualLeaves'] ?? '').toString()) ?? 5;
    final medical = int.tryParse((worker['medicalLeaves'] ?? '').toString()) ?? 1;

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
    final leaveBalances = worker['leaveBalances'] as Map<String, dynamic>?;
    final fieldName = switch (normalizeLeaveType(type)) {
      'Annual Leave' => 'annualLeave',
      'Sick Leave' => 'sickLeave',
      'Casual Leave' => 'casualLeave',
      'Medical Leave' => 'medicalLeave',
      _ => '',
    };
    if (fieldName.isEmpty) return 0;
    if (leaveBalances != null && leaveBalances.containsKey(fieldName)) {
      return int.tryParse(leaveBalances[fieldName]?.toString() ?? '0') ?? 0;
    }
    return switch (fieldName) {
      'annualLeave' => int.tryParse((worker['availableAnnualLeaves'] ?? worker['annualLeaves'] ?? '0').toString()) ?? 0,
      'sickLeave' => int.tryParse((worker['sickLeaves'] ?? '0').toString()) ?? 0,
      'casualLeave' => int.tryParse((worker['casualLeaves'] ?? '0').toString()) ?? 0,
      'medicalLeave' => int.tryParse((worker['medicalLeaves'] ?? '0').toString()) ?? 0,
      _ => 0,
    };
  }

  
  
  
  static int configuredLimitForType(
    Map<String, dynamic> worker,
    String type,
  ) {
    final normType = normalizeLeaveType(type);
    switch (normType) {
      case 'Annual Leave':
        final annualLimit = int.tryParse(worker['annualLeaves']?.toString() ?? '0') ?? 0;
        return annualLimit > 0 ? annualLimit : configuredPaidLeaveAllowance(worker);
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
    final leaveBalances = worker['leaveBalances'] as Map<String, dynamic>?;
    if (leaveBalances != null) {
      final annual = int.tryParse(leaveBalances['annualLeave']?.toString() ?? '0') ?? 0;
      final sick = int.tryParse(leaveBalances['sickLeave']?.toString() ?? '0') ?? 0;
      final casual = int.tryParse(leaveBalances['casualLeave']?.toString() ?? '0') ?? 0;
      final medical = int.tryParse(leaveBalances['medicalLeave']?.toString() ?? '0') ?? 0;
      return annual + sick + casual + medical;
    }
    final annual = int.tryParse((worker['availableAnnualLeaves'] ?? worker['annualLeaves'] ?? '0').toString()) ?? 0;
    final sick = int.tryParse((worker['sickLeaves'] ?? '0').toString()) ?? 0;
    final casual = int.tryParse((worker['casualLeaves'] ?? '0').toString()) ?? 0;
    final medical = int.tryParse((worker['medicalLeaves'] ?? '0').toString()) ?? 0;
    return annual + sick + casual + medical;
  }

  
  
  
  static bool isWorkerLimitReached(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    const types = ['Annual Leave', 'Sick Leave', 'Casual Leave', 'Medical Leave'];
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
            date.isBefore(today),
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
