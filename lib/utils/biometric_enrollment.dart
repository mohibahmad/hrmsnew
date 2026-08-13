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

  if (result == BiometricAuthResult.cancelled) {
    if (context.mounted) _showPasswordHint(context);
    return false;
  }

  if (result != BiometricAuthResult.success) {
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

void _showPasswordHint(BuildContext context) {
  FlashySnackBar.show(
    context,
    message: 'biometric_cancelled_password_hint'.tr(),
  );
}
