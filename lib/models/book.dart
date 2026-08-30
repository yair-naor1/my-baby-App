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

  Book({
    required this.bookId,
    required this.childName,
    required this.birthDate,
    required this.ownerIds,
    required this.language,
    required this.createdAt,
    required this.schemaVersion,
  });
}
