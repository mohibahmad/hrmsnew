import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dashboard_chart_service.dart';

void main() {
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
}
