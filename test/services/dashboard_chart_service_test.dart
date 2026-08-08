import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dashboard_chart_service.dart';

void main() {
  group('DashboardChartService.buildSeries', () {
    test('does not cap valid expense amounts at one billion', () {
      final now = DateTime(2026, 8, 8);
      final records = <Map<String, dynamic>>[
        {'date': now, 'amount': 98888888.0},
        {'date': now, 'amount': 2222333123.0},
        {'date': now, 'amount': 25000.0},
        {'date': now, 'amount': 25000.0},
        {'date': now, 'amount': 123123123123.0},
        {'date': now, 'amount': 25000.0},
      ];

      final series = DashboardChartService.buildSeries(
        records: records,
        valueOf: (record) => record['amount'] as double,
        dateOf: (record) => record['date'] as DateTime,
        period: 'Yearly',
        now: now,
      );

      expect(series.total, 125444420134.0);
      expect(series.points[7].value, 125444420134.0);
    });
  });
}
