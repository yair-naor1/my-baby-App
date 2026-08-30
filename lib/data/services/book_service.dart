import '../../services/photo_storage_service.dart';
import '../repositories/book_repository.dart';
import '../repositories/memory_repository.dart';

/// Coordinates deleting a book with cleaning up its memories' photo files.
///
/// [BookRepository.deleteBook] already removes every memory document and
/// the book document itself; this adds the photo-storage cleanup that was
/// previously missing entirely, so deleting a book no longer orphans every
/// photo in it (docs/CODE_REVIEW.md §4).
class BookService {
  BookService({
    required BookRepository bookRepository,
    required MemoryRepository memoryRepository,
    required PhotoStorageService photoStorage,
  }) // Fields stay private while constructor params stay public-named, so
  // an initializing formal (which would force them to share a name) isn't
  // usable here.
  : _bookRepository = bookRepository, // ignore: prefer_initializing_formals
    // ignore: prefer_initializing_formals
    _memoryRepository = memoryRepository,
    _photoStorage = photoStorage; // ignore: prefer_initializing_formals

  final BookRepository _bookRepository;
  final MemoryRepository _memoryRepository;
  final PhotoStorageService _photoStorage;

  Future<void> deleteBook(String bookId) async {
    final memories = await _memoryRepository.getMemoriesOnce(bookId);
    final allPhotos = memories.expand((memory) => memory.photoRefs).toList();

    await _bookRepository.deleteBook(bookId);

    if (allPhotos.isNotEmpty) {
      try {
        await _photoStorage.deletePhotos(allPhotos);
      } catch (_) {
        // The book and its memories are already gone; a leftover Drive
        // file is a lesser harm than reporting a failed delete that
        // actually succeeded.
      }
    }
  }
}
