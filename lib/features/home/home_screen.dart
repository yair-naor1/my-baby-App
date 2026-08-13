import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/repositories/book_repository.dart';
import '../../models/book.dart';
import '../books/create_book_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final bookRepository = BookRepository();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Baby Book'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),

      body: StreamBuilder<List<Book>>(
        stream: bookRepository.watchMyBooks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          final books = snapshot.data ?? [];

          if (books.isEmpty) {
            return const Center(
              child: Text(
                'No books yet.\nCreate your first one!',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];

              return Card(
                child: ListTile(
                  title: Text(book.childName),
                  subtitle: Text(
                    'Born ${book.birthDate.day}/'
                    '${book.birthDate.month}/'
                    '${book.birthDate.year}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Next step: open the Book timeline.
                  },
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
              builder: (_) => const CreateBookScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}