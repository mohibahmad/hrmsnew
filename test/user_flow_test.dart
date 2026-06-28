import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms/main.dart';
import 'package:hrms/screens/login_screen.dart';
import 'package:hrms/screens/home_screen.dart';
import 'package:hrms/services/firestore_service.dart';
import 'package:flutter/services.dart';
import 'firebase_mock.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    FirestoreService.isTesting = false;

    final channels = [
      'plugins.flutter.io/firebase_auth',
      'plugins.flutter.io/firebase_auth_macos',
      'plugins.flutter.io/firebase_auth_ios',
      'plugins.flutter.io/firebase_auth_android',
    ];
    for (var name in channels) {
      final channel = MethodChannel(name);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        print('INTERCEPTED ON $name: ${methodCall.method}');
        return {
          'app': '[DEFAULT]',
          'user': {
            'uid': 'guest_uid',
            'isAnonymous': true,
            'isEmailVerified': false,
            'displayName': 'Guest User',
          }
        };
      });
    }

    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('User flow: splash screen redirects to login and enters guest mode',
      (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };

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

    // 1. Splash screen loads
    await tester.pump();
    expect(find.text('Human Resource Management System'), findsOneWidget);

    // 2. Allow splash screen timer to fire and transition to Login Screen
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // 3. Verify we are on the login screen
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);

    FirestoreService.isTesting = true;

    // 4. Tap the "Continue as Guest" button
    await tester.tap(find.text('Continue as Guest'));
    
    // Pump frames to let the login process complete, transition to HomeScreen,
    // and let the 4-second snackbar timer dismiss itself completely.
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 5. Verify we transitioned to HomeScreen dashboard portal
    expect(find.byType(HomeScreen), findsOneWidget);

    FlutterError.onError = originalOnError;
  });
}
