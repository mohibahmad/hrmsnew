import 'dart:async';
import '../../utils/ui_helpers.dart';
import '../../utils/auth_widgets.dart';
import '../../utils/helpers.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../riverpod_providers.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../shared/app_constants.dart';
import '../../utils/utils.dart';
import '../general/home_screen.dart';
import 'login_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final TapGestureRecognizer _signInRecognizer;

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isGuestLoading = false;
  bool _submitted = false;
  bool _googleEnabled = true;
  bool _initialized = false;

  late final AuthService _authService;
  late final FirestoreService _firestoreService;

  StreamSubscription? _googleSub;

  bool get _anyLoading => _isLoading || _isGoogleLoading || _isGuestLoading;

  @override
  void initState() {
    super.initState();
    _signInRecognizer = TapGestureRecognizer()..onTap = _openLogin;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestoreService = ref.read(firestoreServiceProvider);

    _googleSub = AuthService.googleEnabledStream().listen(
      (enabled) {
        if (!mounted) return;
        if (_googleEnabled != enabled) setState(() => _googleEnabled = enabled);
      },
      onError: (Object error, StackTrace stackTrace) {
        ErrorReporter.report(error, stackTrace, context: 'signupGoogleConfig');
      },
    );
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _signInRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _openLogin() {
    if (!mounted || _anyLoading) return;
    Navigator.of(
      context,
    ).pushReplacement(authTransitionRoute(builder: (_) => const LoginScreen()));
  }

  void _openHome() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(authTransitionRoute(builder: (_) => const HomeScreen()));
  }

  Future<void> _handleGoogleLogin() async {
    if (_anyLoading || !_googleEnabled) return;
    setState(() => _isGoogleLoading = true);

    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential == null || !mounted) return;

      if (await _firestoreService.isCurrentUserDeleted()) {
        await _authService.signOut();
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'account_deleted_contact'.tr(),
            isError: true,
          );
        return;
      }

      final profile = await _firestoreService.getUserProfile();
      if (profile == null) {
        await _authService.signOut();
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'user_not_found'.tr(),
            isError: true,
          );
        return;
      }

      if (!mounted) return;
      FlashySnackBar.show(
        context,
        title: 'success'.tr(),
        message: 'welcome_back'.tr(),
      );
      _openHome();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted)
        return;
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'google_login_failed'.tr(),
          isError: true,
        );
    } on FirebaseAuthException catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupGoogle');
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'google_login_failed'.tr(),
          isError: true,
        );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupGoogle');
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isGuestLoading = true);
    try {
      await _authService.signInAnonymously();
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'continuing_as_guest'.tr(),
        );
        _openHome();
      }
    } catch (_) {
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'guest_login_failed'.tr(),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<bool> _cleanupIncompleteSignup(User? user) async {
    if (user == null) return false;
    try {
      await user.delete();
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupAuthCleanup');
      try {
        await _authService.signOut();
      } catch (signOutError, signOutStack) {
        ErrorReporter.report(
          signOutError,
          signOutStack,
          context: 'signupAuthCleanupSignOut',
        );
      }
      return false;
    }
  }

  Future<void> _handleSignUp() async {
    if (_anyLoading) return;
    if (!_submitted) setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();

      bool isDeleted;
      try {
        isDeleted = await _firestoreService.isEmailDeleted(email);
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'signupDeletedEmailCheck');
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'network_error'.tr(),
            isError: true,
          );
        return;
      }

      if (isDeleted) {
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'account_deleted_contact'.tr(),
            isError: true,
          );
        return;
      }

      final credential = await _authService.signUp(
        email: email,
        password: _passwordController.text,
      );
      final emailLocalPart = Validators.nameFromEmail(email);

      try {
        await credential.user?.updateDisplayName(emailLocalPart);
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'signupDisplayName');
      }

      try {
        await _firestoreService.createUserProfile(
          username: emailLocalPart,
          email: email,
          phone: '',
        );
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'signupCreateProfile');
        final deleted = await _cleanupIncompleteSignup(credential.user);
        if (!deleted && mounted) {
          FlashySnackBar.show(
            context,
            message: 'signup_recovery_required'.tr(),
            isError: true,
          );
          return;
        }
        rethrow;
      }

      try {
        await _firestoreService.addNotification({
          'type': 'welcome',
          'title': 'notif_title_welcome'.tr(
            namedArgs: {'name': emailLocalPart},
          ),
          'message': 'notif_msg_welcome'.tr(),
          'data': {'name': emailLocalPart},
        });
      } catch (e, st) {
        ErrorReporter.report(e, st, context: 'signupWelcomeNotification');
      }

      if (mounted) {
        try {
          await offerBiometricLogin(
            context: context,
            email: email,
            password: _passwordController.text,
          );
        } catch (e, st) {
          ErrorReporter.report(e, st, context: 'signupBiometricOffer');
        }
      }

      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'notif_title_welcome'.tr(namedArgs: {'name': emailLocalPart}),
          message: 'notif_msg_welcome'.tr(),
        );
        _openHome();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted)
        FlashySnackBar.show(
          context,
          message: _firebaseSignupError(e),
          isError: true,
        );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupEmail');
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _firebaseSignupError(FirebaseAuthException e) {
    if (e.code == 'email-already-in-use') return 'email_already_in_use'.tr();

    return switch (e.code) {
      'invalid-email' => 'invalid_email_address'.tr(),
      'weak-password' => 'weak_password'.tr(),
      'operation-not-allowed' => 'email_accounts_not_enabled'.tr(),
      'too-many-requests' => 'too_many_requests'.tr(),
      'network-request-failed' ||
      'network-error' ||
      'unavailable' => 'network_error'.tr(),
      _ =>
        (e.message?.toLowerCase().contains('network') ?? false)
            ? 'network_error'.tr()
            : 'signup_failed'.tr(
                namedArgs: {'code': e.code, 'message': e.message ?? ''},
              ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              if (isDesktop) Expanded(flex: 11, child: _buildDesktopPanel()),
              Expanded(flex: 9, child: _buildFormPanel()),
            ],
          ),
          Positioned(top: 40, right: 40, child: _buildLanguageButton()),
        ],
      ),
    );
  }

  Widget _buildDesktopPanel() {
    return Container(
      color: const Color(0xFF165CDB),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth.clamp(0.0, 880.0);
          final scale = (panelWidth / 880.0).clamp(0.4, 1.0);
          final mockupWidth = panelWidth + (520 * scale) - 90;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: 50,
                left: 100,
                right: 40,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'welcome_to_hrms'.tr(),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        fontFamily: 'SF Pro Display',
                        height: 0.9,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'welcome_banner_subtitle'.tr(),
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        fontFamily: 'SF Pro Display',
                        height: 1.2,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 380 * scale,
                left: -520 * scale,
                child: Transform.rotate(
                  angle: -0.18,
                  child: Container(
                    width: mockupWidth,
                    height: 800 * scale,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border(
                        left: BorderSide(
                          color: const Color(0xFF000000),
                          width: 20 * scale,
                        ),
                        right: BorderSide(
                          color: const Color(0xFF000000),
                          width: 20 * scale,
                        ),
                        bottom: BorderSide(
                          color: const Color(0xFF000000),
                          width: 20 * scale,
                        ),
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Colors.white,
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 30,
                          offset: const Offset(10, 9),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/dashboard_mockup.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topLeft,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
        child: Transform.translate(
          offset: const Offset(0, -16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Image.asset(
                    'assets/app_icon.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'create_account'.tr(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'signup_subtitle'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSignupForm(),
                const SizedBox(height: 24),
                _buildSignupButton(),
                const SizedBox(height: 24),
                _buildDivider(),
                const SizedBox(height: 16),
                if (_googleEnabled) ...[
                  buildSocialButton(
                    text: 'continue_with_google'.tr(),
                    icon: SvgPicture.asset(
                      'assets/google_icon.svg',
                      width: 18,
                      height: 18,
                    ),
                    isLoading: _isGoogleLoading,
                    onPressed: _anyLoading ? null : _handleGoogleLogin,
                    backgroundColor: Colors.white,
                    textColor: const Color(0xFF000000),
                  ),
                  const SizedBox(height: 12),
                ],
                buildSocialButton(
                  text: 'continue_as_guest'.tr(),
                  icon: SvgPicture.asset(
                    'assets/guest_icon.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF0044C9),
                      BlendMode.srcIn,
                    ),
                  ),
                  isLoading: _isGuestLoading,
                  onPressed: _anyLoading ? null : _handleGuestLogin,
                  backgroundColor: Colors.white,
                  textColor: const Color(0xFF0044C9),
                  border: BorderSide(
                    color: const Color(0xFF0044C9).withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: RichText(
                    text: TextSpan(
                      text: 'already_have_account'.tr(),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: 'sign_in'.tr(),
                          style: const TextStyle(
                            color: Color(0xFFFF1014),
                            fontWeight: FontWeight.w500,
                          ),
                          recognizer: _signInRecognizer,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthTextField(
            controller: _emailController,
            label: 'email_label'.tr(),
            hint: 'email_hint'.tr(),
            enabled: !_anyLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty)
                return 'email_required'.tr();
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim()))
                return 'email_invalid'.tr();
              return null;
            },
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _passwordController,
            label: 'password_label'.tr(),
            hint: 'password_hint'.tr(),
            isPassword: true,
            enabled: !_anyLoading,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) return 'password_enter'.tr();
              if (value.length < 6) return 'password_too_short'.tr();
              return null;
            },
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _confirmPasswordController,
            label: 'confirm_password'.tr(),
            hint: 'confirm_password_hint'.tr(),
            isPassword: true,
            enabled: !_anyLoading,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (!_anyLoading) _handleSignUp();
            },
            validator: (value) {
              if (value == null || value.isEmpty)
                return 'confirm_password_required'.tr();
              if (value != _passwordController.text)
                return 'passwords_do_not_match'.tr();
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignupButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _anyLoading ? null : _handleSignUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0044C9),
          foregroundColor: const Color(0xFFFFFFFF),
          disabledBackgroundColor: const Color(0xFF0044C9).withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFFFFF)),
                ),
              )
            : Text(
                'create_account'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFFFFF),
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or'.tr(),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  Widget _buildLanguageButton() {
    return GestureDetector(
      onTap: () => showLanguageModal(context),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            'assets/langauge_icon.png',
            width: 24,
            height: 24,
            color: const Color(0xFF0044C9),
          ),
        ),
      ),
    );
  }
}
