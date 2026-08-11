import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';

final firestoreServiceProvider = Provider<FirestoreService>(
  (ref) => FirestoreService(),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(),
);

final profilePicNotifierProvider = Provider<ValueNotifier<String?>>(
  (ref) => AuthService.profilePicNotifier,
);
final companyStampNotifierProvider = Provider<ValueNotifier<String?>>(
  (ref) => AuthService.companyStampNotifier,
);
