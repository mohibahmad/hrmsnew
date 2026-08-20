import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/preferences_service.dart';

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(),
);

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final profilePicNotifierProvider = Provider<ValueNotifier<String?>>(
  (ref) => AuthService.profilePicNotifier,
);
final companyStampNotifierProvider = Provider<ValueNotifier<String?>>(
  (ref) => AuthService.companyStampNotifier,
);

class SessionTimeoutSettings {
  final bool enabled;
  final int durationMinutes;

  const SessionTimeoutSettings({
    required this.enabled,
    required this.durationMinutes,
  });

  SessionTimeoutSettings copyWith({
    bool? enabled,
    int? durationMinutes,
  }) {
    return SessionTimeoutSettings(
      enabled: enabled ?? this.enabled,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}

class SessionTimeoutSettingsNotifier extends StateNotifier<SessionTimeoutSettings> {
  SessionTimeoutSettingsNotifier()
      : super(SessionTimeoutSettings(
          enabled: PreferencesService.cachedSessionTimeoutEnabled,
          durationMinutes: PreferencesService.cachedSessionTimeoutDuration,
        ));

  Future<void> setEnabled(bool value) async {
    await PreferencesService.setSessionTimeoutEnabled(value);
    state = state.copyWith(enabled: value);
  }

  Future<void> setDurationMinutes(int value) async {
    await PreferencesService.setSessionTimeoutDuration(value);
    state = state.copyWith(durationMinutes: value);
  }
}

final sessionTimeoutSettingsProvider =
    StateNotifierProvider<SessionTimeoutSettingsNotifier, SessionTimeoutSettings>((ref) {
  return SessionTimeoutSettingsNotifier();
});
