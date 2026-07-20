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
}
