import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/auth_widgets.dart';
import '../../riverpod_providers.dart';
import '../../services/auth_service.dart';
import '../../shared/app_constants.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  late AuthService _authService;

  bool _isLoading = false;
  bool _submitted = false;
  bool _emailSent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = ref.read(authServiceProvider);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_isLoading) return;

    final wasEmailSent = _emailSent;

    if (!wasEmailSent) {
      setState(() => _submitted = true);
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }

    final email = _emailController.text.trim().toLowerCase();
    setState(() => _isLoading = true);

    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;

      setState(() {
        _emailSent = true;
        _submitted = false;
      });

      if (wasEmailSent) {
        _showMessage('password_reset_link'.tr(), isError: false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'user-not-found':
          setState(() {
            _emailSent = true;
            _submitted = false;
          });
          if (wasEmailSent) {
            _showMessage('password_reset_link'.tr(), isError: false);
          }
        case 'invalid-email':
          _showMessage('invalid_email_address_short'.tr(), isError: true);
        case 'too-many-requests':
          _showMessage('too_many_requests'.tr(), isError: true);
        case 'network-request-failed' || 'network-error' || 'unavailable':
          _showMessage('network_error'.tr(), isError: true);
        case 'user-disabled':
          _showMessage('user_disabled'.tr(), isError: true);
        case 'operation-not-allowed':
          _showMessage('operation_not_allowed'.tr(), isError: true);
        default:
          _showMessage('password_reset_failed'.tr(), isError: true);
      }
    } catch (_) {
      if (mounted) _showMessage('unexpected_error'.tr(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    FlashySnackBar.show(context, message: message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              if (isDesktop) Expanded(flex: 11, child: _buildDesktopPanel()),
              Expanded(flex: 9, child: _buildFormPanel()),
            ],
          ),
          Positioned(top: 40, right: 40, child: _buildLanguageButton()),
        ],
      ),
    );
  }

  Widget _buildDesktopPanel() {
    return Container(
      color: const Color(0xFF165CDB),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth.clamp(0.0, 880.0);
          final scale = (panelWidth / 880.0).clamp(0.4, 1.0);
          final mockupWidth = panelWidth + (520 * scale) - 90;

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
                    Text(
                      'welcome_to_hrms'.tr(),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        fontFamily: 'SF Pro Display',
                        height: 0.9,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'welcome_banner_subtitle'.tr(),
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        fontFamily: 'SF Pro Display',
                        height: 1.2,
                        letterSpacing: 1.8,
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
    );
  }

  Widget _buildFormPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
        child: Transform.translate(
          offset: const Offset(0, -16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Image.asset(
                    'assets/app_icon.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 50),
                Text(
                  'reset_password'.tr(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _emailSent
                      ? 'forgot_password_subtitle_reset'.tr()
                      : 'forgot_password_link_subtitle'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 20),
                _emailSent ? _buildEmailSentContent() : _buildEmailForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton() {
    return GestureDetector(
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
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTextField(
                controller: _emailController,
                label: 'email_label'.tr(),
                hint: 'email_hint'.tr(),
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _sendResetEmail(),
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
          ),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          label: 'send_reset_link'.tr(),
          onPressed: _sendResetEmail,
        ),
        const SizedBox(height: 18),
        Center(
          child: _buildTapText(
            label: 'back'.tr(),
            onTap: () {
              final route = ModalRoute.of(context);
              if (route != null && route.isCurrent) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildEmailSentContent() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mark_email_unread_rounded,
                color: Color(0xFF0284C7),
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'password_reset_email_sent'.tr(
                        namedArgs: {'email': _emailController.text.trim()},
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'check_email_reset_link'.tr(
                        namedArgs: {'email': _emailController.text.trim()},
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          label: 'back_to_login'.tr(),
          onPressed: () {
            final route = ModalRoute.of(context);
            if (route != null && route.isCurrent) {
              Navigator.of(context).pop(true);
            }
          },
        ),
        const SizedBox(height: 18),
        Center(
          child: _buildTapText(
            label: 'resend_email'.tr(),
            onTap: _isLoading ? null : _sendResetEmail,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
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
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFFFFF)),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFFFFF),
                ),
              ),
      ),
    );
  }

  Widget _buildTapText({required String label, VoidCallback? onTap}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xFFFF1014),
              fontWeight: FontWeight.bold,
            ),
            recognizer: TapGestureRecognizer()..onTap = onTap,
          ),
        ],
      ),
    );
  }
}
