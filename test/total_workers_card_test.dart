import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/dashboard/rounded_donut_chart.dart';
import 'package:hrms/widgets/dashboard/total_workers_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('French worker card keeps chart and legends separated', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      EasyLocalization(
        key: const ValueKey('french-workers-card'),
        saveLocale: false,
        supportedLocales: const [Locale('en'), Locale('fr')],
        path: 'assets/translations',
        startLocale: const Locale('fr'),
        fallbackLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 220,
                  child: TotalWorkersCard(
                    count: 8,
                    maleCount: 4,
                    femaleCount: 3,
                    otherCount: 1,
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
    expect(find.text('Total des travailleurs'), findsOneWidget);
    expect(find.text('Homme'), findsOneWidget);
    expect(find.text('Femme'), findsOneWidget);
    expect(find.text('Autre'), findsOneWidget);
    expect(find.text('Sexe'), findsOneWidget);

    final chartRect = tester.getRect(find.byType(RoundedDonutChart));
    final maleLegendRect = tester.getRect(find.text('Homme'));
    final titleRect = tester.getRect(find.text('Total des travailleurs'));

    expect(chartRect.right, lessThanOrEqualTo(maleLegendRect.left));
    expect(titleRect.bottom, lessThanOrEqualTo(chartRect.top));
  });

  testWidgets('wide worker card keeps chart details compact and centered', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      EasyLocalization(
        key: const ValueKey('wide-workers-card'),
        saveLocale: false,
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 220,
                  child: TotalWorkersCard(
                    count: 8,
                    maleCount: 4,
                    femaleCount: 3,
                    otherCount: 1,
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
    expect(find.text('Gender'), findsOneWidget);
    final chartRect = tester.getRect(find.byType(RoundedDonutChart));
    final lastPercentRect = tester.getRect(find.text('13%'));
    final cardRect = tester.getRect(find.byType(Card));
    final groupCenter = (chartRect.left + lastPercentRect.right) / 2;

    expect(lastPercentRect.right - chartRect.left, lessThanOrEqualTo(320));
    expect(groupCenter, closeTo(cardRect.center.dx, 20));
  });
}
