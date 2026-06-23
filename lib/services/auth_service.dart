import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'preferences_service.dart';
import 'firestore_service.dart';
import 'error_reporter.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final ValueNotifier<String?> profilePicNotifier =
      ValueNotifier<String?>(null);

  /// Toggle this to `true` to bypass native SDKs and log in instantly in
  /// demo mode. Set to `false` to use the real Google/Apple sign-in flows.
  static const bool useDemoAuth = false;
  // static const bool useDemoAppleAuth = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

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
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await PreferencesService.setLoggedIn(true);
    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await PreferencesService.setLoggedIn(true);
    await _clearSeededDummyDataIfNeeded();
    return credential;
  }

  /// Sign in Anonymously (Continue as Guest)
  Future<UserCredential> signInAnonymously({
    String displayName = 'Guest User',
  }) async {
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) {
      await credential.user!.updateDisplayName(displayName).catchError((_) {});
    }
    await PreferencesService.setLoggedIn(true);
    await _clearSeededDummyDataIfNeeded();
    return credential;
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await GoogleSignIn.instance.initialize();
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
    await _auth.signOut();
    await PreferencesService.clear();
  }

  /// Send password reset email
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }
}

class UserAvatar extends StatelessWidget {
  final double radius;
  const UserAvatar({super.key, this.radius = 18});

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
            imageWidget = Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallback(size),
            );
          } else if (url.startsWith('data:image')) {
            try {
              final String base64Content = url.substring(
                url.indexOf(',') + 1,
              );
              imageWidget = Image.memory(
                base64Decode(base64Content),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallback(size),
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
              errorBuilder: (context, error, stackTrace) => _buildFallback(size),
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
          child: ClipOval(
            child: imageWidget,
          ),
        );
      },
    );
  }

  Widget _buildFallback(double size) {
    return Image.asset(
      'assets/profile_pic.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          color: const Color(0xFFE2E8F0),
          child: Icon(
            Icons.person,
            size: size * 0.6,
            color: const Color(0xFF64748B),
          ),
        );
      },
    );
  }
}
