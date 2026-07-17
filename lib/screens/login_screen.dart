import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../services/error_reporter.dart';
import '../utils/snackbar_utils.dart';
import '../shared/auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
        if (await _handleDeletedAccountIfNeeded()) return;
        if (!mounted) return;

        final profile = await FirestoreService().getUserProfile();
        if (profile != null) {
          final pic = profile['profilePic'];
          if (pic != null && pic.isNotEmpty) {
            AuthService.profilePicNotifier.value = pic;
            await PreferencesService.setProfilePicUrl(pic);
          }
          final isPremium = profile['isPremium'] == true;
          await PreferencesService.setPremium(isPremium);
        }

        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'welcome_back'.tr(),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on GoogleSignInException catch (e, st) {
      ErrorReporter.report(e, st, context: 'googleSignIn');
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return;
      }
      if (mounted) {
        _showErrorSnackBar('google_login_failed'.tr());
      }
    } on FirebaseException catch (e, st) {
      ErrorReporter.report(e, st, context: 'googleSignIn');
      if (mounted) {
        _showErrorSnackBar('google_login_failed'.tr());
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'googleSignIn');
      if (mounted) {
        _showErrorSnackBar('unexpected_error'.tr());
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
        if (await _handleDeletedAccountIfNeeded()) return;
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
        _showErrorSnackBar('apple_login_failed'.tr());
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('apple_login_failed'.tr());
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
    } catch (_) {
      if (mounted) {
        _showErrorSnackBar('guest_login_failed'.tr());
      }
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    _submitted = true;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final enteredEmail = _emailController.text.trim().toLowerCase();
      await _authService.signIn(
        email: enteredEmail,
        password: _passwordController.text,
      );
      if (mounted) {
        final loggedInEmail =
            _authService.currentUser?.email?.trim().toLowerCase();
        if (loggedInEmail == null || loggedInEmail != enteredEmail) {
          await _authService.signOut();
          if (mounted) {
            _showErrorSnackBar('login_failed'.tr(namedArgs: {'code': 'email-mismatch'}));
          }
          return;
        }
        final profile = await FirestoreService().getUserProfile();
        if (profile == null) {
          await _authService.signOut();
          if (mounted) {
            _showErrorSnackBar('user_not_found'.tr());
          }
          return;
        }
        if (_authService.currentUser?.displayName == null ||
            _authService.currentUser!.displayName!.isEmpty) {
          final username = profile['username']?.toString();
          if (username != null && username.isNotEmpty) {
            await _authService.currentUser?.updateDisplayName(username);
          }
        }
        if (await _handleDeletedAccountIfNeeded()) return;
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
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'user_not_found'.tr();
          break;
        case 'wrong-password':
          message = 'wrong_password'.tr();
          break;
        case 'invalid-email':
          message = 'invalid_email'.tr();
          break;
        case 'user-disabled':
          message = 'user_disabled'.tr();
          break;
        case 'too-many-requests':
          message = 'too_many_requests'.tr();
          break;
        case 'network-request-failed':
        case 'network-error':
        case 'unavailable':
          message = 'network_error'.tr();
          break;
        case 'invalid-credential':
          message = 'invalid_credential'.tr();
          break;
        case 'operation-not-allowed':
          message = 'operation_not_allowed'.tr();
          break;
        default:
          if (e.message != null &&
              e.message!.toLowerCase().contains('network')) {
            message = 'network_error'.tr();
          } else {
            message = 'login_failed'.tr(namedArgs: {'code': e.code});
          }
      }
      if (mounted) {
        _showErrorSnackBar(message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('unexpected_error'.tr());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    FlashySnackBar.show(context, message: message, isError: true);
  }

  Future<bool> _handleDeletedAccountIfNeeded() async {
    final user = _authService.currentUser;
    if (user == null) return false;

    if (user.isAnonymous || user.uid.startsWith('guest_')) return false;

    final email = user.email;
    if (email == null || email.isEmpty) return false;

    try {
      final isDeleted = await FirestoreService().isCurrentUserDeleted();
      if (isDeleted) {
        await _authService.signOut();
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'account_deleted_contact'.tr(),
            isError: true,
          );
        }
        return true;
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'handleDeletedAccount');
    }

    return false;
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
      const SizedBox(height: 32),

      Text(
        'welcome_back'.tr(),
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
        'sign_in_subtitle'.tr(),
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
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
                    return 'email_invalid'.tr();
                  }
                  return null;
                },
            ),
            const SizedBox(height: 12),
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
                  return 'password_required'.tr();
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
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _anyLoading
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                );
              },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'forget_password'.tr(),
            style: TextStyle(
              color: Color(0xFFFF1014),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _anyLoading ? null : _handleLogin,
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
                  'log_in'.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFFFFF),
                    fontFamily: 'SF Pro Display',
                    height: 1.0,
                  ),
                ),
        ),
      ),
      const SizedBox(height: 16),
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
      const SizedBox(height: 16),

      // Continue with Google Button
      if (_googleEnabled)
        buildSocialButton(context: context,
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
      // buildSocialButton(context: context,
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
      buildSocialButton(context: context,
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
            text: 'dont_have_account'.tr(),
            style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: 13,
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'sign_up'.tr(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro Display',
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const SignupScreen(),
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
