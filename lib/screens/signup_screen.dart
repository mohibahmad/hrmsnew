import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
import 'home_screen.dart';
import 'login_screen.dart';

const String _googleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="20px" height="20px">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.5 24c0-1.55-.15-3.24-.47-4.77H24v9.03h12.75c-.55 2.89-2.2 5.33-4.66 7l7.25 5.62C43.59 36.43 46.5 30.73 46.5 24z"/>
  <path fill="#FBBC05" d="M10.54 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.98-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.25-5.62c-2.03 1.37-4.63 2.19-8.64 2.19-6.26 0-11.57-4.22-13.46-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>
''';

const String _appleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="20px" height="20px" fill="#FFFFFF">
  <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.93.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.499c.87-1.066 1.43-2.56 1.261-4.04-1.274.052-2.813.858-3.722 1.91-.78.897-1.467 2.418-1.287 3.873 1.416.104 2.873-.675 3.748-1.743z"/>
</svg>
''';

const String _guestSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
  <circle cx="12" cy="7" r="4"/>
</svg>
''';

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

  bool get _anyLoading =>
      _isLoading || _isGoogleLoading || _isAppleLoading || _isGuestLoading;

  final AuthService _authService = AuthService();

  static const Map<String, Locale> _languageMap = {
    'English': Locale('en'),
    'Español': Locale('es'),
    'Français': Locale('fr'),
    'Português': Locale('pt'),
    'Русский': Locale('ru'),
  };

  void _showLanguageModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.05),
      builder: (BuildContext ctx) {
        final allLanguages = _languageMap.keys.toList();
        final currentCode = context.locale.languageCode;
        final currentLang = allLanguages.firstWhere(
          (l) => _languageMap[l]!.languageCode == currentCode,
          orElse: () => 'English',
        );
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 40.0, top: 96.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'select_language'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...allLanguages.map((lang) {
                          final isSel = currentLang == lang;
                          return InkWell(
                            onTap: () {
                              context.setLocale(_languageMap[lang]!);
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? const Color(0xFFF1F3F5)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    lang,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  if (isSel)
                                    const Icon(
                                      Icons.check,
                                      size: 18,
                                      color: Color(0xFF0247C4),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
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

      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'success'.tr(),
          message: 'account_created_successfully'.tr(),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        try {
          final credential = await _authService.signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
          // Don't overwrite existing profile — just sign in and navigate
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
          return;
        } on FirebaseAuthException catch (signInError) {
          if (signInError.code == 'wrong-password') {
            message = 'email_already_in_use_wrong_password'.tr();
          } else {
            message = 'email_already_in_use'.tr();
          }
        }
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

  Future<bool> _handleDeletedAccountIfNeeded() async {
    final email = _authService.currentUser?.email;
    if (email == null) return false;

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

  Widget _buildSocialButton({
    required String text,
    required Widget icon,
    required VoidCallback? onPressed,
    required bool isLoading,
    Color? backgroundColor,
    Color? textColor,
    BorderSide? border,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.white,
          foregroundColor: textColor ?? const Color(0xFF000000),
          disabledForegroundColor: (textColor ?? const Color(0xFF000000))
              .withValues(alpha: 0.6),
          disabledBackgroundColor: backgroundColor ?? Colors.white,
          side: border ?? BorderSide(color: Colors.grey.shade200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                      width: 36,
                      height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      textColor ?? const Color(0xFF000000),
                    ),
                  ),
                ),
              )
            else
              icon,
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
                color: isLoading
                    ? (textColor ?? const Color(0xFF000000)).withValues(
                        alpha: 0.6,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
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
            _InputLabel(label: 'username_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              enabled: !_anyLoading,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('username_hint'.tr()),
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
            _InputLabel(label: 'email_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              enabled: !_anyLoading,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('email_hint'.tr()),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'email_required'.tr();
                }
                if (!value.trim().contains('@')) {
                  return 'email_must_contain_at'.tr();
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                  return 'email_invalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            _InputLabel(label: 'password_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              enabled: !_anyLoading,
              obscureText: _obscurePassword,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration(
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
      _buildSocialButton(
        text: 'continue_with_google'.tr(),
        icon: SvgPicture.string(_googleSvg, width: 16, height: 16),
        isLoading: _isGoogleLoading,
        onPressed: _anyLoading ? null : _handleGoogleLogin,
        backgroundColor: Colors.white,
        textColor: const Color(0xFF000000),
      ),
      const SizedBox(height: 8),

      // Continue with Apple Button
      _buildSocialButton(
        text: 'continue_with_apple'.tr(),
        icon: SvgPicture.string(
          _appleSvg,
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        isLoading: _isAppleLoading,
        onPressed: _anyLoading ? null : _handleAppleLogin,
        backgroundColor: const Color(0xFF0F172A),
        textColor: Colors.white,
        border: const BorderSide(color: Color(0xFF0F172A)),
      ),
      const SizedBox(height: 8),

      // Continue as Guest Button
      _buildSocialButton(
        text: 'continue_as_guest'.tr(),
        icon: SvgPicture.string(
          _guestSvg,
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

  InputDecoration _inputDecoration(
    String hintText, {
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: isPassword
          ? Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFFCBCBCB),
                  size: 20,
                ),
                onPressed: onToggleVisibility,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            )
          : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: const BorderSide(color: Color(0xFF0044C9), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: const BorderSide(color: Color(0xFFFF1014), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: const BorderSide(color: Color(0xFFFF1014), width: 1.5),
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFFF1014),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: 'SF Pro Display',
        height: 1.3,
      ),
      errorMaxLines: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardDecoration = BoxDecoration(
      color: Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(40),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
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
              onTap: _showLanguageModal,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 10,
                        ),
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

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
        height: 1.0,
      ),
    );
  }
}
