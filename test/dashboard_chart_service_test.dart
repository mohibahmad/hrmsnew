import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dashboard_chart_service.dart';

void main() {
  test('cancelled payroll is excluded from dashboard salary totals', () {
    final series = DashboardChartService.buildSeries(
      records: [
        {
          'status': 'Paid',
          'netSalary': 50000,
          'payPeriod': DateTime(2026, 7, 1),
        },
        {
          'status': 'Cancelled',
          'netSalary': 30000,
          'payPeriod': DateTime(2026, 7, 1),
        },
      ],
      valueOf: (record) => (record['netSalary'] as num).toDouble(),
      period: 'Month',
      now: DateTime(2026, 7, 10),
    );

    expect(series.total, 50000);
  });

  test('yearly series groups real values by calendar month', () {
    final series = DashboardChartService.buildSeries(
      records: [
        {'createdAt': DateTime(2026, 6, 10), 'amount': 100},
        {'createdAt': DateTime(2026, 7, 5), 'amount': 250},
      ],
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'Yearly',
      now: DateTime(2026, 7, 21),
    );

    expect(series.points, hasLength(12));
    expect(series.points[5].date.month, 6);
    expect(series.points[5].value, 100);
    expect(series.points[6].date.month, 7);
    expect(series.points[6].value, 250);
    expect(series.total, 350);
  });

  test('monthly series ends at the month-to-date total', () {
    final series = DashboardChartService.buildSeries(
      records: [
        {'createdAt': DateTime(2026, 7, 2), 'amount': 100},
        {'createdAt': DateTime(2026, 7, 10), 'amount': 50},
      ],
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'Month',
      now: DateTime(2026, 7, 21),
    );

    expect(series.points, hasLength(21));
    expect(series.points[1].value, 100);
    expect(series.points[9].value, 150);
    expect(series.points.last.value, 150);
    expect(series.total, 150);
  });

  test('expense date strings are placed in the correct month', () {
    final series = DashboardChartService.buildSeries(
      records: [
        {'date': '10/06/2026', 'createdAt': DateTime(2026, 7, 1), 'amount': 75},
      ],
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: '6 Month',
      dateOf: DashboardChartService.expenseRecordDate,
      now: DateTime(2026, 7, 21),
    );

    final june = series.points.singleWhere((point) => point.date.month == 6);
    expect(june.value, 75);
  });

  test('dummy salary graph has the exact normalized Expenses shape', () {
    final expenses = [
      {'date': '05/01/2026', 'amount': 100.0},
      {'date': '10/02/2026', 'amount': 250.0},
      {'date': '15/03/2026', 'amount': 50.0},
      {'date': '07/07/2026', 'amount': 200.0},
      {'date': '15/07/2026', 'amount': 400.0},
    ];
    final expenseSeries = DashboardChartService.buildSeries(
      records: expenses,
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'Yearly',
      dateOf: DashboardChartService.expenseRecordDate,
      now: DateTime(2026, 7, 21),
    );
    final salarySeries = DashboardChartService.buildDummySalarySeries(
      expenses: expenses,
      totalSalary: 250000,
      period: 'Yearly',
      now: DateTime(2026, 7, 21),
    );

    expect(salarySeries.points, hasLength(expenseSeries.points.length));
    for (var index = 0; index < expenseSeries.points.length; index++) {
      final expenseRatio =
          expenseSeries.points[index].value / expenseSeries.total;
      final salaryRatio = salarySeries.points[index].value / salarySeries.total;
      expect(salaryRatio, closeTo(expenseRatio, 0.0000001));
    }
    expect(salarySeries.total, closeTo(250000, 0.000001));
  });

  test('guest salary uses Expenses shape only for Yearly', () {
    final salaryRecords = [
      {'payrollDate': '15/07/2026', 'netSalary': 1000.0},
    ];
    final expenses = [
      {'date': '05/01/2026', 'amount': 100.0},
      {'date': '10/02/2026', 'amount': 200.0},
    ];

    final yearly = DashboardChartService.buildGuestSalarySeries(
      salaryRecords: salaryRecords,
      expenses: expenses,
      totalSalary: 1000,
      period: 'Yearly',
      now: DateTime(2026, 7, 21),
    );
    final monthly = DashboardChartService.buildGuestSalarySeries(
      salaryRecords: salaryRecords,
      expenses: expenses,
      totalSalary: 1000,
      period: 'Month',
      now: DateTime(2026, 7, 21),
    );

    expect(yearly.points[0].value, closeTo(1000 / 3, 0.000001));
    expect(yearly.points[1].value, closeTo(2000 / 3, 0.000001));
    expect(yearly.points[6].value, 0);
    expect(monthly.points[13].value, 0);
    expect(monthly.points[14].value, 1000);
    expect(monthly.points.last.value, 1000);
  });

  test(
    'leave chart expands leave days and filters them by dropdown period',
    () {
      final records = [
        {
          'workerId': 'worker-1',
          'type': 'Sick Leave',
          'startDate': '28/07/2026',
          'endDate': '30/07/2026',
          'status': 'Assigned',
        },
        {
          'workerId': 'worker-2',
          'type': 'Casual Leave',
          'selectedDates': ['2026-06-15'],
          'status': 'Assigned',
        },
        {
          'workerId': 'worker-3',
          'type': 'Medical Leave',
          'selectedDates': ['2026-07-30'],
          'status': 'Cancelled',
        },
      ];

      final today = DashboardChartService.leaveDaysForPeriod(
        records: records,
        period: 'Today',
        now: DateTime(2026, 7, 30),
      );
      final week = DashboardChartService.leaveDaysForPeriod(
        records: records,
        period: 'Week',
        now: DateTime(2026, 7, 30),
      );
      final yearly = DashboardChartService.leaveDaysForPeriod(
        records: records,
        period: 'Yearly',
        now: DateTime(2026, 7, 30),
      );

      expect(today, hasLength(1));
      expect(week, hasLength(3));
      expect(yearly, hasLength(4));
      expect(yearly.where((day) => day['type'] == 'Medical Leave'), isEmpty);
    },
  );

  test('leave chart dedups same worker/date across mismatched identities', () {
    final workers = [
      {
        'id': 'worker-1',
        'workerId': 'worker-1',
        'email': 'jane@example.com',
        'name': 'Jane',
      },
      {
        'id': 'worker-2',
        'workerId': 'worker-2',
        'email': 'bob@example.com',
        'name': 'Bob',
      },
    ];
    final merged = DashboardChartService.mergedLeaveDaysForPeriod(
      timeOffRecords: [
        {
          'workerId': 'worker-1',
          'type': 'Sick Leave',
          'selectedDates': ['2026-07-30'],
          'status': 'Assigned',
        },
      ],
      attendanceRecords: [
        // Same worker as the time-off record, but identified by email only.
        {
          'email': 'jane@example.com',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Sick Leave',
        },
        // Different worker identified by name only.
        {
          'name': 'Bob',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Casual Leave',
        },
      ],
      period: 'Today',
      now: DateTime(2026, 7, 30),
      workers: workers,
    );

    // worker-1 appears once (time-off + attendance collapsed to one day),
    // worker-2 (attendance only) is a second day.
    expect(merged, hasLength(2));
    expect(merged.where((day) => day['type'] == 'Sick Leave'), hasLength(1));
    expect(merged.where((day) => day['type'] == 'Casual Leave'), hasLength(1));
  });

  test('leave chart keeps same-named workers separate (no name collapse)', () {
    final workers = [
      {
        'id': 'worker-1',
        'workerId': 'worker-1',
        'email': 'a@example.com',
        'name': 'Alex',
      },
      {
        'id': 'worker-2',
        'workerId': 'worker-2',
        'email': 'b@example.com',
        'name': 'Alex',
      },
    ];
    final merged = DashboardChartService.mergedLeaveDaysForPeriod(
      timeOffRecords: const [],
      attendanceRecords: [
        {
          'email': 'a@example.com',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Sick Leave',
        },
        {
          'email': 'b@example.com',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Casual Leave',
        },
      ],
      period: 'Today',
      now: DateTime(2026, 7, 30),
      workers: workers,
    );

    // Same name but different emails → both days must be kept.
    expect(merged, hasLength(2));
    expect(merged.where((day) => day['type'] == 'Sick Leave'), hasLength(1));
    expect(merged.where((day) => day['type'] == 'Casual Leave'), hasLength(1));
  });

  test('leave chart merges attendance-only leave types without duplicates', () {
    final merged = DashboardChartService.mergedLeaveDaysForPeriod(
      timeOffRecords: [
        {
          'workerId': 'worker-1',
          'type': 'Sick Leave',
          'selectedDates': ['2026-07-30'],
          'status': 'Assigned',
        },
      ],
      attendanceRecords: [
        {
          'workerId': 'worker-1',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Sick Leave',
        },
        {
          'workerId': 'worker-2',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'reason': 'Medical appointment',
        },
        {
          'workerId': 'guest-worker',
          'status': 'Leave',
          'attendanceDate': '2026-07-30',
          'type': 'Casual Leave',
          'excludeFromLeaveChart': true,
        },
      ],
      period: 'Today',
      now: DateTime(2026, 7, 30),
    );

    expect(merged, hasLength(2));
    expect(merged.where((day) => day['type'] == 'Sick Leave'), hasLength(1));
    expect(merged.where((day) => day['type'] == 'Medical Leave'), hasLength(1));
    expect(merged.where((day) => day['type'] == 'Casual Leave'), isEmpty);
  });
}
