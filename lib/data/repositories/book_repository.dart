import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/book.dart';

class BookRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createBook({
    required String childName,
    required DateTime birthDate,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final bookRef = _firestore.collection('books').doc();

    await bookRef.set({
      'bookId': bookRef.id,
      'childName': childName,
      'birthDate': birthDate,
      'ownerIds': [user.uid],
      'language': 'en',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Book>> watchMyBooks() {
    final user = _auth.currentUser;

    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('books')
        .where('ownerIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
          final books = snapshot.docs.map((doc) {
            final data = doc.data();

            return Book(
              bookId: doc.id,
              childName: data['childName'] as String,
              birthDate: (data['birthDate'] as Timestamp).toDate(),
              ownerIds: List<String>.from(data['ownerIds']),
              language: data['language'] as String? ?? 'en',
              createdAt:
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList();

          books.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          return books;
        });
  }
}
