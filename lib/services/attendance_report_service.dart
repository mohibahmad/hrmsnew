import 'package:cloud_firestore/cloud_firestore.dart';

import 'attendance_service.dart';
import 'time_off_service.dart';
import '../utils/date_utils.dart';

class AttendanceDateRange {
  final DateTime start;
  final DateTime end;

  const AttendanceDateRange({required this.start, required this.end});

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return !day.isBefore(startDay) && !day.isAfter(endDay);
  }
}

class WorkerAttendanceSnapshot {
  final List<Map<String, dynamic>> records;

  const WorkerAttendanceSnapshot(this.records);

  int get totalWorkingDays => records.length;
  int get presents => records.where((d) => d['status'] == 'Present').length;
  int get absents => records.where((d) => d['status'] == 'Absent').length;
  int get leaves => records.where((d) => d['status'] == 'Leave').length;
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
    final end = DateTime(now.year, now.month, now.day);
    final normalizedPeriod = switch (period.trim()) {
      'Weekly' => 'Week',
      'Monthly' => 'Month',
      '6 Monthly' => '6 Month',
      '6 Months' => '6 Month',
      _ => period.trim(),
    };

    final start = switch (normalizedPeriod) {
      'Week' => end.subtract(Duration(days: end.weekday - DateTime.monday)),
      'Month' => DateTime(now.year, now.month, 1),
      '6 Month' => DateTime(now.year, now.month - 5, 1),
      'Yearly' => DateTime(now.year, 1, 1),
      _ => end,
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

    final rawRecords = AttendanceService.recordsForWorker(
      worker: worker,
      attendanceRecords: attendanceRecords,
    );

    for (final record in rawRecords) {
      final date = recordDateForRecord(record);
      if (date == null || !range.contains(date)) continue;

      final key = _dateKey(date);
      final existing = recordsByDay[key];
      if (existing == null || _shouldReplaceRecord(existing, record)) {
        recordsByDay[key] = Map<String, dynamic>.from(record);
      }
    }

    final leaveDates = TimeOffService.allLeaveDatesForWorker(
      worker,
      timeOffRecords,
    );

    for (final leaveDate in leaveDates) {
      if (!range.contains(leaveDate)) continue;

      final normalizedLeaveDate = DateTime(
        leaveDate.year,
        leaveDate.month,
        leaveDate.day,
      );
      final key = _dateKey(normalizedLeaveDate);
      final existing = recordsByDay[key] ?? const <String, dynamic>{};
      final leave = TimeOffService.activeLeaveForWorker(
        worker,
        timeOffRecords,
        onDate: normalizedLeaveDate,
      );
      final leaveReason = leave == null ? '' : TimeOffService.leaveType(leave);

      recordsByDay[key] = {
        ...existing,
        'workerId': worker['id'] ?? worker['workerId'] ?? existing['workerId'],
        'name': worker['name'] ?? existing['name'] ?? 'Worker',
        'email': worker['email'] ?? existing['email'] ?? '',
        'role': worker['position'] ?? worker['role'] ?? existing['role'] ?? '',
        'workType':
            worker['type1'] ??
            worker['workType'] ??
            existing['workType'] ??
            'Full Time',
        'attendanceType':
            worker['type2'] ??
            worker['attendanceType'] ??
            existing['attendanceType'] ??
            'On-Site',
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
