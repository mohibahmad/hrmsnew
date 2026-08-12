import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/time_off_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeOffExportService tests', () {
    final sampleRecords = [
      {
        'workerName': 'Hamza Ali',
        'leaveType': 'Sick Leave',
        'startDate': '2026-02-01',
        'endDate': '2026-02-05',
        'days': 5,
        'status': 'Approved',
        'reason': 'Fever',
      },
      {
        'workerName': 'Maryam Khan',
        'leaveType': 'Casual Leave',
        'startDate': '2026-02-10',
        'endDate': '2026-02-11',
        'days': 2,
        'status': 'Approved',
        'reason': 'Personal work',
      },
    ];

    test('generateCsvContent formats records into CSV string correctly', () {
      final csv = TimeOffExportService.generateCsvContent(sampleRecords);

      expect(csv, contains('Worker Name,Leave Type,From Date,To Date,Days,Status,Reason'));
      expect(csv, contains('"Hamza Ali","Sick Leave"'));
      expect(csv, contains('"01 Feb 2026","05 Feb 2026","5","Approved"'));
      expect(csv, contains('"Maryam Khan","Casual Leave"'));
    });

    test('generatePdfReport produces non-empty PDF bytes', () async {
      final pdfBytes = await TimeOffExportService.generatePdfReport(
        records: sampleRecords,
        periodLabel: '01 Feb 2026 - 28 Feb 2026',
        leaveTypeFilter: 'All',
        companyName: 'Test HRMS Company',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(0));
    });
  });
}
