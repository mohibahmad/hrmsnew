import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:window_manager/window_manager.dart';

import 'providers.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/biometric_service.dart';
import 'services/dummy_data.dart';
import 'services/error_reporter.dart';
import 'services/preferences_service.dart';
import 'utils/localization_helper.dart';
import 'utils/navigation_utils.dart';
import 'widgets/session_timeout_gate.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      _setupErrorHandling();

      try {
        await EasyLocalization.ensureInitialized();

        await initializeDateFormatting();

        await PreferencesService.initFromPrefs();

        if (PreferencesService.cachedIsGuest) {
          final cachedUrl = PreferencesService.cachedProfilePicUrl;
          if (cachedUrl != null && cachedUrl.trim().isNotEmpty) {
            AuthService.profilePicNotifier.value = cachedUrl;
          }

          final cachedStamp = PreferencesService.cachedCompanyStampUrl;
          if (cachedStamp != null && cachedStamp.trim().isNotEmpty) {
            AuthService.companyStampNotifier.value = cachedStamp;
          }
        }

        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );

        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: 100 * 1024 * 1024,
        );

        await DummyData.loadFromPrefs();

        await _initializeMacOSWindow();

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
            child: const ProviderScope(child: HRMSApp()),
          ),
        );
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'AppInitialization',
          fatal: true,
        );

        runApp(StartupErrorApp(error: error));
      }
    },
    (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'Zone', fatal: true);
    },
  );
}

void _setupErrorHandling() {
  final originalOnError = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    final errorMessage = details.exception.toString();

    final isKnownKeyboardAssertion =
        details.exception is AssertionError &&
        errorMessage.contains('!_pressedKeys.containsKey(event.physicalKey)');

    if (isKnownKeyboardAssertion) {
      if (kDebugMode) {
        debugPrint('Ignored keyboard assertion: $errorMessage');
      }
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

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorReporter.report(
      error,
      stackTrace,
      context: 'PlatformDispatcher',
      fatal: true,
    );

    return false;
  };
}

Future<void> _initializeMacOSWindow() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
    return;
  }

  try {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1440, 850),
      minimumSize: Size(1360, 800),
      center: true,
      title: 'HRMS',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (error, stackTrace) {
    ErrorReporter.report(
      error,
      stackTrace,
      context: 'WindowManager',
      fatal: false,
    );
  }
}

class HRMSApp extends ConsumerWidget {
  const HRMSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      title: 'HRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'SF Pro Display'),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const SplashScreen(),
      builder: (context, child) {
        return SessionTimeoutGate(
          isSessionActive: () {
            final user = ref.read(authServiceProvider).currentUser;
            return user != null && !user.isAnonymous;
          },
          isBiometricAvailable: BiometricService.isAvailable,
          loadBiometricName: BiometricService.getBiometricName,
          authenticate: () async {
            final biometricName = await BiometricService.getBiometricName();
            return BiometricService.authenticate(
              localizedReason: 'session_unlock_reason'.tr(
                namedArgs: {
                  'biometric': LocalizationHelper.localizeBiometricName(
                    biometricName,
                  ),
                },
              ),
            );
          },
          onSignInAgain: () async {
            final authService = ref.read(authServiceProvider);
            try {
              await authService.signOut(preserveBiometricLogin: true);
            } catch (error, stackTrace) {
              ErrorReporter.report(
                error,
                stackTrace,
                context: 'sessionTimeoutSignOut',
              );
            }
            _rootNavigatorKey.currentState?.pushAndRemoveUntil(
              noTransitionRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'App could not start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please restart the app and check your internet connection.',
                  textAlign: TextAlign.center,
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  SelectableText(error.toString(), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
