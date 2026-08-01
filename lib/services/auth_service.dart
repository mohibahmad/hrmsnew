import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../firebase_options.dart';
import 'dummy_data.dart';
import 'preferences_service.dart';
import 'firestore_service.dart';
import 'error_reporter.dart';

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance!;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final User _guestUser = GuestUser();

  AuthService() {
    _instance = this;
  }

  static final ValueNotifier<String?> profilePicNotifier =
      ValueNotifier<String?>(null);

  Stream<User?> get authStateChanges {
    if (FirestoreService.isTesting) {
      return Stream.value(MockUser());
    }
    if (PreferencesService.cachedIsGuest) {
      return Stream.value(_guestUser);
    }
    return _auth.authStateChanges();
  }

  User? get currentUser {
    if (FirestoreService.isTesting) {
      return MockUser();
    }
    if (PreferencesService.cachedIsGuest) {
      return _guestUser;
    }
    return _auth.currentUser;
  }

  Future<void> _clearSeededDummyDataIfNeeded() async {
    try {
      await FirestoreService.instance.clearDummyDataForCurrentUser();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'clearSeededDummyData');
    }
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _resolvedName(
    User user, {
    String? preferredName,
    required String fallback,
  }) {
    final preferred = preferredName?.trim() ?? '';
    if (preferred.isNotEmpty) return preferred;

    final current = user.displayName?.trim() ?? '';
    if (current.isNotEmpty) return current;

    final email = user.email?.trim() ?? '';
    final separator = email.indexOf('@');
    if (separator > 0) {
      final localPart = email.substring(0, separator).trim();
      if (localPart.isNotEmpty) return localPart;
    }

    return fallback;
  }

  Future<void> _safeUpdateDisplayName(User user, String name) async {
    if (name.trim().isEmpty || user.displayName?.trim() == name.trim()) return;
    try {
      await user.updateDisplayName(name.trim());
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'updateAuthDisplayName');
    }
  }

  Future<Map<String, dynamic>> _ensureSocialProfile({
    required User user,
    required String name,
  }) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('hrms_user')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));

    final existing = snapshot.data();
    if (snapshot.exists && existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final email = _normalizeEmail(user.email ?? '');
    await FirestoreService.instance.createUserProfile(
      username: name,
      email: email,
      phone: '',
    );

    return {
      'username': name,
      'email': email,
      'phone': '',
      'uid': user.uid,
      'isPremium': false,
      'hasDummyData': false,
    };
  }

  Future<void> _rollbackAuthenticatedSession(String contextName) async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: '${contextName}AuthSignOut');
    }

    try {
      await PreferencesService.clear();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: '${contextName}PreferencesClear');
    }

    profilePicNotifier.value = null;
  }

  Future<void> _setPremiumFromProfile(Map<String, dynamic>? profile) async {
    await PreferencesService.setPremium(profile?['isPremium'] == true);
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );
      await PreferencesService.setGuest(false);
      await PreferencesService.setLoggedIn(true);
      return credential;
    } on FirebaseAuthException {
      rethrow;
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'emailSignUp');
      rethrow;
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: _normalizeEmail(email),
        password: password,
      );
      await PreferencesService.setGuest(false);
      await PreferencesService.setLoggedIn(true);
      await _syncPremiumStatusFromFirestore();
      await _clearSeededDummyDataIfNeeded();
      return credential;
    } on FirebaseAuthException {
      rethrow;
    } catch (e, st) {
      if (credential != null) {
        await _rollbackAuthenticatedSession('emailSignInRollback');
      }
      ErrorReporter.report(e, st, context: 'emailSignIn');
      rethrow;
    }
  }

  Future<UserCredential> signInAnonymously({
    String displayName = 'Guest User',
  }) async {
    await PreferencesService.setLoggedIn(true);
    await PreferencesService.setGuest(true);
    await DummyData.resetToDefaults();
    profilePicNotifier.value = null;
    return GuestUserCredential(_guestUser);
  }

  Future<UserCredential?> signInWithGoogle() async {
    UserCredential? authenticatedCredential;
    try {
      String? clientId;
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        clientId = DefaultFirebaseOptions.currentPlatform.iosClientId;
      }

      await GoogleSignIn.instance.initialize(clientId: clientId);
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      authenticatedCredential = userCredential;
      final user = userCredential.user;
      if (user == null) {
        throw StateError('Google authentication returned no user');
      }

      await PreferencesService.setGuest(false);

      final name = _resolvedName(
        user,
        preferredName: googleUser.displayName,
        fallback: 'User',
      );
      await _safeUpdateDisplayName(user, name);

      final profile = await _ensureSocialProfile(user: user, name: name);
      await PreferencesService.setLoggedIn(true);
      await _setPremiumFromProfile(profile);
      await _clearSeededDummyDataIfNeeded();
      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    } catch (e, st) {
      if (authenticatedCredential != null) {
        await _rollbackAuthenticatedSession('googleSignInRollback');
      }
      ErrorReporter.report(e, st, context: 'googleSignIn');
      rethrow;
    }
  }

  Future<UserCredential?> signInWithApple() async {
    UserCredential? authenticatedCredential;
    try {
      final appleProvider = OAuthProvider('apple.com');
      appleProvider.setCustomParameters({'locale': 'en'});
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      final userCredential = await _auth.signInWithProvider(appleProvider);
      authenticatedCredential = userCredential;
      final user = userCredential.user;
      if (user == null) {
        throw StateError('Apple authentication returned no user');
      }

      await PreferencesService.setGuest(false);

      final name = _resolvedName(user, fallback: 'Apple User');
      await _safeUpdateDisplayName(user, name);

      final profile = await _ensureSocialProfile(user: user, name: name);
      await PreferencesService.setLoggedIn(true);
      await _setPremiumFromProfile(profile);
      await _clearSeededDummyDataIfNeeded();
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'popup-closed-by-user') {
        return null;
      }
      if (authenticatedCredential != null) {
        await _rollbackAuthenticatedSession('appleSignInRollback');
      }
      rethrow;
    } catch (e, st) {
      if (authenticatedCredential != null) {
        await _rollbackAuthenticatedSession('appleSignInRollback');
      }
      ErrorReporter.report(e, st, context: 'appleSignIn');
      rethrow;
    }
  }

  Future<void> signOut({bool preserveBiometricLogin = false}) async {
    final isGuest = await PreferencesService.isGuest();
    await PreferencesService.setGuest(false);
    if (!isGuest) {
      await _auth.signOut();
    }
    await PreferencesService.clear(
      preserveBiometricCredentials: preserveBiometricLogin,
    );
    profilePicNotifier.value = null;
  }

  Future<void> _syncPremiumStatusFromFirestore() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        await PreferencesService.setPremium(false);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('hrms_user')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      await PreferencesService.setPremium(
        snapshot.data()?['isPremium'] == true,
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'syncPremiumStatus');
      try {
        await PreferencesService.setPremium(false);
      } catch (fallbackError, fallbackStack) {
        ErrorReporter.report(
          fallbackError,
          fallbackStack,
          context: 'syncPremiumStatusFallback',
        );
      }
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: _normalizeEmail(email));
  }
}

class UserAvatar extends StatelessWidget {
  final double radius;
  const UserAvatar({super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.profilePicNotifier,
      builder: (context, photoUrl, _) {
        final double size = radius * 2;
        final url = photoUrl?.trim();

        Widget imageWidget;
        if (url != null && url.isNotEmpty) {
          if (url.startsWith('http')) {
            imageWidget = CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildFallback(size),
              errorWidget: (context, url, error) => _buildFallback(size),
            );
          } else if (url.startsWith('data:image')) {
            try {
              final commaIndex = url.indexOf(',');
              if (commaIndex < 0 || commaIndex == url.length - 1) {
                throw const FormatException('Invalid image data');
              }
              final base64Content = url.substring(commaIndex + 1);
              imageWidget = Image.memory(
                base64Decode(base64Content),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallback(size),
              );
            } catch (e) {
              imageWidget = _buildFallback(size);
            }
          } else {
            imageWidget = Image.file(
              File(url),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildFallback(size),
            );
          }
        } else {
          imageWidget = _buildFallback(size);
        }

        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
          ),
          child: ClipOval(child: imageWidget),
        );
      },
    );
  }

  Widget _buildFallback(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.white,
      child: Image.asset(
        'assets/company_profile_placeholder.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFFE2E8F0),
            child: Icon(
              Icons.business_rounded,
              size: size * 0.6,
              color: const Color(0xFF0247C4),
            ),
          );
        },
      ),
    );
  }
}

class MockUser implements User {
  @override
  final String uid = 'guest_uid';
  @override
  final String? email = null;
  @override
  final String? displayName = 'Guest User';
  @override
  final String? photoURL = null;
  @override
  final bool isAnonymous = true;

  @override
  Future<void> updateDisplayName(String? displayName) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockUserCredential implements UserCredential {
  @override
  final User user = MockUser();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GuestUser implements User {
  final String _uid = 'guest_${DateTime.now().millisecondsSinceEpoch}';

  @override
  String get uid => _uid;

  @override
  String? get email => null;

  @override
  String? get displayName => 'Guest User';

  @override
  bool get isAnonymous => true;

  @override
  String? get photoURL => null;

  @override
  Future<void> updateDisplayName(String? displayName) async {}

  @override
  Future<void> updatePhotoURL(String? photoURL) async {}

  @override
  Future<void> updatePassword(String? password) async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> delete() async {}

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? app]) async {}

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    return MockIdTokenResult();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    return 'guest_token_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GuestUserCredential implements UserCredential {
  GuestUserCredential(this.user);

  @override
  final User user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockIdTokenResult implements IdTokenResult {
  @override
  String get token => 'mock_token';

  @override
  DateTime get expirationTime => DateTime.now().add(const Duration(hours: 1));

  @override
  String get signInProvider => 'anonymous';

  @override
  Map<String, dynamic> get claims => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
