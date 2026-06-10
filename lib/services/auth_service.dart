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
  Future<UserCredential> signInAnonymously({
    String displayName = 'Guest User',
  }) async {
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) {
      await credential.user!.updateDisplayName(displayName).catchError((_) {});
      await FirestoreService()
          .seedDummyDataForUser(
            uid: credential.user!.uid,
            displayName: displayName,
            email:
                '${displayName.toLowerCase().replaceAll(' ', '.')}@hrms-demo.com',
          )
          .catchError((_) {});
    }
    await PreferencesService.setLoggedIn(true);
    return credential;
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    if (useDemoAuth) {
      return await signInAnonymously(displayName: 'Google Demo User');
    }
    try {
      // google_sign_in v7: use the singleton instance and the `authenticate`
      // method. It throws on user cancel, so we let the caller handle that.
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.idToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        final name =
            googleUser.displayName ?? userCredential.user!.email ?? 'User';
        await userCredential.user!.updateDisplayName(name);
        // Seed dummy data so the screens have content after Google sign-in
        await FirestoreService().seedDummyDataForUser(
          uid: userCredential.user!.uid,
          displayName: name,
          email:
              userCredential.user!.email ??
              '${name.toLowerCase().replaceAll(' ', '.')}@google-demo.com',
        );
      }
      await PreferencesService.setLoggedIn(true);
      return userCredential;
    } on GoogleSignInException catch (e) {
      // User explicitly cancelled — return null so login screen stays put.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    } catch (e) {
      // Real auth not configured in this environment — fall back to
      // anonymous demo sign-in so the rest of the app remains usable.
      final fallbackCredential = await signInAnonymously(
        displayName: 'Google Demo User',
      );
      return fallbackCredential;
    }
  }

  /// Sign in with Apple
  // Future<UserCredential?> signInWithApple() async {
  //   if (useDemoAuth || useDemoAppleAuth) {
  //     return null;
  //   }
  //   try {
  //     final appleCredential = await SignInWithApple.getAppleIDCredential(
  //       scopes: [
  //         AppleIDAuthorizationScopes.email,
  //         AppleIDAuthorizationScopes.fullName,
  //       ],
  //     );
  //     final AuthCredential credential = OAuthProvider('apple.com').credential(
  //       idToken: appleCredential.identityToken,
  //       rawNonce: appleCredential.state,
  //     );
  //     final userCredential = await _auth.signInWithCredential(credential);
  //     if (userCredential.user != null) {
  //       final name = appleCredential.givenName != null
  //           ? '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'
  //                 .trim()
  //           : (userCredential.user!.email ?? 'User');
  //       await userCredential.user!.updateDisplayName(name);
  //       // Seed dummy data so the screens have content after Apple sign-in
  //       await FirestoreService().seedDummyDataForUser(
  //         uid: userCredential.user!.uid,
  //         displayName: name,
  //         email:
  //             userCredential.user!.email ??
  //             '${name.toLowerCase().replaceAll(' ', '.')}@apple-demo.com',
  //       );
  //     }
  //     await PreferencesService.setLoggedIn(true);
  //     return userCredential;
  //   } on SignInWithAppleAuthorizationException catch (e) {
  //     // User explicitly cancelled — return null so login screen stays put.
  //     if (e.code == AuthorizationErrorCode.canceled) {
  //       return null;
  //     }
  //     rethrow;
  //   } catch (e) {
  //     // Real auth not configured in this environment — fall back to
  //     // anonymous demo sign-in so the rest of the app remains usable.
  //     final fallbackCredential = await signInAnonymously(
  //       displayName: 'Apple Demo User',
  //     );
  //     return fallbackCredential;
  //   }
  // }

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
