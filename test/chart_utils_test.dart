import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/chart_utils.dart';

void main() {
  group('getChartData adaptive behavior', () {
    test('adapts to the records actual date range when none are in the '
        'selected period (e.g. last year while This Year is selected)', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2025, 7, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 7, 15), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.isAdaptive, isTrue);
      expect(chart.labels.length, 12);
      expect(chart.values.length, 12);
      // Every record lands in exactly one bucket.
      expect(chart.values.reduce((a, b) => a + b), 3);
      expect(chart.rangeStart, DateTime(2025, 7, 1));
      expect(chart.rangeEnd, DateTime(2025, 8, 10));
    });

    test('month period adapts with 4 buckets over the actual range', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2025, 2, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 2, 10), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 2, 20), 'status': 'present'},
      ];

      final chart = getChartData('This Month', docs, false, 'en_US');

      expect(chart.isAdaptive, isTrue);
      expect(chart.labels.length, 4);
      expect(chart.values.reduce((a, b) => a + b), 3);
    });

    test('counts records on a single day exactly once (no multi-count)', () {
      final docs = <Map<String, dynamic>>[
        for (int i = 0; i < 5; i++)
          {'attendanceDate': DateTime(2025, 7, 1), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.isAdaptive, isTrue);
      expect(chart.values.reduce((a, b) => a + b), 5);
    });

    test('counts a record landing on a bucket boundary exactly once', () {
      // Day indices 0, 3, 14, 40 of a Jul 1 -> Aug 10 (41 day) range;
      // index 3 is the boundary between the first two of the 12 buckets.
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2025, 7, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 7, 4), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 7, 15), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.values.reduce((a, b) => a + b), 4);
      // First two records (Jul 1 and Jul 4) both land in bucket 0.
      expect(chart.values.first, 2);
    });

    test('keeps normal period buckets when records are inside the period', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': now, 'status': 'present'},
      ];

      final chart = getChartData('Today', docs, false, 'en_US');

      expect(chart.isAdaptive, isFalse);
      expect(chart.labels.length, 7);
      expect(chart.values.reduce((a, b) => a + b), 1);
      expect(chart.rangeStart, isNull);
      expect(chart.rangeEnd, isNull);
    });

    test('year chart keeps missing months at zero', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(now.year, 7, 1), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.isAdaptive, isFalse);
      expect(chart.values, hasLength(12));
      expect(chart.values[6], 1);
      expect(chart.values.where((value) => value == 0).length, 11);
    });

    test('All Time includes attendance records across multiple years', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2023, 1, 10), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 7, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2026, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('All Time', docs, false, 'en_US');

      expect(chart.isAdaptive, isTrue);
      expect(chart.labels, ['JAN 23', 'JUL 25', 'AUG 26']);
      expect(chart.values, hasLength(3));
      expect(chart.values.reduce((a, b) => a + b), 3);
      expect(chart.rangeStart, DateTime(2023, 1, 10));
      expect(chart.rangeEnd, DateTime(2026, 8, 10));
    });

    test('All Time creates one point for one recorded month', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2026, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('All Time', docs, false, 'en_US');

      expect(chart.labels, ['AUG 26']);
      expect(chart.values, [1.0]);
      expect(chart.rangeStart, DateTime(2026, 8, 10));
      expect(chart.rangeEnd, DateTime(2026, 8, 10));
    });
  });

  group('latestAttendanceRecordPerWorker', () {
    test('keeps only the latest status for each worker', () {
      final records = <Map<String, dynamic>>[
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(2026, 7, 10),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(2026, 8, 10),
          'status': 'Present',
        },
        {
          'workerId': 'worker-2',
          'attendanceDate': DateTime(2026, 8, 10),
          'status': 'Absent',
        },
      ];

      final latest = latestAttendanceRecordPerWorker(records);

      expect(latest, hasLength(2));
      expect(
        latest.singleWhere(
          (record) => record['workerId'] == 'worker-1',
        )['status'],
        'Present',
      );
      expect(
        latest.singleWhere(
          (record) => record['workerId'] == 'worker-2',
        )['status'],
        'Absent',
      );
    });

    test('uses the latest edit for duplicate records on the same day', () {
      final records = <Map<String, dynamic>>[
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(2026, 8, 10),
          'createdAt': DateTime(2026, 8, 10, 8),
          'updatedAt': DateTime(2026, 8, 10, 8),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(2026, 8, 10),
          'createdAt': DateTime(2026, 8, 10, 8),
          'updatedAt': DateTime(2026, 8, 10, 9),
          'status': 'Present',
        },
      ];

      final latest = latestAttendanceRecordPerWorker(records.reversed.toList());

      expect(latest, hasLength(1));
      expect(latest.single['status'], 'Present');
    });

    test('keeps the latest worker status in every month for This Year', () {
      final now = DateTime.now();
      final records = <Map<String, dynamic>>[
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(now.year, 1, 10),
          'status': 'Present',
        },
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(now.year, 2, 10),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(now.year, 8, 9),
          'status': 'Absent',
        },
        {
          'workerId': 'worker-1',
          'attendanceDate': DateTime(now.year, 8, 10),
          'status': 'Present',
        },
      ];

      final latest = latestAttendanceRecordPerWorker(
        records,
        period: 'This Year',
        now: now,
      );

      expect(latest, hasLength(3));
      expect(
        latest.singleWhere(
          (record) => (record['attendanceDate'] as DateTime).month == 8,
        )['status'],
        'Present',
      );
    });
  });
}
