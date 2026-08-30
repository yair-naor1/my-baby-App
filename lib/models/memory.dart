import 'photo_reference.dart';

/// Bump when the Firestore document shape for
/// `books/{bookId}/memories/{memoryId}` changes in a way old clients can't
/// read safely. See PRODUCT_SPEC.md §8.4.
const currentMemorySchemaVersion = 1;

class Memory {
  final String memoryId;
  final DateTime memoryDate;
  final String text;
  final List<PhotoReference> photoRefs;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hiddenFromBook;
  final int schemaVersion;

  Memory({
    required this.memoryId,
    required this.memoryDate,
    required this.text,
    required this.photoRefs,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.hiddenFromBook,
    required this.schemaVersion,
  });
}
