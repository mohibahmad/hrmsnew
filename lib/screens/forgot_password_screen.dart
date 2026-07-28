import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../shared/auth_widgets.dart';
import '../utils/snackbar_utils.dart';

enum _PasswordResetStep { email, otp, password }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late AuthService _authService;

  _PasswordResetStep _step = _PasswordResetStep.email;
  bool _isLoading = false;
  bool _submitted = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _resetToken;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = Provider.of<AuthService>(context, listen: false);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _requestOtp({bool isResend = false}) async {
    if (!isResend) {
      _submitted = true;
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.requestPasswordResetOtp(_emailController.text);
      if (!mounted) return;
      _otpController.clear();
      setState(() {
        _step = _PasswordResetStep.otp;
        _submitted = false;
      });
      _startResendTimer();
      FlashySnackBar.show(
        context,
        title: 'otp_sent'.tr(),
        message: 'otp_sent_if_account_exists'.tr(),
      );
    } on FirebaseFunctionsException catch (error) {
      _showFunctionsError(error);
    } catch (_) {
      _showUnexpectedError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    _submitted = true;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final token = await _authService.verifyPasswordResetOtp(
        email: _emailController.text,
        otp: _otpController.text,
      );
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _resetToken = token;
        _step = _PasswordResetStep.password;
        _submitted = false;
        _resendSeconds = 0;
      });
      FlashySnackBar.show(
        context,
        title: 'otp_verified'.tr(),
        message: 'otp_verified_message'.tr(),
      );
    } on FirebaseFunctionsException catch (error) {
      _showFunctionsError(error);
    } catch (_) {
      _showUnexpectedError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmPasswordReset() async {
    _submitted = true;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final resetToken = _resetToken;
    if (resetToken == null || resetToken.isEmpty) {
      _showMessage('otp_session_expired'.tr(), isError: true);
      _goToStep(_PasswordResetStep.otp);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.confirmPasswordResetOtp(
        email: _emailController.text,
        resetToken: resetToken,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        title: 'password_reset_success'.tr(),
        message: 'password_reset_success_message'.tr(),
      );
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (error) {
      _showFunctionsError(error);
    } catch (_) {
      _showUnexpectedError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFunctionsError(FirebaseFunctionsException error) {
    if (!mounted) return;
    final message = switch (error.code) {
      'resource-exhausted' => 'otp_too_many_requests'.tr(),
      'invalid-argument' when _step == _PasswordResetStep.email =>
        'invalid_email_address_short'.tr(),
      'invalid-argument' => 'invalid_or_expired_otp'.tr(),
      'failed-precondition' => 'password_requirements_not_met'.tr(),
      'deadline-exceeded' || 'unavailable' => 'network_error_short'.tr(),
      _ => 'password_reset_failed'.tr(),
    };
    _showMessage(message, isError: true);
  }

  void _showUnexpectedError() {
    if (mounted) _showMessage('unexpected_error'.tr(), isError: true);
  }

  void _showMessage(String message, {required bool isError}) {
    FlashySnackBar.show(context, message: message, isError: isError);
  }

  void _goToStep(_PasswordResetStep step) {
    setState(() {
      _step = step;
      _submitted = false;
      if (step != _PasswordResetStep.password) _resetToken = null;
    });
    _otpController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  void _handleBack() {
    if (_step == _PasswordResetStep.password) {
      _goToStep(_PasswordResetStep.otp);
    } else if (_step == _PasswordResetStep.otp) {
      _resendTimer?.cancel();
      _goToStep(_PasswordResetStep.email);
    } else {
      Navigator.of(context).pop();
    }
  }

  String get _title => switch (_step) {
    _PasswordResetStep.email => 'reset_password'.tr(),
    _PasswordResetStep.otp => 'verify_otp'.tr(),
    _PasswordResetStep.password => 'reset_password'.tr(),
  };

  String get _subtitle => switch (_step) {
    _PasswordResetStep.email => 'forgot_password_otp_subtitle'.tr(),
    _PasswordResetStep.otp => 'enter_otp_sent_to'.tr(
      namedArgs: {'email': _emailController.text.trim()},
    ),
    _PasswordResetStep.password => 'create_new_password_subtitle'.tr(),
  };

  String get _buttonLabel => switch (_step) {
    _PasswordResetStep.email => 'send_otp'.tr(),
    _PasswordResetStep.otp => 'verify_otp'.tr(),
    _PasswordResetStep.password => 'reset_password'.tr(),
  };

  Future<void> _handlePrimaryAction() => switch (_step) {
    _PasswordResetStep.email => _requestOtp(),
    _PasswordResetStep.otp => _verifyOtp(),
    _PasswordResetStep.password => _confirmPasswordReset(),
  };

  // ─── Decoration helpers (matching login/signup) ───

  InputDecoration _buildInputDecoration(String hint, {bool isPassword = false, bool obscureText = false, VoidCallback? onToggleVisibility}) {
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

  // ─── UI ───

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
              // Left Blue Banner (desktop only)
              if (isDesktop)
                Expanded(
                  flex: 11,
                  child: Container(
                    color: const Color(0xFF165CDB),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 40,
                          left: 20,
                          right: 40,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome to HRMS',
                                style: TextStyle(
                                  fontSize: 55,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const Text(
                                'Manage your entire workforce effortlessly\nwith our smart, automated HRM platform.',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  fontFamily: 'SF Pro Display',
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 280,
                          left: -460,
                          
                          child: Transform.rotate(
                            angle: -0.15,
                            child: Container(
                              width: 1200,
                              height: 800,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                border: const Border(
                                  left: BorderSide(color: Color(0xFF000000), width: 20),
                                  right: BorderSide(color: Color(0xFF000000), width: 20),
                                  bottom: BorderSide(color: Color(0xFF000000), width: 20),
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
                    ),
                  ),
                ),

              // Right Side Form
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
                          children: [
                            Center(
                              child: SvgPicture.asset(
                                'assets/HR_dark.svg',
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 50),
                            const Text(
                              'Reset Password',
                              style: TextStyle(
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
                              'Secure your account with a new password',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade800,
                                fontFamily: 'SF Pro Display',
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildStepIndicator(),
                            const SizedBox(height: 20),
                            Form(
                              key: _formKey,
                              autovalidateMode: _submitted
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              child: _buildCurrentForm(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handlePrimaryAction,
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
                                        _buttonLabel,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFFFFFF),
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Center(
                              child: RichText(
                                text: TextSpan(
                                  text: '',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _step == _PasswordResetStep.email
                                          ? 'dont_need_this'.tr()
                                          : 'back'.tr(),
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = _handleBack,
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
                ),
              ),
            ],
          ),

          // Floating Language selector
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

  Widget _buildStepIndicator() {
    final currentIndex = _step.index;
    return Row(
      children: List.generate(3, (index) {
        final active = index <= currentIndex;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF0247C4) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCurrentForm() {
    switch (_step) {
      case _PasswordResetStep.email:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('email_label'.tr()),
            TextFormField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handlePrimaryAction(),
              style: const TextStyle(fontSize: 15, fontFamily: 'SF Pro Display'),
              decoration: _buildInputDecoration('email_hint'.tr()),
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
          ],
        );
      case _PasswordResetStep.otp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('otp_code'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _otpController,
              enabled: !_isLoading,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onFieldSubmitted: (_) => _handlePrimaryAction(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _buildInputDecoration('otp_hint'.tr()),
              validator: (value) {
                if (value == null || value.length != 6) {
                  return 'enter_six_digit_otp'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'did_not_receive_otp'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                TextButton(
                  onPressed: _isLoading || _resendSeconds > 0
                      ? null
                      : () => _requestOtp(isResend: true),
                  child: Text(
                    _resendSeconds > 0
                        ? 'resend_otp_in'.tr(
                            namedArgs: {'seconds': '$_resendSeconds'},
                          )
                        : 'resend_otp'.tr(),
                  ),
                ),
              ],
            ),
          ],
        );
      case _PasswordResetStep.password:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFieldLabel('new_password'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPasswordController,
              enabled: !_isLoading,
              obscureText: _obscureNewPassword,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 15, fontFamily: 'SF Pro Display'),
              decoration: _buildInputDecoration(
                'new_password_hint'.tr(),
                isPassword: true,
                obscureText: _obscureNewPassword,
                onToggleVisibility: () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'password_enter'.tr();
                }
                if (value.length < 6) return 'password_too_short'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildFieldLabel('confirm_new_password'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_isLoading,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handlePrimaryAction(),
              style: const TextStyle(fontSize: 15, fontFamily: 'SF Pro Display'),
              decoration: _buildInputDecoration(
                'confirm_new_password_hint'.tr(),
                isPassword: true,
                obscureText: _obscureConfirmPassword,
                onToggleVisibility: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'confirm_password_required'.tr();
                }
                if (value != _newPasswordController.text) {
                  return 'passwords_do_not_match'.tr();
                }
                return null;
              },
            ),
          ],
        );
    }
  }
}
