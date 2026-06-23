import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../screens/pricing_screen.dart';
import '../services/auth_service.dart';

class PremiumGate {
  static const int freeEntryLimit = 2;

  static bool _isShowingDialog = false;

  static bool canAddEntry({
    required int currentEntryCount,
    required bool isPremium,
    required bool isGuest,
  }) {
    if (isPremium || isGuest) return true;
    return currentEntryCount < freeEntryLimit;
  }

  static Future<bool> shouldShowUpgradeDialog(BuildContext context) async {
    final isPremium = await PreferencesService.isPremium();
    if (isPremium) return false;
    if (_isShowingDialog) return false;

    _isShowingDialog = true;
    if (!context.mounted) {
      _isShowingDialog = false;
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (_) => const SubscriptionDialog(),
    );

    _isShowingDialog = false;
    return result ?? false;
  }
}
