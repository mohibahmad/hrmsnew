import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
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
  bool _obscurePassword = true;
  bool _submitted = false;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    _submitted = true;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email. Please sign up first.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        case 'network-request-failed':
        case 'network-error':
        case 'unavailable':
          message =
              'Network error. Please check your internet connection and try again.';
          break;
        case 'invalid-credential':
          message = 'Invalid email or password. Please try again.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password sign-in is not enabled. Contact support.';
          break;
        default:
          if (e.message != null &&
              e.message!.toLowerCase().contains('network')) {
            message =
                'Network error. Please check your internet connection and try again.';
          } else {
            message = 'Login failed (${e.code}). Please try again.';
          }
      }
      if (mounted) {
        _showErrorSnackBar(message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    FlashySnackBar.show(context, message: message, isError: true);
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailController.text);
    final formKey = GlobalKey<FormState>();
    bool isSending = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendReset() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => isSending = true);
              try {
                await _authService.resetPassword(emailController.text.trim());
                if (context.mounted) {
                  Navigator.of(dialogContext).pop();
                  FlashySnackBar.show(
                    context,
                    message: 'Password reset email sent. Check your inbox.',
                    title: 'Success',
                    isError: false,
                  );
                }
              } on FirebaseAuthException catch (e) {
                setDialogState(() => isSending = false);
                String message;
                switch (e.code) {
                  case 'user-not-found':
                    message = 'No user found for this email.';
                    break;
                  case 'invalid-email':
                    message = 'Invalid email address.';
                    break;
                  case 'network-request-failed':
                  case 'network-error':
                  case 'unavailable':
                    message = 'Network error. Please check your connection.';
                    break;
                  default:
                    if (e.message != null &&
                        e.message!.toLowerCase().contains('network')) {
                      message = 'Network error. Please check your connection.';
                    } else {
                      message = 'Failed to send reset email.';
                    }
                }
                if (context.mounted) {
                  FlashySnackBar.show(context, message: message, isError: true);
                }
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 32,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_reset_rounded,
                                  color: Color(0xFF0044C9),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Reset Password',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF000000),
                                  fontFamily: 'SF Pro Display',
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Enter your email and we\'ll send a secure link to reset your password.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Body
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Email Address',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'SF Pro Display',
                                  color: Color(0xFF000000),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'you@example.com',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF0044C9),
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFFF1014),
                                      width: 1,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFFF1014),
                                      width: 1.5,
                                    ),
                                  ),
                                  errorStyle: const TextStyle(
                                    color: Color(0xFFFF1014),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Email is required';
                                  }
                                  if (!RegExp(
                                    r'^[^@]+@[^@]+\.[^@]+',
                                  ).hasMatch(value.trim())) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        // Footer
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: TextButton(
                                    onPressed: isSending
                                        ? null
                                        : () =>
                                              Navigator.of(dialogContext).pop(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF334155),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 44,
                                  child: ElevatedButton(
                                    onPressed: isSending ? null : sendReset,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0044C9),
                                      foregroundColor: Color(0xFFFFFFFF),
                                      disabledBackgroundColor: const Color(
                                        0xFF0044C9,
                                      ).withOpacity(0.6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: isSending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Color(0xFFFFFFFF),
                                                  ),
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Send Reset Link',
                                                style: TextStyle(
                                                  color: Color(0xFFFFFFFF),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                              ),
                                              SizedBox(width: 6),
                                              Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 16,
                                                color: Color(0xFFFFFFFF),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
    emailController.dispose();
  }

  List<Widget> _buildFormContent(BuildContext context) {
    return [
      Center(
        child: SvgPicture.asset(
          'assets/HR_dark.svg',
          height: 66,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 32),

      const Text(
        'Welcome Back!',
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
        'Sign in to continue your HR journey',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF000000),
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
            const _InputLabel(label: 'E-mail'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('Enter your e-mail'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.trim().contains('@')) {
                  return 'Email must contain @';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                  return 'Please enter a valid email (e.g. name@domain.com)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const _InputLabel(label: 'Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration(
                'Enter your password',
                isPassword: true,
                obscureText: _obscurePassword,
                onToggleVisibility: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                // Check if password has at least one letter and one number/digit
                return null;
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: _showForgotPasswordDialog,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Forget password',
            style: TextStyle(
              color: Color(0xFFFF1014),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0044C9),
            foregroundColor: Color(0xFFFFFFFF),
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
              : const Text(
                  'Log in',
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
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
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
      const SizedBox(height: 20),
      Center(
        child: RichText(
          text: TextSpan(
            text: "Don't have an account? ",
            style: const TextStyle(
              color: Color(0xFF000000),
              fontSize: 13,
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'Sign Up',
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
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10)),
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
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(0xFFFFFFFF),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/langauge_icon.png',
                  width: 35,
                  height: 35,
                  color: const Color(0xFF0247C4),
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
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 24,
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
