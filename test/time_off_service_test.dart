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

  test('does not hide worker for non-approved leave', () {
    final pending = [
      {...leaves.first, 'status': 'Pending'},
    ];
    expect(
      TimeOffService.isWorkerOnLeave(
        worker,
        pending,
        onDate: DateTime(2026, 7, 2),
      ),
      isFalse,
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

  test('paid leave balance is recalculated from approved records', () {
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
    expect(TimeOffService.remainingPaidLeave(workerWithAllowance, records), 3);
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
}
