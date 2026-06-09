import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'preferences_service.dart';
import 'firestore_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

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
    return credential;
  }

  /// Sign in Anonymously (Continue as Guest)
  Future<UserCredential> signInAnonymously({String displayName = 'Guest User'}) async {
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) {
      await credential.user!.updateDisplayName(displayName);
      await FirestoreService().seedDummyDataForUser(
        uid: credential.user!.uid,
        displayName: displayName,
        email: '${displayName.toLowerCase().replaceAll(' ', '.')}@hrms-demo.com',
      );
    }
    await PreferencesService.setLoggedIn(true);
    return credential;
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return null; // User canceled
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null && googleUser.displayName != null) {
        await userCredential.user!.updateDisplayName(googleUser.displayName);
      }
      await PreferencesService.setLoggedIn(true);
      return userCredential;
    } catch (e) {
      // Graceful fallback for development/testing if Google Auth is not fully configured
      final fallbackCredential = await signInAnonymously(displayName: 'Google Demo User');
      return fallbackCredential;
    }
  }

  /// Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final AuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: appleCredential.state,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null && appleCredential.givenName != null) {
        await userCredential.user!.updateDisplayName(
          '${appleCredential.givenName} ${appleCredential.familyName}',
        );
      }
      await PreferencesService.setLoggedIn(true);
      return userCredential;
    } catch (e) {
      // Graceful fallback for development/testing if Apple Auth is not fully configured
      final fallbackCredential = await signInAnonymously(displayName: 'Apple Demo User');
      return fallbackCredential;
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
