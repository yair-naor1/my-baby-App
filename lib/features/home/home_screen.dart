import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/services/book_service.dart';
import '../../models/book.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../books/book_form_screen.dart';
import '../books/book_screen.dart';
import '../../services/google_drive_service.dart';
import '../../widgets/drive_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bookRepository = BookRepository();
  final _googleDriveService = GoogleDriveService();
  final _authRepository = AuthRepository();
  late final _bookService = BookService(
    bookRepository: _bookRepository,
    memoryRepository: MemoryRepository(),
    photoStorage: _googleDriveService,
  );
  late final _booksStream = _bookRepository.watchMyBooks();
  late bool _isGoogleLinked = _checkGoogleLinked();
  bool _isLinkingGoogle = false;

  bool _checkGoogleLinked() {
    return FirebaseAuth.instance.currentUser?.providerData.any(
          (info) => info.providerId == 'google.com',
        ) ??
        false;
  }

  Future<void> _linkGoogleAccount() async {
    setState(() {
      _isLinkingGoogle = true;
    });

    try {
      await _authRepository.signInWithGoogle();

      if (!mounted) return;

      setState(() {
        _isGoogleLinked = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google account linked.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() {
          _isLinkingGoogle = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try {
      await _googleDriveService.clearSession();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _renameBook(Book book) async {
    var editedName = book.childName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Book'),
          content: TextFormField(
            initialValue: book.childName,
            autofocus: true,
            decoration: const InputDecoration(labelText: "Child's name"),
            onChanged: (value) {
              editedName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = editedName.trim();

                if (name.isNotEmpty) {
                  Navigator.pop(context, name);
                }
              },
              child: const Text('Save'),
            ),
          ],
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
        return AlertDialog(
          title: const Text('Delete book?'),
          content: Text(
            'Delete ${book.childName} and all memories in this book?\n\n'
            'This cannot be undone.',
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
      await _bookService.deleteBook(book.bookId);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My albums'),
        actions: [
          if (!_isGoogleLinked)
            IconButton(
              onPressed: _isLinkingGoogle ? null : _linkGoogleAccount,
              icon: _isLinkingGoogle
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              tooltip: 'Link Google Account',
            ),
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No books yet.\nCreate your first one!',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  key: ValueKey(book.bookId),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: _BookAvatar(book: book),
                    title: Text(book.childName),
                    subtitle: Text('Born ${formatShortDate(book.birthDate)}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameBook(book);
                        } else if (value == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookFormScreen(book: book),
                            ),
                          );
                        } else if (value == 'delete') {
                          _deleteBook(book);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Book Info'),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename Book'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Book'),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookScreen(book: book),
                        ),
                      );
                    },
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
            MaterialPageRoute(builder: (_) => const BookFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// The book's cover photo (spec §7.1/§7.2) where one is set, falling back to
/// the baby icon placeholder.
class _BookAvatar extends StatelessWidget {
  const _BookAvatar({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final coverPhoto = book.coverPhoto;

    if (coverPhoto == null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          Icons.child_care,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: DriveImage(
          fileId: coverPhoto.thumbnailFileId ?? coverPhoto.originalFileId,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
