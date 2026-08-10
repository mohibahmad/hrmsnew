import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class PreferencesService {
  static const String _loggedInKey = 'is_logged_in';
  static const String _guestKey = 'is_guest';
  static const String _premiumKey = 'is_premium';
  static const String _profilePicUrlKey = 'profile_pic_url';
  static const String _profilePicLocalPathKey = 'profile_pic_local_path';
  static const String _companyStampUrlKey = 'company_stamp_url';
  static const String _companyCurrencyKey = 'company_currency';
  static const String _rateUsNeverShowKey = 'rate_us_never_show';
  static const String _rateUsRemindLaterKey = 'rate_us_remind_later';
  static const String _rateUsFirstExpenseKey = 'rate_us_first_expense';
  static const String _rateUsFirstWorkerKey = 'rate_us_first_worker';
  static const String _rateUsFirstHolidayKey = 'rate_us_first_holiday';
  static const String _rateUsFirstBulkWorkerKey = 'rate_us_first_bulk_worker';
  static const String _rateUsFirstAssetKey = 'rate_us_first_asset';
  static const String _companyWorkingDaysKey = 'company_working_days';
  static const String _guestProfileKey = 'guest_profile_data';
  static const String _guestWorkersKey = 'guest_workers_data';
  static const String _guestPayrollKey = 'guest_payroll_data';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricEmailKey = 'biometric_email';
  static const String _biometricPasswordKey = 'biometric_password';
  static const String _sessionLockedKey = 'session_locked';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static String? _cachedProfilePicUrl;
  static String? _cachedCompanyStampUrl;
  static String? _cachedCompanyCurrency;
  static bool _cachedIsGuest = false;
  static bool _cachedIsPremium = false;
  static Directory? _guestDataDir;

  static Future<Directory> _getGuestDataDir() async {
    if (_guestDataDir != null) return _guestDataDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _guestDataDir = await Directory(
      '${appDir.path}/guest_data',
    ).create(recursive: true);
    return _guestDataDir!;
  }

  static const String _localImagesDirName = 'company_images';

  static Future<String?> persistImageLocally({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = await Directory(
        '${appDir.path}/$_localImagesDirName',
      ).create(recursive: true);
      final file = File('${imageDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _guestFile(String name) async {
    final dir = await _getGuestDataDir();
    return File('${dir.path}/$name');
  }

  static Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedProfilePicUrl = prefs.getString(_profilePicUrlKey);
    _cachedCompanyStampUrl = prefs.getString(_companyStampUrlKey);
    _cachedCompanyCurrency = prefs.getString(_companyCurrencyKey);
    _cachedIsGuest = prefs.getBool(_guestKey) ?? false;
    _cachedIsPremium = prefs.getBool(_premiumKey) ?? false;

    if ((_cachedCompanyStampUrl == null || _cachedCompanyStampUrl!.isEmpty) &&
        prefs.containsKey(_guestProfileKey)) {
      try {
        final guestData = jsonDecode(prefs.getString(_guestProfileKey) ?? '{}');
        final stampFromGuest =
            (guestData['companyStampUrl'] ?? guestData['stampUrl'])
                ?.toString()
                .trim();
        if (stampFromGuest != null && stampFromGuest.isNotEmpty) {
          _cachedCompanyStampUrl = stampFromGuest;
        }
      } catch (_) {}
    }
  }

  static String? get cachedProfilePicUrl => _cachedProfilePicUrl;
  static String? get cachedCompanyStampUrl => _cachedCompanyStampUrl;
  static String? get cachedCompanyCurrency => _cachedCompanyCurrency;
  static bool get cachedIsGuest => _cachedIsGuest;

  static bool get cachedIsPremium => _cachedIsPremium;

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  static Future<void> setGuest(bool value) async {
    _cachedIsGuest = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestKey, value);
  }

  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedIsGuest = prefs.getBool(_guestKey) ?? false;
    return _cachedIsGuest;
  }

  static Future<void> setPremium(bool value) async {
    _cachedIsPremium = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, value);
  }

  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_premiumKey) ?? false;
  }

  static Future<Set<int>> getCompanyWorkingDays() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_companyWorkingDaysKey);
    if (saved == null) return {1, 2, 3, 4, 5};
    final days = saved
        .map(int.tryParse)
        .whereType<int>()
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
    return days.isEmpty ? {1, 2, 3, 4, 5} : days;
  }

  static Future<void> setCompanyWorkingDays(Iterable<int> weekdays) async {
    final days =
        weekdays
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList()
          ..sort();
    if (days.isEmpty) {
      throw ArgumentError('At least one company working day is required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _companyWorkingDaysKey,
      days.map((day) => day.toString()).toList(),
    );
  }

  static Future<void> setGuestProfileData(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guestProfileKey, jsonEncode(data));
  }

  static Future<Map<String, String>?> getGuestProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestProfileKey);
    if (raw == null || raw.isEmpty) return null;
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<List<Map<String, dynamic>>?> getGuestWorkers() async {
    try {
      final file = await _guestFile('workers.json');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_guestWorkersKey);
      if (raw == null || raw.isEmpty) return null;
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    }
  }

  static Future<void> setGuestPayroll(
    List<Map<String, dynamic>> payroll,
  ) async {
    try {
      final file = await _guestFile('payroll.json');
      await file.writeAsString(jsonEncode(payroll));
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestPayrollKey, jsonEncode(payroll));
    }
  }

  static Future<List<Map<String, dynamic>>?> getGuestPayroll() async {
    try {
      final file = await _guestFile('payroll.json');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_guestPayrollKey);
      if (raw == null || raw.isEmpty) return null;
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    }
  }

  static Future<void> setProfilePicUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_profilePicUrlKey, url);
    } else {
      await prefs.remove(_profilePicUrlKey);
    }

    _cachedProfilePicUrl = url;
    AuthService.profilePicNotifier.value = url;
  }

  static Future<void> setProfilePicLocalPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null && path.isNotEmpty) {
      await prefs.setString(_profilePicLocalPathKey, path);
    } else {
      await prefs.remove(_profilePicLocalPathKey);
    }
  }

  static Future<String?> getProfilePicLocalPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profilePicLocalPathKey);
  }

  static Future<String?> getProfilePicUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_profilePicUrlKey);
    _cachedProfilePicUrl = url;
    return url;
  }

  static Future<void> setCompanyStampUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_companyStampUrlKey, url);
    } else {
      await prefs.remove(_companyStampUrlKey);
    }

    _cachedCompanyStampUrl = url;
    AuthService.companyStampNotifier.value = url;
  }

  static Future<void> setCompanyCurrency(String? currency) async {
    final prefs = await SharedPreferences.getInstance();
    if (currency != null && currency.isNotEmpty) {
      await prefs.setString(_companyCurrencyKey, currency);
    } else {
      await prefs.remove(_companyCurrencyKey);
    }
    _cachedCompanyCurrency = currency;
  }

  static Future<String?> getCompanyCurrency() async {
    if (_cachedCompanyCurrency != null && _cachedCompanyCurrency!.isNotEmpty) {
      return _cachedCompanyCurrency;
    }
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getString(_companyCurrencyKey);
    _cachedCompanyCurrency = c;
    return c;
  }

  static Future<String?> getCompanyStampUrl() async {
    if (_cachedCompanyStampUrl != null && _cachedCompanyStampUrl!.isNotEmpty) {
      return _cachedCompanyStampUrl;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_companyStampUrlKey);
    _cachedCompanyStampUrl = url;
    return url;
  }

  static Future<bool> getRateUsNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rateUsNeverShowKey) ?? false;
  }

  static Future<void> setRateUsNeverShow(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rateUsNeverShowKey, value);
  }

  static Future<DateTime?> getRateUsRemindLater() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_rateUsRemindLaterKey);
    if (timestamp != null) {
      return DateTime.tryParse(timestamp);
    }
    return null;
  }

  static Future<void> setRateUsRemindLater() async {
    final prefs = await SharedPreferences.getInstance();

    final remindDate = DateTime.now().add(const Duration(days: 1));
    await prefs.setString(_rateUsRemindLaterKey, remindDate.toIso8601String());
  }

  static Future<bool> _getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> wasFirstExpenseTriggered() =>
      _getBool(_rateUsFirstExpenseKey);
  static Future<void> markFirstExpenseTriggered() =>
      _setBool(_rateUsFirstExpenseKey, true);

  static Future<bool> wasFirstWorkerTriggered() =>
      _getBool(_rateUsFirstWorkerKey);
  static Future<void> markFirstWorkerTriggered() =>
      _setBool(_rateUsFirstWorkerKey, true);

  static Future<bool> wasFirstHolidayTriggered() =>
      _getBool(_rateUsFirstHolidayKey);
  static Future<void> markFirstHolidayTriggered() =>
      _setBool(_rateUsFirstHolidayKey, true);

  static Future<bool> wasFirstBulkWorkerTriggered() =>
      _getBool(_rateUsFirstBulkWorkerKey);
  static Future<void> markFirstBulkWorkerTriggered() =>
      _setBool(_rateUsFirstBulkWorkerKey, true);

  static Future<bool> wasFirstAssetTriggered() =>
      _getBool(_rateUsFirstAssetKey);
  static Future<void> markFirstAssetTriggered() =>
      _setBool(_rateUsFirstAssetKey, true);

  static Future<bool> isSessionLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sessionLockedKey) ?? false;
  }

  static Future<void> setSessionLocked(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionLockedKey, value);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, value);
  }

  static Future<String?> getBiometricEmail() async {
    return _readBiometricCredential(_biometricEmailKey);
  }

  static Future<void> setBiometricCredentials({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.write(key: _biometricEmailKey, value: email);
      await _secureStorage.write(key: _biometricPasswordKey, value: password);

      await prefs.remove(_biometricEmailKey);
      await prefs.remove(_biometricPasswordKey);
    } catch (_) {
      await _secureStorage.delete(key: _biometricEmailKey);
      await _secureStorage.delete(key: _biometricPasswordKey);
      rethrow;
    }
  }

  static Future<String?> getBiometricPassword() async {
    return _readBiometricCredential(_biometricPasswordKey);
  }

  static Future<String?> _readBiometricCredential(String key) async {
    final securelyStored = await _secureStorage.read(key: key);
    if (securelyStored != null && securelyStored.isNotEmpty) {
      return securelyStored;
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null) return null;

    String value;
    try {
      value = utf8.decode(base64Decode(encoded));
    } catch (_) {
      value = encoded;
    }

    if (value.isEmpty) return null;
    await _secureStorage.write(key: key, value: value);
    await prefs.remove(key);
    return value;
  }

  static Future<void> clearBiometricCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    await prefs.remove(_biometricEmailKey);
    await prefs.remove(_biometricPasswordKey);
    await _secureStorage.delete(key: _biometricEmailKey);
    await _secureStorage.delete(key: _biometricPasswordKey);
  }

  static Future<void> clear({bool preserveBiometricCredentials = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInKey);
    await prefs.remove(_guestKey);
    await prefs.remove(_premiumKey);
    await prefs.remove(_profilePicUrlKey);
    await prefs.remove(_rateUsNeverShowKey);
    await prefs.remove(_rateUsRemindLaterKey);
    await prefs.remove(_rateUsFirstExpenseKey);
    await prefs.remove(_rateUsFirstWorkerKey);
    await prefs.remove(_rateUsFirstHolidayKey);
    await prefs.remove(_rateUsFirstBulkWorkerKey);
    await prefs.remove(_rateUsFirstAssetKey);
    await prefs.remove(_companyWorkingDaysKey);
    await prefs.remove(_sessionLockedKey);
    await prefs.remove(_guestPayrollKey);
    if (!preserveBiometricCredentials) {
      await clearBiometricCredentials();
    }
    _cachedProfilePicUrl = null;
    _cachedIsGuest = false;
    _cachedIsPremium = false;
  }
}
