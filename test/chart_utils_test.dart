import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/utils/chart_utils.dart';

void main() {
  group('attendanceRecordsForPeriod', () {
    final now = DateTime(2026, 8, 11, 15);
    final records = <Map<String, dynamic>>[
      {
        'id': 'legacy-record-without-worker-link',
        'name': 'Ali',
        'attendanceDate': DateTime(2026, 8, 11, 9),
        'status': 'Absent',
      },
      {
        'workerId': 'worker-2',
        'attendanceDate': DateTime(2026, 8, 10),
        'status': 'Present',
      },
      {
        'workerId': 'worker-3',
        'attendanceDate': DateTime(2026, 7, 31),
        'status': 'Absent',
      },
    ];

    test('Today includes an August 11 legacy absent record', () {
      final result = attendanceRecordsForPeriod(records, 'Today', now: now);

      expect(result, hasLength(1));
      expect(result.single['status'], 'Absent');
    });

    test('This Week includes all attendance records in the current week', () {
      final result = attendanceRecordsForPeriod(records, 'This Week', now: now);

      expect(result, hasLength(2));
    });
  });

  group('getChartData adaptive behavior', () {
    test('uses supplied attendance records instead of demo values', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': now, 'status': 'present'},
        {'attendanceDate': now, 'status': 'present'},
      ];

      final chart = getChartData('Today', docs, true, 'en_US');

      expect(chart.values.reduce((a, b) => a + b), 2);
    });

    test('uses the correct Firebase date bucket for each selected period', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': now, 'status': 'present'},
        {
          'attendanceDate': DateTime(now.year, now.month - 1, 1),
          'status': 'present',
        },
      ];

      final month = getChartData('This Month', docs, false, 'en_US');
      final sixMonths = getChartData('Last 6 Months', docs, false, 'en_US');
      final year = getChartData('This Year', docs, false, 'en_US');

      expect(month.values.reduce((a, b) => a + b), 1);
      expect(sixMonths.values.reduce((a, b) => a + b), 2);
      expect(year.values.reduce((a, b) => a + b), 2);
    });

    test('excludes records outside the selected period', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2025, 7, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 7, 15), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.isAdaptive, isFalse);
      expect(chart.labels.length, 12);
      expect(chart.values.length, 12);
      expect(chart.values.reduce((a, b) => a + b), 0);
      expect(chart.rangeStart, isNull);
      expect(chart.rangeEnd, isNull);
    });

    test('month period excludes records outside the current month', () {
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(2025, 2, 1), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 2, 10), 'status': 'present'},
        {'attendanceDate': DateTime(2025, 2, 20), 'status': 'present'},
      ];

      final chart = getChartData('This Month', docs, false, 'en_US');

      expect(chart.isAdaptive, isFalse);
      expect(chart.labels.length, 4);
      expect(chart.values.reduce((a, b) => a + b), 0);
    });

    test('counts every supplied attendance record in its selected bucket', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        for (int i = 0; i < 5; i++)
          {'attendanceDate': now, 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.isAdaptive, isFalse);
      expect(chart.values.reduce((a, b) => a + b), 5);
    });

    test('counts each current-year record in exactly one month bucket', () {
      final now = DateTime.now();
      final docs = <Map<String, dynamic>>[
        {'attendanceDate': DateTime(now.year, 1, 1), 'status': 'present'},
        {'attendanceDate': DateTime(now.year, 1, 4), 'status': 'present'},
        {'attendanceDate': DateTime(now.year, 7, 15), 'status': 'present'},
        {'attendanceDate': DateTime(now.year, 8, 10), 'status': 'present'},
      ];

      final chart = getChartData('This Year', docs, false, 'en_US');

      expect(chart.values.reduce((a, b) => a + b), 4);
      // The first two records are both in January.
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

    test(
      'keeps the latest worker status for duplicate records on each day',
      () {
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

        expect(latest, hasLength(4));
        expect(
          latest.singleWhere(
            (record) =>
                (record['attendanceDate'] as DateTime).month == 8 &&
                (record['attendanceDate'] as DateTime).day == 10,
          )['status'],
          'Present',
        );
      },
    );
  });
}
