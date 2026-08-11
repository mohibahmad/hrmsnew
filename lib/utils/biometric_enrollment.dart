import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../services/preferences_service.dart';
import 'localization_helper.dart';
import 'snackbar_utils.dart';

Future<bool> offerBiometricLogin({
  required BuildContext context,
  required String email,
  required String password,
}) async {
  final available = await BiometricService.isAvailable();
  if (!available) {
    final supported = await BiometricService.isSupported();
    if (supported && context.mounted) {
      FlashySnackBar.show(
        context,
        message: 'biometric_not_enrolled'.tr(),
        isError: true,
      );
    }
    return false;
  }

  final biometricName = await BiometricService.getBiometricName();
  if (!context.mounted) return false;

  final result = await BiometricService.authenticate(
    localizedReason: 'enable_biometric_signup_reason'.tr(
      namedArgs: {
        'biometric': LocalizationHelper.localizeBiometricName(biometricName),
      },
    ),
  );

  // User cancelled (tapped Cancel / swiped away) – don't show a scary
  // "authentication failed" toast. Suggest the password flow instead.
  if (result == BiometricAuthResult.cancelled) {
    if (context.mounted) _showPasswordHint(context);
    return false;
  }

  if (result != BiometricAuthResult.success) {
    // Determine the right message based on the result type.
    switch (result) {
      case BiometricAuthResult.lockedOut:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_locked_out'.tr(),
            isError: true,
          );
        }
        break;
      case BiometricAuthResult.permanentlyLockedOut:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_permanently_locked_out'.tr(),
            isError: true,
          );
        }
        break;
      case BiometricAuthResult.notAvailable:
        if (context.mounted) {
          FlashySnackBar.show(
            context,
            message: 'biometric_not_enrolled'.tr(),
            isError: true,
          );
        }
        break;
      default:
        // generic failure / any cancel-mapped case → just suggest the password
        // flow instead of the harsh "Authentication failed".
        if (context.mounted) _showPasswordHint(context);
    }
    return false;
  }

  try {
    await PreferencesService.setBiometricCredentials(
      email: email,
      password: password,
    );
    await PreferencesService.setBiometricEnabled(true);
  } catch (_) {
    await PreferencesService.clearBiometricCredentials();
    if (context.mounted) {
      FlashySnackBar.show(
        context,
        message: 'biometric_credentials_not_found'.tr(),
        isError: true,
      );
    }
    return false;
  }

  if (context.mounted) {
    FlashySnackBar.show(
      context,
      title: 'success'.tr(),
      message: 'biometric_enabled_success'.tr(),
    );
  }
  return true;
}

/// Friendly non-error toast shown when the user skips/cancels the biometric
/// prompt, suggesting they sign in with their password instead.
void _showPasswordHint(BuildContext context) {
  FlashySnackBar.show(
    context,
    message: 'biometric_cancelled_password_hint'.tr(),
  );
}
