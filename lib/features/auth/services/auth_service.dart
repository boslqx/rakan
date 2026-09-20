import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_throttle.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Current user stream — UI listens to this
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user — null if not logged in
  User? get currentUser => _auth.currentUser;

  // Email/Password Sign Up
  Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Send email verification immediately after account creation. The
      // account already exists at this point, so a failure here must not
      // surface as a sign-up error — the verification screen offers a
      // resend instead.
      try {
        await credential.user?.sendEmailVerification();
      } catch (_) {}
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Email/Password Sign In
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final locked = await LoginThrottle.remainingLock();
    if (locked > Duration.zero) {
      throw 'Too many failed attempts. Try again in ${_fmt(locked)}.';
    }
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await LoginThrottle.reset();
      return cred;
    } on FirebaseAuthException catch (e) {
      if (_isCredentialFailure(e.code)) {
        final lock = await LoginThrottle.recordFailure();
        if (lock > Duration.zero) {
          throw 'Too many failed attempts. Try again in ${_fmt(lock)}.';
        }
      }
      throw _handleAuthException(e);
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase marks federated (Google) sign-ins as emailVerified=true
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } on PlatformException {
      throw 'Google sign-in failed. Please try again.';
    }
  }

  // Whether the CURRENTLY CACHED user object is verified
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // Forces Firebase to re-fetch the user's current verification status
  Future<bool> reloadAndCheckVerified() async {
    try {
      await _auth.currentUser?.reload();
      final verified = _auth.currentUser?.emailVerified ?? false;
      // Refresh the ID token so the emailVerified claim used by Firestore
      // security rules is up to date.
      if (verified) await _auth.currentUser?.getIdToken(true);
      return verified;
    } on FirebaseAuthException catch (e) {
      // Account deleted/disabled elsewhere: end the session.
      if (e.code == 'user-not-found' ||
          e.code == 'user-disabled' ||
          e.code == 'user-token-expired') {
        await signOut();
      }
      return false;
    }
  }

  // Resend the verification email
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Password Reset. 'user-not-found' is swallowed on purpose so the UI can't
  // be used to discover which emails have accounts.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      throw _handleAuthException(e);
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  bool _isCredentialFailure(String code) =>
      code == 'wrong-password' ||
      code == 'invalid-credential' ||
      code == 'user-not-found' ||
      code == 'invalid-login-credentials';

  String _fmt(Duration d) => d.inMinutes >= 1
      ? '${(d.inSeconds / 60).ceil()} min'
      : '${d.inSeconds.clamp(1, 60)} sec';

  // Error Handler
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      // Deliberately vague: don't reveal whether the email exists.
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'That password is too weak. Choose a stronger one.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}