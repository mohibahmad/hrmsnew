import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../services/biometric_service.dart';
import '../services/error_reporter.dart';
import '../utils/biometric_enrollment.dart';
import '../utils/localization_helper.dart';
import '../utils/ui_utils.dart';

import 'forgot_password_screen.dart';
import 'home_screen.dart';
import '../shared/auth_widgets.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isGuestLoading = false;
  bool _isBiometricLoading = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _googleEnabled = true;
  bool _initialized = false;
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  bool _autoBiometricTriggered = false;

  bool get _anyLoading =>
      _isLoading || _isGoogleLoading || _isGuestLoading || _isBiometricLoading;

  late AuthService _authService;
  late FirestoreService _firestoreService;
  late final TapGestureRecognizer _signUpRecognizer;

  StreamSubscription? _googleSub;

  void _openHome() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(noTransitionRoute(builder: (_) => const HomeScreen()));
  }

  Future<void> _handleMissingProfile(String? email) async {
    var isDeleted = false;
    final normalizedEmail = email?.trim().toLowerCase() ?? '';

    if (normalizedEmail.isNotEmpty) {
      try {
        isDeleted = await _firestoreService.isEmailDeleted(normalizedEmail);
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'loginMissingProfileDeletedEmailCheck',
        );
      }
    }

    await _authService.signOut();
    if (!mounted) return;

    if (isDeleted) {
      _showDeletedAccountSnackBar();
    } else {
      _showErrorSnackBar('user_not_found'.tr());
    }
  }

  @override
  void initState() {
    super.initState();
    _signUpRecognizer = TapGestureRecognizer();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    var available = false;
    var hasSaved = false;
    try {
      available = await BiometricService.isAvailable();
      final enabled = await PreferencesService.isBiometricEnabled();
      final email = await PreferencesService.getBiometricEmail();
      final password = await PreferencesService.getBiometricPassword();
      hasSaved = enabled && email != null && password != null;
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'checkBiometricStatus');
    }
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _hasSavedCredentials = hasSaved;
      });
      if (_biometricAvailable && _hasSavedCredentials) {
        _autoTriggerBiometric();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestoreService = ref.read(firestoreServiceProvider);

    _googleSub = FirebaseFirestore.instance
        .collection('social_hrms')
        .doc('google')
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            final rawEnabled = doc.data()?['googleEnable'];
            final enabled = rawEnabled is bool ? rawEnabled : true;
            if (_googleEnabled != enabled) {
              setState(() => _googleEnabled = enabled);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            ErrorReporter.report(
              error,
              stackTrace,
              context: 'loginGoogleConfig',
            );
          },
        );
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _signUpRecognizer.dispose();
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
          if (mounted) _showDeletedAccountSnackBar();
          return;
        }
        if (!mounted) return;

        final profile = await _firestoreService.getUserProfile();
        if (profile == null) {
          await _handleMissingProfile(_authService.currentUser?.email);
          return;
        }

        final pic = (profile['profilePic'] ?? '').toString().trim();
        if (pic.isNotEmpty) {
          AuthService.profilePicNotifier.value = pic;
          await PreferencesService.setProfilePicUrl(pic);
        } else {
          AuthService.profilePicNotifier.value = null;
          await PreferencesService.setProfilePicUrl(null);
        }
        await PreferencesService.setPremium(profile['isPremium'] == true);

        if (!mounted) return;
        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'welcome_back'.tr(),
        );
        _openHome();
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
        _openHome();
      }
    } catch (_) {
      if (mounted) {
        _showErrorSnackBar('guest_login_failed'.tr());
      }
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<void> _handleLogin({bool authenticatedWithBiometrics = false}) async {
    setState(() {
      _submitted = true;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final enteredEmail = _emailController.text.trim().toLowerCase();

    try {
      await _authService.signIn(
        email: enteredEmail,
        password: _passwordController.text,
      );
      if (mounted) {
        if (await _firestoreService.isCurrentUserDeleted()) {
          await _authService.signOut();
          if (mounted) _showDeletedAccountSnackBar();
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
          await _handleMissingProfile(enteredEmail);
          return;
        }
        if (_authService.currentUser?.displayName == null ||
            _authService.currentUser!.displayName!.isEmpty) {
          final username = profile['username']?.toString();
          if (username != null && username.isNotEmpty) {
            await _authService.currentUser?.updateDisplayName(username);
          }
        }

        if (!authenticatedWithBiometrics && _biometricAvailable) {
          final biometricEnabled =
              await PreferencesService.isBiometricEnabled();
          final savedEmail = await PreferencesService.getBiometricEmail();
          final sameAccount =
              biometricEnabled &&
              savedEmail?.trim().toLowerCase() == enteredEmail;

          if (sameAccount) {
            await PreferencesService.setBiometricCredentials(
              email: enteredEmail,
              password: _passwordController.text,
            );
          } else {
            await PreferencesService.clearBiometricCredentials();
            if (mounted) {
              await offerBiometricLogin(
                context: context,
                email: enteredEmail,
                password: _passwordController.text,
              );
            }
          }
        }

        if (!mounted) return;
        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'welcome_back'.tr(),
        );
        _openHome();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          if (await _firestoreService.isEmailDeleted(enteredEmail)) {
            if (mounted) _showDeletedAccountSnackBar();
            return;
          }
        } catch (error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'loginDeletedEmailCheck',
          );
        }
      }

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

  Future<void> _handleBiometricLogin() async {
    if (_anyLoading) return;

    setState(() => _isBiometricLoading = true);

    try {
      final biometricName = await BiometricService.getBiometricName();
      final result = await BiometricService.authenticate(
        localizedReason: 'login_with_biometric_reason'.tr(
          namedArgs: {
            'biometric': LocalizationHelper.localizeBiometricName(
              biometricName,
            ),
          },
        ),
      );

      if (result == BiometricAuthResult.cancelled) {
        if (mounted) _showBiometricPasswordHint();
        return;
      }

      if (result != BiometricAuthResult.success) {
        switch (result) {
          case BiometricAuthResult.lockedOut:
            if (mounted) {
              _showErrorSnackBar('biometric_locked_out'.tr());
            }
            break;
          case BiometricAuthResult.permanentlyLockedOut:
            if (mounted) {
              _showErrorSnackBar('biometric_permanently_locked_out'.tr());
            }
            break;
          case BiometricAuthResult.notAvailable:
            if (mounted) {
              _showErrorSnackBar('biometric_not_enrolled'.tr());
            }
            break;
          default:
            if (mounted) _showBiometricPasswordHint();
        }
        return;
      }

      final email = await PreferencesService.getBiometricEmail();
      final password = await PreferencesService.getBiometricPassword();

      if (email == null || password == null) {
        await PreferencesService.clearBiometricCredentials();
        if (mounted) {
          setState(() => _hasSavedCredentials = false);
          _showErrorSnackBar('biometric_credentials_not_found'.tr());
        }
        return;
      }

      if (mounted) {
        _emailController.text = email;
        _passwordController.text = password;
        await _handleLogin(authenticatedWithBiometrics: true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('biometric_auth_failed'.tr());
      }
    } finally {
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
    }
  }

  void _autoTriggerBiometric() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_autoBiometricTriggered &&
          _biometricAvailable &&
          _hasSavedCredentials &&
          !_anyLoading) {
        _autoBiometricTriggered = true;
        _handleBiometricLogin();
      }
    });
  }

  void _showErrorSnackBar(String message) {
    FlashySnackBar.show(context, message: message, isError: true);
  }

  void _showBiometricPasswordHint() {
    FlashySnackBar.show(
      context,
      message: 'biometric_cancelled_password_hint'.tr(),
    );
  }

  void _showDeletedAccountSnackBar() {
    FlashySnackBar.show(
      context,
      title: 'account_deleted'.tr(),
      message: 'account_deleted_contact_message'.tr(),
      isError: true,
    );
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
    _signUpRecognizer.onTap = _anyLoading
        ? null
        : () {
            Navigator.of(context).pushReplacement(
              authTransitionRoute(builder: (_) => const SignupScreen()),
            );
          };

    return [
      Center(
        child: Image.asset(
          'assets/app_icon.png',
          height: 120,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 30),

      Text(
        'welcome_back'.tr(),
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
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
                if (value == null || value.isEmpty) {
                  return 'password_required'.tr();
                }
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
                  authTransitionRoute(
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
            disabledBackgroundColor: const Color(0xFF0044C9).withValues(alpha: 0.6),
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
          color: const Color(0xFF0044C9).withValues(alpha: 0.4),
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
                recognizer: _signUpRecognizer,
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
                        final mockupWidth = panelWidth + (520 * scale) - 80;

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
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'welcome_to_hrms'.tr(),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 58,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        fontFamily: 'SF Pro',
                                        height: 1,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'welcome_banner_subtitle'.tr(),
                                    maxLines: 2,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFFFFFFF),

                                      fontFamily: 'SF Pro',
                                      height: 1.2,
                                      letterSpacing: 2,
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
                                        color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.08),
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
