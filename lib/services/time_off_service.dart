class TimeOffService {
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
      final status = (leave['status'] ?? 'Approved')
          .toString()
          .trim()
          .toLowerCase();
      if (status != 'approved') continue;

      final leaveEmail = (leave['email'] ?? '').toString().trim().toLowerCase();
      final leaveName = (leave['name'] ?? leave['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final sameWorker = workerEmail.isNotEmpty && leaveEmail.isNotEmpty
          ? workerEmail == leaveEmail
          : workerName.isNotEmpty && workerName == leaveName;
      if (!sameWorker) continue;

      final leaveDates = selectedDatesForRecord(leave);
      if (leaveDates.contains(target)) return leave;
    }
    return null;
  }

  static bool isWorkerOnLeave(
    Map<String, dynamic> worker,
    List<Map<String, dynamic>> timeOffRecords, {
    DateTime? onDate,
  }) => activeLeaveForWorker(worker, timeOffRecords, onDate: onDate) != null;
}
