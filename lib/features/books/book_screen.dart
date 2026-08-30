import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../data/services/memory_service.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../../models/photo_reference.dart';
import '../../services/google_drive_service.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../../widgets/drive_image.dart';
import '../memories/memory_form_screen.dart';

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

  final _memoryRepository = MemoryRepository();
  late final MemoryService _memoryService = MemoryService(
    photoStorage: GoogleDriveService(),
    memoryRepository: _memoryRepository,
  );
  late final Stream<List<Memory>> _recentStream = _memoryRepository
      .watchRecentMemories(widget.book.bookId, limit: _pageSize);

  // One-shot older pages loaded via "Load earlier memories". Not live —
  // see MemoryRepository.getOlderMemories.
  final List<Memory> _olderMemories = [];
  int _olderPagesLoaded = 0;
  bool _hasMoreOlderPages = true;
  bool _isLoadingOlder = false;

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

  Future<void> _deleteMemory(Memory memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete memory?'),
          content: const Text(
            'This memory will be permanently removed from the book.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
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

  void _openMemory(Memory? memory) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryFormScreen(
          bookId: widget.book.bookId,
          memory: memory,
          memoryService: _memoryService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.childName)),
      body: Column(
        children: [
          _BookCoverHeader(book: widget.book),
          Expanded(child: _buildMemoryList(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openMemory(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMemoryList(BuildContext context) {
    return StreamBuilder<List<Memory>>(
        stream: _recentStream,

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final recent = snapshot.data ?? [];

          // The live "recent" page is authoritative for any memory it
          // contains; a memory only present in a statically-loaded older
          // page falls back to that copy.
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
                  const Text(
                    'No memories yet.\nAdd your first memory!',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final showLoadMore = _olderPagesLoaded == 0
              ? recent.length >= _pageSize
              : _hasMoreOlderPages;

          final itemCount = memories.length + (showLoadMore ? 1 : 0);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (showLoadMore && index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: _isLoadingOlder
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: () =>
                                _loadOlderMemories(memories.first.memoryDate),
                            child: const Text('Load earlier memories'),
                          ),
                  ),
                );
              }

              final memory = memories[showLoadMore ? index - 1 : index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MemoryCard(
                  key: ValueKey(memory.memoryId),
                  memory: memory,
                  onTap: () => _openMemory(memory),
                  onDelete: () => _deleteMemory(memory),
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
      child: DriveImage(
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
    required this.onTap,
    required this.onDelete,
  });

  static const double height = 96;
  static const double _thumbnailSize = 72;

  final Memory memory;
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
                        formatShortDate(memory.memoryDate),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        memory.text.isNotEmpty ? memory.text : 'Photo memory',
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
                  tooltip: 'Delete memory',
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
              child: DriveImage(
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
