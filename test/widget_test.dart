import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms/main.dart';

import 'firebase_mock.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('App launches splash screen', (WidgetTester tester) async {
    // Set simulator viewport size to match target desktop dimensions to prevent layout overflows
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [
          Locale('en'),
          Locale('es'),
          Locale('fr'),
          Locale('pt'),
          Locale('ru'),
        ],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: const HRMSApp(),
      ),
    );

    await tester.pump();

    // Verify the splash screen shows the HR SVG logo
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Human Resource Management System'), findsOneWidget);

    // Let the timer fire and transition complete so no timers are pending
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });
}