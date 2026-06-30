import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _loggedInKey = 'is_logged_in';
  static const String _premiumKey = 'is_premium';
  static const String _profilePicUrlKey = 'profile_pic_url';

  /// Synchronous cache of the profile pic URL so it's available on the first
  /// frame (no async delay). Populated the first time [getProfilePicUrl] is
  /// called, or explicitly via [initFromPrefs].
  static String? _cachedProfilePicUrl;

  /// Call this once at app startup (e.g. in main()) to pre-populate the sync
  /// cache from SharedPreferences before any widget builds.
  static Future<void> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedProfilePicUrl = prefs.getString(_profilePicUrlKey);
  }

  /// Synchronous getter – returns the cached value immediately, or null if
  /// [initFromPrefs] hasn't completed yet.
  static String? get cachedProfilePicUrl => _cachedProfilePicUrl;

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<void> setPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, value);
  }

  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_premiumKey) ?? false;
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

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInKey);
    await prefs.remove(_premiumKey);
    await prefs.remove(_profilePicUrlKey);
    _cachedProfilePicUrl = null;
  }
}
