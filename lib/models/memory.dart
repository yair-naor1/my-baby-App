import 'photo_reference.dart';

class Memory {
  final String memoryId;
  final DateTime memoryDate;
  final String text;
  final List<PhotoReference> photoRefs;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hiddenFromBook;

  Memory({
    required this.memoryId,
    required this.memoryDate,
    required this.text,
    required this.photoRefs,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.hiddenFromBook,
  });
}
