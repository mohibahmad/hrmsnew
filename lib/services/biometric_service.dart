
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAuthResult {
  success,
  cancelled,
  failed,
  lockedOut,
  permanentlyLockedOut,
  notAvailable,
  error,
}

class BiometricService {

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isSupported() async {
    try {

      final isDeviceSupported = await _auth.isDeviceSupported();
      final canCheckBiometrics = await _auth.canCheckBiometrics;

      return isDeviceSupported && canCheckBiometrics;
    } catch (e) {
      debugPrint('Biometric support check failed: $e');
      return false;
    }
  }

  static Future<bool> isAvailable() async {
    try {

      if (!await isSupported()) return false;

      final biometrics = await _auth.getAvailableBiometrics();

      return biometrics.isNotEmpty;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Failed to get available biometrics: $e');
      return [];
    }
  }

  static Future<BiometricAuthResult> authenticate({
    required String localizedReason,
    bool biometricOnly = true,
    bool persistAcrossBackgrounding = true,
  }) async {
    try {

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: persistAcrossBackgrounding,
      );

      if (authenticated) {
        return BiometricAuthResult.success;
      }
      return BiometricAuthResult.cancelled;
    } on LocalAuthException catch (e) {

      debugPrint('Biometric authentication error: ${e.code} - ${e.description}');

      final code = e.code.name.toLowerCase();

      return switch (code) {
        'lockedout' ||
        'auth_locked_out' ||
        'too_many_attempts' =>
          BiometricAuthResult.lockedOut,
        'permanentlylockedout' ||
        'auth_permanently_locked_out' =>
          BiometricAuthResult.permanentlyLockedOut,
        'notavailable' ||
        'biometrynotavailable' ||
        'biometry_not_available' ||
        'notenrolled' ||
        'biometrynotenrolled' ||
        'biometry_not_enrolled' ||
        'passcodenotset' ||
        'passcode_not_set' =>
          BiometricAuthResult.notAvailable,
        _ => BiometricAuthResult.failed,
      };
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return BiometricAuthResult.error;
    }
  }

  static Future<String> getBiometricName() async {

    final types = await getAvailableBiometrics();

    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    }

    if (types.contains(BiometricType.fingerprint)) {
      final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      return isApple ? 'Touch ID' : 'Fingerprint';
    }

    if (types.contains(BiometricType.iris)) {
      return 'Iris';
    }

    return 'Biometric';
  }
}