import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress the annoying HardwareKeyboard assertion on macOS that happens when
  // the app loses focus while a key is pressed (e.g. CMD+M or CMD+Tab).
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception is AssertionError) {
      final errorStr = details.exception.toString();
      if (errorStr.contains('!_pressedKeys.containsKey(event.physicalKey)')) {
        return; // Suppress this specific assertion
      }
    }
    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
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
    debugPrint('Firebase initialization failed: $e\n$st');
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
      } catch (e) {
        debugPrint('windowManager setup failed: $e');
      }
    }());
  }

  runApp(const HRMSApp());
}

class HRMSApp extends StatelessWidget {
  const HRMSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HRMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'SF Pro Display'),
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
