import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';

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
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) return false;
    final isPremium = await PreferencesService.isPremium();
    if (isPremium) return false;
    return false;
  }
}
