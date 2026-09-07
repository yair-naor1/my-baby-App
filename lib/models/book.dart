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

  // 'gregorian' (default), 'hebrew', or 'both' — how dates are displayed for
  // this book (memory dates, birth date). Independent of [language]: a
  // Hebrew-language book doesn't have to want Hebrew-calendar dates, and
  // vice versa. Never affects the date *picker* itself, only the read-only
  // text shown once a date is picked.
  final String dateDisplay;

  final DateTime createdAt;
  final int schemaVersion;

  // Optional book-creation questions — spec §7.1: "birth place, birth time,
  // weight at birth, the birth story, and a cover photo."
  final String? birthPlace;
  final String? birthTime;
  final double? birthWeightKg;
  final String? birthStory;
  final PhotoReference? coverPhoto;
  final List<PhotoReference> birthPhotos;

  // 'male', 'female', or null (not specified). Used only to get Hebrew
  // grammatical gender right in AI text enhancement (spec §15) — never
  // shown as a label anywhere in the UI.
  final String? childGender;

  // IdeaPrompt.id values the parent has manually marked as already
  // captured, in the Ideas ((i)) screen — a soft, user-driven checklist,
  // never inferred automatically from memory content.
  final List<String> usedIdeaIds;

  Book({
    required this.bookId,
    required this.childName,
    required this.birthDate,
    required this.ownerIds,
    required this.language,
    required this.dateDisplay,
    required this.createdAt,
    required this.schemaVersion,
    this.birthPlace,
    this.birthTime,
    this.birthWeightKg,
    this.birthStory,
    this.coverPhoto,
    this.birthPhotos = const [],
    this.childGender,
    this.usedIdeaIds = const [],
  });
}
