import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'preferences_service.dart';
import 'firestore_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Toggle this to `true` to bypass native SDKs and log in instantly in
  /// demo mode. Set to `false` to use the real Google/Apple sign-in flows.
  static const bool useDemoAuth = false;
  // static const bool useDemoAppleAuth = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> _clearSeededDummyDataIfNeeded() async {
    try {
      await FirestoreService().clearDummyDataForCurrentUser();
    } catch (_) {}
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
    await _clearSeededDummyDataIfNeeded();
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
