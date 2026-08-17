import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class PreferencesService {
  static const String _guestKey = 'is_guest';
  static const String _premiumKey = 'is_premium';
  static const String _profilePicUrlKey = 'profile_pic_url';
  static const String _profilePicLocalPathKey = 'profile_pic_local_path';
  static const String _companyStampUrlKey = 'company_stamp_url';
  static const String _companyCurrencyKey = 'company_currency';
  static const String _rateUsNeverShowKey = 'rate_us_never_show';
  static const String _payrollReminderIgnoredPrefix = 'payroll_reminder_ignored_';
  static const String _payrollReminderSnoozedPrefix = 'payroll_reminder_snoozed_';
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
  static const String _localImagesDirName = 'company_images';

  static String? _cachedProfilePicUrl;
  static String? _cachedCompanyStampUrl;
  static String? _cachedCompanyCurrency;
  static bool _cachedIsGuest = false;
  static bool _cachedIsPremium = false;
  static Directory? _guestDataDir;

  static String? get cachedProfilePicUrl => _cachedProfilePicUrl;
  static String? get cachedCompanyStampUrl => _cachedCompanyStampUrl;
  static String? get cachedCompanyCurrency => _cachedCompanyCurrency;
  static bool get cachedIsGuest => _cachedIsGuest;
  static bool get cachedIsPremium => _cachedIsPremium;

  static Future<Directory> _getGuestDataDir() async {
    if (_guestDataDir != null) return _guestDataDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _guestDataDir = await Directory('${appDir.path}/guest_data').create(recursive: true);
    return _guestDataDir!;
  }

  static Future<File> _guestFile(String name) async {
    final dir = await _getGuestDataDir();
    return File('${dir.path}/$name');
  }

  static Future<String?> persistImageLocally({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = await Directory('${appDir.path}/$_localImagesDirName').create(recursive: true);
      final file = File('${imageDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedProfilePicUrl = prefs.getString(_profilePicUrlKey);
    _cachedCompanyStampUrl = prefs.getString(_companyStampUrlKey);
    _cachedCompanyCurrency = prefs.getString(_companyCurrencyKey);
    _cachedIsGuest = prefs.getBool(_guestKey) ?? false;
    _cachedIsPremium = prefs.getBool(_premiumKey) ?? false;

    _migrateStampFromGuestProfile(prefs);
  }

  static void _migrateStampFromGuestProfile(SharedPreferences prefs) {
    if ((_cachedCompanyStampUrl == null || _cachedCompanyStampUrl!.isEmpty) && prefs.containsKey(_guestProfileKey)) {
      try {
        final guestData = jsonDecode(prefs.getString(_guestProfileKey) ?? '{}');
        final stamp = (guestData['companyStampUrl'] ?? guestData['stampUrl'])?.toString().trim();
        if (stamp != null && stamp.isNotEmpty) {
          _cachedCompanyStampUrl = stamp;
        }
      } catch (_) {}
    }
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
    const defaultDays = {1, 2, 3, 4, 5};

    if (saved == null) return defaultDays;

    final days = saved.map(int.tryParse).whereType<int>().where((day) => day >= DateTime.monday && day <= DateTime.sunday).toSet();
    return days.isEmpty ? defaultDays : days;
  }

  static Future<void> setCompanyWorkingDays(Iterable<int> weekdays) async {
    final days = weekdays.where((day) => day >= DateTime.monday && day <= DateTime.sunday).toSet().toList()..sort();
    if (days.isEmpty) {
      throw ArgumentError('At least one company working day is required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_companyWorkingDaysKey, days.map((day) => day.toString()).toList());
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

  static Future<void> setGuestPayroll(List<Map<String, dynamic>> payroll) async {
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

  static Future<String?> getCompanyStampUrl() async {
    if (_cachedCompanyStampUrl != null && _cachedCompanyStampUrl!.isNotEmpty) {
      return _cachedCompanyStampUrl;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_companyStampUrlKey);
    _cachedCompanyStampUrl = url;
    return url;
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

  static Future<bool> getRateUsNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rateUsNeverShowKey) ?? false;
  }

  static Future<void> setRateUsNeverShow(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rateUsNeverShowKey, value);
  }

  static Future<void> snoozePayrollReminder(String periodKey, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = now ?? DateTime.now();
    final snoozedUntil = DateTime(current.year, current.month, current.day + 1);
    await prefs.setString('$_payrollReminderSnoozedPrefix$periodKey', snoozedUntil.toIso8601String());
  }

  static Future<void> ignorePayrollReminder(String periodKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_payrollReminderIgnoredPrefix$periodKey', true);
    await prefs.remove('$_payrollReminderSnoozedPrefix$periodKey');
  }

  static Future<bool> isPayrollReminderIgnored(String periodKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_payrollReminderIgnoredPrefix$periodKey') ?? false;
  }

 static Future<bool> isPayrollReminderSnoozed(
  String periodKey, {
  DateTime? now,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_payrollReminderSnoozedPrefix$periodKey';
  final raw = prefs.getString(key);

  if (raw == null || raw.isEmpty) return false;

  final until = DateTime.tryParse(raw);
  if (until == null) {
    await prefs.remove(key);
    return false;
  }

  final current = now ?? DateTime.now();

  final nextMidnight = DateTime(
    current.year,
    current.month,
    current.day + 1,
  );

    if (until.isAfter(nextMidnight)) {
    await prefs.remove(key);
    return false;
  }

  if (!until.isAfter(current)) {
    await prefs.remove(key);
    return false;
  }

  return true;
}
  static Future<bool> _getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> wasFirstExpenseTriggered() => _getBool(_rateUsFirstExpenseKey);
  static Future<void> markFirstExpenseTriggered() => _setBool(_rateUsFirstExpenseKey, true);
  static Future<bool> wasFirstWorkerTriggered() => _getBool(_rateUsFirstWorkerKey);
  static Future<void> markFirstWorkerTriggered() => _setBool(_rateUsFirstWorkerKey, true);
  static Future<bool> wasFirstHolidayTriggered() => _getBool(_rateUsFirstHolidayKey);
  static Future<void> markFirstHolidayTriggered() => _setBool(_rateUsFirstHolidayKey, true);
  static Future<bool> wasFirstBulkWorkerTriggered() => _getBool(_rateUsFirstBulkWorkerKey);
  static Future<void> markFirstBulkWorkerTriggered() => _setBool(_rateUsFirstBulkWorkerKey, true);
  static Future<bool> wasFirstAssetTriggered() => _getBool(_rateUsFirstAssetKey);
  static Future<void> markFirstAssetTriggered() => _setBool(_rateUsFirstAssetKey, true);

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

  static Future<String?> getBiometricPassword() async {
    return _readBiometricCredential(_biometricPasswordKey);
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

    final keysToRemove = [
      _guestKey,
      _premiumKey,
      _profilePicUrlKey,
      _rateUsNeverShowKey,
      _rateUsFirstExpenseKey,
      _rateUsFirstWorkerKey,
      _rateUsFirstHolidayKey,
      _rateUsFirstBulkWorkerKey,
      _rateUsFirstAssetKey,
      _profilePicLocalPathKey,
      _companyStampUrlKey,
      _companyCurrencyKey,
      _companyWorkingDaysKey,
      _sessionLockedKey,
      _guestPayrollKey,
    ];

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }

    final reminderKeys = prefs.getKeys().where((key) => key.startsWith(_payrollReminderIgnoredPrefix) || key.startsWith(_payrollReminderSnoozedPrefix)).toList();
    for (final key in reminderKeys) {
      await prefs.remove(key);
    }

    if (!preserveBiometricCredentials) {
      await clearBiometricCredentials();
    }

    _cachedProfilePicUrl = null;
    _cachedCompanyStampUrl = null;
    _cachedCompanyCurrency = null;
    _cachedIsGuest = false;
    _cachedIsPremium = false;
  }
}