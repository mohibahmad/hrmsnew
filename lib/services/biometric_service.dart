import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Represents the result of a biometric authentication attempt.
enum BiometricAuthResult {
  /// Authentication succeeded (biometric or device fallback).
  success,

  /// User cancelled the biometric prompt (tapped Cancel / swiped away).
  /// If the user tapped "Use Password" and then succeeded, [success] is
  /// returned instead. If they cancelled the password prompt, [cancelled]
  /// is returned.
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
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e) {
      debugPrint('Biometric support check failed: $e');
      return false;
    }
  }

  static Future<bool> isAvailable() async {
    try {
      if (!await isSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
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

  /// Authenticates using biometrics and returns a detailed result.
  ///
  /// In local_auth 3.x:
  /// - Returns `true`  → user authenticated successfully (biometric or fallback).
  /// - Returns `false` → user cancelled (tapped Cancel / swiped away) — no exception thrown.
  /// - Throws `LocalAuthException` → real error (locked out, not available, etc.).
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

      // `true`  = success.
      // `false` = user cancelled the prompt (no exception is thrown).
      if (authenticated) return BiometricAuthResult.success;
      return BiometricAuthResult.cancelled;
    } on LocalAuthException catch (e) {
      debugPrint(
        'Biometric authentication error: ${e.code} - ${e.description}',
      );

      final code = e.code.name.toLowerCase();

      // --- Lockout ---
      if (code == 'lockedout' ||
          code == 'auth_locked_out' ||
          code == 'too_many_attempts') {
        return BiometricAuthResult.lockedOut;
      }
      if (code == 'permanentlylockedout' ||
          code == 'auth_permanently_locked_out') {
        return BiometricAuthResult.permanentlyLockedOut;
      }

      // --- Not available / not enrolled ---
      if (code == 'notavailable' ||
          code == 'biometrynotavailable' ||
          code == 'biometry_not_available' ||
          code == 'notenrolled' ||
          code == 'biometrynotenrolled' ||
          code == 'biometry_not_enrolled' ||
          code == 'passcodenotset' ||
          code == 'passcode_not_set') {
        return BiometricAuthResult.notAvailable;
      }

      // --- Actual failure (wrong fingerprint, etc.) ---
      return BiometricAuthResult.failed;
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return BiometricAuthResult.error;
    }
  }

  static Future<String> getBiometricName() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        return 'Touch ID';
      }
      return 'Fingerprint';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris';
    }
    return 'Biometric';
  }
}
