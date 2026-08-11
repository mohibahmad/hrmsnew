import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dashboard_chart_service.dart';

void main() {
  test('All Time dashboard series includes values across multiple years', () {
    final records = <Map<String, dynamic>>[
      {'date': DateTime(2023, 1, 10), 'amount': 100.0},
      {'date': DateTime(2025, 7, 1), 'amount': 250.0},
      {'date': DateTime(2026, 8, 10), 'amount': 50.0},
    ];

    final series = DashboardChartService.buildSeries(
      records: records,
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'All Time',
      dateOf: DashboardChartService.expenseRecordDate,
      now: DateTime(2026, 8, 11),
    );

    expect(series.points.map((point) => point.date), [
      DateTime(2023, 1, 1),
      DateTime(2025, 7, 1),
      DateTime(2026, 8, 1),
    ]);
    expect(series.total, 400.0);
  });

  test(
    'All Time dashboard series creates one point for one recorded month',
    () {
      final series = DashboardChartService.buildSeries(
        records: [
          {'date': DateTime(2026, 8, 10), 'amount': 5400.0},
        ],
        valueOf: (record) => (record['amount'] as num).toDouble(),
        period: 'All Time',
        dateOf: DashboardChartService.expenseRecordDate,
        now: DateTime(2026, 8, 11),
      );

      expect(series.points, hasLength(1));
      expect(series.points.single.date, DateTime(2026, 8, 1));
      expect(series.points.single.value, 5400.0);
      expect(series.total, 5400.0);
    },
  );

  test('dashboard aliases use their matching timeframe buckets', () {
    final records = <Map<String, dynamic>>[
      {'date': DateTime(2026, 8, 10), 'amount': 10.0},
    ];

    final week = DashboardChartService.buildSeries(
      records: records,
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'This Week',
      dateOf: DashboardChartService.expenseRecordDate,
      now: DateTime(2026, 8, 11),
    );
    final sixMonths = DashboardChartService.buildSeries(
      records: records,
      valueOf: (record) => (record['amount'] as num).toDouble(),
      period: 'Last 6 Months',
      dateOf: DashboardChartService.expenseRecordDate,
      now: DateTime(2026, 8, 11),
    );

    expect(week.points, hasLength(7));
    expect(week.total, 10.0);
    expect(sixMonths.points, hasLength(6));
    expect(sixMonths.total, 10.0);
  });
}
