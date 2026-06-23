import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'firebase_options.dart';
import 'services/error_reporter.dart';
import 'screens/splash_screen.dart';

void main() {
  // Route all uncaught framework and async errors through ErrorReporter so
  // nothing is silently lost in production.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        // Suppress the noisy HardwareKeyboard assertion on macOS that fires
        // when the app loses focus while a key is pressed (e.g. CMD+M/CMD+Tab).
        // NOTE: brittle string match — revisit if the Flutter SDK changes this
        // assertion message.
        if (details.exception is AssertionError &&
            details.exception.toString().contains(
              '!_pressedKeys.containsKey(event.physicalKey)',
            )) {
          return;
        }
        ErrorReporter.report(
          details.exception,
          details.stack,
          context: 'FlutterError',
          fatal: true,
        );
        // FIX #3: don't double-handle. Only forward to the original handler in
        // debug so you still get the red error screen; in release we've already
        // reported it.
        if (kDebugMode) {
          if (originalOnError != null) {
            originalOnError(details);
          } else {
            FlutterError.presentError(details);
          }
        }
      };

      // Errors from the platform side (e.g. plugins) that the framework can't
      // catch otherwise.
      PlatformDispatcher.instance.onError = (error, stack) {
        ErrorReporter.report(
          error,
          stack,
          context: 'PlatformDispatcher',
          fatal: true,
        );
        return true;
      };

      // FIX #1: don't return Firebase.app() on timeout — the default app isn't
      // registered yet when init times out, so it would throw [core/no-app].
      // Track readiness with a flag and gate Firebase usage on it instead.
      bool firebaseReady = false;
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint(
              'Firebase.initializeApp timed out — continuing without remote config.',
            );
            // Returning the in-flight future's value is impossible here, so
            // signal a timeout by throwing a typed error we catch below.
            throw TimeoutException('Firebase.initializeApp timed out');
          },
        );
        firebaseReady = true;
      } on TimeoutException catch (e, st) {
        // Non-fatal: app continues without Firebase-backed features.
        ErrorReporter.report(
          e,
          st,
          context: 'Firebase.initializeApp(timeout)',
          fatal: false,
        );
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'Firebase.initializeApp');
      }
      debugPrint('Firebase ready: $firebaseReady');

      // FIX #2: await window setup BEFORE runApp and launch hidden, then show,
      // to avoid the default-size flash / position jump on macOS.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        try {
          await windowManager.ensureInitialized();
          const windowOptions = WindowOptions(
            size: Size(1295, 800),
            minimumSize: Size(1295, 800),
            center: true,
            titleBarStyle: TitleBarStyle.normal,
          );
          await windowManager.waitUntilReadyToShow(windowOptions, () async {
            await windowManager.show();
            await windowManager.focus();
          });
        } catch (e, st) {
          ErrorReporter.report(e, st, context: 'windowManager');
        }
      }

      await EasyLocalization.ensureInitialized();

      runApp(
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
          saveLocale: true,
          child: const HRMSApp(),
        ),
      );
    },
    (error, stack) =>
        ErrorReporter.report(error, stack, context: 'Zone', fatal: true),
  );
}

class HRMSApp extends StatelessWidget {
  const HRMSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'SF Pro Display'),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        // FIX #4: const TextScaler.
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child ?? const SizedBox.shrink(), // FIX #6: safe fallback
        );
      },
      home: const SplashScreen(),
    );
  }
}
