import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_report_service.dart';

void main() {
  group('Worker Attendance Preview — future time off excluded', () {
    final worker = {
      'workerId': 'w1',
      'id': 'w1',
      'name': 'Aisha Hill',
      'email': 'aisha@example.com',
    };

    final rawAttendance = <Map<String, dynamic>>[
      {
        'id': 'att-present',
        'workerId': 'w1',
        'name': 'Aisha Hill',
        'email': 'aisha@example.com',
        'attendanceDate': '2026-08-11',
        'status': 'Present',
      },
    ];

    final timeOffRecords = <Map<String, dynamic>>[
      {
        'id': 'leave-1',
        'workerId': 'w1',
        'name': 'Aisha Hill',
        'email': 'aisha@example.com',
        'type': 'Annual Leave',
        'status': 'Approved',
        'startDate': '2026-08-10',
        'endDate': '2026-08-10',
        'selectedDates': ['2026-08-10'],
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
        'endDate': '2026-09-15',
        'selectedDates': [
          '2026-09-05', '2026-09-06', '2026-09-07', '2026-09-08',
          '2026-09-09', '2026-09-10', '2026-09-11', '2026-09-12',
          '2026-09-13', '2026-09-14', '2026-09-15',
        ],
        'isPaidLeave': true,
      },
    ];

    test('Last 6 Months on 2026-08-17 counts 1 leave, not the 11 future days',
        () {
      final now = DateTime(2026, 8, 17);



      final records = AttendanceReportService.recordsForWorker(
        worker: worker,
        attendanceRecords: rawAttendance,
        timeOffRecords: timeOffRecords,
        range: AttendanceReportService.rangeForPeriod('Last 6 Months',
            referenceDate: now),
      );

      final leaves =
          records.where((d) => d['status'] == 'Leave').length;
      final presents =
          records.where((d) => d['status'] == 'Present').length;
      final total = records.length;



      final futureDates = records
          .map((r) => AttendanceReportService.recordDateForRecord(r))
          .where((d) => d != null && d.isAfter(now))
          .length;

      expect(leaves, 1, reason: 'Total Leaves must be 1 (Aug 10), not 11');
      expect(presents, 1);
      expect(total, 2, reason: 'Total Working Days must exclude future days');
      expect(futureDates, 0,
          reason: 'No future September time-off dates may be counted yet');
      expect(
        records.any((r) =>
            AttendanceReportService.recordDateForRecord(r)?.month == 9),
        isFalse,
        reason: 'September leave must remain stored but contribute zero',
      );
    });

    test('leave starting today through the future counts only today', () {

      final records = AttendanceReportService.recordsForWorker(
        worker: worker,
        attendanceRecords: rawAttendance,
        timeOffRecords: [
          {
            'id': 'leave-span',
            'workerId': 'w1',
            'name': 'Aisha Hill',
            'email': 'aisha@example.com',
            'type': 'Annual Leave',
            'status': 'Approved',
            'startDate': '2026-08-17',
            'endDate': '2026-08-27',
            'isPaidLeave': true,
          },
        ],
        range: AttendanceReportService.rangeForPeriod('Last 6 Months',
            referenceDate: DateTime(2026, 8, 17)),
      );

      final leaves =
          records.where((d) => d['status'] == 'Leave').length;
      expect(leaves, 1,
          reason: 'Only the portion on/before today counts as leave');
    });
  });
}
