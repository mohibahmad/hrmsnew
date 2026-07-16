import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/preferences_service.dart';

/// Shows the Rate Us dialog if eligible (never_show is false AND
/// remind_later hasn't been set or its date has passed).
/// Returns true if the dialog was shown, false otherwise.
Future<void> showRateUsDialogNow(BuildContext context) async {
  if (!context.mounted) return;
  _showRateUsDialog(context);
}

Future<bool> tryShowRateUsDialog(BuildContext context) async {
  final neverShow = await PreferencesService.getRateUsNeverShow();
  if (neverShow) return false;

  final remindLater = await PreferencesService.getRateUsRemindLater();
  if (remindLater != null && DateTime.now().isBefore(remindLater)) return false;

  if (!context.mounted) return false;

  _showRateUsDialog(context);
  return true;
}

Future<bool> tryShowFirstMilestoneRateUs(BuildContext context, String milestone) async {
  final neverShow = await PreferencesService.getRateUsNeverShow();
  if (neverShow) return false;

  final remindLater = await PreferencesService.getRateUsRemindLater();
  if (remindLater != null && DateTime.now().isBefore(remindLater)) return false;

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
    default:
      return false;
  }

  if (alreadyTriggered) return false;

  if (!context.mounted) return false;

  await markTriggered();
  _showRateUsDialog(context);
  return true;
}

void _showRateUsDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'RateUsDialog',
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12 * animation.value,
          sigmaY: 12 * animation.value,
        ),
        child: FadeTransition(
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
                      color: const Color(0xFF000000).withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF7ED),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.star_rounded,
                          color: Color(0xFFF59E0B),
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'rate_us'.tr(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'rate_us_desc'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w400,
                        fontFamily: 'SF Pro Display',
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Stars row
                    const _StarRating(),
                    const SizedBox(height: 28),
                    // Rate Now button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          final inAppReview = InAppReview.instance;
                          if (await inAppReview.isAvailable()) {
                            await inAppReview.requestReview();
                          } else {
                            await launchUrl(
                              Uri.parse(
                                'https://apps.apple.com/app/hrms-workforce-manager/id6743024022',
                              ),
                            );
                          }
                          await PreferencesService.setRateUsNeverShow(true);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            'rate_now'.tr(),
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
                    const SizedBox(height: 12),
                    // Remind me later
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await PreferencesService.setRateUsRemindLater();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'remind_me_later'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF000000),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Never show again text button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await PreferencesService.setRateUsNeverShow(true);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'never_show_again'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _StarRating extends StatefulWidget {
  const _StarRating();

  @override
  State<_StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<_StarRating> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _rating = index + 1;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                index < _rating ? Icons.star : Icons.star_border,
                color: const Color(0xFFF59E0B),
                size: 40,
              ),
            ),
          ),
        );
      }),
    );
  }
}
