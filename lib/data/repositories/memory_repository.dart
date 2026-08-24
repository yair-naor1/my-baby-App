import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/memory.dart';

class MemoryRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createMemory({
    required String bookId,
    required String text,
    DateTime? memoryDate,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final memoryRef = _firestore
        .collection('books')
        .doc(bookId)
        .collection('memories')
        .doc();

    await memoryRef.set({
      'memoryId': memoryRef.id,
      'memoryDate': memoryDate ?? DateTime.now(),
      'text': text,
      'photoRefs': <String>[],
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'hiddenFromBook': false,
    });
  }

  Future<void> updateMemory({
    required String bookId,
    required String memoryId,
    required String text,
    required DateTime memoryDate,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _firestore
        .collection('books')
        .doc(bookId)
        .collection('memories')
        .doc(memoryId)
        .update({
          'text': text,
          'memoryDate': memoryDate,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> deleteMemory({
    required String bookId,
    required String memoryId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _firestore
        .collection('books')
        .doc(bookId)
        .collection('memories')
        .doc(memoryId)
        .delete();
  }

  Stream<List<Memory>> watchMemories(String bookId) {
    return _firestore
        .collection('books')
        .doc(bookId)
        .collection('memories')
        .orderBy('memoryDate')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();

            return Memory(
              memoryId: doc.id,
              memoryDate: (data['memoryDate'] as Timestamp).toDate(),
              text: data['text'] as String? ?? '',
              photoRefs: List<String>.from(data['photoRefs'] ?? []),
              createdBy: data['createdBy'] as String,
              createdAt:
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              updatedAt:
                  (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              hiddenFromBook: data['hiddenFromBook'] as bool? ?? false,
            );
          }).toList();
        });
  }
}
