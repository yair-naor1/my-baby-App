import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/memory.dart';
import '../../models/photo_reference.dart';

class MemoryRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _memoriesCollection(String bookId) {
    return _firestore.collection('books').doc(bookId).collection('memories');
  }

  Memory _memoryFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    return Memory(
      memoryId: doc.id,
      memoryDate: (data['memoryDate'] as Timestamp).toDate(),
      text: data['text'] as String? ?? '',
      photoRefs: (data['photoRefs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PhotoReference.fromMap)
          .toList(),
      createdBy: data['createdBy'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hiddenFromBook: data['hiddenFromBook'] as bool? ?? false,
      schemaVersion: data['schemaVersion'] as int? ?? 1,
    );
  }

  Future<void> createMemory({
    required String bookId,
    required String text,
    required List<PhotoReference> photoRefs,
    DateTime? memoryDate,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final memoryRef = _memoriesCollection(bookId).doc();

    await memoryRef.set({
      'memoryId': memoryRef.id,
      'memoryDate': memoryDate ?? DateTime.now(),
      'text': text,
      'photoRefs': photoRefs.map((photo) => photo.toMap()).toList(),
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'hiddenFromBook': false,
      'schemaVersion': currentMemorySchemaVersion,
    });
  }

  Future<void> updateMemory({
    required String bookId,
    required String memoryId,
    required String text,
    required DateTime memoryDate,
    required List<PhotoReference> photoRefs,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _memoriesCollection(bookId).doc(memoryId).update({
      'text': text,
      'memoryDate': memoryDate,
      'photoRefs': photoRefs.map((photo) => photo.toMap()).toList(),
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

    await _memoriesCollection(bookId).doc(memoryId).delete();
  }

  /// Live view of the most recent [limit] memories, newest `memoryDate`
  /// first. Bounded so a book with hundreds of memories doesn't stream its
  /// entire history on every open. Pair with [getOlderMemories] to page
  /// further back. See PRODUCT_SPEC.md §16.
  Stream<List<Memory>> watchRecentMemories(String bookId, {required int limit}) {
    return _memoriesCollection(bookId)
        .orderBy('memoryDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_memoryFromDoc).toList());
  }

  /// One-shot fetch of up to [limit] memories older than [before]. Not a
  /// live stream — a page loaded this way won't reflect later edits until
  /// the screen reloads it, which is an accepted trade-off for keeping
  /// pagination simple (see docs/CODE_REVIEW.md §7).
  Future<List<Memory>> getOlderMemories(
    String bookId, {
    required DateTime before,
    required int limit,
  }) async {
    final snapshot = await _memoriesCollection(bookId)
        .orderBy('memoryDate', descending: true)
        .startAfter([Timestamp.fromDate(before)])
        .limit(limit)
        .get();

    return snapshot.docs.map(_memoryFromDoc).toList();
  }

  /// Every memory in the book in one shot, unordered concerns aside — used
  /// for whole-book operations (e.g. collecting every photo to delete when
  /// the book itself is deleted), not for display.
  Future<List<Memory>> getMemoriesOnce(String bookId) async {
    final snapshot = await _memoriesCollection(bookId).get();

    return snapshot.docs.map(_memoryFromDoc).toList();
  }
}
