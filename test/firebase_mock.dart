import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Installs a mock Firebase platform so widget tests can construct
/// `FirebaseAuth.instance` (and other Firebase services) without a real
/// `Firebase.initializeApp()`. Mirrors production, where Firebase is always
/// initialized before any screen is built.
///
/// Call once, then `await Firebase.initializeApp()`.
void setupFirebaseCoreMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FirebasePlatform.instance = _MockFirebasePlatform();
}

const _options = FirebaseOptions(
  apiKey: 'test',
  appId: 'test',
  messagingSenderId: 'test',
  projectId: 'test',
);

class _MockFirebasePlatform extends FirebasePlatform {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _MockFirebaseApp(name);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _MockFirebaseApp(name ?? defaultFirebaseAppName, options);

  @override
  List<FirebaseAppPlatform> get apps => [_MockFirebaseApp()];
}

class _MockFirebaseApp extends FirebaseAppPlatform {
  _MockFirebaseApp([String name = defaultFirebaseAppName, FirebaseOptions? options])
    : super(name, options ?? _options);
}
