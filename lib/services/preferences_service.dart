import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _loggedInKey = 'is_logged_in';
  static const String _guestKey = 'is_guest';
  static const String _premiumKey = 'is_premium';
  static const String _profilePicUrlKey = 'profile_pic_url';
  static const String _rateUsNeverShowKey = 'rate_us_never_show';
  static const String _rateUsRemindLaterKey = 'rate_us_remind_later';
  static const String _rateUsFirstExpenseKey = 'rate_us_first_expense';
  static const String _rateUsFirstWorkerKey = 'rate_us_first_worker';
  static const String _rateUsFirstHolidayKey = 'rate_us_first_holiday';
  static const String _rateUsFirstBulkWorkerKey = 'rate_us_first_bulk_worker';
  static const String _rateUsFirstAssetKey = 'rate_us_first_asset';
  static const String _companyWorkingDaysKey = 'company_working_days';
  static const String _companySalaryDayKey = 'company_salary_day';
  static const String _guestProfileKey = 'guest_profile_data';
  static const String _guestWorkersKey = 'guest_workers_data';
  static const String _guestPayrollKey = 'guest_payroll_data';

  /// Synchronous cache of the profile pic URL so it's available on the first
  /// frame (no async delay). Populated the first time [getProfilePicUrl] is
  /// called, or explicitly via [initFromPrefs].
  static String? _cachedProfilePicUrl;
  static bool _cachedIsGuest = false;

  /// Call this once at app startup (e.g. in main()) to pre-populate the sync
  /// cache from SharedPreferences before any widget builds.
  static Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedProfilePicUrl = prefs.getString(_profilePicUrlKey);
    _cachedIsGuest = prefs.getBool(_guestKey) ?? false;
  }

  /// Synchronous getter – returns the cached value immediately, or null if
  /// [initFromPrefs] hasn't completed yet.
  static String? get cachedProfilePicUrl => _cachedProfilePicUrl;
  static bool get cachedIsGuest => _cachedIsGuest;

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

  static Future<int?> getCompanySalaryDay() async {
    final prefs = await SharedPreferences.getInstance();
    final day = prefs.getInt(_companySalaryDayKey);
    return day != null && day >= 1 && day <= 31 ? day : null;
  }

  static Future<void> setCompanySalaryDay(int day) async {
    if (day < 1 || day > 31) {
      throw ArgumentError.value(day, 'day', 'Salary day must be from 1 to 31');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_companySalaryDayKey, day);
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

  static Future<void> clearGuestProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestProfileKey);
  }

  static Future<void> setGuestWorkers(
    List<Map<String, dynamic>> workers,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guestWorkersKey, jsonEncode(workers));
  }

  static Future<List<Map<String, dynamic>>?> getGuestWorkers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestWorkersKey);
    if (raw == null || raw.isEmpty) return null;
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  static Future<void> clearGuestWorkers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestWorkersKey);
  }

  static Future<void> setGuestPayroll(
    List<Map<String, dynamic>> payroll,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guestPayrollKey, jsonEncode(payroll));
  }

  static Future<List<Map<String, dynamic>>?> getGuestPayroll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestPayrollKey);
    if (raw == null || raw.isEmpty) return null;
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  static Future<void> clearGuestPayroll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestPayrollKey);
  }

  static Future<void> setProfilePicUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_profilePicUrlKey, url);
    } else {
      await prefs.remove(_profilePicUrlKey);
    }
    // Also update the sync cache immediately
    _cachedProfilePicUrl = url;
  }

  static Future<String?> getProfilePicUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_profilePicUrlKey);
    _cachedProfilePicUrl = url;
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
    // Remind in 1 day
    final remindDate = DateTime.now().add(const Duration(days: 1));
    await prefs.setString(_rateUsRemindLaterKey, remindDate.toIso8601String());
  }

  // ============== Rate Us counters for milestone triggers ==============

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

  static Future<void> clear() async {
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
    await prefs.remove(_companySalaryDayKey);
    await prefs.remove(_guestPayrollKey);
    _cachedProfilePicUrl = null;
    _cachedIsGuest = false;
  }
}
