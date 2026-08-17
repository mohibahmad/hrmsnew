import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  group('Payroll historical leave counts exclude future time off', () {
    final worker = {
      'workerId': 'w1',
      'id': 'w1',
      'name': 'Aisha Hill',
      'email': 'aisha@example.com',
    };

    final records = [
      {
        'id': 'leave-1',
        'workerId': 'w1',
        'name': 'Aisha Hill',
        'email': 'aisha@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'startDate': '2026-08-10',
        'endDate': '2026-08-12',
        'selectedDates': ['2026-08-10', '2026-08-11', '2026-08-12'],
        'isPaidLeave': true,
      },
      {
        'id': 'leave-2',
        'workerId': 'w1',
        'name': 'Aisha Hill',
        'email': 'aisha@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'startDate': '2026-09-05',
        'endDate': '2026-09-09',
        'selectedDates': ['2026-09-05', '2026-09-06', '2026-09-07', '2026-09-08', '2026-09-09'],
        'isPaidLeave': true,
      },
    ];

    test('counts only dates within the selected payroll period and excludes future dates', () {
      final counts = TimeOffService.monthlyLeaveCounts(
        worker,
        records,
        month: DateTime(2026, 8, 1),
        startDate: DateTime(2026, 7, 17),
        endDate: DateTime(2026, 8, 17),
        referenceDate: DateTime(2026, 8, 17),
      );

      expect(counts['paidLeaves'], 3);
      expect(counts['unpaidLeaves'], 0);
      expect(counts['leaves'], 3);
    });
  });
}
