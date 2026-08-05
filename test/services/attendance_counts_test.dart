import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';

void main() {
  test('countRecordsByStatus counts every record (day-level), not per worker',
      () {
    final records = [
      {
        'name': 'A',
        'status': 'Present',
        'attendanceDate': DateTime(2026, 1, 5),
      },
      {
        'name': 'A',
        'status': 'Present',
        'attendanceDate': DateTime(2026, 1, 6),
      },
      {'name': 'B', 'status': 'Absent', 'attendanceDate': DateTime(2026, 1, 5)},
      {'name': 'C', 'status': 'Leave', 'attendanceDate': DateTime(2026, 1, 5)},
      {
        'name': 'D',
        'status': 'present',
        'attendanceDate': DateTime(2026, 1, 5),
      },
    ];

    final counts = AttendanceService.countRecordsByStatus(records, []);

    expect(counts['present'], 3,
        reason: 'Same worker on two days counts both days');
    expect(counts['absent'], 1);
    expect(counts['leave'], 1);
  });

  test('worker on approved time-off that day counts as Leave, not Present',
      () {
    final records = [
      {
        'name': 'A',
        'email': 'a@x.com',
        'status': 'Present',
        'attendanceDate': DateTime(2026, 1, 5),
      },
    ];
    final timeOff = [
      {
        'email': 'a@x.com',
        'startDate': DateTime(2026, 1, 4),
        'endDate': DateTime(2026, 1, 6),
      },
    ];

    final counts = AttendanceService.countRecordsByStatus(records, timeOff);

    expect(counts['present'], 0);
    expect(counts['leave'], 1);
  });

  test('cancelled/rejected time-off does not turn a Present into Leave', () {
    final records = [
      {
        'name': 'A',
        'email': 'a@x.com',
        'status': 'Present',
        'attendanceDate': DateTime(2026, 1, 5),
      },
    ];
    final timeOff = [
      {
        'email': 'a@x.com',
        'startDate': DateTime(2026, 1, 4),
        'endDate': DateTime(2026, 1, 6),
        'status': 'Rejected',
      },
    ];

    final counts = AttendanceService.countRecordsByStatus(records, timeOff);

    expect(counts['present'], 1);
    expect(counts['leave'], 0);
  });
}
