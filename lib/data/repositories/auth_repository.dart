import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_user.dart';

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

    await _firestore
        .collection('users')
        .doc(appUser.uid)
        .set(appUser.toMap());

    return appUser;
  }
  Future<UserCredential> login({
    required String email,
    required String password,
      }) async {
        return _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
}
}