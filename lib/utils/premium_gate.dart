import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../screens/pricing_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';

class PremiumGate {
  static const int freeEntryLimit = 2;

  static bool _isShowingDialog = false;

  static bool canAddEntry({
    required int currentEntryCount,
    required bool isPremium,
    required bool isGuest,
  }) {
    // Guests are NOT allowed to add entries - they must login first
    if (isGuest) return false;
    if (isPremium) return true;
    return currentEntryCount < freeEntryLimit;
  }

  static Future<bool> shouldShowUpgradeDialog(BuildContext context) async {
    // Guest users: redirect to login screen instead of showing upgrade dialog
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
          (route) => false,
        );
      }
      return false;
    }
    final isPremium = await PreferencesService.isPremium();
    if (isPremium) return false;
    if (_isShowingDialog) return false;

    _isShowingDialog = true;
    try {
      if (!context.mounted) return false;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (_) => const SubscriptionDialog(),
      );

      return result ?? false;
    } finally {
      _isShowingDialog = false;
    }
  }
}