import 'package:cloud_firestore/cloud_firestore.dart';

class TimeOffService {
  static const Set<String> paidLeaveTypes = {
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
  };

  static const Set<String> unpaidLeaveTypes = {'Unpaid Leave'};

  static String normalizeLeaveType(String type) {
    final normalized = type.trim();
    if (normalized == 'Custom Leave' || normalized == 'Maternity Leave') {
      return 'Unpaid Leave';
    }
    return normalized;
  }

  static String leaveType(Map<String, dynamic> record) {
    return normalizeLeaveType(
      (record['action'] ?? record['type'] ?? record['leaveType'] ?? '')
          .toString(),
    );
  }

  static bool isPaidLeaveType(String type) => paidLeaveTypes.contains(type);

  static bool isUnpaidLeaveType(String type) => unpaidLeaveTypes.contains(type);

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

    final parsed = DateTime.tryParse(value.toString().trim());
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
  }) {
    final date = onDate ?? DateTime.now();
    final target = DateTime(date.year, date.month, date.day);
    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
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
      if (leaveDates.contains(target)) return leave;
    }
    return null;
  }

  static Set<DateTime> allLeaveDatesForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final dates = <DateTime>{};
    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
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

    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
        .toString()
        .trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    var used = 0;

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
      used += selectedDatesForRecord(record).length;
    }
    return used;
  }

  /// Counts every time-off day against the worker's configured annual
  /// allowance, while keeping paid/unpaid classification separate for payroll.
  static int leaveDaysUsedForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    if (timeOffRecords.isEmpty) return 0;

    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
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

  static int configuredPaidLeaveAllowance(Map<String, dynamic> worker) {
    final rawAllowance = worker['annualLeaves'];
    final parsed = rawAllowance is num
        ? rawAllowance.toInt()
        : num.tryParse((rawAllowance ?? '0').toString())?.toInt() ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static int remainingPaidLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final total = configuredPaidLeaveAllowance(worker);
    if (timeOffRecords.isEmpty) return total;

    final used = leaveDaysUsedForWorker(
      worker,
      timeOffRecords,
      excludingRecordId: excludingRecordId,
    );
    return (total - used).clamp(0, total);
  }

  static bool hasOverlappingApprovedLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
    Iterable<DateTime> requestedDates, {
    String? excludingRecordId,
  }) {
    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
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
  }) {
    final workerId = (worker['id'] ?? worker['workerId'] ?? '')
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
      final dates = selectedDatesForRecord(
        record,
      ).where((date) => date.year == month.year && date.month == month.month);
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
