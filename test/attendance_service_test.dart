import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  test('approved time off overrides stale present attendance', () {
    final result = AttendanceService.applyApprovedTimeOff(
      attendanceRecord: {
        'workerId': 'ethan-id',
        'name': 'Ethan',
        'status': 'Present',
      },
      timeOffRecord: {
        'workerId': 'ethan-id',
        'action': 'Sick Leave',
        'status': 'Approved',
      },
      automaticDescription: 'Automatically marked On Leave',
    );

    expect(result['status'], 'Leave');
    expect(result['type'], 'Sick Leave');
    expect(result['desc'], 'Automatically marked On Leave');
    expect(result['source'], 'auto_leave');
  });

  test('today leave assignment keys detect a second worker added live', () {
    final today = DateTime(2026, 8, 10);
    final existing = <Map<String, dynamic>>[
      {
        'id': 'leave-1',
        'workerId': 'worker-1',
        'action': 'Annual Leave',
        'selectedDates': [today],
      },
    ];
    final updated = <Map<String, dynamic>>[
      ...existing,
      {
        'id': 'leave-2',
        'workerId': 'ethan-id',
        'action': 'Sick Leave',
        'selectedDates': [today],
      },
    ];

    final previousKeys = TimeOffService.activeLeaveAssignmentKeysForDate(
      existing,
      today,
    );
    final currentKeys = TimeOffService.activeLeaveAssignmentKeysForDate(
      updated,
      today,
    );

    expect(previousKeys, hasLength(1));
    expect(currentKeys, hasLength(2));
    expect(previousKeys.containsAll(currentKeys), isFalse);
  });
}
