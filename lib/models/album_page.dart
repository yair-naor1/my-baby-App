import 'memory.dart';
import 'photo_reference.dart';

/// How a memory page's photo(s) are arranged — a content-level decision, not
/// a visual one. Each [AlbumDesign] renderer interprets the same arrangement
/// in its own visual language, so this stays here rather than in a design.
enum AlbumPageArrangement { textOnly, singlePhoto, photoGrid }

/// One page of a generated album. Sealed so every renderer (in-app viewer,
/// PDF export) gets an exhaustiveness check from the analyzer if a new page
/// kind is ever added — no silently-unhandled case.
sealed class AlbumPage {
  const AlbumPage();
}

class AlbumCoverPage extends AlbumPage {
  final String childName;
  final DateTime birthDate;
  final PhotoReference? coverPhoto;

  const AlbumCoverPage({
    required this.childName,
    required this.birthDate,
    this.coverPhoto,
  });
}

/// One or more memories sharing a page. The layout builder currently always
/// produces single-memory pages (see AlbumLayoutBuilder) — this stays a list
/// so the "several short memories on one page" grouping from
/// PRODUCT_SPEC.md §14 can be added later without changing the page shape
/// every renderer already depends on.
class AlbumMemoryPage extends AlbumPage {
  final List<Memory> memories;
  final AlbumPageArrangement arrangement;

  const AlbumMemoryPage({required this.memories, required this.arrangement});
}

/// A chapter-style divider inserted before the first memory of a new month
/// of the child's life, so the album reads as a timeline rather than one
/// undifferentiated stream of memory pages.
class AlbumMonthDividerPage extends AlbumPage {
  /// 0 = the child's first month, 1 = the second, and so on.
  final int monthNumber;

  /// A representative photo from that month, if any memory in it has one —
  /// purely decorative, never required.
  final PhotoReference? representativePhoto;

  const AlbumMonthDividerPage({
    required this.monthNumber,
    this.representativePhoto,
  });
}
