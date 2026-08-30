import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/app_user.dart';
import '../../services/google_drive_service.dart';

/// Thrown by [AuthRepository.signInWithGoogle] when the Google account's
/// email already belongs to an existing email/password Baby Book account.
/// The UI should ask for that account's password and call
/// [AuthRepository.resolveGoogleAccountConflict] to link them, rather than
/// just reporting failure — the Google sign-in itself already succeeded,
/// only the Firebase-side linking step needs the password to proceed safely.
class GoogleAccountConflict implements Exception {
  GoogleAccountConflict({
    required this.email,
    required this.pendingCredential,
    required this.googleAccount,
  });

  final String email;
  final AuthCredential pendingCredential;
  final GoogleSignInAccount googleAccount;
}

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final firebaseUser = credential.user;

    if (firebaseUser == null) {
      throw Exception('Failed to create user');
    }

    final appUser = AppUser(
      uid: firebaseUser.uid,
      email: email,
      displayName: displayName,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(appUser.uid).set(appUser.toMap());

    return appUser;
  }

  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Signs into (or creates) the Baby Book account using a Google account,
  /// and grants Drive photo-storage access in the same consent step — one
  /// tap, no separate "connect storage" prompt later.
  ///
  /// If already logged in (e.g. via email/password), this links the Google
  /// credential to the current account instead of creating a second one, so
  /// existing books aren't orphaned under a new identity.
  Future<AppUser> signInWithGoogle() async {
    final driveService = GoogleDriveService();
    final account = await driveService.signInInteractively();

    final idToken = account.authentication.idToken;

    if (idToken == null) {
      throw Exception('Google sign-in did not return an identity token.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final alreadySignedInUser = _auth.currentUser;

    UserCredential userCredential;

    try {
      if (alreadySignedInUser != null) {
        userCredential = await alreadySignedInUser.linkWithCredential(
          credential,
        );
      } else {
        userCredential = await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential' &&
          e.email != null) {
        throw GoogleAccountConflict(
          email: e.email!,
          pendingCredential: credential,
          googleAccount: account,
        );
      }
      rethrow;
    }

    return _finishGoogleSignIn(userCredential, account, driveService);
  }

  /// Completes a Google sign-in that hit a [GoogleAccountConflict]: signs
  /// into the existing email/password account with [password], then links
  /// the Google credential to it — so the two providers end up on the same
  /// Baby Book identity instead of the user needing to separately visit
  /// "Link Google Account" afterwards.
  Future<AppUser> resolveGoogleAccountConflict({
    required GoogleAccountConflict conflict,
    required String password,
  }) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: conflict.email,
      password: password,
    );

    final linkedCredential = await userCredential.user!.linkWithCredential(
      conflict.pendingCredential,
    );

    return _finishGoogleSignIn(
      linkedCredential,
      conflict.googleAccount,
      GoogleDriveService(),
    );
  }

  Future<AppUser> _finishGoogleSignIn(
    UserCredential userCredential,
    GoogleSignInAccount account,
    GoogleDriveService driveService,
  ) async {
    final firebaseUser = userCredential.user;

    if (firebaseUser == null) {
      throw Exception('Failed to sign in with Google');
    }

    await driveService.rememberSignedInAccountFor(firebaseUser.uid);

    final userDoc = await _firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .get();

    final appUser = AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? account.email,
      displayName:
          firebaseUser.displayName ?? account.displayName ?? account.email,
      createdAt:
          (userDoc.data()?['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );

    if (!userDoc.exists) {
      await _firestore
          .collection('users')
          .doc(appUser.uid)
          .set(appUser.toMap());
    }

    return appUser;
  }
}
