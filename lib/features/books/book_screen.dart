import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../data/services/memory_service.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
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
      body: StreamBuilder<List<Memory>>(
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
            return const Center(
              child: Text(
                'No memories yet.\nAdd your first memory!',
                textAlign: TextAlign.center,
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

              final previewPhotos = memory.photoRefs.take(3).toList();

              return Card(
                key: ValueKey(memory.memoryId),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openMemory(memory),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (previewPhotos.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final photo in previewPhotos)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: DriveImage(
                                      key: ValueKey(
                                        photo.thumbnailFileId ??
                                            photo.originalFileId,
                                      ),
                                      fileId:
                                          photo.thumbnailFileId ??
                                          photo.originalFileId,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        if (memory.text.isNotEmpty)
                          Text(
                            memory.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                        if (memory.text.isNotEmpty) const SizedBox(height: 6),

                        Row(
                          children: [
                            Expanded(
                              child: Text(formatShortDate(memory.memoryDate)),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _openMemory(memory);
                                } else if (value == 'delete') {
                                  _deleteMemory(memory);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openMemory(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
