import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/dashboard_chart_service.dart';
import 'package:hrms/widgets/dashboard/sparkline_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('tooltip stays anchored above the touched chart point', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      EasyLocalization(
        saveLocale: false,
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 220,
                  child: SparklineCard(
                    title: 'Expenses',
                    amount: r'$12,345',
                    rawValue: 12345,
                    points: [
                      DashboardChartPoint(
                        date: DateTime(2026, 7, 1),
                        value: 1000,
                      ),
                      DashboardChartPoint(
                        date: DateTime(2026, 7, 20),
                        value: 12345,
                      ),
                    ],
                    period: 'Month',
                    lineColor: const Color(0xFF0EA5E9),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final tooltip = chart.data.lineTouchData.touchTooltipData;
    expect(tooltip.fitInsideHorizontally, isTrue);
    expect(tooltip.fitInsideVertically, isFalse);
    expect(tooltip.maxContentWidth, lessThanOrEqualTo(180));
  });
}
