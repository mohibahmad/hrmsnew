import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/preferences_service.dart';
import 'utils/firestore_record_utils.dart';

export 'utils/firestore_record_utils.dart' show FirestoreRecords;

extension AsyncProviderListener on WidgetRef {
  void listenAsync<T>(
    ProviderListenable<AsyncValue<T>> provider,
    FutureOr<void> Function(T value) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = true,
  }) {
    listenManual(
      provider,
      (previous, next) => next.when(
        data: (value) {
          onData(value);
        },
        error: (error, stackTrace) => onError?.call(error, stackTrace),
        loading: () {},
      ),
      fireImmediately: fireImmediately,
    );
  }
}

final Provider<FirestoreService> firestoreServiceProvider =
    Provider<FirestoreService>(
      (ref) =>
          FirestoreService(authService: () => ref.read(authServiceProvider)),
    );

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (ref) =>
      AuthService(firestoreService: () => ref.read(firestoreServiceProvider)),
);

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final googleSignInEnabledProvider = StreamProvider.autoDispose<bool>((ref) {
  return AuthService.googleEnabledStream();
});

final userProfileProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) {
  return ref.watch(firestoreServiceProvider).userProfileStream;
});

final workersProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .workersStream
      .map(firestoreRecords);
});

final attendanceProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .attendanceStream
      .map(firestoreRecords);
});

final payrollProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .payrollStream
      .map(firestoreRecords);
});

final expensesProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .expensesStream
      .map(firestoreRecords);
});

final timeOffProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .timeoffStream
      .map(firestoreRecords);
});

final assetsProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref.watch(firestoreServiceProvider).assetsStream.map(firestoreRecords);
});

final holidaysProvider = StreamProvider.autoDispose<FirestoreRecords>((ref) {
  return ref
      .watch(firestoreServiceProvider)
      .holidaysStream
      .map(firestoreRecords);
});

final notificationsProvider = StreamProvider.autoDispose<FirestoreRecords>((
  ref,
) {
  return ref
      .watch(firestoreServiceProvider)
      .notificationsStream
      .map(firestoreRecords);
});

final unreadNotificationCountProvider = Provider.autoDispose<AsyncValue<int>>((
  ref,
) {
  return ref
      .watch(notificationsProvider)
      .whenData(
        (records) => records.where((record) => record['isRead'] != true).length,
      );
});

final attendanceForWorkerProvider = StreamProvider.autoDispose
    .family<FirestoreRecords, String>((ref, workerId) {
      return ref
          .watch(firestoreServiceProvider)
          .attendanceStreamForWorker(workerId)
          .map(firestoreRecords);
    });

final attendanceForPeriodProvider = StreamProvider.autoDispose
    .family<FirestoreRecords, ({DateTime start, DateTime end})>((ref, period) {
      return ref
          .watch(firestoreServiceProvider)
          .attendanceStreamForPeriod(start: period.start, end: period.end)
          .map(firestoreRecords);
    });

final timeOffForWorkerProvider = StreamProvider.autoDispose
    .family<FirestoreRecords, String>((ref, workerId) {
      return ref
          .watch(firestoreServiceProvider)
          .timeoffForWorkerStream(workerId)
          .map(firestoreRecords);
    });

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

  SessionTimeoutSettings copyWith({bool? enabled, int? durationMinutes}) {
    return SessionTimeoutSettings(
      enabled: enabled ?? this.enabled,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}

class SessionTimeoutSettingsNotifier
    extends StateNotifier<SessionTimeoutSettings> {
  SessionTimeoutSettingsNotifier()
    : super(
        SessionTimeoutSettings(
          enabled: PreferencesService.cachedSessionTimeoutEnabled,
          durationMinutes: PreferencesService.cachedSessionTimeoutDuration,
        ),
      );

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
    StateNotifierProvider<
      SessionTimeoutSettingsNotifier,
      SessionTimeoutSettings
    >((ref) {
      return SessionTimeoutSettingsNotifier();
    });
