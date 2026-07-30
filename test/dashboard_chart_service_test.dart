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
}
