import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
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
  bool _isGuestLoading = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _googleEnabled = true;

  bool get _anyLoading => _isLoading || _isGoogleLoading || _isGuestLoading;

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
          if (mounted) _showErrorSnackBar('account_deleted_contact'.tr());
          return;
        }
        if (!mounted) return;

        final profile = await _firestoreService.getUserProfile();
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
    setState(() {
      _submitted = true;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final enteredEmail = _emailController.text.trim().toLowerCase();
      await _authService.signIn(
        email: enteredEmail,
        password: _passwordController.text,
      );
      if (mounted) {
        if (await _firestoreService.isCurrentUserDeleted()) {
          await _authService.signOut();
          if (mounted) _showErrorSnackBar('account_deleted_contact'.tr());
          return;
        }

        final loggedInEmail = _authService.currentUser?.email
            ?.trim()
            .toLowerCase();
        if (loggedInEmail == null || loggedInEmail != enteredEmail) {
          await _authService.signOut();
          if (mounted) {
            _showErrorSnackBar(
              'login_failed'.tr(namedArgs: {'code': 'email-mismatch'}),
            );
          }
          return;
        }
        final profile = await _firestoreService.getUserProfile();
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
        'welcome_back'.tr(),
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
        'sign_in_subtitle'.tr(),
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_anyLoading) {
                  _handleLogin();
                }
              },
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
                  return 'password_required'.tr();
                if (value.length < 6) return 'password_too_short'.tr();
                return null;
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

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
        child: Text(
          'forget_password'.tr(),
          style: TextStyle(
            color: Color(0xFFFF0000),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),

      const SizedBox(height: 24),

      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _anyLoading ? null : _handleLogin,
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
                  'log_in'.tr(),
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
            text: 'dont_have_account'.tr(),
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'sign_up'.tr(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SF Pro Display',
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = _anyLoading
                      ? null
                      : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const SignupScreen(),
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
                        
                        final scale = (constraints.maxWidth / 880.0).clamp(
                          0.4,
                          1.2,
                        );

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
                                    style: const TextStyle(
                                      fontSize: 63,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontFamily: 'SF Pro Display',
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  Text(
                                    'welcome_banner_subtitle'.tr(),
                                    style: const TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                      fontFamily: 'SF Pro Display',
                                      height: 1.4,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Positioned(
                              top: 380 * scale,
                              left: -520 * scale,
                              right: 80,
                              child: Transform.rotate(
                                angle: -0.18,
                                child: Container(
                                  width: 1200 * scale,
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
