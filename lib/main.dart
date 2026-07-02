import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'firebase_options.dart';
import 'services/dummy_data.dart';
import 'services/error_reporter.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/preferences_service.dart';
import 'screens/splash_screen.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await PreferencesService.initFromPrefs();

      final cachedUrl = PreferencesService.cachedProfilePicUrl;
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        AuthService.profilePicNotifier.value = cachedUrl;
      }

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
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
        if (kDebugMode) {
          if (originalOnError != null) {
            originalOnError(details);
          } else {
            FlutterError.presentError(details);
          }
        }
      };

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
        );

        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );

        debugPrint('🔥 Firebase initialized successfully');
      } catch (e) {
        debugPrint('🔥 Firebase initialization FAILED: $e');

        rethrow;
      }

      DummyData.loadFromPrefs();

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
          child: MultiProvider(
            providers: [
              Provider<FirestoreService>(create: (_) => FirestoreService()),
              Provider<AuthService>(create: (_) => AuthService()),
            ],
            child: const HRMSApp(),
          ),
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
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}
