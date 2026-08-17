import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers.dart';
import '../screens/auth/login_screen.dart';
import '../screens/general/pricing_screen.dart';
import '../services/preferences_service.dart';

Widget _blurDialogTransition(
  Animation<double> animation,
  Widget child,
) {
  final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
  return Stack(
    fit: StackFit.expand,
    children: [
      BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10 * animation.value,
          sigmaY: 10 * animation.value,
        ),
        child: Container(
          color: const Color(0xFF0F172A).withValues(alpha: 0.35 * animation.value),
        ),
      ),
      FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curve, child: child),
      ),
    ],
  );
}

Future<void> showLogoutDialog(BuildContext context) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'LogoutDialog',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        _blurDialogTransition(animation, const _LogoutDialogContent()),
  );

  if (confirmed == true) {
    try {
      if (!context.mounted) return;
      final container = ProviderScope.containerOf(context);
      await container.read(authServiceProvider).signOut(preserveBiometricLogin: true);
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('unable_to_sign_out'.tr()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _LogoutDialogContent extends StatelessWidget {
  const _LogoutDialogContent();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF1F2), Color(0xFFFFE4E6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFE11D48),
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'sign_out_dialog_title'.tr(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  fontFamily: 'SF Pro Display',
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'sign_out_dialog_desc'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF475569),
                  fontFamily: 'SF Pro Display',
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(8),
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
                          'sign_out'.tr(),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeleteDialog {
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String content,
    String confirmButtonText = 'delete',
  }) async {
    final resolvedConfirmText = confirmButtonText.tr();
    final confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DeleteDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return _DeleteDialogInner(
          animation: animation,
          curve: curve,
          title: title,
          content: content,
          resolvedConfirmText: resolvedConfirmText,
        );
      },
    );
    return confirm ?? false;
  }
}

class _DeleteDialogInner extends StatefulWidget {
  const _DeleteDialogInner({
    required this.animation,
    required this.curve,
    required this.title,
    required this.content,
    required this.resolvedConfirmText,
  });

  final Animation<double> animation;
  final Animation<double> curve;
  final String title;
  final String content;
  final String resolvedConfirmText;

  @override
  State<_DeleteDialogInner> createState() => _DeleteDialogInnerState();
}

class _DeleteDialogInnerState extends State<_DeleteDialogInner> {
  bool _tapped = false;

  void _popWith(bool result) {
    if (_tapped) return;
    _tapped = true;
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10 * widget.animation.value,
            sigmaY: 10 * widget.animation.value,
          ),
          child: Container(
            color: const Color(0xFF0F172A).withValues(alpha: 0.35 * widget.animation.value),
          ),
        ),
        FadeTransition(
          opacity: widget.animation,
          child: ScaleTransition(
            scale: widget.curve,
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
                    color: const Color(0xFF000000).withValues(alpha: 0.15),
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
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.content,
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
                        child: GestureDetector(
                          onTap: () => _popWith(false),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
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
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _popWith(true),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
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
                              widget.resolvedConfirmText,
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
  }
}
void showGuestRestrictionDialog(BuildContext context) {
  final authService = ProviderScope.containerOf(
    context,
  ).read(authServiceProvider);

  showDialog(
    context: context,
    barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 32),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF4C84E0),
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'guest_feature_locked'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'guest_feature_desc'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF6B7280),
                  fontFamily: 'SF Pro Display',
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0247C4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await authService.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  child: Text(
                    'sign_in'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'cancel'.tr(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
class PremiumGate {
  static const int freeEntryLimit = 2;

  static bool canAddEntry({
    required int currentEntryCount,
    required bool isPremium,
    required bool isGuest,
  }) {
    if (isGuest) return true;
    if (isPremium) return true;
    return currentEntryCount < freeEntryLimit;
  }

  static Future<bool> shouldShowUpgradeDialog(BuildContext context) async {
    final isGuest =
        ProviderScope.containerOf(
          context,
        ).read(authServiceProvider).currentUser?.isAnonymous ??
        false;
    if (isGuest) return false;
    final isPremium = await PreferencesService.isPremium();
    if (isPremium) return false;

    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (context) => const SubscriptionDialog(),
      );
    }
    return false;
  }
}
Future<bool> tryShowFirstMilestoneRateUs(String milestone) async {
  if (await PreferencesService.getRateUsNeverShow()) return false;
  bool alreadyTriggered;
  Future<void> Function() markTriggered;
  switch (milestone) {
    case 'expense':
      alreadyTriggered = await PreferencesService.wasFirstExpenseTriggered();
      markTriggered = PreferencesService.markFirstExpenseTriggered;
      break;
    case 'worker':
      alreadyTriggered = await PreferencesService.wasFirstWorkerTriggered();
      markTriggered = PreferencesService.markFirstWorkerTriggered;
      break;
    case 'holiday':
      alreadyTriggered = await PreferencesService.wasFirstHolidayTriggered();
      markTriggered = PreferencesService.markFirstHolidayTriggered;
      break;
    case 'bulk_worker':
      alreadyTriggered = await PreferencesService.wasFirstBulkWorkerTriggered();
      markTriggered = PreferencesService.markFirstBulkWorkerTriggered;
      break;
    case 'asset':
      alreadyTriggered = await PreferencesService.wasFirstAssetTriggered();
      markTriggered = PreferencesService.markFirstAssetTriggered;
      break;
    default:
      return false;
  }

  if (alreadyTriggered) return false;

  await markTriggered();
  await _requestReview();
  return true;
}

Future<void> _requestReview() async {
  await PreferencesService.setRateUsNeverShow(true);
  try {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
    } else {
      await launchUrl(
        Uri.parse(
          'https://apps.apple.com/app/hrms-workforce-manager/id6743024022',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {}
}
class FlashySnackBar {
  static OverlayEntry? _currentEntry;
  static bool _currentIsLoading = false;
  static String? _lastMessageKey;
  static DateTime? _lastMessageTime;

  static const Duration _duplicateWindow = Duration(milliseconds: 700);

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    bool isError = false,
    bool isLoading = false,
    int? maxLines = 3,
    Duration displayDuration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    final routeName = ModalRoute.of(context)?.settings.name;
    final messageKey = '$isError:$isLoading:$title:$message:${routeName ?? ''}';
    final now = DateTime.now();
    final isDuplicate =
        _lastMessageKey == messageKey &&
        _lastMessageTime != null &&
        now.difference(_lastMessageTime!) < _duplicateWindow;

    if (isDuplicate) return;

    _lastMessageKey = messageKey;
    _lastMessageTime = now;

    if (_currentEntry != null && _currentEntry!.mounted) {
      _currentEntry!.remove();
    }
    _currentEntry = null;

    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlashySnackBarBody(
        message: message,
        title: title,
        isError: isError,
        isLoading: isLoading,
        maxLines: maxLines,
        onDismiss: () {
          if (entry.mounted) {
            _currentEntry = null;
            entry.remove();
          }
        },
      ),
    );

    _currentEntry = entry;
    _currentIsLoading = isLoading;
    overlay.insert(entry);

    // Loading toasts stay visible (replaced by the next toast) so the user
    // sees continuous progress during long operations.
    if (!isLoading) {
      Future.delayed(displayDuration, () {
        if (entry.mounted) {
          if (_currentEntry == entry) _currentEntry = null;
          entry.remove();
        }
      });
    }
  }

  /// Removes the currently visible toast if it is still a loading toast.
  /// Safe to call after an operation ends early; a success/error toast that
  /// replaced the loading one is left untouched.
  static void dismiss() {
    if (!_currentIsLoading) return;
    final entry = _currentEntry;
    if (entry != null && entry.mounted) {
      _currentEntry = null;
      entry.remove();
    }
  }
}

class _FlashySnackBarBody extends StatefulWidget {
  final String message;
  final String? title;
  final bool isError;
  final bool isLoading;
  final int? maxLines;
  final VoidCallback onDismiss;

  const _FlashySnackBarBody({
    required this.message,
    this.title,
    required this.isError,
    this.isLoading = false,
    required this.maxLines,
    required this.onDismiss,
  });

  @override
  State<_FlashySnackBarBody> createState() => _FlashySnackBarBodyState();
}

class _FlashySnackBarBodyState extends State<_FlashySnackBarBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isError
                        ? [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]
                        : [const Color(0xFF0247C4), const Color(0xFF4A7FE0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (widget.isError
                                  ? const Color(0xFFFF4B2B)
                                  : const Color(0xFF0247C4))
                              .withValues(alpha: 0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFFFFFFFF),
                              ),
                            )
                          : widget.isError
                              ? const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFFFFFFF),
                                  size: 22,
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFFFFFFFF),
                                  size: 22,
                                ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ??
                                (widget.isError
                                    ? 'error_title'.tr()
                                    : widget.isLoading
                                    ? 'loading'.tr()
                                    : 'success'.tr()),
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            softWrap: true,
                            maxLines: widget.maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

PageRoute<T> noTransitionRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

PageRoute<T> authTransitionRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class SvgFillColorMapper extends ColorMapper {
  const SvgFillColorMapper({required this.source, required this.replacement});

  final Color source;
  final Color replacement;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == source ? replacement : color;
  }

  @override
  bool operator ==(Object other) =>
      other is SvgFillColorMapper &&
      other.source == source &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(source, replacement);
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final cleanText = newValue.text.replaceAll(',', '');
    final parts = cleanText.split('.');
    if (parts.length > 2) return oldValue;
    if (parts.length == 2 && parts[1].length > 2) return oldValue;

    final rawInteger = parts[0];
    if (rawInteger.length > 12) return oldValue;

    String formattedInteger = '';
    if (rawInteger.isNotEmpty) {
      final parsed = int.tryParse(rawInteger);
      if (parsed == null) return oldValue;
      formattedInteger = NumberFormat('#,##0', 'en_US').format(parsed);
    }

    final formatted = parts.length > 1 ? '$formattedInteger.${parts[1]}' : formattedInteger;
    final charsFromEnd = newValue.text.length - newValue.selection.end;
    final selectionIndex = (formatted.length - charsFromEnd).clamp(0, formatted.length);

    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: selectionIndex));
  }
}
