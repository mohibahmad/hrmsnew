import 'dart:ui';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/leave_policy_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
import 'leave_policy_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/delete_dialog.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
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

  void _showLeavePolicyListDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      builder: (_) => _LeavePolicyListDialog(firestore: _firestore),
    );
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
                  _buildActionSettingItem(
                    'assets/leave.svg',
                    'leave_policy'.tr(),
                    'add_policy'.tr(),
                    onTap: widget.isGuest
                        ? null
                        : () => _showLeavePolicyListDialog(),
                    disabled: widget.isGuest,
                    preserveIconColors: true,
                    iconColorMapper: const SvgFillColorMapper(
                      source: Color(0xFFFF7B00),
                      replacement: Color(0xFF000000),
                    ),
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
    String iconPath,
    String text,
    String buttonText, {
    VoidCallback? onTap,
    bool disabled = false,
    Color? buttonColor,
    bool showCheckmark = false,
    bool preserveIconColors = false,
    ColorMapper? iconColorMapper,
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
                child: Text(
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

class _LeavePolicyListDialog extends StatefulWidget {
  final FirestoreService firestore;
  const _LeavePolicyListDialog({required this.firestore});

  @override
  State<_LeavePolicyListDialog> createState() => _LeavePolicyListDialogState();
}

class _LeavePolicyListDialogState extends State<_LeavePolicyListDialog> {
  List<Map<String, dynamic>> _policies = [];
  bool _isLoading = true;
  String? _busyPolicyId;

  @override
  void initState() {
    super.initState();
    _loadPolicies();
  }

  void _loadPolicies() {
    widget.firestore.leavePoliciesStream.listen((snap) {
      if (!mounted) return;
      setState(() {
        _policies = snap.docs
            .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
            .toList();
        _isLoading = false;
      });
    });
  }

  Future<Map<String, dynamic>> _companyProfile() async {
    try {
      return await widget.firestore.getUserProfile() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  void _showAddForm() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeavePolicyDialog(
        onSave: (data) async {
          await widget.firestore.addLeavePolicy(data);
        },
      ),
    );
  }

  void _showEditForm(Map<String, dynamic> policy) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeavePolicyDialog(
        existingPolicy: policy,
        onSave: (data) async {
          await widget.firestore.updateLeavePolicy(policy['id'], data);
        },
      ),
    );
  }

  void _viewPolicy(Map<String, dynamic> policy) {
    showDialog(
      context: context,
      builder: (_) => PolicyDetailDialog(policy: policy),
    );
  }

  Future<void> _downloadPolicy(Map<String, dynamic> policy) async {
    final id = (policy['id'] ?? policy['policyName'] ?? '').toString();
    if (_busyPolicyId != null) return;
    setState(() => _busyPolicyId = id);
    try {
      final profile = await _companyProfile();
      final companyName = (profile['businessName'] ?? profile['companyName'])
          ?.toString();
      final bytes = await LeavePolicyService.generatePdf(
        policy,
        companyName: companyName,
        companyId: profile['companyId']?.toString(),
      );
      final saved = await LeavePolicyService.downloadPdf(
        bytes,
        (policy['policyName'] ?? 'company_leave_policy').toString(),
      );
      if (saved && mounted) {
        FlashySnackBar.show(context, message: 'Leave policy PDF downloaded');
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Unable to download leave policy PDF',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyPolicyId = null);
    }
  }

  Future<void> _sharePolicy(Map<String, dynamic> policy) async {
    final id = (policy['id'] ?? policy['policyName'] ?? '').toString();
    if (_busyPolicyId != null) return;
    setState(() => _busyPolicyId = id);
    try {
      final profile = await _companyProfile();
      final companyName = (profile['businessName'] ?? profile['companyName'])
          ?.toString();
      final bytes = await LeavePolicyService.generatePdf(
        policy,
        companyName: companyName,
        companyId: profile['companyId']?.toString(),
      );
      final fileName = LeavePolicyService.safeFileName(
        (policy['policyName'] ?? 'company_leave_policy').toString(),
      );
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: LeavePolicyService.formattedText(
            policy,
            companyName: companyName,
          ),
          subject: (policy['policyName'] ?? 'Company Leave Policy').toString(),
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
          ],
          fileNameOverrides: [fileName],
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Unable to share leave policy',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyPolicyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.policy_outlined,
                      color: Color(0xFF4F46E5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leave Policy',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Manage company leave policies',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _showAddForm,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF4F46E5,
                              ).withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Add Policy',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(
                        color: Color(0xFF4F46E5),
                      ),
                    )
                  : _policies.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.policy_outlined,
                              color: Color(0xFF94A3B8),
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No policies yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Create your first leave policy\nto get started',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                              height: 1.4,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _policies.length,
                      itemBuilder: (context, index) {
                        final p = _policies[index];
                        final isActive = p['isActive'] ?? true;
                        final isBusy =
                            _busyPolicyId ==
                            (p['id'] ?? p['policyName'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : const Color(0xFFFAFBFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFFF1F5F9),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? const Color(0xFFEEF2FF)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.description_outlined,
                                      color: isActive
                                          ? const Color(0xFF4F46E5)
                                          : const Color(0xFF94A3B8),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['policyName'] ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: isActive
                                                ? const Color(0xFF1E293B)
                                                : const Color(0xFF94A3B8),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${p['leaveType'] ?? ''}  \u2022  ${p['allowedLeaves'] ?? ''} days/yr  \u2022  ${p['paidUnpaid'] ?? ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isActive ? 'Active' : 'Disabled',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isActive
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFF94A3B8),
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                height: 1,
                                color: const Color(0xFFF1F5F9),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _actBtn(
                                    'Edit',
                                    Icons.edit_outlined,
                                    () => _showEditForm(p),
                                  ),
                                  _actBtn(
                                    isBusy ? 'Generating…' : 'Download PDF',
                                    Icons.download_outlined,
                                    isBusy ? () {} : () => _downloadPolicy(p),
                                  ),
                                  _actBtn(
                                    'Share',
                                    Icons.share_outlined,
                                    isBusy ? () {} : () => _sharePolicy(p),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actBtn(
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color != null
                ? color.withValues(alpha: 0.06)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
          ),
          margin: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color ?? const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color ?? const Color(0xFF64748B),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
