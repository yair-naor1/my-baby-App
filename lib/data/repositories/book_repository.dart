import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/book.dart';
import '../../models/photo_reference.dart';

class BookRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Book _bookFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    return Book(
      bookId: doc.id,
      childName: data['childName'] as String,
      birthDate: (data['birthDate'] as Timestamp).toDate(),
      ownerIds: List<String>.from(data['ownerIds']),
      language: data['language'] as String? ?? 'en',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      schemaVersion: data['schemaVersion'] as int? ?? 1,
      birthPlace: data['birthPlace'] as String?,
      birthTime: data['birthTime'] as String?,
      birthWeightKg: (data['birthWeightKg'] as num?)?.toDouble(),
      birthHeightCm: (data['birthHeightCm'] as num?)?.toDouble(),
      birthStory: data['birthStory'] as String?,
      coverPhoto: data['coverPhoto'] != null
          ? PhotoReference.fromMap(data['coverPhoto'] as Map<String, dynamic>)
          : null,
      birthPhotos: (data['birthPhotos'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PhotoReference.fromMap)
          .toList(),
    );
  }

  Future<Book?> getBook(String bookId) async {
    final doc = await _firestore.collection('books').doc(bookId).get();

    if (!doc.exists) return null;

    return _bookFromDoc(doc);
  }

  /// Allocates a book id before the Firestore document exists, so photos can
  /// be uploaded to that book's Drive folder first — same upload-before-write
  /// ordering [MemoryRepository]/[MemoryService] use, needed here because a
  /// new book has no id yet at the point its cover/birth photos are chosen.
  String reserveBookId() => _firestore.collection('books').doc().id;

  Future<void> updateBookName({
    required String bookId,
    required String childName,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _firestore.collection('books').doc(bookId).update({
      'childName': childName,
    });
  }

  /// Updates every book-info field editable after creation. Always writes
  /// every field so clearing an optional value (e.g. removing the birth
  /// story) actually clears it in Firestore rather than leaving it stale.
  Future<void> updateBookInfo({
    required String bookId,
    required String childName,
    required DateTime birthDate,
    String? birthPlace,
    String? birthTime,
    double? birthWeightKg,
    double? birthHeightCm,
    String? birthStory,
    PhotoReference? coverPhoto,
    required List<PhotoReference> birthPhotos,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _firestore.collection('books').doc(bookId).update({
      'childName': childName,
      'birthDate': birthDate,
      'birthPlace': birthPlace,
      'birthTime': birthTime,
      'birthWeightKg': birthWeightKg,
      'birthHeightCm': birthHeightCm,
      'birthStory': birthStory,
      'coverPhoto': coverPhoto?.toMap(),
      'birthPhotos': birthPhotos.map((photo) => photo.toMap()).toList(),
    });
  }

  Future<void> deleteBook(String bookId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    final memories = await _firestore
        .collection('books')
        .doc(bookId)
        .collection('memories')
        .get();

    var batch = _firestore.batch();
    var operationCount = 0;

    for (final memory in memories.docs) {
      batch.delete(memory.reference);
      operationCount++;

      if (operationCount == 450) {
        await batch.commit();
        batch = _firestore.batch();
        operationCount = 0;
      }
    }

    if (operationCount > 0) {
      await batch.commit();
    }

    await _firestore.collection('books').doc(bookId).delete();
  }

  /// Creates the book document at [bookId] — reserve it first with
  /// [reserveBookId] so any cover/birth photos can be uploaded to that id's
  /// Drive folder before this write, following the same order
  /// [MemoryService.saveMemory] uses for memory photos.
  Future<void> createBook({
    required String bookId,
    required String childName,
    required DateTime birthDate,
    String? birthPlace,
    String? birthTime,
    double? birthWeightKg,
    double? birthHeightCm,
    String? birthStory,
    PhotoReference? coverPhoto,
    List<PhotoReference> birthPhotos = const [],
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('User is not logged in');
    }

    await _firestore.collection('books').doc(bookId).set({
      'bookId': bookId,
      'childName': childName,
      'birthDate': birthDate,
      'birthPlace': birthPlace,
      'birthTime': birthTime,
      'birthWeightKg': birthWeightKg,
      'birthHeightCm': birthHeightCm,
      'birthStory': birthStory,
      'coverPhoto': coverPhoto?.toMap(),
      'birthPhotos': birthPhotos.map((photo) => photo.toMap()).toList(),
      'ownerIds': [user.uid],
      'language': 'en',
      'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': currentBookSchemaVersion,
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
          final books = snapshot.docs.map(_bookFromDoc).toList();

          books.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          return books;
        });
  }
}
