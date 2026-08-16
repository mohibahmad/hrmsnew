
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attendance_service.dart';
import 'time_off_service.dart';
import '../utils/utils.dart';

class AttendanceDateRange {
  final DateTime start;
  final DateTime end;
  final Set<DateTime>? discreteDates;

  const AttendanceDateRange({
    required this.start,
    required this.end,
    this.discreteDates,
  });

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);

    if (discreteDates != null && discreteDates!.isNotEmpty) {
      return discreteDates!.any(
        (d) => d.year == day.year && d.month == day.month && d.day == day.day,
      );
    }

    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return !day.isBefore(startDay) && !day.isAfter(endDay);
  }
}

class WorkerAttendanceSnapshot {
  final List<Map<String, dynamic>> records;
  final int? expectedWorkingDays;

  const WorkerAttendanceSnapshot(this.records, {this.expectedWorkingDays});

  int get totalWorkingDays =>
      (expectedWorkingDays != null && expectedWorkingDays! > 0)
          ? expectedWorkingDays!
          : records.length;

  int get presents =>
      records.where((d) => normalizedAttendanceStatus(d) == 'present').length;

  int get absents =>
      records.where((d) => normalizedAttendanceStatus(d) == 'absent').length;

  int get leaves =>
      records.where((d) => normalizedAttendanceStatus(d) == 'leave').length;

  double get percentage =>
      totalWorkingDays == 0 ? 0 : (presents / totalWorkingDays) * 100;

}

class AttendanceReportService {

  AttendanceReportService._();

  static AttendanceDateRange rangeForPeriod(
    String period, {
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final normalizedPeriod = switch (period.trim()) {
      'Weekly' || 'This Week' => 'Week',
      'Monthly' || 'This Month' => 'Month',
      '6 Monthly' || '6 Months' || 'Last 6 Months' => '6 Month',
      'Yearly' || 'This Year' => 'Yearly',
      'All Time' => 'All Time',
      _ => period.trim(),
    };

    final start = switch (normalizedPeriod) {
      'Today' => today,
      'Week' => today.subtract(Duration(days: today.weekday - 1)),
      'Month' => DateTime(today.year, today.month, 1),
      '6 Month' => DateTime(today.year, today.month - 5, 1),
      'Yearly' => DateTime(today.year, 1, 1),
      'All Time' => DateTime(1970, 1, 1),
      _ => today,
    };

    final end = switch (normalizedPeriod) {
      'Today' => today,
      'Week' => start.add(const Duration(days: 6)),
      'Month' => DateTime(today.year, today.month + 1, 0),
      '6 Month' => DateTime(today.year, today.month + 1, 0),
      'Yearly' => DateTime(today.year, 12, 31),
      'All Time' => DateTime(2099, 12, 31),
      _ => today,
    };

    return AttendanceDateRange(start: start, end: end);
  }

  static DateTime? recordDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse((value ?? '').toString());
  }

  static DateTime? recordDateForRecord(Map<String, dynamic> record) {
    return AppDateUtils.attendanceRecordDate(record);
  }

  static String csvTextDate(DateTime? date) {
    if (date == null) return '';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '\t${date.day.toString().padLeft(2, '0')}-'
        '${months[date.month - 1]}-${date.year}';
  }

  static DateTime? _recordRevisionDate(Map<String, dynamic> record) {
    for (final key in ['updatedAt', 'createdAt']) {
      final date = recordDate(record[key]);
      if (date != null) return date;
    }
    return null;
  }

  static bool _shouldReplaceRecord(
    Map<String, dynamic> existing,
    Map<String, dynamic> candidate,
  ) {
    final existingRevision = _recordRevisionDate(existing);
    final candidateRevision = _recordRevisionDate(candidate);

    if (candidateRevision != null && existingRevision == null) return true;
    if (candidateRevision == null && existingRevision != null) return false;
    if (candidateRevision == null || existingRevision == null) return false;

    return candidateRevision.isAfter(existingRevision);
  }

  static List<Map<String, dynamic>> recordsForWorker({
    required Map<String, dynamic> worker,
    required List<Map<String, dynamic>> attendanceRecords,
    required List<Map<String, dynamic>> timeOffRecords,
    required AttendanceDateRange range,
  }) {
    final recordsByDay = <String, Map<String, dynamic>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rawRecords = AttendanceService.recordsForWorker(
      worker: worker,
      attendanceRecords: attendanceRecords,
    );

    final leaveDates = TimeOffService.allLeaveDatesForWorker(
      worker,
      timeOffRecords,
    ).where((date) => !date.isAfter(today)).toSet();
    final leaveDateKeys = leaveDates.map(_dateKey).toSet();

    for (final record in rawRecords) {
      final date = recordDateForRecord(record);

      if (date == null || date.isAfter(today) || !range.contains(date)) {
        continue;
      }

      final status = (record['status'] ?? '').toString().trim().toLowerCase();
      final key = _dateKey(date);

      if (status == 'leave' && !leaveDateKeys.contains(key)) continue;

      final existing = recordsByDay[key];
      if (existing == null || _shouldReplaceRecord(existing, record)) {
        recordsByDay[key] = Map<String, dynamic>.from(record);
      }
    }

    final leaveIndex = <String, Map<String, dynamic>>{};
    for (final leave in timeOffRecords) {
      if (!TimeOffService.isActiveRecord(leave)) continue;
      if (!_belongsLeaveToWorker(leave, worker)) continue;

      for (final date in TimeOffService.selectedDatesForRecord(leave)) {
        final key = _dateKey(date);
        leaveIndex[key] ??= leave;
      }
    }

    for (final leaveDate in leaveDates) {
      if (!range.contains(leaveDate)) continue;

      final normalizedLeaveDate = DateTime(
        leaveDate.year,
        leaveDate.month,
        leaveDate.day,
      );

      final key = _dateKey(normalizedLeaveDate);
      final existing = recordsByDay[key] ?? const <String, dynamic>{};
      final leave = leaveIndex[key];
      final leaveReason = leave == null ? '' : TimeOffService.leaveType(leave);

      recordsByDay[key] = {
        ...existing,
        'workerId': worker['id'] ?? worker['workerId'] ?? existing['workerId'],
        'name': worker['name'] ?? existing['name'] ?? 'Worker',
        'email': worker['email'] ?? existing['email'] ?? '',
        'role': worker['position'] ?? worker['role'] ?? existing['role'] ?? '',
        'workType': worker['type1'] ?? worker['workType'] ?? existing['workType'] ?? 'Full Time',
        'attendanceType': worker['type2'] ?? worker['attendanceType'] ?? existing['attendanceType'] ?? 'On-Site',
        'attendanceDate': normalizedLeaveDate,
        'createdAt': normalizedLeaveDate,
        'status': 'Leave',
        'reason': leaveReason.trim().isNotEmpty
            ? leaveReason
            : (existing['reason'] ?? existing['desc'] ?? '-'),
      };
    }

    final records = recordsByDay.values.toList();
    records.sort((a, b) {
      final aDate = recordDateForRecord(a);
      final bDate = recordDateForRecord(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return records;
  }

  static bool _belongsLeaveToWorker(
    Map<String, dynamic> leave,
    Map<String, dynamic> worker,
  ) {

    final workerId = (worker['id'] ?? worker['workerId'] ?? '').toString().trim();
    final leaveWorkerId = (leave['workerId'] ?? '').toString().trim();
    if (workerId.isNotEmpty && leaveWorkerId.isNotEmpty) {
      return workerId == leaveWorkerId;
    }

    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final leaveEmail = (leave['email'] ?? '').toString().trim().toLowerCase();
    if (workerEmail.isNotEmpty && leaveEmail.isNotEmpty) {
      return workerEmail == leaveEmail;
    }

    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();
    final leaveName = (leave['name'] ?? leave['workerName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return workerName.isNotEmpty && workerName == leaveName;
  }

  static WorkerAttendanceSnapshot snapshotForWorker({
    required Map<String, dynamic> worker,
    required List<Map<String, dynamic>> attendanceRecords,
    required List<Map<String, dynamic>> timeOffRecords,
    required AttendanceDateRange range,
  }) {
    return WorkerAttendanceSnapshot(
      recordsForWorker(
        worker: worker,
        attendanceRecords: attendanceRecords,
        timeOffRecords: timeOffRecords,
        range: range,
      ),
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}