import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoIcons;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/leave_policy_service.dart';
import '../services/upload_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../shared/app_constants.dart';
import '../utils/svg_fill_color_mapper.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends StatefulWidget {
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
  bool _initialized = false;
  bool _isDeletingAccount = false;
  bool _isOpeningExternalLink = false;
  bool _isSharingApp = false;
  Map<String, dynamic>? _currentLeavePolicy;
  bool _isLoadingPolicy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _loadLeavePolicy();
  }

  Future<void> _loadLeavePolicy() async {
    if (!mounted || _isLoadingPolicy) return;
    setState(() => _isLoadingPolicy = true);
    try {
      final policies = await _firestore.getLeavePolicies();
      if (mounted) {
        setState(() {
          _currentLeavePolicy = policies.isNotEmpty ? policies.first : null;
          _isLoadingPolicy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPolicy = false);
    }
  }

  String _getCurrentLanguageName() {
    final code = context.locale.languageCode;
    for (final entry in languageMap.entries) {
      if (entry.value.languageCode == code) return entry.key;
    }
    return 'English';
  }

  Future<void> _resetPassword(BuildContext context) async {
    final email = _authService.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      final emailSent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
      );
      if (emailSent == true && context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'password_reset_sent'.tr(),
          title: 'success'.tr(),
        );
      }
    } else {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'no_email_found_for_account'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    if (_isDeletingAccount) return;

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
                                  onTap: () => Navigator.pop(context, true),
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
          ],
        );
      },
    );

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
        message: 'failed_to_delete_account'.tr(
          namedArgs: {'error': 'user-not-found'},
        ),
        isError: true,
      );
      return;
    }

    setState(() => _isDeletingAccount = true);
    var profileMarkedDeleted = false;

    try {
      await _firestore.deleteUserData();
      profileMarkedDeleted = true;
      await user.delete();

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
          await _firestore.updateUserProfile({
            'isDeleted': false,
            'deletedAt': null,
          });
        } catch (_) {}
      }
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_delete_account'.tr(
            namedArgs: {'error': error.code},
          ),
          isError: true,
        );
      }
    } catch (error) {
      if (profileMarkedDeleted && _authService.currentUser != null) {
        try {
          await _firestore.updateUserProfile({
            'isDeleted': false,
            'deletedAt': null,
          });
        } catch (_) {}
      }
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_delete_account'.tr(
            namedArgs: {'error': error.runtimeType.toString()},
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
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

  Future<void> _shareApp() async {
    if (!mounted || _isSharingApp) return;
    setState(() => _isSharingApp = true);
    try {
      const appLink =
          'https://apps.apple.com/app/hrms-workforce-manager/id6743024022';
      final text = 'share_app_text'.tr(namedArgs: {'link': appLink});
      await SharePlus.instance.share(ShareParams(text: text));
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

  void _showLeavePolicyListDialog({Map<String, dynamic>? editPolicy}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'AddLeavePolicyDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 8 * animation.value,
                  sigmaY: 8 * animation.value,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Container(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: _AddLeavePolicyDialog(
                  onSaved: _loadLeavePolicy,
                  editPolicy: editPolicy,
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) => _loadLeavePolicy());
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
                  ),
                  _buildLeavePolicySettingItem(),
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
    String iconPath,
    String text,
    String buttonText, {
    VoidCallback? onTap,
    bool disabled = false,
    Color? buttonColor,
    bool showCheckmark = false,
    bool preserveIconColors = false,
    ColorMapper? iconColorMapper,
    IconData? buttonIcon,
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
          Opacity(
            opacity: disabled ? 0.4 : 1,
            child: iconPath.endsWith('.svg')
                ? SvgPicture.asset(
                    iconPath,
                    width: 24,
                    height: 24,
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
                : Image.asset(iconPath, width: 24, height: 24),
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

  void _sharePolicy(Map<String, dynamic> policy) {
    final policyName = (policy['policyName'] ?? 'Leave Policy').toString();
    final annualDays = policy['annualLeaveDays'] ?? 0;
    final sickDays = policy['sickLeaves'] ?? '0';
    final casualDays = policy['casualLeaves'] ?? '0';
    final medicalDays = policy['medicalLeaves'] ?? '0';
    final notes = (policy['description'] ?? '').toString();

    final text = StringBuffer()
      ..writeln('Leave Policy: $policyName')
      ..writeln()
      ..writeln('Annual Leave Allowance: $annualDays days')
      ..writeln('  - Sick Leave: $sickDays days')
      ..writeln('  - Casual Leave: $casualDays days')
      ..writeln('  - Medical Leave: $medicalDays days')
      ..writeln('  Applies to: All Workers');
    if (notes.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Notes: $notes');
    }
    text.writeln('\nShared via HRMS App');

    _showShareOptionsDialog(policy, text.toString());
  }

  void _showShareOptionsDialog(Map<String, dynamic> policy, String text) {
    final borderLight = const Color(0xFFE5E7EB);
    final bgLight = const Color(0xFFF8FAFC);
    final primaryBlue = const Color(0xFF0D52D6);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SharePolicyDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 3 * animation.value,
                  sigmaY: 3 * animation.value,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Container(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    width: 580,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'share_policy'.tr(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                                letterSpacing: -0.5,
                              ),
                            ),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    color: Color(0xFF6B7280),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'share_policy_subtitle'.tr(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildShareOptionCard(
                                iconAsset: 'assets/whatsapp.png',
                                label: 'share_whatsapp'.tr(),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _sharePolicyToWhatsApp(policy, text);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildShareOptionCard(
                                iconAsset: 'assets/email_icon.png',
                                label: 'share_email'.tr(),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _sharePolicyToEmail(policy, text);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildShareOptionCard(
                                iconAsset: 'assets/pdf.png',
                                label: 'download_pdf'.tr(),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _downloadPolicyPdf(policy);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildShareOptionCard(
                                iconAsset: 'assets/copylink.png',
                                label: 'copy_link'.tr(),
                                onTap: () {
                                  Navigator.pop(context);
                                  _copyPolicyLink(policy);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: bgLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.description_outlined,
                                color: Color(0xFF6B7280),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'share_as_pdf'.tr(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 40,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  side: BorderSide(
                                    color: borderLight,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'cancel'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _sharePolicyPdf(policy);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'share'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
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
          ],
        );
      },
    );
  }

  Widget _buildShareOptionCard({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
    String? iconAsset,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconAsset != null)
                SizedBox(
                  height: 32,
                  width: 32,
                  child: Image.asset(
                    iconAsset,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                )
              else
                Icon(icon, color: iconColor, size: 32),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePolicyPdf(Map<String, dynamic> policy) async {
    // Official PDFs must never be generated with a fake/generic company name.
    // If the company profile cannot be loaded (network/permission) or the
    // business name is missing, abort PDF generation and surface the error.
    final profile = await _firestore.getUserProfileOrThrow();
    final companyName = (profile?['businessName'] ?? '').toString().trim();
    final companyId = (profile?['companyId'] ?? '').toString().trim();

    if (companyName.isEmpty) {
      throw StateError('Company profile is required');
    }

    return LeavePolicyService.generatePdf(
      policy,
      companyName: companyName,
      companyId: companyId,
    );
  }

  Future<void> _downloadPolicyPdf(Map<String, dynamic> policy) async {
    try {
      final bytes = await _generatePolicyPdf(policy);
      final name = LeavePolicyService.safeFileName(
        (policy['policyName'] ?? 'leave_policy').toString(),
      );
      final saved = await LeavePolicyService.downloadPdf(bytes, name);
      if (saved && mounted) {
        FlashySnackBar.show(context, message: 'policy_pdf_saved'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  Future<void> _sharePolicyPdf(Map<String, dynamic> policy) async {
    try {
      final bytes = await _generatePolicyPdf(policy);
      final dir = await getTemporaryDirectory();
      final name = LeavePolicyService.safeFileName(
        (policy['policyName'] ?? 'leave_policy').toString(),
      );
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
      );
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  /// Generates the policy PDF and uploads it to Firebase Storage, returning
  /// the public HTTPS download URL. Only this URL is shared (WhatsApp, email,
  /// copy link) so recipients open the real PDF in their browser — never a
  /// local device path.
  Future<String> _uploadPolicyPdfToStorage(Map<String, dynamic> policy) async {
    final bytes = await _generatePolicyPdf(policy);
    final name = LeavePolicyService.safeFileName(
      (policy['policyName'] ?? 'leave_policy').toString(),
    );
    final results = await UploadService.uploadFiles(
      files: [
        UploadFile(
          folder: 'leave_policy',
          fileName: name,
          bytes: bytes,
          mimeType: 'application/pdf',
        ),
      ],
    );
    final result = results.isNotEmpty ? results.first : null;
    if (result == null || !result.isSuccess || result.url == null) {
      throw StateError(result?.error ?? 'Failed to upload leave policy PDF');
    }
    return result.url!;
  }

  /// Uploads the policy PDF while showing a brief progress dialog and returns
  /// its public HTTPS link.
  Future<String> _preparePolicyPdfLink(Map<String, dynamic> policy) async {
    if (!mounted) throw StateError('Screen is no longer mounted');
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'PreparingPolicyPdf',
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            elevation: 8,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'preparing_policy_pdf'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final url = await _uploadPolicyPdfToStorage(policy);
      if (mounted) navigator.pop();
      return url;
    } catch (_) {
      if (mounted) navigator.pop();
      rethrow;
    }
  }

  Future<void> _sharePolicyToWhatsApp(
    Map<String, dynamic> policy,
    String text,
  ) async {
    try {
      final url = await _preparePolicyPdfLink(policy);
      final message = '$text\n\n$url';
      final uri = Uri.parse(
        'whatsapp://send?text=${Uri.encodeComponent(message)}',
      );
      final launched = await canLaunchUrl(uri);
      if (launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await SharePlus.instance.share(ShareParams(text: message));
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  Future<void> _sharePolicyToEmail(
    Map<String, dynamic> policy,
    String text,
  ) async {
    try {
      final url = await _preparePolicyPdfLink(policy);
      final body = '$text\n\n$url';
      final subject = Uri.encodeComponent('Leave Policy');
      final uri = Uri.parse(
        'mailto:?subject=$subject&body=${Uri.encodeComponent(body)}',
      );
      final launched = await canLaunchUrl(uri);
      if (launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await SharePlus.instance.share(
          ShareParams(text: body, subject: 'Leave Policy'),
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  /// Uploads the policy PDF to Firebase Storage and copies the public HTTPS
  /// download link (never a local file path) to the clipboard.
  Future<void> _copyPolicyLink(Map<String, dynamic> policy) async {
    try {
      final url = await _preparePolicyPdfLink(policy);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        FlashySnackBar.show(context, message: 'policy_link_copied'.tr());
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: e.toString(), isError: true);
      }
    }
  }

  Widget _buildLeavePolicySettingItem() {
    final hasPolicy = _currentLeavePolicy != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: widget.isGuest ? 0.4 : 1,
            child: SvgPicture.asset(
              'assets/leave.svg',
              width: 24,
              height: 24,
              colorMapper: const SvgFillColorMapper(
                source: Color(0xFFFF7B00),
                replacement: Color(0xFF000000),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'leave_policy'.tr(),
              style: TextStyle(
                fontSize: 16,
                color: widget.isGuest
                    ? const Color(0xFFAAAAAA)
                    : const Color(0xFF000000),
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
          if (hasPolicy) ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.isGuest
                    ? null
                    : () => _showLeavePolicyListDialog(
                        editPolicy: _currentLeavePolicy,
                      ),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isGuest
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'view_policy'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
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
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.isGuest
                    ? null
                    : () => _sharePolicy(_currentLeavePolicy!),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isGuest
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.isGuest
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF0247C4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: widget.isGuest
                            ? const Color(0xFFAAAAAA)
                            : const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'share_policy'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.isGuest
                              ? const Color(0xFFAAAAAA)
                              : const Color(0xFF3B82F6),
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
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.isGuest ? null : _showDeletePolicyDialog,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isGuest
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.isGuest
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFFEF4444),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/delete_icon.svg',
                        width: 16,
                        height: 16,
                        colorFilter: ColorFilter.mode(
                          widget.isGuest
                              ? const Color(0xFFAAAAAA)
                              : const Color(0xFFEF4444),
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'delete_policy'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.isGuest
                              ? const Color(0xFFAAAAAA)
                              : const Color(0xFFEF4444),
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
          if (!hasPolicy)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.isGuest
                    ? null
                    : () => _showLeavePolicyListDialog(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isGuest
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add,
                        size: 18,
                        color: widget.isGuest
                            ? const Color(0xFFAAAAAA)
                            : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'add_policy'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.isGuest
                              ? const Color(0xFFAAAAAA)
                              : Colors.white,
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

  Future<void> _showDeletePolicyDialog() async {
    final confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeletePolicyDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
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
                          'delete_policy'.tr(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'delete_policy_confirm'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w400,
                            fontFamily: 'SF Pro Display',
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () =>
                                      Navigator.pop(dialogContext, false),
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
                                  onTap: () =>
                                      Navigator.pop(dialogContext, true),
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
                                      'delete'.tr(),
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
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    try {
      await _firestore.deleteLeavePolicy(_currentLeavePolicy?['id']);
      if (!mounted) return;
      setState(() => _currentLeavePolicy = null);
      FlashySnackBar.show(context, message: 'policy_deleted_success'.tr());
    } catch (e) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'failed_to_delete_policy'.tr(
          namedArgs: {'error': e.toString()},
        ),
        isError: true,
      );
    }
  }

  Widget _buildSimpleSettingItem(
    String iconPath,
    String text, {
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
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

class _AddLeavePolicyDialog extends StatefulWidget {
  const _AddLeavePolicyDialog({this.onSaved, this.editPolicy});

  final VoidCallback? onSaved;
  final Map<String, dynamic>? editPolicy;

  @override
  State<_AddLeavePolicyDialog> createState() => _AddLeavePolicyDialogState();
}

class _AddLeavePolicyDialogState extends State<_AddLeavePolicyDialog> {
  static const Color _textDark = Color(0xFF111827);
  static const Color _textGrey = Color(0xFF6B7280);
  static const Color _borderLight = Color(0xFFE5E7EB);
  static const Color _primaryBlue = Color(0xFF0247C4);
  static const Color _bgLight = Color(0xFFF9FAFB);

  late final TextEditingController _policyNameController;
  late final TextEditingController _sickLeaveController;
  late final TextEditingController _casualLeaveController;
  late final TextEditingController _medicalLeaveController;
  late final TextEditingController _notesController;
  DateTime _effectiveFromDate = DateTime(2026, 1, 1);
  DateTime _leaveYearDate = DateTime(2026, 1, 1);
  final String _applyTo = 'All Workers';
  bool _isSaving = false;
  bool _isFullyEditable = false;
  bool get _isEditing => widget.editPolicy != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final p = widget.editPolicy!;
      _policyNameController = TextEditingController(
        text: (p['policyName'] ?? '').toString(),
      );
      _sickLeaveController = TextEditingController(
        text: (p['sickLeaves'] ?? '0').toString(),
      );
      _casualLeaveController = TextEditingController(
        text: (p['casualLeaves'] ?? '0').toString(),
      );
      _medicalLeaveController = TextEditingController(
        text: (p['medicalLeaves'] ?? '0').toString(),
      );
      _notesController = TextEditingController(
        text: (p['description'] ?? '').toString(),
      );
      if (p['startDate'] != null) {
        try {
          _effectiveFromDate = DateTime.parse(p['startDate'].toString());
        } catch (_) {}
      }
    } else {
      _policyNameController = TextEditingController(
        text: 'Standard Leave Policy 2026',
      );
      _sickLeaveController = TextEditingController(text: '8');
      _casualLeaveController = TextEditingController(text: '10');
      _medicalLeaveController = TextEditingController(text: '7');
      _notesController = TextEditingController(
        text:
            'Leave will be counted on working days only. Company holidays and weekly off days are excluded.',
      );
    }
  }

  int get _totalDays {
    final sick = int.tryParse(_sickLeaveController.text.trim()) ?? 0;
    final casual = int.tryParse(_casualLeaveController.text.trim()) ?? 0;
    final medical = int.tryParse(_medicalLeaveController.text.trim()) ?? 0;
    return sick + casual + medical;
  }

  @override
  void dispose() {
    _policyNameController.dispose();
    _sickLeaveController.dispose();
    _casualLeaveController.dispose();
    _medicalLeaveController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatYearRange(DateTime date) {
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[date.month - 1]} - Dec ${date.year}';
  }

  void _showCupertinoDatePicker({
    required DateTime initialDate,
    required void Function(DateTime) onDateSelected,
  }) {
    DateTime selected = initialDate;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Date Picker',
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              child: Center(
                child: StatefulBuilder(
                  builder: (_, setPickerState) {
                    return Container(
                      width: 380,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0247C4,
                            ).withValues(alpha: 0.18),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.calendar,
                                  size: 20,
                                  color: _primaryBlue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'select_date'.tr(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _textDark,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: CupertinoDatePicker(
                              mode: CupertinoDatePickerMode.date,
                              initialDateTime: initialDate,
                              minimumDate: DateTime(2020),
                              maximumDate: DateTime(2100),
                              onDateTimeChanged: (DateTime newDate) {
                                setPickerState(() {
                                  selected = newDate;
                                });
                              },
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'cancel'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF374151),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      onDateSelected(selected);
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _primaryBlue,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'done'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _savePolicy() async {
    if (_isSaving) return;

    final policyName = _policyNameController.text.trim();
    if (policyName.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_policy_name'.tr(),
        isError: true,
      );
      return;
    }

    final annualLeaveDays = _totalDays;
    if (annualLeaveDays <= 0) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_days'.tr(),
        isError: true,
      );
      return;
    }
    if (annualLeaveDays > 366) {
      FlashySnackBar.show(
        context,
        message: 'max_days_limit_reached'.tr(namedArgs: {'limit': '366'}),
        isError: true,
      );
      return;
    }

    final sickDays = int.tryParse(_sickLeaveController.text.trim()) ?? 0;
    final casualDays = int.tryParse(_casualLeaveController.text.trim()) ?? 0;
    final medicalDays = int.tryParse(_medicalLeaveController.text.trim()) ?? 0;

    setState(() => _isSaving = true);

    try {
      final firestore = Provider.of<FirestoreService>(context, listen: false);

      final policyData = <String, dynamic>{
        'policyName': policyName,
        'annualLeaveDays': annualLeaveDays,
        'sickLeaves': sickDays.toString(),
        'casualLeaves': casualDays.toString(),
        'medicalLeaves': medicalDays.toString(),
        'startDate': _effectiveFromDate.toIso8601String(),
        'leaveYear': _formatYearRange(_leaveYearDate),
        'applicableTo': _applyTo,
        'description': _notesController.text.trim(),
      };

      // Fetch all workers and their active time-off records BEFORE saving the
      // policy so we can compute each worker's already-used paid days. This
      // prevents a policy edit from silently restoring used leave.
      final workersSnapshot = await firestore.getWorkersOnce();
      final workers = workersSnapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
      final timeOffRecords = await firestore.getTimeoffOnce();

      // Apply the policy to all workers in controlled Firestore batches
      // (450 writes per batch). This avoids a partially applied policy when a
      // network failure occurs mid-way through a large company.
      final updatedCount = await firestore.applyLeavePolicyToWorkers(
        workers: workers,
        annualLeaveDays: annualLeaveDays,
        policyName: policyName,
        timeOffRecords: timeOffRecords,
      );

      // Only persist the policy document after all worker batches succeeded.
      // This keeps the policy and worker allowances consistent.
      if (_isEditing) {
        await firestore.updateLeavePolicy(widget.editPolicy!['id'], policyData);
      } else {
        await firestore.addLeavePolicy(policyData);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved?.call();
        FlashySnackBar.show(
          context,
          message:
              (_isEditing
                      ? 'policy_updated_applied'
                      : 'leave_policy_saved_applied')
                  .tr(namedArgs: {'count': updatedCount.toString()}),
          title: 'Success',
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_save_leave_policy'.tr(
            namedArgs: {'error': e.toString()},
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('policy_name'.tr()),
                      const SizedBox(height: 8),
                      _buildTextField(
                        _policyNameController,
                        enabled: !_isEditing || _isFullyEditable,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('effective_from'.tr()),
                                const SizedBox(height: 8),
                                _buildDateField(
                                  _formatDate(_effectiveFromDate),
                                  prefixIcon: Icons.calendar_month_rounded,
                                  enabled: !_isEditing || _isFullyEditable,
                                  onTap: () => _showCupertinoDatePicker(
                                    initialDate: _effectiveFromDate,
                                    onDateSelected: (date) => setState(
                                      () => _effectiveFromDate = date,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle('leave_year'.tr()),
                                const SizedBox(height: 8),
                                _buildDateField(
                                  _formatYearRange(_leaveYearDate),
                                  enabled: !_isEditing || _isFullyEditable,
                                  onTap: () => _showCupertinoDatePicker(
                                    initialDate: _leaveYearDate,
                                    onDateSelected: (date) =>
                                        setState(() => _leaveYearDate = date),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'leave_types_entitlements'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textDark,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'set_days_for_leave_types'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          color: _textGrey,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLeaveTypeField(
                        'sick_leave_title'.tr(),
                        _sickLeaveController,
                        Icons.sick_outlined,
                        enabled: !_isEditing || _isFullyEditable,
                      ),
                      const SizedBox(height: 12),
                      _buildLeaveTypeField(
                        'casual_leave_title'.tr(),
                        _casualLeaveController,
                        Icons.weekend_outlined,
                        enabled: !_isEditing || _isFullyEditable,
                      ),
                      const SizedBox(height: 12),
                      _buildLeaveTypeField(
                        'medical_leave_title'.tr(),
                        _medicalLeaveController,
                        Icons.medical_services_outlined,
                        enabled: !_isEditing || _isFullyEditable,
                      ),
                      const SizedBox(height: 24),
                      _buildTotalLeavesBox(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('apply_to'.tr()),
                      const SizedBox(height: 8),
                      _buildReadonlyField(
                        'all_workers'.tr(),
                        prefixIcon: Icons.people_outline,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'applied_to_all_workers'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _textGrey,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'all_leave_types_deducted'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _textGrey,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('policy_notes_optional'.tr()),
                      const SizedBox(height: 8),
                      _buildLargeTextField(
                        _notesController,
                        enabled: !_isEditing || _isFullyEditable,
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: Text(
              widget.editPolicy?['policyName'] ?? 'view_policy'.tr(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textDark,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          if (!_isFullyEditable)
            GestureDetector(
              onTap: () => setState(() => _isFullyEditable = true),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgPicture.asset(
                  'assets/edit_icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF0247C4),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'add_leave_policy'.tr(),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _textDark,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'create_leave_policy_desc'.tr(),
          style: TextStyle(
            fontSize: 13,
            color: _textGrey,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _textDark,
        fontFamily: 'SF Pro Display',
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: TextStyle(
        fontSize: 14,
        color: _textDark,
        fontFamily: 'SF Pro Display',
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryBlue),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderLight),
        ),
        fillColor: enabled ? null : _bgLight,
        filled: !enabled,
      ),
    );
  }

  Widget _buildLargeTextField(
    TextEditingController controller, {
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      maxLines: 5,
      enabled: enabled,
      style: TextStyle(
        fontSize: 13,
        color: _textDark,
        height: 1.5,
        fontFamily: 'SF Pro Display',
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryBlue),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _borderLight),
        ),
        fillColor: enabled ? null : _bgLight,
        filled: !enabled,
      ),
    );
  }

  Widget _buildDateField(
    String text, {
    IconData? prefixIcon,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: enabled ? null : _bgLight,
            border: Border.all(color: _borderLight),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(
                  prefixIcon,
                  size: 18,
                  color: enabled ? _textGrey : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: enabled ? _textDark : const Color(0xFF9CA3AF),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: enabled ? _textGrey : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadonlyField(String text, {IconData? prefixIcon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bgLight,
        border: Border.all(color: _borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (prefixIcon != null) ...[
            Icon(prefixIcon, size: 18, color: _textGrey),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: _textDark,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          const Icon(Icons.lock_outline, size: 16, color: _textGrey),
        ],
      ),
    );
  }

  Widget _buildLeaveTypeField(
    String title,
    TextEditingController controller,
    IconData icon, {
    bool enabled = true,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE5EEFC),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(child: Icon(icon, size: 20, color: _primaryBlue)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _textDark,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            enabled: enabled,
            style: TextStyle(
              fontSize: 14,
              color: _textDark,
              fontFamily: 'SF Pro Display',
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _primaryBlue),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _borderLight),
              ),
              fillColor: enabled ? null : _bgLight,
              filled: !enabled,
              suffixText: 'days',
              suffixStyle: TextStyle(
                fontSize: 12,
                color: _textGrey,
                fontFamily: 'SF Pro Display',
              ),
            ),
            onChanged: (value) {
              setState(() {});
              if (value.isEmpty) return;
              final total = _totalDays;
              if (total > 366) {
                final current = int.tryParse(value) ?? 0;
                final others = total - current;
                final maxAllowed = 366 - others;
                if (maxAllowed <= 0) {
                  controller.clear();
                } else {
                  controller.text = maxAllowed.toString();
                  controller.selection = TextSelection.collapsed(
                    offset: controller.text.length,
                  );
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTotalLeavesBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: _bgLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'total_annual_leaves'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _textDark,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'sick_casual_medical'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: _textGrey,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          Text(
            '$_totalDays days',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _textDark,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canSave = !_isEditing || _isFullyEditable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderLight, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 44,
            width: 100,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _borderLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'cancel'.tr(),
                style: TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 44,
            width: 150,
            child: ElevatedButton(
              onPressed: _isSaving || !canSave ? null : _savePolicy,
              style: ElevatedButton.styleFrom(
                backgroundColor: canSave
                    ? _primaryBlue
                    : const Color(0xFFD1D5DB),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _isEditing ? 'save_changes'.tr() : 'save_policy'.tr(),
                      style: TextStyle(
                        color: canSave ? Colors.white : const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
