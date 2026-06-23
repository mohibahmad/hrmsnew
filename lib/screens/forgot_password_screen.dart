import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
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
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 40.0, top: 40.0),
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
          title: 'success'.tr(),
          message: 'password_reset_sent'.tr(),
          isError: false,
        );
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'no_user_found'.tr();
          break;
        case 'invalid-email':
          message = 'invalid_email_address_short'.tr();
          break;
        case 'network-request-failed':
        case 'network-error':
        case 'unavailable':
          message = 'network_error_short'.tr();
          break;
        default:
          if (e.message != null &&
              e.message!.toLowerCase().contains('network')) {
            message = 'network_error_short'.tr();
          } else {
            message = 'failed_send_reset'.tr();
          }
      }
      if (mounted) {
        FlashySnackBar.show(context, message: message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
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
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: Offset(0, 10)),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
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
                    width: 22,
                    height: 22,
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
                              Text(
                                'forgot_password'.tr(),
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
                                'forgot_password_subtitle'.tr(),
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
                                    ? AutovalidateMode.always
                                    : AutovalidateMode.disabled,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _InputLabel(label: 'email_label'.tr()),
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
                                        'email_hint'.tr(),
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'email_required'.tr();
                                        }
                                        if (!RegExp(
                                          r'^[^@]+@[^@]+\.[^@]+',
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
                                      : Text(
                                          'send_reset_link'.tr(),
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
                                child: RichText(
                                  text: TextSpan(
                                    text: 'dont_need_this'.tr(),
                                    style: const TextStyle(
                                      color: Color(0xFF000000),
                                      fontSize: 13,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'back_to_login'.tr(),
                                        style: const TextStyle(
                                          color: Color(0xFFFF1014),
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            Navigator.of(context).pop();
                                          },
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
    disabledBorder: OutlineInputBorder(
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
