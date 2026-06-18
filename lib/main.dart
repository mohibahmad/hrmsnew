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
        if (originalOnError != null) {
          originalOnError(details);
        } else {
          FlutterError.presentError(details);
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

      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint(
              'Firebase.initializeApp timed out — continuing without remote config.',
            );
            return Firebase.app();
          },
        );
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'Firebase.initializeApp');
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        unawaited(() async {
          try {
            await windowManager.ensureInitialized();
            await windowManager.waitUntilReadyToShow().then((_) async {
              await windowManager.setMinimumSize(const Size(1280, 800));
              await windowManager.setSize(const Size(1280, 800));
              await windowManager.center();
              await windowManager.show();
              await windowManager.focus();
            });
          } catch (e, st) {
            ErrorReporter.report(e, st, context: 'windowManager');
          }
        }());
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
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
