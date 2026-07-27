import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_service.dart';

void main() {
  const worker = <String, dynamic>{
    'name': 'Test Worker',
    'email': 'worker@example.com',
    'annualLeaves': '3',
  };

  final attendanceLeave = <String, dynamic>{
    'id': 'attendance-leave-1',
    'name': 'Test Worker',
    'email': 'worker@example.com',
    'action': 'Medical Leave',
    'type': 'Medical Leave',
    'startDate': '2026-07-27',
    'endDate': '2026-07-27',
    'selectedDates': [DateTime(2026, 7, 27)],
    'status': 'Approved',
    'isPaidLeave': true,
    'source': 'attendance',
  };

  test('marking attendance as Leave deducts exactly one paid leave', () {
    expect(TimeOffService.remainingPaidLeave(worker, const []), 3);
    expect(TimeOffService.remainingPaidLeave(worker, [attendanceLeave]), 2);
    expect(
      TimeOffService.paidDaysUsedForWorker(worker, [attendanceLeave]),
      1,
    );
  });

  test('editing attendance Leave back to Present restores the leave', () {
    final recordsAfterPresent = [attendanceLeave]
        .where((record) => record['id'] != 'attendance-leave-1')
        .toList();

    expect(TimeOffService.remainingPaidLeave(worker, recordsAfterPresent), 3);
    expect(
      TimeOffService.paidDaysUsedForWorker(worker, recordsAfterPresent),
      0,
    );
  });
}
