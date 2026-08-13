class Book {
  final String bookId;
  final String childName;
  final DateTime birthDate;
  final List<String> ownerIds;
  final String language;
  final DateTime createdAt;

  Book({
    required this.bookId,
    required this.childName,
    required this.birthDate,
    required this.ownerIds,
    required this.language,
    required this.createdAt,
  });
}