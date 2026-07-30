import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  const worker = {'name': 'Ali Khan', 'email': 'ali@example.com'};
  final leaves = <Map<String, dynamic>>[
    {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'startDate': '2026-07-01',
      'endDate': '2026-07-04',
      'status': 'Approved',
    },
  ];

  test('hides worker on every inclusive approved leave date', () {
    for (var day = 1; day <= 4; day++) {
      expect(
        TimeOffService.isWorkerOnLeave(
          worker,
          leaves,
          onDate: DateTime(2026, 7, day),
        ),
        isTrue,
      );
    }
  });

  test('shows worker again the day after leave ends', () {
    expect(
      TimeOffService.isWorkerOnLeave(
        worker,
        leaves,
        onDate: DateTime(2026, 7, 5),
      ),
      isFalse,
    );
  });

  test('worker ID keeps time off connected after email and name changes', () {
    final linkedWorker = {
      'id': 'worker-1',
      'name': 'Updated Name',
      'email': 'new@example.com',
    };
    final linkedLeave = [
      {
        'workerId': 'worker-1',
        'name': 'Old Name',
        'email': 'old@example.com',
        'selectedDates': ['2026-07-02'],
      },
    ];

    expect(
      TimeOffService.isWorkerOnLeave(
        linkedWorker,
        linkedLeave,
        onDate: DateTime(2026, 7, 2),
      ),
      isTrue,
    );
  });

  test('legacy unsupported leave types normalize to unpaid leave', () {
    expect(TimeOffService.normalizeLeaveType('Custom Leave'), 'Unpaid Leave');
    expect(
      TimeOffService.normalizeLeaveType('Maternity Leave'),
      'Unpaid Leave',
    );
  });

  test('only treats explicitly selected non-contiguous dates as leave', () {
    final selectedLeave = <Map<String, dynamic>>[
      {
        'name': 'Ali Khan',
        'email': 'ali@example.com',
        'startDate': '2026-07-15',
        'endDate': '2026-07-30',
        'selectedDates': [
          '2026-07-15',
          '2026-07-21',
          '2026-07-25',
          '2026-07-30',
        ],
        'requestedDays': 4,
        'status': 'Approved',
      },
    ];

    for (final day in [15, 21, 25, 30]) {
      expect(
        TimeOffService.isWorkerOnLeave(
          worker,
          selectedLeave,
          onDate: DateTime(2026, 7, day),
        ),
        isTrue,
      );
    }

    for (final day in [16, 20, 22, 29]) {
      expect(
        TimeOffService.isWorkerOnLeave(
          worker,
          selectedLeave,
          onDate: DateTime(2026, 7, day),
        ),
        isFalse,
      );
    }
  });

  test('expands legacy start and end dates for backward compatibility', () {
    final dates = TimeOffService.selectedDatesForRecord(leaves.first);

    expect(dates, hasLength(4));
    expect(dates.first, DateTime(2026, 7, 1));
    expect(dates.last, DateTime(2026, 7, 4));
  });

  test('builds an inclusive forward range for swipe selection', () {
    final dates = TimeOffService.inclusiveDateRange(
      DateTime(2026, 7, 10),
      DateTime(2026, 7, 14),
    );

    expect(dates, hasLength(5));
    expect(dates.first, DateTime(2026, 7, 10));
    expect(dates.last, DateTime(2026, 7, 14));
  });

  test('builds an inclusive reverse range for backward swipe selection', () {
    final dates = TimeOffService.inclusiveDateRange(
      DateTime(2026, 8, 2),
      DateTime(2026, 7, 30),
    );

    expect(dates, [
      DateTime(2026, 8, 2),
      DateTime(2026, 8, 1),
      DateTime(2026, 7, 31),
      DateTime(2026, 7, 30),
    ]);
  });

  test('annual allowance is consumed by both paid and unpaid records', () {
    const workerWithAllowance = {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'annualLeaves': '5',
    };
    final records = [
      {
        'id': 'paid-1',
        'email': 'ali@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': ['2026-07-01', '2026-07-02'],
      },
      {
        'id': 'unpaid-1',
        'email': 'ali@example.com',
        'type': 'Unpaid Leave',
        'isPaidLeave': false,
        'status': 'Approved',
        'selectedDates': ['2026-07-03'],
      },
    ];

    expect(
      TimeOffService.paidDaysUsedForWorker(workerWithAllowance, records),
      2,
    );
    expect(
      TimeOffService.leaveDaysUsedForWorker(workerWithAllowance, records),
      3,
    );
    expect(TimeOffService.remainingPaidLeave(workerWithAllowance, records), 2);
  });

  test('the same time-off date only consumes annual allowance once', () {
    const workerWithAllowance = {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'annualLeaves': '2',
    };
    final records = [
      {
        'email': 'ali@example.com',
        'type': 'Sick Leave',
        'selectedDates': ['2026-07-01'],
      },
      {
        'email': 'ali@example.com',
        'type': 'Unpaid Leave',
        'isPaidLeave': false,
        'selectedDates': ['2026-07-01'],
      },
    ];

    expect(
      TimeOffService.leaveDaysUsedForWorker(workerWithAllowance, records),
      1,
    );
    expect(TimeOffService.remainingPaidLeave(workerWithAllowance, records), 1);
  });

  test('using the full allowance exhausts the attendance leave balance', () {
    const workerWithAllowance = {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'annualLeaves': '15',
    };
    final records = [
      {
        'email': 'ali@example.com',
        'type': 'Medical Leave',
        'selectedDates': [
          for (var day = 1; day <= 15; day++)
            '2026-07-${day.toString().padLeft(2, '0')}',
        ],
      },
    ];

    expect(TimeOffService.remainingPaidLeave(workerWithAllowance, records), 0);
  });

  test('editing excludes the old record from available paid balance', () {
    const workerWithAllowance = {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'annualLeaves': '5',
    };
    final records = [
      {
        'id': 'paid-1',
        'email': 'ali@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': ['2026-07-01', '2026-07-02'],
      },
    ];

    expect(
      TimeOffService.remainingPaidLeave(
        workerWithAllowance,
        records,
        excludingRecordId: 'paid-1',
      ),
      5,
    );
  });

  test('empty time-off records return the full configured allowance', () {
    const workerWithAllowance = {
      'name': 'Ali Khan',
      'email': 'ali@example.com',
      'annualLeaves': 5.0,
    };

    expect(
      TimeOffService.paidDaysUsedForWorker(workerWithAllowance, const []),
      0,
    );
    expect(TimeOffService.remainingPaidLeave(workerWithAllowance, const []), 5);
  });

  test(
    'invalid or negative paid leave allowance is safely treated as zero',
    () {
      expect(
        TimeOffService.configuredPaidLeaveAllowance({'annualLeaves': '-5'}),
        0,
      );
      expect(
        TimeOffService.configuredPaidLeaveAllowance({
          'annualLeaves': 'invalid',
        }),
        0,
      );
      expect(
        TimeOffService.remainingPaidLeave({'annualLeaves': '-5'}, const []),
        0,
      );
    },
  );

  test('detects overlapping approved time off but ignores edited record', () {
    final records = [
      {
        'id': 'leave-1',
        'email': 'ali@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': ['2026-07-10', '2026-07-11'],
      },
    ];

    expect(
      TimeOffService.hasOverlappingApprovedLeave(worker, records, [
        DateTime(2026, 7, 11),
      ]),
      isTrue,
    );
    expect(
      TimeOffService.hasOverlappingApprovedLeave(worker, records, [
        DateTime(2026, 7, 11),
      ], excludingRecordId: 'leave-1'),
      isFalse,
    );
  });

  test('monthly counts separate paid and unpaid leave without duplicates', () {
    final records = [
      {
        'email': 'ali@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'selectedDates': ['2026-07-01', '2026-07-02'],
      },
      {
        'email': 'ali@example.com',
        'type': 'Unpaid Leave',
        'isPaidLeave': false,
        'status': 'Approved',
        'selectedDates': ['2026-07-03', '2026-07-03', '2026-08-01'],
      },
    ];

    expect(
      TimeOffService.monthlyLeaveCounts(
        worker,
        records,
        month: DateTime(2026, 7),
      ),
      {'paidLeaves': 2, 'unpaidLeaves': 1, 'leaves': 3},
    );
  });

  test(
    'cancelled time off restores balance and no longer blocks attendance',
    () {
      const workerWithAllowance = {
        'id': 'worker-1',
        'name': 'Ali Khan',
        'email': 'ali@example.com',
        'annualLeaves': '5',
      };
      final records = [
        {
          'id': 'leave-1',
          'workerId': 'worker-1',
          'email': 'ali@example.com',
          'type': 'Sick Leave',
          'status': 'Cancelled',
          'selectedDates': ['2026-07-29', '2026-07-30'],
        },
      ];

      expect(
        TimeOffService.isWorkerOnLeave(
          workerWithAllowance,
          records,
          onDate: DateTime(2026, 7, 29),
        ),
        isFalse,
      );
      expect(
        TimeOffService.leaveDaysUsedForWorker(workerWithAllowance, records),
        0,
      );
      expect(
        TimeOffService.remainingPaidLeave(workerWithAllowance, records),
        5,
      );
      expect(
        TimeOffService.hasOverlappingApprovedLeave(
          workerWithAllowance,
          records,
          [DateTime(2026, 7, 29)],
        ),
        isFalse,
      );
    },
  );
}
