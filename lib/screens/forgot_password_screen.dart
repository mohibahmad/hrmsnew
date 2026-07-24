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

  @override
  Widget build(BuildContext context) {
    final cardDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(40),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );

    return PopScope(
      canPop: _step == _PasswordResetStep.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
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
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
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
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: cardDecoration,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Center(
                                  child: SvgPicture.asset(
                                    'assets/HR_dark.svg',
                                    height: 76,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _buildStepIndicator(),
                                const SizedBox(height: 22),
                                Text(
                                  _title,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _subtitle,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Form(
                                  key: _formKey,
                                  autovalidateMode: _submitted
                                      ? AutovalidateMode.always
                                      : AutovalidateMode.disabled,
                                  child: _buildCurrentForm(),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handlePrimaryAction,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0044C9),
                                      foregroundColor: Colors.white,
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
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            _buttonLabel,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontFamily: 'SF Pro Display',
                                              height: 1,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(
                                  child: RichText(
                                    text: TextSpan(
                                      text: 'dont_need_this'.tr(),
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'back'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFFFF1014),
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = _handleBack,
                                        ),
                                      ],
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
            _InputLabel(label: 'email_label'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handlePrimaryAction(),
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _inputDecoration('email_hint'.tr()),
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
          ],
        );
      case _PasswordResetStep.otp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InputLabel(label: 'otp_code'.tr()),
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
              decoration: _inputDecoration('otp_hint'.tr()),
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
            _InputLabel(label: 'new_password'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPasswordController,
              enabled: !_isLoading,
              obscureText: _obscureNewPassword,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _passwordInputDecoration(
                'new_password_hint'.tr(),
                obscure: _obscureNewPassword,
                onToggle: () =>
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
            const SizedBox(height: 14),
            _InputLabel(label: 'confirm_new_password'.tr()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_isLoading,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handlePrimaryAction(),
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
              decoration: _passwordInputDecoration(
                'confirm_new_password_hint'.tr(),
                obscure: _obscureConfirmPassword,
                onToggle: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
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
        color: Colors.black,
        fontFamily: 'SF Pro Display',
        height: 1,
      ),
    );
  }
}

InputDecoration _passwordInputDecoration(
  String hintText, {
  required bool obscure,
  required VoidCallback onToggle,
}) {
  return _inputDecoration(hintText).copyWith(
    suffixIcon: IconButton(
      onPressed: onToggle,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: const Color(0xFF64748B),
      ),
    ),
  );
}

InputDecoration _inputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFF0044C9), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: const BorderSide(color: Color(0xFFFF1014)),
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
