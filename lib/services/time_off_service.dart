class TimeOffService {
  static const Set<String> paidLeaveTypes = {
    'Annual Leave',
    'Sick Leave',
    'Casual Leave',
    'Medical Leave',
  };

  static const Set<String> unpaidLeaveTypes = {
    'Unpaid Leave',
    // Legacy records used Custom Leave as the unlimited/non-quota option.
    'Custom Leave',
  };

  static String leaveType(Map<String, dynamic> record) {
    return (record['action'] ?? record['type'] ?? record['leaveType'] ?? '')
        .toString()
        .trim();
  }

  static bool isApproved(Map<String, dynamic> record) {
    return (record['status'] ?? 'Approved').toString().trim().toLowerCase() ==
        'approved';
  }

  static bool isPaidLeaveType(String type) => paidLeaveTypes.contains(type);

  static bool isUnpaidLeaveType(String type) => unpaidLeaveTypes.contains(type);

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

    // Supports Firestore Timestamp without coupling this helper to Firestore.
    try {
      final dynamic converted = value.toDate();
      if (converted is DateTime) {
        return DateTime(converted.year, converted.month, converted.day);
      }
    } catch (_) {}

    final parsed = DateTime.tryParse(value.toString().trim());
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Returns every date touched from [start] through [end], including both
  /// endpoints. The returned order follows the drag direction.
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

  /// Returns the exact leave dates for a record. New records persist an
  /// explicit `selectedDates` list; legacy records are expanded from their
  /// inclusive start/end range.
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
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final leave in timeOffRecords) {
      if (!isApproved(leave)) continue;
      if (!_belongsToWorker(
        leave,
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

  /// Returns all dates the worker has approved time off for, across all records.
  /// Used to exclude those days from attendance counts.
  static Set<DateTime> allLeaveDatesForWorker(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords,
  ) {
    final dates = <DateTime>{};
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final leave in timeOffRecords) {
      if (!isApproved(leave)) continue;
      if (!_belongsToWorker(
        leave,
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
    required String workerEmail,
    required String workerName,
  }) {
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
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    var used = 0;

    for (final record in timeOffRecords) {
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!isApproved(record) || !isPaidRecord(record)) continue;
      if (!_belongsToWorker(
        record,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      used += selectedDatesForRecord(record).length;
    }
    return used;
  }

  static int configuredPaidLeaveAllowance(Map<String, dynamic> worker) {
    return int.tryParse((worker['annualLeaves'] ?? '0').toString()) ?? 0;
  }

  static int remainingPaidLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    String? excludingRecordId,
  }) {
    final total = configuredPaidLeaveAllowance(worker);
    final used = paidDaysUsedForWorker(
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
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final requested = requestedDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();

    for (final record in timeOffRecords) {
      if (excludingRecordId != null &&
          record['id']?.toString() == excludingRecordId) {
        continue;
      }
      if (!isApproved(record)) continue;
      if (!_belongsToWorker(
        record,
        workerEmail: workerEmail,
        workerName: workerName,
      )) {
        continue;
      }
      if (selectedDatesForRecord(record).any(requested.contains)) return true;
    }
    return false;
  }

  /// Counts approved paid and unpaid time-off dates in [month]. Dates are
  /// de-duplicated so overlapping records cannot deduct payroll twice.
  static Map<String, int> monthlyLeaveCounts(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    required DateTime month,
  }) {
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final paidDates = <DateTime>{};
    final unpaidDates = <DateTime>{};

    for (final record in timeOffRecords) {
      if (!isApproved(record)) continue;
      if (!_belongsToWorker(
        record,
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

    // If a legacy overlap exists, paid leave wins and the date is not charged.
    unpaidDates.removeAll(paidDates);
    return {
      'paidLeaves': paidDates.length,
      'unpaidLeaves': unpaidDates.length,
      'leaves': paidDates.length + unpaidDates.length,
    };
  }
}
