import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_service.dart';

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
}
