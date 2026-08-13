import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/preferences_service.dart';
import '../screens/pricing_screen.dart';

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
