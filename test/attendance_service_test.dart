import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';

void main() {
  test('attendance row workerId wins over the attendance document id', () {
    expect(
      AttendanceService.workerIdFor(const {
        'id': 'attendance-document-id',
        'workerId': 'worker-1',
      }),
      'worker-1',
    );
  });

  test('attendance preview matches a worker by email even if name changed', () {
    final records = AttendanceService.recordsForWorker(
      worker: const {'name': 'Ali Khan', 'email': 'ali@example.com'},
      attendanceRecords: const [
        {'name': 'Ali K.', 'email': 'ali@example.com', 'status': 'Leave'},
        {
          'name': 'Another Worker',
          'email': 'other@example.com',
          'status': 'Leave',
        },
      ],
    );

    expect(records, hasLength(1));
    expect(records.single['status'], 'Leave');
  });

  test('attendance preview falls back to normalized name without email', () {
    final records = AttendanceService.recordsForWorker(
      worker: const {'name': '  Ali   Khan  ', 'email': ''},
      attendanceRecords: const [
        {'name': 'ali khan', 'email': '', 'status': 'Leave'},
      ],
    );

    expect(records, hasLength(1));
  });

  test('legacy placeholder email falls back to worker name', () {
    final records = AttendanceService.recordsForWorker(
      worker: const {'name': 'Ali Khan', 'email': 'worker@email.com'},
      attendanceRecords: const [
        {'name': 'Ali Khan', 'email': 'worker@email.com', 'status': 'Leave'},
        {'name': 'Sara Khan', 'email': 'worker@email.com', 'status': 'Leave'},
      ],
    );

    expect(records, hasLength(1));
    expect(records.single['name'], 'Ali Khan');
  });

  test('worker ID takes priority for new attendance records', () {
    final records = AttendanceService.recordsForWorker(
      worker: const {'id': 'worker-1', 'name': 'Ali', 'email': 'same@test.com'},
      attendanceRecords: const [
        {
          'workerId': 'worker-1',
          'name': 'Old Ali',
          'email': 'same@test.com',
          'status': 'Leave',
        },
        {
          'workerId': 'worker-2',
          'name': 'Ali',
          'email': 'same@test.com',
          'status': 'Leave',
        },
      ],
    );

    expect(records, hasLength(1));
    expect(records.single['workerId'], 'worker-1');
  });

  test('attendance before worker creation date is ignored', () {
    final records = AttendanceService.recordsForWorker(
      worker: {
        'id': 'worker-1',
        'name': 'Ali',
        'createdAt': DateTime(2026, 7, 31),
      },
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'name': 'Ali',
          'attendanceDate': '2026-07-30',
          'status': 'Present',
        },
      ],
    );

    expect(records, isEmpty);
  });

  test('attendance on worker creation date remains valid', () {
    final records = AttendanceService.recordsForWorker(
      worker: {
        'id': 'worker-1',
        'name': 'Ali',
        'createdAt': DateTime(2026, 7, 30, 18),
      },
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'name': 'Ali',
          'attendanceDate': '2026-07-30',
          'status': 'Present',
        },
      ],
    );

    expect(records, hasLength(1));
  });

  test('attendance list clears status dated before worker creation', () {
    final combined = AttendanceService.combineAttendance(
      workersList: [
        {'id': 'worker-1', 'name': 'Ali', 'createdAt': DateTime(2026, 7, 31)},
      ],
      rawAttendanceDocs: const [
        {
          'workerId': 'worker-1',
          'name': 'Ali',
          'attendanceDate': '2026-07-30',
          'status': 'Present',
        },
      ],
    );

    expect(combined.single['status'], isEmpty);
  });

  test('attendance list keeps placeholder-email workers separate', () {
    final combined = AttendanceService.combineAttendance(
      workersList: const [
        {'id': 'worker-1', 'name': 'Ali', 'email': 'worker@email.com'},
        {'id': 'worker-2', 'name': 'Sara', 'email': 'worker@email.com'},
      ],
      rawAttendanceDocs: const [
        {
          'id': 'attendance-1',
          'name': 'Ali',
          'email': 'worker@email.com',
          'status': 'Leave',
        },
        {
          'id': 'attendance-2',
          'name': 'Sara',
          'email': 'worker@email.com',
          'status': 'Present',
        },
      ],
    );

    final byWorkerId = {
      for (final record in combined) record['workerId']: record,
    };
    expect(byWorkerId['worker-1']?['status'], 'Leave');
    expect(byWorkerId['worker-2']?['status'], 'Present');
  });
}
