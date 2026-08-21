import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:hrms/riverpod_providers.dart';
import 'package:hrms/services/core/auth_service.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/screens/home/home_screen.dart';
import 'package:hrms/screens/auth/login_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestoreService;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_navigationScheduled) return;
    _navigationScheduled = true;

    precacheImage(const AssetImage('assets/splashscreenbg.png'), context);
    _authService = ref.read(authServiceProvider);
    _firestoreService = ref.read(firestoreServiceProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) => _navigateWhenReady());
  }

  Future<void> _navigateWhenReady() async {
    final minimumSplash = Future<void>.delayed(const Duration(milliseconds: 350));

    final results = await Future.wait([
      _getSessionLocked(),
      _getIsGuest(),
      _getUser(),
    ]);

    final sessionLocked = results[0] as bool;
    final isGuest = results[1] as bool;
    var user = results[2] as User?;

    if (!isGuest && user != null && !user.isAnonymous) {
      user = await _validateUserProfile(user);
    }

    await minimumSplash;

    if (!mounted) return;

    final destination = (user != null || isGuest) && (!sessionLocked || isGuest)
        ? const HomeScreen()
        : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnimation =
              Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );

          final fadeAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeIn,
          );

          return FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: slideAnimation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Future<bool> _getSessionLocked() async {
    try {
      return await PreferencesService.isSessionLocked().timeout(
        const Duration(milliseconds: 1500),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashSessionLocked');
      return true;
    }
  }

  Future<bool> _getIsGuest() async {
    try {
      return await PreferencesService.isGuest().timeout(
        const Duration(milliseconds: 1500),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashGuestStatus');
      return false;
    }
  }

  Future<User?> _getUser() async {
    final current = _authService.currentUser;
    if (current != null) return current;
    try {
      return await ref
          .read(authStateProvider.future)
          .timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () => _authService.currentUser,
          );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashAuthState');
      return _authService.currentUser;
    }
  }

  Future<User?> _validateUserProfile(User user) async {
    try {
      final profile = await _firestoreService.getUserProfileOrThrow().timeout(
        const Duration(milliseconds: 1500),
      );

      final isDeleted = profile?['isDeleted'] == true;
      if (isDeleted) {
        await _authService.signOut();
        return null;
      }

      return user;
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashProfileValidation');
      return user;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B64D3),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/splashscreenbg.png', fit: BoxFit.cover),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/HR.svg',
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 35),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'human_resource_management_system'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
