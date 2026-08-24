import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/repositories/book_repository.dart';
import '../../models/book.dart';
import '../books/create_book_screen.dart';
import '../books/book_screen.dart';
import '../../services/google_drive_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bookRepository = BookRepository();
  final _googleDriveService = GoogleDriveService();
  late final _booksStream = _bookRepository.watchMyBooks();

  Future<void> _logout() async {
    try {
      await _googleDriveService.clearSession();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baby Book'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),

      body: StreamBuilder<List<Book>>(
        stream: _booksStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
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
                key: ValueKey(book.bookId),
                child: ListTile(
                  title: Text(book.childName),
                  subtitle: Text(
                    'Born ${book.birthDate.day}/'
                    '${book.birthDate.month}/'
                    '${book.birthDate.year}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BookScreen(book: book)),
                    );
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
            MaterialPageRoute(builder: (_) => const CreateBookScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
