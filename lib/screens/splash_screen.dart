import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _authService = context.read<AuthService>();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animationController.forward();

    _navigateWhenReady();
  }

  Future<void> _navigateWhenReady() async {
    final minimumSplash = Future<void>.delayed(const Duration(seconds: 2));

    final isGuest = await PreferencesService.isGuest();
    AuthService.isGuestUser = isGuest;

    User? user;

    try {
      user = await _authService.authStateChanges.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => _authService.currentUser,
      );
    } catch (_) {
      user = _authService.currentUser;
    }

    await minimumSplash;

    if (!mounted) return;

    final destination = user != null || isGuest
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
                      style: TextStyle(
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
