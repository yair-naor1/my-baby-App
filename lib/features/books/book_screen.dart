import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/book_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/services/book_service.dart';
import '../../data/services/memory_service.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../../models/photo_reference.dart';
import '../../services/r2_photo_storage_service.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../../widgets/stored_photo_image.dart';
import '../albums/album_generate_sheet.dart';
import '../memories/memory_form_screen.dart';
import 'book_form_screen.dart';
import 'ideas_screen.dart';

class BookScreen extends StatefulWidget {
  final Book book;

  const BookScreen({super.key, required this.book});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  // Bounded so a book with hundreds of memories doesn't stream its entire
  // history on every open — see PRODUCT_SPEC.md §16 and
  // docs/CODE_REVIEW.md §7.
  static const _pageSize = 30;

  final _bookRepository = BookRepository();
  final _memoryRepository = MemoryRepository();
  final _photoStorage = R2PhotoStorageService();
  late final MemoryService _memoryService = MemoryService(
    photoStorage: _photoStorage,
    memoryRepository: _memoryRepository,
  );
  late final BookService _bookService = BookService(
    bookRepository: _bookRepository,
    memoryRepository: _memoryRepository,
    photoStorage: _photoStorage,
  );
  late final Stream<Book?> _bookStream = _bookRepository.watchBook(
    widget.book.bookId,
  );
  late final Stream<List<Memory>> _recentStream = _memoryRepository
      .watchRecentMemories(widget.book.bookId, limit: _pageSize);

  // One-shot older pages loaded via "Load earlier memories". Not live —
  // see MemoryRepository.getOlderMemories.
  final List<Memory> _olderMemories = [];
  int _olderPagesLoaded = 0;
  bool _hasMoreOlderPages = true;
  bool _isLoadingOlder = false;

  // Google Photos-style ordering toggle for the timeline — newest-first by
  // default, flippable back to the spec's chronological (oldest-first)
  // order. Local UI state only, not persisted: each open of the book starts
  // newest-first again.
  bool _newestFirst = true;

  Future<void> _loadOlderMemories(DateTime before) async {
    if (_isLoadingOlder) return;

    setState(() {
      _isLoadingOlder = true;
    });

    try {
      final older = await _memoryRepository.getOlderMemories(
        widget.book.bookId,
        before: before,
        limit: _pageSize,
      );

      if (!mounted) return;

      setState(() {
        _olderMemories.addAll(older);
        _olderPagesLoaded++;
        _hasMoreOlderPages = older.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlder = false;
        });
      }
    }
  }

  Future<void> _deleteMemory(Memory memory, {required bool isHebrew}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        // showDialog uses the root navigator, so it never inherits any
        // Directionality this screen's own tree might declare — without an
        // explicit one here, Hebrew text shapes correctly but the
        // paragraph still aligns to the app-wide LTR default.
        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(isHebrew ? 'למחוק את הזיכרון?' : 'Delete memory?'),
            content: Text(
              isHebrew
                  ? 'הזיכרון יוסר לצמיתות מהספר.'
                  : 'This memory will be permanently removed from the book.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(isHebrew ? 'ביטול' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isHebrew ? 'מחיקה' : 'Delete'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _memoryService.deleteMemory(
        bookId: widget.book.bookId,
        memory: memory,
      );

      if (!mounted) return;

      // The recent list is live and will drop this on its own; a page
      // loaded via "Load earlier memories" is not, so remove it manually.
      setState(() {
        _olderMemories.removeWhere((m) => m.memoryId == memory.memoryId);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  void _openMemory(Memory? memory, Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryFormScreen(
          bookId: widget.book.bookId,
          memory: memory,
          memoryService: _memoryService,
          childGender: book.childGender,
          dateDisplay: book.dateDisplay,
          language: book.language,
        ),
      ),
    );
  }

  void _openIdeas(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => IdeasScreen(book: book)),
    );
  }

  void _editBookInfo(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookFormScreen(book: book)),
    );
  }

  Future<void> _renameBook(Book book) async {
    var editedName = book.childName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        final isHebrew = book.language == 'he';

        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(isHebrew ? 'שינוי שם הספר' : 'Rename Book'),
            content: TextFormField(
              initialValue: book.childName,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isHebrew ? "שם הילד/ה" : "Child's name",
              ),
              onChanged: (value) {
                editedName = value;
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isHebrew ? 'ביטול' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = editedName.trim();

                  if (name.isNotEmpty) {
                    Navigator.pop(context, name);
                  }
                },
                child: Text(isHebrew ? 'שמירה' : 'Save'),
              ),
            ],
          ),
        );
      },
    );

    if (newName == null || !mounted) return;

    try {
      await _bookRepository.updateBookName(
        bookId: book.bookId,
        childName: newName,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _deleteBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isHebrew = book.language == 'he';

        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(isHebrew ? 'למחוק את הספר?' : 'Delete book?'),
            content: Text(
              isHebrew
                  ? 'למחוק את ${book.childName} ואת כל הזיכרונות בספר הזה?\n\n'
                        'לא ניתן לבטל פעולה זו.'
                  : 'Delete ${book.childName} and all memories in this book?\n\n'
                        'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(isHebrew ? 'ביטול' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isHebrew ? 'מחיקה' : 'Delete'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _bookService.deleteBook(book.bookId);

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _openAlbum(Book book) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Memory> memories;

    try {
      memories = await _memoryRepository.getMemoriesOnce(widget.book.bookId);
    } catch (e) {
      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      return;
    }

    if (!mounted) return;

    Navigator.pop(context);

    await showAlbumGenerateSheet(
      context,
      book: book,
      memories: memories,
      photoStorage: _photoStorage,
    );
  }

  void _showComingSoon(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shares this book's share code (spec §11) — its own `bookId`, an
  /// unguessable Firestore auto-id doubling as a non-expiring invite code —
  /// straight through the OS share sheet (WhatsApp, Messages, email, etc.)
  /// via share_plus. Goes directly to the share sheet with no intermediate
  /// dialog; most share sheets already offer their own "copy" target for
  /// anyone who wants the code without picking an app.
  Future<void> _shareAlbum(Book book) async {
    final isHebrew = book.language == 'he';
    final box = context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        text: isHebrew
            ? 'הצטרפו לספר של ${book.childName} באפליקציית '
                  'Baby Book! קוד ההצטרפות: ${book.bookId}'
            : "Join ${book.childName}'s book on Baby Book! "
                  'Use this code: ${book.bookId}',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Book?>(
      stream: _bookStream,
      initialData: widget.book,
      builder: (context, snapshot) {
        final book = snapshot.data ?? widget.book;

        return Scaffold(
          appBar: AppBar(
            title: Text(book.childName),
            actions: [
              IconButton(
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: Icon(
                  _newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                ),
                tooltip: book.language == 'he'
                    ? (_newestFirst
                          ? 'מהחדש לישן — הקישו למיון הפוך'
                          : 'מהישן לחדש — הקישו למיון הפוך')
                    : (_newestFirst
                          ? 'Newest first — tap to reverse'
                          : 'Oldest first — tap to reverse'),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'ideas':
                      _openIdeas(book);
                    case 'album':
                      _openAlbum(book);
                    case 'album_settings':
                      _showComingSoon(
                        book.language == 'he'
                            ? 'הגדרות אלבום יגיעו בקרוב.'
                            : 'Album Settings is coming soon.',
                      );
                    case 'print_guide':
                      _showComingSoon(
                        book.language == 'he'
                            ? 'מדריך ההדפסה יגיע בקרוב.'
                            : 'The printing guide is coming soon.',
                      );
                    case 'share_album':
                      _shareAlbum(book);
                    case 'edit_info':
                      _editBookInfo(book);
                    case 'rename':
                      _renameBook(book);
                    case 'delete':
                      _deleteBook(book);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'ideas',
                    child: Text(book.language == 'he' ? 'רעיונות' : 'Ideas'),
                  ),
                  PopupMenuItem(
                    value: 'album',
                    child: Text(book.language == 'he' ? 'אלבום' : 'Album'),
                  ),
                  PopupMenuItem(
                    value: 'album_settings',
                    child: Text(
                      book.language == 'he' ? 'הגדרות אלבום' : 'Album Settings',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'print_guide',
                    child: Text(
                      book.language == 'he' ? 'מדריך הדפסה' : 'Printing Guide',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_album',
                    child: Text(
                      book.language == 'he' ? 'שיתוף אלבום' : 'Share Album',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'edit_info',
                    child: Text(
                      book.language == 'he'
                          ? 'עריכת פרטי הספר'
                          : 'Edit Book Info',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(
                      book.language == 'he' ? 'שינוי שם' : 'Rename Book',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      book.language == 'he' ? 'מחיקת ספר' : 'Delete Book',
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _BookCoverHeader(book: book),
              Expanded(child: _buildMemoryList(context, book)),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openMemory(null, book),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildMemoryList(BuildContext context, Book book) {
    return StreamBuilder<List<Memory>>(
      stream: _recentStream,

      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final isHebrew = book.language == 'he';

        if (snapshot.hasError) {
          return Center(
            child: Text(
              isHebrew
                  ? 'שגיאה: ${snapshot.error}'
                  : 'Error: ${snapshot.error}',
            ),
          );
        }

        final recent = snapshot.data ?? [];

        // The live "recent" page is authoritative for any memory it
        // contains; a memory only present in a statically-loaded older
        // page falls back to that copy. Chronological (oldest-first) is
        // the canonical order the rest of the app (album, pagination
        // cursor) relies on — [_newestFirst] only flips the *display*
        // order, applied last.
        final byId = <String, Memory>{
          for (final memory in _olderMemories) memory.memoryId: memory,
          for (final memory in recent) memory.memoryId: memory,
        };
        final memories = byId.values.toList()
          ..sort((a, b) => a.memoryDate.compareTo(b.memoryDate));

        if (memories.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  isHebrew
                      ? 'אין עדיין זיכרונות.\nהוסיפו את הזיכרון הראשון שלכם!'
                      : 'No memories yet.\nAdd your first memory!',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final showLoadMore = _olderPagesLoaded == 0
            ? recent.length >= _pageSize
            : _hasMoreOlderPages;

        final ordered = _newestFirst ? memories.reversed.toList() : memories;
        final itemCount = ordered.length + (showLoadMore ? 1 : 0);

        // "Load earlier memories" always targets the oldest loaded memory
        // regardless of display order, since it pages further into the
        // past — so it belongs at whichever end of the list the oldest
        // memory is currently shown.
        final loadMoreAtEnd = _newestFirst;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final isLoadMoreSlot =
                showLoadMore &&
                (loadMoreAtEnd ? index == itemCount - 1 : index == 0);

            if (isLoadMoreSlot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: _isLoadingOlder
                      ? const CircularProgressIndicator()
                      : TextButton(
                          onPressed: () =>
                              _loadOlderMemories(memories.first.memoryDate),
                          child: Text(
                            isHebrew
                                ? 'טעינת זיכרונות ישנים יותר'
                                : 'Load earlier memories',
                          ),
                        ),
                ),
              );
            }

            final memory =
                ordered[loadMoreAtEnd || !showLoadMore ? index : index - 1];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemoryCard(
                key: ValueKey(memory.memoryId),
                memory: memory,
                dateDisplay: book.dateDisplay,
                isHebrew: isHebrew,
                onTap: () => _openMemory(memory, book),
                onDelete: () => _deleteMemory(memory, isHebrew: isHebrew),
              ),
            );
          },
        );
      },
    );
  }
}

/// The book's cover photo (spec §7.1/§7.2) shown at the top when entering
/// the album. Collapses to nothing when no cover photo is set, so a book
/// without one loses no space to a placeholder.
class _BookCoverHeader extends StatelessWidget {
  const _BookCoverHeader({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final coverPhoto = book.coverPhoto;

    if (coverPhoto == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 160,
      child: StoredPhotoImage(
        fileId: coverPhoto.thumbnailFileId ?? coverPhoto.originalFileId,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Every memory renders at the same fixed height regardless of how much
/// text or how many photos it has — a memory with five photos takes the
/// same vertical space as a text-only one. Photos are represented by a
/// single fixed-size thumbnail plus a "+N" badge rather than a row that
/// would grow with the photo count.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    super.key,
    required this.memory,
    required this.dateDisplay,
    required this.isHebrew,
    required this.onTap,
    required this.onDelete,
  });

  static const double height = 96;
  static const double _thumbnailSize = 72;

  final Memory memory;
  final String dateDisplay;
  final bool isHebrew;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _MemoryThumbnail(
                  photoRefs: memory.photoRefs,
                  size: _thumbnailSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatDate(memory.memoryDate, dateDisplay),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        memory.text.isNotEmpty
                            ? memory.text
                            : (isHebrew ? 'זיכרון עם תמונה' : 'Photo memory'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: memory.text.isEmpty
                            ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context).colorScheme.outline,
                              )
                            : Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: isHebrew ? 'מחיקת זיכרון' : 'Delete memory',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({required this.photoRefs, required this.size});

  final List<PhotoReference> photoRefs;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (photoRefs.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.auto_stories_outlined,
          color: colorScheme.onSecondaryContainer,
        ),
      );
    }

    final firstPhoto = photoRefs.first;
    final extraCount = photoRefs.length - 1;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: size,
              height: size,
              child: StoredPhotoImage(
                key: ValueKey(
                  firstPhoto.thumbnailFileId ?? firstPhoto.originalFileId,
                ),
                fileId: firstPhoto.thumbnailFileId ?? firstPhoto.originalFileId,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (extraCount > 0)
            Positioned.directional(
              textDirection: Directionality.of(context),
              end: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
