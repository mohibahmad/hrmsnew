import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
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
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: 12 * widget.animation.value,
        sigmaY: 12 * widget.animation.value,
      ),
      child: FadeTransition(
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
    );
  }
}
