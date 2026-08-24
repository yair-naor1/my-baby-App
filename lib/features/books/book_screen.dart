import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../../widgets/drive_image.dart';
import '../memories/memory_form_screen.dart';

class BookScreen extends StatefulWidget {
  final Book book;

  const BookScreen({super.key, required this.book});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  @override
  Widget build(BuildContext context) {
    final memoryRepository = MemoryRepository();

    return Scaffold(
      appBar: AppBar(title: Text(widget.book.childName)),
      body: StreamBuilder<List<Memory>>(
        stream: memoryRepository.watchMemories(widget.book.bookId),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final memories = snapshot.data ?? [];

          if (memories.isEmpty) {
            return const Center(
              child: Text(
                'No memories yet.\nAdd your first memory!',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: memories.length,
            itemBuilder: (context, index) {
              final memory = memories[index];

              final previewPhotos = memory.photoRefs.take(5).toList();

              return Card(
                key: ValueKey(memory.memoryId),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MemoryFormScreen(
                          bookId: widget.book.bookId,
                          memory: memory,
                        ),
                      ),
                    );
                  },
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
                              child: Text(
                                '${memory.memoryDate.day}/'
                                '${memory.memoryDate.month}/'
                                '${memory.memoryDate.year}',
                              ),
                            ),
                            const Icon(Icons.chevron_right),
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
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemoryFormScreen(bookId: widget.book.bookId),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
