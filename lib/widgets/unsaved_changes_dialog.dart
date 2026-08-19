import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class UnsavedChangesDialog {
  static Future<bool> show(BuildContext context) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'UnsavedChangesDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 10 * animation.value,
                sigmaY: 10 * animation.value,
              ),
              child: Container(
                color: const Color(0xFF0F172A).withOpacity(0.35 * animation.value),
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
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withOpacity(0.15),
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
                        'discard_changes'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'unsaved_changes_message'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, false),
                              style: ButtonStyle(
                                elevation: WidgetStateProperty.all(0),
                                backgroundColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                foregroundColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 18)),
                                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                shadowColor: WidgetStateProperty.all(Colors.transparent),
                              ),
                              child: Text(
                                'cancel'.tr(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ButtonStyle(
                                elevation: WidgetStateProperty.all(0),
                                backgroundColor: WidgetStateProperty.all(const Color(0xFFEF4444)),
                                foregroundColor: WidgetStateProperty.all(Colors.white),
                                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 18)),
                                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                shadowColor: WidgetStateProperty.all(Colors.transparent),
                              ),
                              child: Text(
                                'discard'.tr(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
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
    return result ?? false;
  }
}
