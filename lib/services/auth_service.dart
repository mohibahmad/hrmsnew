import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../firebase_options.dart';
import 'preferences_service.dart';
import 'firestore_service.dart';
import 'error_reporter.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static final ValueNotifier<String?> profilePicNotifier =
      ValueNotifier<String?>(null);

  /// Set to `true` when a guest user logged in via fallback (no real Firebase user).
  static bool get isGuestUser => _isGuestUser;
  static bool _isGuestUser = false;
  static set isGuestUser(bool value) => _isGuestUser = value;

  Stream<User?> get authStateChanges {
    if (FirestoreService.isTesting) {
      return Stream.value(MockUser());
    }
    if (isGuestUser) {
      return Stream.value(GuestUser());
    }
    return _auth.authStateChanges();
  }

  User? get currentUser {
    if (FirestoreService.isTesting) {
      return MockUser();
    }
    if (isGuestUser) {
      return GuestUser();
    }
    return _auth.currentUser;
  }

  Future<void> _clearSeededDummyDataIfNeeded() async {
    try {
      await FirestoreService().clearDummyDataForCurrentUser();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'clearSeededDummyData');
    }
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isGuestUser = false;
      await PreferencesService.setGuest(false);
      await PreferencesService.setLoggedIn(true);
      return credential;
    } on FirebaseAuthException {
      // Real Firebase error — let the caller (signup_screen) handle it
      rethrow;
    } catch (_) {
      // Non-Firebase error (e.g. network) — also rethrow so caller can show error
      rethrow;
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isGuestUser = false;
      await PreferencesService.setGuest(false);
      await PreferencesService.setLoggedIn(true);
      await _syncPremiumStatusFromFirestore();
      await _clearSeededDummyDataIfNeeded();
      return credential;
    } on FirebaseAuthException {
      // Let the caller handle specific Firebase errors (wrong password, etc.)
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  /// Sign in Anonymously (Continue as Guest) - Local only, no Firebase
  Future<UserCredential> signInAnonymously({
    String displayName = 'Guest User',
  }) async {
    _isGuestUser = true;
    await PreferencesService.setLoggedIn(true);
    await PreferencesService.setGuest(true);
    return GuestUserCredential();
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      String? clientId;
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        clientId = DefaultFirebaseOptions.currentPlatform.iosClientId;
      }
      await GoogleSignIn.instance.initialize(clientId: clientId);
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        final name =
            googleUser.displayName ?? userCredential.user!.email ?? 'User';
        await userCredential.user!.updateDisplayName(name);

        // Ensure user profile is created in Firestore
        final firestore = FirestoreService();
        final profile = await firestore.getUserProfile();
        if (profile == null) {
          await firestore.createUserProfile(
            username: name,
            email: userCredential.user!.email ?? '',
            phone: '',
          );
        }
      }
      await PreferencesService.setLoggedIn(true);
      _isGuestUser = false;
      await PreferencesService.setGuest(false);
      await _syncPremiumStatusFromFirestore();
      await _clearSeededDummyDataIfNeeded();
      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }

  /// Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleProvider = OAuthProvider('apple.com');
      appleProvider.setCustomParameters({'locale': 'en'});
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      final userCredential = await _auth.signInWithProvider(appleProvider);
      if (userCredential.user != null) {
        final name = userCredential.user!.displayName ?? 'Apple User';

        // Ensure user profile is created in Firestore
        final firestore = FirestoreService();
        final profile = await firestore.getUserProfile();
        if (profile == null) {
          await firestore.createUserProfile(
            username: name,
            email: userCredential.user!.email ?? '',
            phone: '',
          );
        }
      }
      await PreferencesService.setLoggedIn(true);
      _isGuestUser = false;
      await PreferencesService.setGuest(false);
      await _syncPremiumStatusFromFirestore();
      await _clearSeededDummyDataIfNeeded();
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'popup-closed-by-user') {
        return null;
      }
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    final wasGuest = isGuestUser;
    _isGuestUser = false;
    await PreferencesService.setGuest(false);
    if (!wasGuest) {
      await _auth.signOut();
    }
    await PreferencesService.clear();
    profilePicNotifier.value = null;
  }

  /// Sync the user's premium status from Firestore into local preferences.
  /// This is called after every login so that a returning premium user
  /// doesn't see the upgrade dialog again.
  Future<void> _syncPremiumStatusFromFirestore() async {
    try {
      final profile = await FirestoreService().getUserProfile();
      if (profile != null && profile['isPremium'] == true) {
        await PreferencesService.setPremium(true);
      }
    } catch (_) {}
  }

  Future<void> requestPasswordResetOtp(String email) async {
    await _functions.httpsCallable('requestPasswordResetOtp').call({
      'email': email.trim(),
    });
  }

  Future<String> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    final result = await _functions
        .httpsCallable('verifyPasswordResetOtp')
        .call({'email': email.trim(), 'otp': otp.trim()});
    final data = Map<String, dynamic>.from(result.data as Map);
    final resetToken = (data['resetToken'] ?? '').toString();
    if (resetToken.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'The reset verification token is missing.',
      );
    }
    return resetToken;
  }

  Future<void> confirmPasswordResetOtp({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _functions.httpsCallable('confirmPasswordResetOtp').call({
      'email': email.trim(),
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
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
        final url = photoUrl;

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
              final String base64Content = url.substring(url.indexOf(',') + 1);
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
        'assets/profile_placeholder.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFFE2E8F0),
            child: Icon(
              Icons.person,
              size: size * 0.6,
              color: const Color(0xFF64748B),
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
  @override
  final User user = GuestUser();

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
