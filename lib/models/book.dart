import 'photo_reference.dart';

/// Bump when the Firestore document shape for `books/{bookId}` changes in a
/// way old clients can't read safely. See PRODUCT_SPEC.md §8.4.
const currentBookSchemaVersion = 1;

class Book {
  final String bookId;
  final String childName;
  final DateTime birthDate;
  final List<String> ownerIds;
  final String language;
  final DateTime createdAt;
  final int schemaVersion;

  // Optional book-creation questions — spec §7.1: "birth place, birth time,
  // weight/height at birth, the birth story, and a cover photo."
  final String? birthPlace;
  final String? birthTime;
  final double? birthWeightKg;
  final double? birthHeightCm;
  final String? birthStory;
  final PhotoReference? coverPhoto;
  final List<PhotoReference> birthPhotos;

  Book({
    required this.bookId,
    required this.childName,
    required this.birthDate,
    required this.ownerIds,
    required this.language,
    required this.createdAt,
    required this.schemaVersion,
    this.birthPlace,
    this.birthTime,
    this.birthWeightKg,
    this.birthHeightCm,
    this.birthStory,
    this.coverPhoto,
    this.birthPhotos = const [],
  });
}
