import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_report_service.dart';

void main() {
  test(
    'CSV dates use an unambiguous ISO format and blanks for missing dates',
    () {
      expect(
        AttendanceReportService.csvDate(DateTime(2026, 8, 1)),
        '2026-08-01',
      );
      expect(AttendanceReportService.csvDate(null), isEmpty);
    },
  );

  test('share period aliases use the same ranges as attendance filters', () {
    final now = DateTime(2026, 7, 29, 18);

    expect(
      AttendanceReportService.rangeForPeriod(
        'Weekly',
        referenceDate: now,
      ).start,
      DateTime(2026, 7, 22),
    );
    expect(
      AttendanceReportService.rangeForPeriod('Month', referenceDate: now).start,
      DateTime(2026, 6, 29),
    );
    expect(
      AttendanceReportService.rangeForPeriod(
        'Monthly',
        referenceDate: now,
      ).start,
      DateTime(2026, 6, 29),
    );
    expect(
      AttendanceReportService.rangeForPeriod('Yearly', referenceDate: now).end,
      DateTime(2026, 7, 29),
    );
  });

  test('preview and report include one effective record per worker day', () {
    const worker = {
      'id': 'worker-1',
      'name': 'Ali',
      'email': 'ali@example.com',
      'position': 'Designer',
      'type1': 'Full Time',
      'type2': 'On-Site',
    };
    final snapshot = AttendanceReportService.snapshotForWorker(
      worker: worker,
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'createdAt': DateTime(2026, 7, 29, 9),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'createdAt': DateTime(2026, 7, 29, 10),
          'status': 'Present',
        },
        {
          'workerId': 'worker-1',
          'createdAt': DateTime(2026, 7, 28, 10),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'createdAt': DateTime(2026, 7, 27, 10),
          'status': 'Present',
        },
      ],
      timeOffRecords: [
        {
          'workerId': 'worker-1',
          'action': 'Sick Leave',
          'status': 'Approved',
          'selectedDates': [DateTime(2026, 7, 27)],
        },
        {
          'workerId': 'worker-1',
          'action': 'Casual Leave',
          'status': 'Cancelled',
          'selectedDates': [DateTime(2026, 7, 26)],
        },
      ],
      range: AttendanceDateRange(
        start: DateTime(2026, 7, 22),
        end: DateTime(2026, 7, 29),
      ),
    );

    expect(snapshot.totalWorkingDays, 3);
    expect(snapshot.presents, 1);
    expect(snapshot.absents, 1);
    expect(snapshot.leaves, 1);
    expect(snapshot.percentage, closeTo(33.333, 0.01));
    expect(
      snapshot.records.singleWhere(
        (record) =>
            AttendanceReportService.recordDate(record['createdAt'])?.day == 27,
      )['reason'],
      'Sick Leave',
    );
  });

  test('worker id keeps same-email workers separated in reports', () {
    final records = AttendanceReportService.recordsForWorker(
      worker: const {
        'id': 'worker-2',
        'name': 'Sara',
        'email': 'same@example.com',
      },
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'email': 'same@example.com',
          'createdAt': DateTime(2026, 7, 29),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-2',
          'email': 'same@example.com',
          'createdAt': DateTime(2026, 7, 29),
          'status': 'Present',
        },
      ],
      timeOffRecords: const [],
      range: AttendanceDateRange(
        start: DateTime(2026, 7, 29),
        end: DateTime(2026, 7, 29),
      ),
    );

    expect(records, hasLength(1));
    expect(records.single['status'], 'Present');
  });

  test('edited attendanceDate overrides the immutable creation timestamp', () {
    final records = AttendanceReportService.recordsForWorker(
      worker: const {
        'id': 'worker-1',
        'name': 'Carlos Garcia',
        'email': 'carlos@example.com',
      },
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'attendanceDate': '2026-07-30',
          'createdAt': DateTime(2026, 7, 29, 9),
          'status': 'Present',
        },
      ],
      timeOffRecords: const [],
      range: AttendanceDateRange(
        start: DateTime(2026, 7, 30),
        end: DateTime(2026, 7, 30),
      ),
    );

    expect(records, hasLength(1));
    expect(
      AttendanceReportService.recordDateForRecord(records.single),
      DateTime(2026, 7, 30),
    );
  });
}
