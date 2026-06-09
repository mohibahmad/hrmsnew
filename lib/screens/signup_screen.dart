import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
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
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _submitted = false;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Filter phone input: only digits and leading + allowed
    _phoneController.addListener(_filterPhoneInput);
  }

  void _filterPhoneInput() {
    final text = _phoneController.text;
    final filtered = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      // Allow digits always
      if (char == '+' && filtered.isEmpty) {
        // Allow leading +
        filtered.write(char);
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        // Digits 0-9
        filtered.write(char);
      }
      // All other characters are filtered out
    }
    final filteredStr = filtered.toString();
    if (filteredStr != text) {
      _phoneController.value = TextEditingValue(
        text: filteredStr,
        selection: TextSelection.collapsed(offset: filteredStr.length),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_filterPhoneInput);
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
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

      await credential.user?.updateDisplayName(_usernameController.text.trim());

      await FirestoreService().createUserProfile(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'An account with this email already exists.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        case 'weak-password':
          message = 'The password is too weak (min 6 characters).';
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled.';
          break;
        case 'network-request-failed':
        case 'network-error':
        case 'unavailable':
          message =
              'Network error. Please check your internet connection and try again.';
          break;
        default:
          if (e.message != null &&
              e.message!.toLowerCase().contains('network')) {
            message =
                'Network error. Please check your internet connection and try again.';
          } else {
            message = 'Sign up failed (${e.code}): ${e.message}';
          }
      }
      if (mounted) {
        FlashySnackBar.show(context, message: message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'An error occurred: $e',
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
          height: 66,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 24),

      const Text(
        'Create Account',
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
        'Join us to get started on your journey',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF000000),
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
            const _InputLabel(label: 'Username'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('Enter your username'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your username';
                }
                if (value.trim().length < 2) {
                  return 'Username must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            const _InputLabel(label: 'Phone'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('Enter your number'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your phone number';
                }
                // Must have at least 7 digits
                final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                if (digitsOnly.length < 7) {
                  return 'Phone number must have at least 7 digits';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
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
                  return 'Please enter a password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
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
        height: 48,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleSignUp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0044C9),
            foregroundColor: Colors.white,
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
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
      const SizedBox(height: 16),
      Center(
        child: RichText(
          text: TextSpan(
            text: 'Already have an account? ',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontFamily: 'SF Pro Display',
            ),
            children: [
              TextSpan(
                text: 'Sign In',
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
      color: Colors.white,
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
                color: Colors.white,
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
