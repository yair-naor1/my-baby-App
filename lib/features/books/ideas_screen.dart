import 'package:flutter/material.dart';

import '../../data/idea_prompts.dart';
import '../../data/repositories/book_repository.dart';
import '../../models/book.dart';
import '../../models/idea_prompt.dart';

/// The Ideas ((i)) screen: browse categories, then the prompts within one
/// (spec §7.2). Never a questionnaire — tapping a prompt just marks it
/// "already captured / not interested" with a grey strikethrough; it never
/// navigates anywhere, so browsing ideas can't accidentally interrupt
/// writing a memory.
class IdeasScreen extends StatelessWidget {
  const IdeasScreen({super.key, required this.book, this.bookRepository});

  final Book book;
  final BookRepository? bookRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ideas')),
      body: ListView.builder(
        itemCount: ideaCategories.length,
        itemBuilder: (context, index) {
          final category = ideaCategories[index];
          final total = ideaPrompts
              .where((idea) => idea.category == category)
              .length;

          return ListTile(
            title: Text(category),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _CategoryIdeasScreen(
                    book: book,
                    category: category,
                    bookRepository: bookRepository,
                  ),
                ),
              );
            },
            subtitle: Text('$total prompts'),
          );
        },
      ),
    );
  }
}

class _CategoryIdeasScreen extends StatefulWidget {
  const _CategoryIdeasScreen({
    required this.book,
    required this.category,
    this.bookRepository,
  });

  final Book book;
  final String category;
  final BookRepository? bookRepository;

  @override
  State<_CategoryIdeasScreen> createState() => _CategoryIdeasScreenState();
}

class _CategoryIdeasScreenState extends State<_CategoryIdeasScreen> {
  late final BookRepository _bookRepository =
      widget.bookRepository ?? BookRepository();
  late final Stream<Book?> _bookStream = _bookRepository.watchBook(
    widget.book.bookId,
  );

  int get _childAgeMonths {
    final now = DateTime.now();
    final birthDate = widget.book.birthDate;

    var months =
        (now.year - birthDate.year) * 12 + (now.month - birthDate.month);
    if (now.day < birthDate.day) months--;

    return months < 0 ? 0 : months;
  }

  bool _isRelevantNow(IdeaPrompt idea, int ageMonths) {
    if (idea.minMonths != null && ageMonths < idea.minMonths!) return false;
    if (idea.maxMonths != null && ageMonths > idea.maxMonths!) return false;
    return true;
  }

  /// Sort order is frozen at screen-open time (uses [widget.book]'s snapshot,
  /// not the live stream) so tapping a prompt never makes it jump position
  /// mid-browse — only its style changes, live, via [_bookStream]. Already-
  /// used prompts still start lower down the *next* time this screen opens.
  late final List<IdeaPrompt> _sortedIdeas = _sortIdeas();

  List<IdeaPrompt> _sortIdeas() {
    final ageMonths = _childAgeMonths;
    final usedAtOpen = widget.book.usedIdeaIds;

    return ideaPrompts.where((idea) => idea.category == widget.category).toList()
      ..sort((a, b) {
        final aUsed = usedAtOpen.contains(a.id);
        final bUsed = usedAtOpen.contains(b.id);
        if (aUsed != bUsed) return aUsed ? 1 : -1;

        final aRelevant = _isRelevantNow(a, ageMonths);
        final bRelevant = _isRelevantNow(b, ageMonths);
        if (aRelevant != bRelevant) return aRelevant ? -1 : 1;

        return 0;
      });
  }

  Future<void> _toggleUsed(IdeaPrompt idea, bool used) async {
    try {
      await _bookRepository.setIdeaUsed(
        bookId: widget.book.bookId,
        ideaId: idea.id,
        used: used,
      );
    } catch (_) {
      // Best-effort — the checklist is a soft convenience, not something
      // worth an error dialog over.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHebrew = widget.book.language == 'he';

    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: StreamBuilder<Book?>(
        stream: _bookStream,
        initialData: widget.book,
        builder: (context, snapshot) {
          final usedIdeaIds = (snapshot.data ?? widget.book).usedIdeaIds;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _sortedIdeas.length,
            itemBuilder: (context, index) {
              final idea = _sortedIdeas[index];
              final used = usedIdeaIds.contains(idea.id);
              final text = isHebrew ? idea.textHe : idea.textEn;
              final outline = Theme.of(context).colorScheme.outline;

              return ListTile(
                title: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  style:
                      DefaultTextStyle.of(context).style.merge(
                        used
                            ? TextStyle(
                                color: outline,
                                decoration: TextDecoration.lineThrough,
                              )
                            : const TextStyle(
                                decoration: TextDecoration.none,
                              ),
                      ),
                  child: Text(text),
                ),
                onTap: () => _toggleUsed(idea, !used),
              );
            },
          );
        },
      ),
    );
  }
}
