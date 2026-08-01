import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('biometric credentials are stored outside SharedPreferences', () async {
    await PreferencesService.setBiometricCredentials(
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
    await PreferencesService.setBiometricEnabled(true);

    expect(await PreferencesService.getBiometricEmail(), 'owner@example.com');
    expect(
      await PreferencesService.getBiometricPassword(),
      'correct horse battery staple',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('biometric_email'), isNull);
    expect(prefs.getString('biometric_password'), isNull);
  });

  test('normal logout can preserve biometric login', () async {
    await PreferencesService.setBiometricCredentials(
      email: 'owner@example.com',
      password: 'secret',
    );
    await PreferencesService.setBiometricEnabled(true);
    await PreferencesService.setPremium(true);

    await PreferencesService.clear(preserveBiometricCredentials: true);

    expect(await PreferencesService.isPremium(), isFalse);
    expect(await PreferencesService.isBiometricEnabled(), isTrue);
    expect(await PreferencesService.getBiometricEmail(), 'owner@example.com');
    expect(await PreferencesService.getBiometricPassword(), 'secret');
  });

  test('legacy base64 credentials migrate to secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'biometric_email': base64Encode(utf8.encode('legacy@example.com')),
      'biometric_password': base64Encode(utf8.encode('legacy-password')),
      'biometric_enabled': true,
    });

    expect(await PreferencesService.getBiometricEmail(), 'legacy@example.com');
    expect(await PreferencesService.getBiometricPassword(), 'legacy-password');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('biometric_email'), isNull);
    expect(prefs.getString('biometric_password'), isNull);
  });
}
