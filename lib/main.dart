import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:window_manager/window_manager.dart';

import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/firebase_options.dart';
import 'package:hrms/screens/auth/splash_screen.dart';
import 'package:hrms/screens/auth/login_screen.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/biometric_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/services/payroll/salary_day_scheduler.dart';
import 'package:hrms/widgets/navigation/session_timeout_gate.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _setupErrorHandling();
      try {
        await _initializeApp();
        runApp(_buildAppWithLocalization());
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

Future<void> _initializeApp() async {
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();
  await PreferencesService.initFromPrefs();
  _loadCachedGuestImages();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024,
  );
  await DummyData.loadFromPrefs();
  await _initializeMacOSWindow();
  unawaited(preloadPersistedCompanyImages());
}

void _loadCachedGuestImages() {
  if (!PreferencesService.cachedIsGuest) return;

  final cachedUrl = PreferencesService.cachedProfilePicUrl;
  if (cachedUrl != null && cachedUrl.trim().isNotEmpty) {
    AuthService.profilePicNotifier.value = cachedUrl;
  }

  final cachedStamp = PreferencesService.cachedCompanyStampUrl;
  if (cachedStamp != null && cachedStamp.trim().isNotEmpty) {
    AuthService.companyStampNotifier.value = cachedStamp;
  }
}

Widget _buildAppWithLocalization() {
  return EasyLocalization(
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
      minimumSize: Size(1460, 800),
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
    final sessionSettings = ref.watch(sessionTimeoutSettingsProvider);

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'HRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        primaryColor: const Color(0xFF0044C9),
      ),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const SplashScreen(),
      builder: (context, child) {
        return SessionTimeoutGate(
          enabled: sessionSettings.enabled,
          timeout: Duration(minutes: sessionSettings.durationMinutes),
          isSessionActive: () => _isUserLoggedIn(ref),
          isBiometricAvailable: BiometricService.isAvailable,
          loadBiometricName: BiometricService.getBiometricName,
          authenticate: () => _authenticateWithBiometric(),
          onSignInAgain: () => _handleSignInAgain(ref),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  bool _isUserLoggedIn(WidgetRef ref) {
    final user =
        ref.read(authStateProvider).asData?.value ??
        ref.read(authServiceProvider).currentUser;
    return user != null && !user.isAnonymous;
  }

  Future<BiometricAuthResult> _authenticateWithBiometric() async {
    final biometricName = await BiometricService.getBiometricName();
    return BiometricService.authenticate(
      reason: 'session_unlock_reason'.tr(
        namedArgs: {
          'biometric': LocalizationHelper.localizeBiometricName(biometricName),
        },
      ),
    );
  }

  Future<void> _handleSignInAgain(WidgetRef ref) async {
    final authService = ref.read(authServiceProvider);
    try {
      await authService.signOut(preserveBiometricLogin: true);
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'sessionTimeoutSignOut');
    }
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      noTransitionRoute(builder: (_) => const LoginScreen()),
      (route) => false,
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
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Color(0xFFFF1014),
                ),
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
