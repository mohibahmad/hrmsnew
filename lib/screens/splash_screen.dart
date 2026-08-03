import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late AuthService _authService;
  late FirestoreService _firestoreService;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_navigationScheduled) return;
    _navigationScheduled = true;

    precacheImage(const AssetImage('assets/splashscreenbg.png'), context);
    _authService = context.read<AuthService>();
    _firestoreService = context.read<FirestoreService>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateWhenReady();
    });
  }

  Future<void> _navigateWhenReady() async {
    final minimumSplash = Future<void>.delayed(const Duration(seconds: 2));

    bool sessionLocked;
    try {
      sessionLocked = await PreferencesService.isSessionLocked().timeout(
        const Duration(seconds: 3),
      );
    } catch (e, st) {
      // Fail-closed: if lock status cannot be verified for an authenticated
      // (non-guest) session, assume the session is locked. Guest mode is
      // handled separately below.
      ErrorReporter.report(e, st, context: 'splashSessionLocked');
      sessionLocked = true;
    }

    bool isGuest;
    try {
      isGuest = await PreferencesService.isGuest().timeout(
        const Duration(seconds: 3),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashGuestStatus');
      isGuest = false;
    }

    User? user;
    try {
      user = await _authService.authStateChanges.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => _authService.currentUser,
      );
    } on TimeoutException catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashAuthTimeout');
      user = _authService.currentUser;
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'splashAuthState');
      user = null;
    }

    if (!isGuest && user != null && !user.isAnonymous) {
      try {
        final profile = await _firestoreService.getUserProfileOrThrow().timeout(
          const Duration(seconds: 8),
        );
        final isDeleted = profile?['isDeleted'] == true;
        if (isDeleted) {
          // Only sign out when the server explicitly confirmed the account
          // is deleted. This is a legitimate, confirmed terminal state.
          await _authService.signOut();
          user = null;
        } else if (profile == null) {
          // The server successfully confirmed the document does not exist.
          // Treat this as a genuine missing account and sign out.
          await _authService.signOut();
          user = null;
        }
      } catch (e, st) {
        // Network/timeout/permission errors are NOT a confirmed deleted or
        // missing account. Preserve the existing authenticated session and
        // continue to Home so the user can retry/offline.
        ErrorReporter.report(e, st, context: 'splashProfileValidation');
      }
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
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );

          final fadeAnimation = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.75, curve: Curves.easeIn),
          );

          return FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: slideAnimation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
                        fontFamily: 'SF Pro Display',
                        height: 1.0,
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
