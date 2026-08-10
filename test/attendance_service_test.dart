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

  test('approved paid leave on the reference date counts in payroll', () {
    final counts = TimeOffService.monthlyLeaveCounts(
      {'id': 'noah-id', 'email': 'noah@example.com'},
      [
        {
          'workerId': 'noah-id',
          'action': 'Annual Leave',
          'status': 'Approved',
          'selectedDates': [DateTime(2026, 8, 10), DateTime(2026, 8, 11)],
        },
      ],
      month: DateTime(2026, 8),
      referenceDate: DateTime(2026, 8, 10),
    );

    expect(counts['paidLeaves'], 1);
    expect(counts['unpaidLeaves'], 0);
    expect(counts['leaves'], 1);
  });

  test('legacy Avery leave counters normalize from total and remaining', () {
    final normalized = TimeOffService.canonicalWorkerLeaveFields({
      'annualLeaves': 14,
      'availableAnnualLeaves': '0',
      'annualLeavesUsed': '2',
      'sickLeaves': '6',
      'availableSickLeaves': '0',
      'sickLeavesUsed': '0',
      'casualLeaves': '3',
      'availableCasualLeaves': '0',
      'casualLeavesUsed': '0',
      'medicalLeaves': '4',
      'availableMedicalLeaves': '4',
      'medicalLeavesUsed': '0',
      'leavesUsed': '2',
      'leaveBalances': {
        'annualLeave': '12',
        'sickLeave': '6',
        'casualLeave': '3',
        'medicalLeave': '4',
      },
    });

    expect(normalized['annualLeavesUsed'], 14);
    expect(normalized['sickLeavesUsed'], 6);
    expect(normalized['casualLeavesUsed'], 3);
    expect(normalized['medicalLeavesUsed'], 0);
    expect(normalized['leavesUsed'], 23);
    expect(normalized['leaveBalances'], {
      'annualLeave': 0,
      'sickLeave': 0,
      'casualLeave': 0,
      'medicalLeave': 4,
    });

    for (final key in [
      'annualLeaves',
      'availableAnnualLeaves',
      'annualLeavesUsed',
      'sickLeaves',
      'availableSickLeaves',
      'sickLeavesUsed',
      'casualLeaves',
      'availableCasualLeaves',
      'casualLeavesUsed',
      'medicalLeaves',
      'availableMedicalLeaves',
      'medicalLeavesUsed',
      'leavesUsed',
    ]) {
      expect(normalized[key], isA<int>(), reason: '$key must be numeric');
    }
  });

  test('balance override recalculates used without inflating allowance', () {
    final normalized = TimeOffService.canonicalWorkerLeaveFields(
      {'annualLeaves': 14, 'availableAnnualLeaves': 0, 'annualLeavesUsed': 14},
      remainingBalances: {'annualLeave': 2},
    );

    expect(normalized['annualLeaves'], 14);
    expect(normalized['availableAnnualLeaves'], 2);
    expect(normalized['annualLeavesUsed'], 12);
  });
}
