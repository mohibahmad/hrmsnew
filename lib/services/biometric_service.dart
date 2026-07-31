import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if biometric authentication is available on the device.
  static Future<bool> isAvailable() async {
    try {
      final available = await _auth.canCheckBiometrics;
      if (!available) {
        final deviceSupported = await _auth.isDeviceSupported();
        return deviceSupported;
      }
      return available;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  /// Get the list of available biometric types.
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Failed to get available biometrics: $e');
      return [];
    }
  }

  /// Authenticate the user using biometrics.
  ///
  /// Returns `true` if authentication was successful.
  static Future<bool> authenticate({
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
      return authenticated;
    } on LocalAuthException catch (e) {
      debugPrint(
        'Biometric authentication error: ${e.code} - ${e.description}',
      );
      return false;
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }

  /// Get a user-friendly name for the available biometric type.
  static Future<String> getBiometricName() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris';
    }
    return 'Biometric';
  }
}
