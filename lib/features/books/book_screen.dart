import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../memories/add_memory_screen.dart';

class BookScreen extends StatelessWidget {
  final Book book;

  const BookScreen({super.key, required this.book});

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
                child: ListTile(
                  title: Text(memory.text),
                  subtitle: Text(
                    '${memory.memoryDate.day}/'
                    '${memory.memoryDate.month}/'
                    '${memory.memoryDate.year}',
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
              builder: (_) => AddMemoryScreen(bookId: book.bookId),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
