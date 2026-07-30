import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
import '../shared/auth_widgets.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  final bool _isAppleLoading = false;
  bool _isGuestLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _submitted = false;
  bool _googleEnabled = true;

  bool get _anyLoading =>
      _isLoading || _isGoogleLoading || _isAppleLoading || _isGuestLoading;

  late AuthService _authService;
  late FirestoreService _firestoreService;

  StreamSubscription? _googleSub;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);

    _googleSub?.cancel();
    _googleSub = FirebaseFirestore.instance
        .collection('social_hrms')
        .doc('google')
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          setState(() {
            _googleEnabled = doc.data()?['googleEnable'] ?? true;
          });
        });
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential != null && mounted) {
        if (await _firestoreService.isCurrentUserDeleted()) {
          await _authService.signOut();
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'account_deleted_contact'.tr(),
              isError: true,
            );
          }
          return;
        }
        if (!mounted) return;
        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'welcome_back'.tr(),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return;
      }
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'google_login_failed'.tr(),
          isError: true,
        );
      }
    } on FirebaseAuthException catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupGoogle');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'google_login_failed'.tr(),
          isError: true,
        );
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'signupGoogle');
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
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
          isError: false,
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'guest_login_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<void> _handleSignUp() async {
    _submitted = true;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();

      bool isDeleted = false;
      try {
        isDeleted = await _firestoreService.isEmailDeleted(email);
      } catch (_) {
        isDeleted = false;
      }

      if (isDeleted) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'account_deleted_contact'.tr(),
            isError: true,
          );
        }
        return;
      }

      final credential = await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final emailLocalPart = _emailController.text.trim().split('@')[0];
      try {
        await credential.user?.updateDisplayName(emailLocalPart);
      } catch (_) {}

      await _firestoreService.createUserProfile(
        username: emailLocalPart,
        email: _emailController.text.trim(),
        phone: '',
      );

      await _firestoreService.addNotification({
        'type': 'welcome',
        'title': 'notif_title_welcome'.tr(namedArgs: {'name': emailLocalPart}),
        'message': 'notif_msg_welcome'.tr(),
        'data': {'name': emailLocalPart},
      });

      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'notif_title_welcome'.tr(namedArgs: {'name': emailLocalPart}),
          message: 'notif_msg_welcome'.tr(),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'email_already_in_use'.tr();
      } else {
        switch (e.code) {
          case 'invalid-email':
            message = 'invalid_email_address'.tr();
            break;
          case 'weak-password':
            message = 'weak_password'.tr();
            break;
          case 'operation-not-allowed':
            message = 'email_accounts_not_enabled'.tr();
            break;
          case 'network-request-failed':
          case 'network-error':
          case 'unavailable':
            message = 'network_error'.tr();
            break;
          default:
            if (e.message != null &&
                e.message!.toLowerCase().contains('network')) {
              message = 'network_error'.tr();
            } else {
              message = 'signup_failed'.tr(
                namedArgs: {'code': e.code, 'message': e.message ?? ''},
              );
            }
        }
      }
      if (mounted) {
        FlashySnackBar.show(context, message: message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_occurred'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _buildCustomInputDecoration(
    String hint, {
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 14,
        fontFamily: 'SF Pro Display',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF0044C9), width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: isPassword
          ? IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey.shade400,
              ),
              onPressed: onToggleVisibility,
            )
          : null,
    );
  }

  Widget _buildFieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  List<Widget> _buildFormContent(BuildContext context) {
    return [
      Center(
        child: SvgPicture.asset(
          'assets/HR_dark.svg',
          height: 80,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 50),

      Text(
        'create_account'.tr(),
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          fontFamily: 'SF Pro Display',
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
          fontFamily: 'SF Pro Display',
          height: 1.0,
        ),
      ),
      const SizedBox(height: 24),

      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('email_label'.tr()),
            TextFormField(
              controller: _emailController,
              enabled: !_anyLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _buildCustomInputDecoration('email_hint'.tr()),
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return 'email_required'.tr();
                if (!RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(value.trim())) {
                  return 'email_invalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('password_label'.tr()),
            TextFormField(
              controller: _passwordController,
              enabled: !_anyLoading,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _buildCustomInputDecoration(
                'password_hint'.tr(),
                isPassword: true,
                obscureText: _obscurePassword,
                onToggleVisibility: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'password_enter'.tr();
                if (value.length < 6) return 'password_too_short'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('confirm_new_password'.tr()),
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_anyLoading,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {},
              style: const TextStyle(
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _buildCustomInputDecoration(
                'confirm_new_password_hint'.tr(),
                isPassword: true,
                obscureText: _obscureConfirmPassword,
                onToggleVisibility: () {
                  setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  );
                },
              ),
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
      ),
      const SizedBox(height: 24),

      SizedBox(
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFFFFF),
                    ),
                  ),
                )
              : Text(
                  'create_account'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFFFFF),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
        ),
      ),

      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'or'.tr(),
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
      ),
      const SizedBox(height: 16),

      if (_googleEnabled)
        buildSocialButton(
          context: context,
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

      if (_googleEnabled) const SizedBox(height: 12),

      buildSocialButton(
        context: context,
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
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'sign_in'.tr(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SF Pro Display',
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                    );
                  },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              if (isDesktop)
                Expanded(
                  flex: 11,
                  child: Container(
                    color: const Color(0xFF165CDB),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final panelWidth = constraints.maxWidth.clamp(
                          0.0,
                          880.0,
                        );
                        final scale = (panelWidth / 880.0).clamp(0.4, 1.0);
                        final mockupWidth = panelWidth + (520 * scale) - 90;

                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              top: 40,
                              left: 80,
                              right: 40,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'welcome_to_hrms'.tr(),

                                    style: TextStyle(
                                      fontSize: 63,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontFamily: 'SF Pro Display',
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  Text(
                                    'welcome_banner_subtitle'.tr(),
                                    style: TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                      fontFamily: 'SF Pro Display',
                                      height: 1.4,
                                      letterSpacing: 2.2,
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
                  ),
                ),

              Expanded(
                flex: 9,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 0,
                    ),
                    child: Transform.translate(
                      offset: const Offset(0, -16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: _buildFormContent(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            top: 40,
            right: 40,
            child: GestureDetector(
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
            ),
          ),
        ],
      ),
    );
  }
}
