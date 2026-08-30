import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_user.dart';
import '../../services/google_drive_service.dart';

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
      if (e.code == 'account-exists-with-different-credential') {
        throw Exception(
          'An account with this email already exists. Log in with your '
          'email and password first — Google sign-in can then be linked to '
          'it from the home screen.',
        );
      }
      rethrow;
    }

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
