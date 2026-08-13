import 'dart:ui';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../shared/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final bool isGuest;
  final VoidCallback? onNotificationTap;

  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.isGuest = false,
    this.onNotificationTap,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
  bool _initialized = false;
  bool _isDeletingAccount = false;
  bool _isOpeningExternalLink = false;
  bool _isSharingApp = false;
  final GlobalKey _shareAppButtonKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
  }

  String _getCurrentLanguageName() {
    final code = context.locale.languageCode;
    for (final entry in languageMap.entries) {
      if (entry.value.languageCode == code) return entry.key;
    }
    return 'English';
  }

  Future<void> _resetPassword(BuildContext context) async {
    final emailController = TextEditingController(
      text: _authService.currentUser?.email ?? '',
    );
    final formKey = GlobalKey<FormState>();
    var isSending = false;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ResetPasswordDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 12 * animation.value,
                  sigmaY: 12 * animation.value,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Container(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: curve,
                child: StatefulBuilder(
                  builder: (dialogContext, setDialogState) {
                    Future<void> sendResetLink() async {
                      if (isSending ||
                          !(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      final email = emailController.text.trim().toLowerCase();
                      setDialogState(() => isSending = true);
                      var sent = false;
                      String? errorMessage;
                      try {
                        await _authService.sendPasswordResetEmail(email);
                        sent = true;
                      } on FirebaseAuthException catch (error) {
                        switch (error.code) {
                          case 'user-not-found':
                            sent = true;
                            break;
                          case 'invalid-email':
                            errorMessage = 'email_invalid'.tr();
                            break;
                          case 'too-many-requests':
                            errorMessage = 'too_many_requests'.tr();
                            break;
                          case 'network-request-failed':
                          case 'network-error':
                          case 'unavailable':
                            errorMessage = 'network_error'.tr();
                            break;
                          default:
                            errorMessage = 'password_reset_failed'.tr();
                        }
                      } catch (_) {
                        errorMessage = 'unexpected_error'.tr();
                      }

                      if (!dialogContext.mounted) return;
                      if (sent) {
                        Navigator.of(dialogContext).pop();
                        if (context.mounted) {
                          FlashySnackBar.show(
                            context,
                            title: 'success'.tr(),
                            message: 'check_email_reset_link'.tr(
                              namedArgs: {'email': email},
                            ),
                          );
                        }
                        return;
                      }
                      setDialogState(() => isSending = false);
                      if (errorMessage != null && context.mounted) {
                        FlashySnackBar.show(
                          context,
                          message: errorMessage,
                          isError: true,
                        );
                      }
                    }

                    return Dialog(
                      backgroundColor: Colors.transparent,
                      child: Container(
                        width: 430,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF000000,
                              ).withValues(alpha: 0.15),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0247C4,
                                      ).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.lock_reset_rounded,
                                      color: Color(0xFF0247C4),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'reset_password'.tr(),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF000000),
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: isSending
                                        ? null
                                        : () =>
                                              Navigator.of(dialogContext).pop(),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'reset_password_email_desc'.tr(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color(0xFF64748B),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'email_label'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: emailController,
                                enabled: !isSending,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.done,
                                autocorrect: false,
                                enableSuggestions: false,
                                onFieldSubmitted: (_) => sendResetLink(),
                                decoration: InputDecoration(
                                  hintText: 'email_hint'.tr(),
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: SvgPicture.asset(
                                      'assets/email.svg',
                                      width: 20,
                                      height: 20,
                                      colorFilter: const ColorFilter.mode(
                                        Color(0xFF0247C4),
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF0247C4),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) {
                                    return 'email_required'.tr();
                                  }
                                  if (!RegExp(
                                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                  ).hasMatch(email)) {
                                    return 'email_invalid'.tr();
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: isSending
                                          ? null
                                          : () => Navigator.of(
                                              dialogContext,
                                            ).pop(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF475569,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFCBD5E1),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: Text('cancel'.tr()),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isSending
                                          ? null
                                          : sendResetLink,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0247C4,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: isSending
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text('send_reset_link'.tr()),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));
    emailController.dispose();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    if (_isDeletingAccount) return;
    final usesPasswordProvider = _authService.currentUserUsesPasswordProvider;
    final deletePasswordController = TextEditingController();
    final deleteFormKey = GlobalKey<FormState>();

    final confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeleteAccountDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 12 * animation.value,
                  sigmaY: 12 * animation.value,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Container(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: curve,
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    width: 380,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: deleteFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.warning_rounded,
                                color: Color(0xFFEF4444),
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'delete_account_question'.tr(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF000000),
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'delete_account_desc'.tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w400,
                              fontFamily: 'SF Pro Display',
                              height: 1.4,
                            ),
                          ),
                          if (usesPasswordProvider) ...[
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'password_label'.tr(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: deletePasswordController,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (deleteFormKey.currentState?.validate() ??
                                    false) {
                                  Navigator.pop(context, true);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: 'password_hint'.tr(),
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF0247C4),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0247C4),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                  ? 'password_required'.tr()
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => Navigator.pop(context, false),
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'cancel'.tr(),
                                        style: const TextStyle(
                                          color: Color(0xFF000000),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () {
                                      if (usesPasswordProvider &&
                                          !(deleteFormKey.currentState
                                                  ?.validate() ??
                                              false)) {
                                        return;
                                      }
                                      Navigator.pop(context, true);
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444),
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFEF4444,
                                            ).withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        'delete_account'.tr(),
                                        style: const TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    final deletionPassword = deletePasswordController.text;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    deletePasswordController.dispose();
    if (confirm != true || !context.mounted) return;

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      await _authService.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      FlashySnackBar.show(
        context,
        message: 'failed_delete_account'.tr(
          namedArgs: {'error': 'user-not-found'},
        ),
        isError: true,
      );
      return;
    }

    setState(() => _isDeletingAccount = true);
    var profileMarkedDeleted = false;

    try {
      await _authService.reauthenticateForAccountDeletion(
        password: usesPasswordProvider ? deletionPassword : null,
      );
      await _firestore.deleteUserData();
      profileMarkedDeleted = true;

      try {
        await _authService.signOut();
      } catch (_) {}

      if (!context.mounted) return;
      FlashySnackBar.show(
        context,
        message: 'account_deleted_successfully'.tr(),
        title: 'account_deleted'.tr(),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (profileMarkedDeleted && _authService.currentUser != null) {
        try {
          await _firestore.updateUserProfile({'isDeleted': false});
        } catch (_) {}
      }
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: _deleteAccountErrorMessage(error),
          isError: true,
        );
      }
    } catch (error) {
      if (profileMarkedDeleted && _authService.currentUser != null) {
        try {
          await _firestore.updateUserProfile({'isDeleted': false});
        } catch (_) {}
      }
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_delete_account'.tr(
            namedArgs: {'error': error.runtimeType.toString()},
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  String _deleteAccountErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'wrong_password'.tr();
      case 'password-required':
        return 'password_required'.tr();
      case 'too-many-requests':
        return 'too_many_requests'.tr();
      case 'network-request-failed':
      case 'network-error':
      case 'unavailable':
        return 'network_error'.tr();
      case 'canceled':
      case 'popup-closed-by-user':
      case 'reauthentication-cancelled':
        return 'cancelled'.tr();
      default:
        return 'failed_delete_account'.tr(namedArgs: {'error': error.code});
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    if (!mounted || _isOpeningExternalLink) return;
    setState(() => _isOpeningExternalLink = true);
    try {
      final uri = Uri.tryParse(rawUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw const FormatException();
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('launch-failed');
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningExternalLink = false);
    }
  }

  Future<void> _rateApp() async {
    await PreferencesService.setRateUsNeverShow(true);
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await _openExternalUrl(
          'https://apps.apple.com/app/hrms-workforce-manager/id6743024022',
        );
      }
    } catch (_) {
      await _openExternalUrl(
        'https://apps.apple.com/app/hrms-workforce-manager/id6743024022',
      );
    }
  }

  Rect? _shareOrigin(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _shareApp() async {
    if (!mounted || _isSharingApp) return;
    setState(() => _isSharingApp = true);
    try {
      const appLink =
          'https://apps.apple.com/app/hrms-workforce-manager/id6743024022';
      final text = 'share_app_text'.tr(namedArgs: {'link': appLink});
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: _shareOrigin(_shareAppButtonKey),
        ),
      );
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'unexpected_error'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingApp = false);
    }
  }

  void _showLanguageModal(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allLanguages = languageMap.keys.toList();
            final currentLang = _getCurrentLanguageName();
            return Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 60.0, top: 40.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF000000).withValues(alpha: 0.1),
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
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...allLanguages.map((lang) {
                          final isSel = currentLang == lang;
                          return InkWell(
                            onTap: () {
                              final locale = languageMap[lang]!;
                              context.setLocale(locale);
                              setModalState(() {});
                              Future.delayed(
                                const Duration(milliseconds: 150),
                                () {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                              );
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
                                      color: Color(0xFF000000),
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  if (isSel)
                                    const Icon(
                                      Icons.check,
                                      color: Color(0xFF0247C4),
                                      size: 16,
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                children: [
                  _buildActionSettingItem(
                    'assets/changepassword.svg',
                    'reset_password_desc'.tr(),
                    'reset_password'.tr(),
                    onTap: widget.isGuest
                        ? null
                        : () => _resetPassword(context),
                    disabled: widget.isGuest,
                  ),
                  _buildActionSettingItem(
                    'assets/permenantly_delete.svg',
                    'delete_profile_desc'.tr(),
                    'delete_profile'.tr(),
                    onTap: widget.isGuest || _isDeletingAccount
                        ? null
                        : () => _deleteAccount(context),
                    disabled: widget.isGuest || _isDeletingAccount,
                    buttonColor: const Color(0xFFFF0004),
                  ),
                  _buildLanguageItem(),
                  _buildSimpleSettingItem(
                    'assets/rating.png',
                    'rate_us'.tr(),
                    onTap: _rateApp,
                  ),
                  _buildSimpleSettingItem(
                    'assets/share.svg',
                    'share_app'.tr(),
                    onTap: _shareApp,
                    itemKey: _shareAppButtonKey,
                  ),
                  _buildSimpleSettingItem(
                    'assets/terms&condition.svg',
                    'terms_condition'.tr(),
                    onTap: () => _openExternalUrl(
                      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                    ),
                  ),
                  _buildSimpleSettingItem(
                    'assets/privacy_policy.svg',
                    'privacy_policy'.tr(),
                    onTap: () => _openExternalUrl(
                      'https://docs.google.com/document/d/1ul6JAXXkdGKgfe9en6yF77u0EChQp32R/edit?rtpof=true&sd=true&tab=t.0',
                    ),
                  ),
                  if (!widget.isGuest)
                    _buildSimpleSettingItem(
                      'assets/signout.svg',
                      'sign_out'.tr(),
                      onTap: widget.onLogout,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'settings'.tr(),
                style: TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onProfileTap,
              child: const UserAvatar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSettingItem(
    dynamic iconSource,
    String text,
    String buttonText, {
    VoidCallback? onTap,
    bool disabled = false,
    Color? buttonColor,
    bool showCheckmark = false,
    bool preserveIconColors = false,
    ColorMapper? iconColorMapper,
    IconData? buttonIcon,
    double iconSize = 24,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: Center(
              child: Opacity(
                opacity: disabled ? 0.4 : 1,
                child: iconSource is IconData
                    ? Icon(
                        iconSource,
                        size: iconSize,
                        color: disabled
                            ? const Color(0xFFAAAAAA)
                            : const Color(0xFF000000),
                      )
                    : iconSource.toString().endsWith('.svg')
                    ? SvgPicture.asset(
                        iconSource.toString(),
                        width: iconSize,
                        height: iconSize,
                        colorMapper: iconColorMapper,
                        colorFilter: preserveIconColors
                            ? null
                            : ColorFilter.mode(
                                disabled
                                    ? const Color(0xFFAAAAAA)
                                    : const Color(0xFF000000),
                                BlendMode.srcIn,
                              ),
                      )
                    : Image.asset(
                        iconSource.toString(),
                        width: iconSize,
                        height: iconSize,
                        color: disabled ? const Color(0xFFAAAAAA) : null,
                      ),
              ),
            ),
          ),
          if (showCheckmark) ...[
            const SizedBox(width: 4),
            SvgPicture.asset(
              'assets/tick_icon.svg',
              width: 16,
              height: 12,
              colorFilter: const ColorFilter.mode(
                Color(0xFF22C55E),
                BlendMode.srcIn,
              ),
            ),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: disabled
                    ? const Color(0xFFAAAAAA)
                    : const Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: disabled ? null : onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: disabled
                      ? const Color(0xFFE0E0E0)
                      : buttonColor ?? const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (buttonIcon != null) ...[
                      Icon(
                        buttonIcon,
                        size: 18,
                        color: disabled
                            ? const Color(0xFFAAAAAA)
                            : buttonColor != null
                            ? Colors.white
                            : const Color(0xFF000000),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      buttonText,
                      style: TextStyle(
                        fontSize: 16,
                        color: disabled
                            ? const Color(0xFFAAAAAA)
                            : buttonColor != null
                            ? Colors.white
                            : const Color(0xFF000000),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                        height: 1.0,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageItem() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showLanguageModal(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Color(0xFF000000),
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/langauge_icon.png',
                  width: 24,
                  height: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'language'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF000000),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Text(
                _getCurrentLanguageName(),
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF000000),
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_drop_down,
                color: Color(0xFF000000),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleSettingItem(
    String iconPath,
    String text, {
    VoidCallback? onTap,
    GlobalKey? itemKey,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: itemKey,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (iconPath.endsWith('.svg'))
                SvgPicture.asset(
                  iconPath,
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF000000),
                    BlendMode.srcIn,
                  ),
                )
              else
                Image.asset(iconPath, width: 24, height: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                    height: 1.0,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
