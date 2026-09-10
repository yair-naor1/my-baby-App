import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/services/book_sharing_service.dart';
import '../../models/book.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../books/book_form_screen.dart';
import '../books/book_screen.dart';
import '../../services/google_auth_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/stored_photo_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bookRepository = BookRepository();
  final _googleAuthService = GoogleAuthService();
  final _authRepository = AuthRepository();
  final _bookSharingService = BookSharingService();
  late final _booksStream = _bookRepository.watchMyBooks();
  late bool _isGoogleLinked = _checkGoogleLinked();
  bool _isLinkingGoogle = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: reminders are best-effort, shouldn't block or fail
    // the home screen if permission is denied or registration errors out.
    NotificationService().initialize();
  }

  bool _checkGoogleLinked() {
    return FirebaseAuth.instance.currentUser?.providerData.any(
          (info) => info.providerId == 'google.com',
        ) ??
        false;
  }

  Future<void> _linkGoogleAccount({required bool isHebrew}) async {
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
        SnackBar(
          content: Text(
            isHebrew ? 'חשבון Google קושר בהצלחה.' : 'Google account linked.',
          ),
        ),
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
      await _googleAuthService.clearSession();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  /// Prompts for a share code (spec §11 — see book_screen.dart's
  /// "Share Album", which shows the code the other parent enters here) and
  /// joins that book via the `joinBook` Cloud Function. [isHebrew] follows
  /// the same signal the rest of this screen uses (the first book's own
  /// language) since no book is selected yet at this exact point.
  Future<void> _joinBook({required bool isHebrew}) async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (context) {
        // showDialog uses the root navigator, above any Directionality this
        // screen might declare — an explicit one here is needed for Hebrew
        // text to actually right-align, not just shape correctly.
        return Directionality(
          textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(isHebrew ? 'הצטרפות לספר' : 'Join a Book'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isHebrew ? 'קוד הצטרפות' : 'Share code',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isHebrew ? 'ביטול' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final trimmed = controller.text.trim();
                  if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
                },
                child: Text(isHebrew ? 'הצטרפות' : 'Join'),
              ),
            ],
          ),
        );
      },
    );

    if (code == null || !mounted) return;

    try {
      final childName = await _bookSharingService.joinBook(code);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isHebrew
                ? 'הצטרפתם לספר של $childName!'
                : "Joined $childName's book!",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Book>>(
      stream: _booksStream,
      builder: (context, snapshot) {
        final books = snapshot.data ?? [];

        // No book-independent language preference exists yet (spec §7.1
        // scopes language per book, not per account) — the first book's own
        // language is the closest available signal for a screen that lists
        // every book at once. Falls back to English before any book loads
        // or exists, matching auth/pre-book screens elsewhere.
        final isHebrew = books.isNotEmpty && books.first.language == 'he';

        return Scaffold(
          appBar: AppBar(
            title: Text(isHebrew ? 'האלבומים שלי' : 'My albums'),
            actions: [
              IconButton(
                onPressed: () => _joinBook(isHebrew: isHebrew),
                icon: const Icon(Icons.group_add),
                tooltip: isHebrew ? 'הצטרפות לספר' : 'Join a Book',
              ),
              if (!_isGoogleLinked)
                IconButton(
                  onPressed: _isLinkingGoogle
                      ? null
                      : () => _linkGoogleAccount(isHebrew: isHebrew),
                  icon: _isLinkingGoogle
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  tooltip: isHebrew
                      ? 'קישור חשבון Google'
                      : 'Link Google Account',
                ),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                tooltip: isHebrew ? 'התנתקות' : 'Logout',
              ),
            ],
          ),

          body: Builder(
            builder: (context) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    isHebrew
                        ? 'שגיאה: ${snapshot.error}'
                        : 'Error: ${snapshot.error}',
                  ),
                );
              }

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
                      Text(
                        isHebrew
                            ? 'אין עדיין ספרים.\nצרו את הספר הראשון שלכם!'
                            : 'No books yet.\nCreate your first one!',
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
                  final bookIsHebrew = book.language == 'he';

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
                        subtitle: Text(
                          bookIsHebrew
                              ? 'נולד/ה '
                                    '${formatDate(book.birthDate, book.dateDisplay)}'
                              : 'Born ${formatDate(book.birthDate, book.dateDisplay)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
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
      },
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
        child: StoredPhotoImage(
          fileId: coverPhoto.thumbnailFileId ?? coverPhoto.originalFileId,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
