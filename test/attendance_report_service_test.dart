import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/attendance_report_service.dart';

void main() {
  group('AttendanceReportService tests', () {
    test('rangeForPeriod handles Last 6 Months correctly', () {
      final now = DateTime(2026, 8, 12);
      final range = AttendanceReportService.rangeForPeriod('Last 6 Months', referenceDate: now);

      expect(range.start, equals(DateTime(2026, 3, 1)));
      expect(range.end, equals(DateTime(2026, 8, 31)));
      expect(range.contains(DateTime(2026, 3, 12)), true);
      expect(range.contains(DateTime(2026, 6, 12)), true);
    });

    test('rangeForPeriod handles This Year correctly', () {
      final now = DateTime(2026, 8, 12);
      final range = AttendanceReportService.rangeForPeriod('This Year', referenceDate: now);

      expect(range.start, equals(DateTime(2026, 1, 1)));
      expect(range.end, equals(DateTime(2026, 12, 31)));
      expect(range.contains(DateTime(2026, 10, 15)), true);
    });

    test('recordsForWorker includes backdated attendance and filters spurious auto-leave', () {
      final worker = {
        'id': 'worker_1',
        'name': 'Abdul Rehman',
        'email': 'abdul@example.com',
        'joiningDate': '2026-08-01',
      };

      final attendanceRecords = [
        {
          'workerId': 'worker_1',
          'attendanceDate': '2026-03-12',
          'status': 'Present',
        },
        {
          'workerId': 'worker_1',
          'attendanceDate': '2026-08-12',
          'status': 'Leave',
          'source': 'auto_leave',
        },
      ];

      final timeOffRecords = <Map<String, dynamic>>[];

      final range = AttendanceReportService.rangeForPeriod(
        'Last 6 Months',
        referenceDate: DateTime(2026, 8, 12),
      );

      final records = AttendanceReportService.recordsForWorker(
        worker: worker,
        attendanceRecords: attendanceRecords,
        timeOffRecords: timeOffRecords,
        range: range,
      );

      // Should include 12 March Present, and exclude spurious 12 August auto-leave since there are no timeOffRecords for 12 August
      expect(records.length, equals(1));
      expect(records.first['status'], equals('Present'));
    });
  });
}
