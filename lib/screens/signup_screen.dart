import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
import '../shared/auth_widgets.dart';
import '../shared/auth_utils.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isGuestLoading = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _googleEnabled = true;

  bool get _anyLoading =>
      _isLoading || _isGoogleLoading || _isAppleLoading || _isGuestLoading;

  final AuthService _authService = AuthService();

  StreamSubscription? _googleSub;

  @override
  void initState() {
    super.initState();
    _googleSub = FirebaseFirestore.instance
        .collection('social_hrms')
        .doc('google')
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _googleEnabled = doc.data()?['googleEnable'] == true;
        });
      } else if (mounted) {
        setState(() {
          _googleEnabled = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential != null && mounted) {
        if (await handleDeletedAccountIfNeeded(context, _authService)) return;
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

  Future<void> _handleAppleLogin() async {
    setState(() {
      _isAppleLoading = true;
    });

    try {
      final userCredential = await _authService.signInWithApple();
      if (userCredential != null && mounted) {
        if (await handleDeletedAccountIfNeeded(context, _authService)) return;
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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'popup-closed-by-user') {
        return;
      }
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'apple_login_failed'.tr(),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'apple_login_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAppleLoading = false);
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
      final isDeleted = await FirestoreService().isEmailDeleted(email);
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

      // updateDisplayName is best-effort — don't let it block profile creation
      try {
        await credential.user?.updateDisplayName(
          _usernameController.text.trim(),
        );
      } catch (_) {}

      await FirestoreService().createUserProfile(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: "",
      );

      final userName = _usernameController.text.trim();
      await FirestoreService().addNotification({
        'type': 'welcome',
        'title': 'notif_title_welcome'.tr(namedArgs: {'name': userName}),
        'message': 'notif_msg_welcome'.tr(),
        'data': {'name': userName},
      });

      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'Welcome $userName! 🎉',
          message:
              'Your HRMS account has been created successfully. Welcome aboard!',
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

  List<Widget> _buildFormContent(BuildContext context) {
    return [
      Center(
        child: SvgPicture.asset(
          'assets/HR_dark.svg',
          height: 76,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 24),

      Text(
        'create_account'.tr(),
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFF000000),
          fontFamily: 'SF Pro Display',
          height: 1.0,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'signup_subtitle'.tr(),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF000000),
          fontFamily: 'SF Pro Display',
          height: 1.0,
        ),
      ),
      const SizedBox(height: 16),

      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputLabel(label: 'username_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              enabled: !_anyLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: inputDecoration('username_hint'.tr()),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'username_required'.tr();
                }
                if (value.trim().length < 2) {
                  return 'username_too_short'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            InputLabel(label: 'email_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              enabled: !_anyLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: inputDecoration('email_hint'.tr()),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'email_required'.tr();
                }
                if (!RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(value.trim())) {
                  return 'email_invalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            InputLabel(label: 'password_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              enabled: !_anyLoading,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {},
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: inputDecoration(
                'password_hint'.tr(),
                isPassword: true,
                obscureText: _obscurePassword,
                onToggleVisibility: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'password_enter'.tr();
                }
                if (value.length < 6) {
                  return 'password_too_short'.tr();
                }
                return null;
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _anyLoading ? null : _handleSignUp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0044C9),
            foregroundColor: Color(0xFFFFFFFF),
            disabledBackgroundColor: const Color(
              0xFF0044C9,
            ).withValues(alpha: 0.6),
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFFFFF),
                    fontFamily: 'SF Pro Display',
                    height: 1.0,
                  ),
                ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
      const SizedBox(height: 12),

      // Continue with Google Button
      if (_googleEnabled)
        buildSocialButton(
          context: context,
          text: 'continue_with_google'.tr(),
          icon: SvgPicture.asset('assets/google_icon.svg', width: 16, height: 16),
          isLoading: _isGoogleLoading,
          onPressed: _anyLoading ? null : _handleGoogleLogin,
          backgroundColor: Colors.white,
          textColor: const Color(0xFF000000),
        ),
      if (_googleEnabled)
        const SizedBox(height: 8),

      // Continue with Apple Button
      // buildSocialButton(
      //   context: context,
      //   text: 'continue_with_apple'.tr(),
      //   icon: SvgPicture.asset(
      //     'assets/apple_icon.svg',
      //     width: 16,
      //     height: 16,
      //     colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      //   ),
      //   isLoading: _isAppleLoading,
      //   onPressed: _anyLoading ? null : _handleAppleLogin,
      //   backgroundColor: const Color(0xFF0F172A),
      //   textColor: Colors.white,
      //   border: const BorderSide(color: Color(0xFF0F172A)),
      // ),
      const SizedBox(height: 8),

      // Continue as Guest Button
      buildSocialButton(
        context: context,
        text: 'continue_as_guest'.tr(),
        icon: SvgPicture.asset(
          'assets/guest_icon.svg',
          width: 16,
          height: 16,
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
          color: const Color(0xFF0044C9).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      const SizedBox(height: 24),

      Center(
        child: RichText(
          text: TextSpan(
            text: 'already_have_account'.tr(),
            style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: 13,
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'sign_in'.tr(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cardDecoration = BoxDecoration(
      color: Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(40),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/auth_bg.png', fit: BoxFit.cover),

          Positioned(
            top: 50,
            right: 40,
            child: GestureDetector(
              onTap: () => showLanguageModal(context),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/langauge_icon.png',
                    width: 28,
                    height: 28,
                    color: const Color(0xFF0247C4),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: cardDecoration,
                        child: SingleChildScrollView(
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
              ),
              const Expanded(flex: 6, child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }
}
