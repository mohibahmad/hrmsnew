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
}
