import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/widgets/session_timeout_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({
    required Future<bool> Function() isBiometricAvailable,
    required Future<bool> Function() authenticate,
    required DateTime Function() clock,
    bool isSessionActive = true,
    Future<void> Function()? onSignInAgain,
  }) {
    return MaterialApp(
      home: SessionTimeoutGate(
        timeout: const Duration(seconds: 1),
        isSessionActive: () => isSessionActive,
        isBiometricAvailable: isBiometricAvailable,
        loadBiometricName: () async => 'Face ID',
        authenticate: authenticate,
        clock: clock,
        onSignInAgain: onSignInAgain ?? () async {},
        child: const Scaffold(body: Center(child: Text('Dashboard'))),
      ),
    );
  }

  testWidgets('inactive guest session never opens the timeout lock', (
    tester,
  ) async {
    var now = DateTime(2026);
    await tester.pumpWidget(
      buildTestApp(
        isSessionActive: false,
        isBiometricAvailable: () async => false,
        authenticate: () async => false,
        clock: () => now,
      ),
    );

    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('session_locked_title'), findsNothing);
  });

  testWidgets('pointer activity restarts the inactivity countdown', (
    tester,
  ) async {
    var now = DateTime(2026);
    await tester.pumpWidget(
      buildTestApp(
        isBiometricAvailable: () async => false,
        authenticate: () async => false,
        clock: () => now,
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 900));
    now = now.add(const Duration(milliseconds: 900));
    await tester.tap(find.text('Dashboard'));
    now = now.add(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('session_locked_title'), findsNothing);

    now = now.add(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('session_locked_title'), findsOneWidget);
  });

  testWidgets('offers sign-in when biometrics are unavailable', (tester) async {
    var signInAgainCalls = 0;
    var now = DateTime(2026);
    await tester.pumpWidget(
      buildTestApp(
        isBiometricAvailable: () async => false,
        authenticate: () async => false,
        clock: () => now,
        onSignInAgain: () async => signInAgainCalls++,
      ),
    );
    await tester.pump();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('session_locked_title'), findsOneWidget);
    expect(find.text('session_sign_in_again'), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);

    await tester.tap(find.text('session_sign_in_again'));
    await tester.pump();

    expect(signInAgainCalls, 1);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('keeps the lock cover visible until sign-in navigation renders', (
    tester,
  ) async {
    final signInCompleter = Completer<void>();
    var now = DateTime(2026);
    await tester.pumpWidget(
      buildTestApp(
        isBiometricAvailable: () async => false,
        authenticate: () async => false,
        clock: () => now,
        onSignInAgain: () => signInCompleter.future,
      ),
    );
    await tester.pump();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.text('session_sign_in_again'));
    await tester.pump();
    expect(find.text('session_locked_title'), findsOneWidget);

    signInCompleter.complete();
    await tester.pump();
    expect(find.text('session_locked_title'), findsOneWidget);

    await tester.pump();
    expect(find.text('session_locked_title'), findsNothing);
  });

  testWidgets('opens biometric verification after the lock screen renders', (
    tester,
  ) async {
    var authenticationCalls = 0;
    var now = DateTime(2026);
    await tester.pumpWidget(
      buildTestApp(
        isBiometricAvailable: () async => true,
        authenticate: () async {
          authenticationCalls++;
          return false;
        },
        clock: () => now,
      ),
    );
    await tester.pump();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    expect(authenticationCalls, 1);
    expect(find.text('session_locked_title'), findsOneWidget);
    expect(find.text('session_unlock_with_biometric'), findsOneWidget);
    expect(find.text('session_biometric_failed'), findsOneWidget);
  });
}
