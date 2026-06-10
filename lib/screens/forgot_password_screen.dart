import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _submitted = false;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    _submitted = true;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.resetPassword(_emailController.text.trim());
      if (mounted) {
        FlashySnackBar.show(
          context,
          title: 'Success',
          message: 'Password reset email sent. Check your inbox.',
          isError: false,
        );
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
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
      if (mounted) {
        FlashySnackBar.show(context, message: message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'An unexpected error occurred. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardDecoration = BoxDecoration(
      color: const Color(0xFFFFFFFF),
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
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
                  width: 22,
                  height: 22,
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
                      constraints: const BoxConstraints(maxWidth: 480),
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
                            children: [
                              Center(
                                child: SvgPicture.asset(
                                  'assets/HR_dark.svg',
                                  height: 58,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 32),
                              const Text(
                                'Forgot Password',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF000000),
                                  fontFamily: 'SF Pro Display',
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter your email and we\'ll send you a secure link to reset your password.',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF000000),
                                  fontFamily: 'SF Pro Display',
                                  height: 1.3,
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
                                      enabled: !_isLoading,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      decoration: _inputDecoration(
                                        'Enter your e-mail',
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        if (!RegExp(
                                          r'^[^@]+@[^@]+\.[^@]+',
                                        ).hasMatch(value.trim())) {
                                          return 'Please enter a valid email (e.g. name@domain.com)';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _handleResetPassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0044C9),
                                    foregroundColor: const Color(0xFFFFFFFF),
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
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Color(0xFFFFFFFF),
                                                ),
                                          ),
                                        )
                                      : const Text(
                                          'Send Reset Link',
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
                              const SizedBox(height: 18),
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF000000),
                                  ),
                                  child: RichText(
                                    text: const TextSpan(
                                      text: "Don't need this? ",
                                      style: TextStyle(
                                        color: Color(0xFF000000),
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'Back to Login',
                                          style: TextStyle(
                                            color: Color(0xFFFF1014),
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
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

InputDecoration _inputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFD4D4D8), width: 1),
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
