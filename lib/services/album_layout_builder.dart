import '../models/album_page.dart';
import '../models/book.dart';
import '../models/memory.dart';
import '../models/photo_reference.dart';
import '../utils/text_direction.dart';

/// Turns a book's memories into an ordered, content-only album page plan.
///
/// Deliberately does not touch photo bytes or [PhotoStorageService] — it only
/// reads [PhotoReference] metadata already sitting on each [Memory], so
/// computing a page count never requires downloading a single photo. It also
/// takes no [AlbumDesign]: this plan describes *what* is on each page, never
/// *how it looks* — see [AlbumDesign]'s doc comment for why that split
/// matters.
class AlbumLayoutBuilder {
  /// [memories] does not need to be pre-sorted or pre-filtered — this method
  /// orders by `memoryDate` (PRODUCT_SPEC.md's "never createdAt" rule),
  /// drops anything [Memory.hiddenFromBook], and inserts a month divider
  /// before the first memory of each new month of the child's life.
  List<AlbumPage> build({required Book book, required List<Memory> memories}) {
    final visible = memories.where((memory) => !memory.hiddenFromBook).toList()
      ..sort((a, b) => a.memoryDate.compareTo(b.memoryDate));

    final pages = <AlbumPage>[
      AlbumCoverPage(
        childName: book.childName,
        birthDate: book.birthDate,
        coverPhoto: book.coverPhoto,
      ),
    ];

    // Grouped up front (rather than tracked while iterating) so the
    // divider's representative photo can look at every memory in its
    // month, not just the ones seen so far.
    final byMonth = <int, List<Memory>>{};
    for (final memory in visible) {
      final month = _monthsSinceBirth(book.birthDate, memory.memoryDate);
      byMonth.putIfAbsent(month, () => []).add(memory);
    }

    for (final month in byMonth.keys) {
      final monthMemories = byMonth[month]!;

      pages.add(
        AlbumMonthDividerPage(
          monthNumber: month,
          representativePhoto: _representativePhoto(monthMemories),
        ),
      );

      for (final memory in monthMemories) {
        pages.add(
          AlbumMemoryPage(
            memories: [memory],
            arrangement: _arrangementFor(memory),
          ),
        );
      }
    }

    return pages;
  }

  /// Whether this album's content is Hebrew — nothing in the app currently
  /// sets [Book.language] to anything but 'en' (see BookRepository.createBook),
  /// so language detection has to look at the actual text instead of trusting
  /// that field. If any real content is Hebrew, the whole album reads RTL —
  /// a book isn't meaningfully "a little bit RTL".
  bool detectIsRtl({required Book book, required List<Memory> memories}) {
    if (book.language == 'he') return true;
    if (containsHebrew(book.childName)) return true;
    return memories.any((memory) => containsHebrew(memory.text));
  }

  int _monthsSinceBirth(DateTime birthDate, DateTime date) {
    var months =
        (date.year - birthDate.year) * 12 + (date.month - birthDate.month);

    if (date.day < birthDate.day) months--;

    return months < 0 ? 0 : months;
  }

  PhotoReference? _representativePhoto(List<Memory> monthMemories) {
    for (final memory in monthMemories) {
      if (memory.photoRefs.isNotEmpty) return memory.photoRefs.first;
    }
    return null;
  }

  AlbumPageArrangement _arrangementFor(Memory memory) {
    if (memory.photoRefs.isEmpty) return AlbumPageArrangement.textOnly;
    if (memory.photoRefs.length == 1) return AlbumPageArrangement.singlePhoto;
    return AlbumPageArrangement.photoGrid;
  }
}
