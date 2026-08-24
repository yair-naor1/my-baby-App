import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../memories/memory_form_screen.dart';

class BookScreen extends StatelessWidget {
  final Book book;

  const BookScreen({super.key, required this.book});

  Future<void> _deleteMemory(
    BuildContext context,
    MemoryRepository repository,
    Memory memory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete memory?'),
          content: const Text('This memory will be permanently deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await repository.deleteMemory(
        bookId: book.bookId,
        memoryId: memory.memoryId,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Memory deleted')));
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete memory: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoryRepository = MemoryRepository();

    return Scaffold(
      appBar: AppBar(title: Text(book.childName)),
      body: StreamBuilder<List<Memory>>(
        stream: memoryRepository.watchMemories(book.bookId),
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

              return Card(
                key: ValueKey(memory.memoryId),
                child: ListTile(
                  title: Text(memory.text),
                  subtitle: Text(
                    '${memory.memoryDate.day}/'
                    '${memory.memoryDate.month}/'
                    '${memory.memoryDate.year}',
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MemoryFormScreen(
                              bookId: book.bookId,
                              memory: memory,
                            ),
                          ),
                        );
                      } else if (value == 'delete') {
                        _deleteMemory(context, memoryRepository, memory);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
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
              builder: (_) => MemoryFormScreen(bookId: book.bookId),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
