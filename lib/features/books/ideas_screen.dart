import 'package:flutter/material.dart';

import '../../data/idea_prompts.dart';
import '../../data/repositories/book_repository.dart';
import '../../models/book.dart';
import '../../models/idea_prompt.dart';
import '../memories/memory_form_screen.dart';

/// The Ideas ((i)) screen: a browsable, tappable bank of memory-capture
/// prompts (spec §7.3), grouped by category. Never a questionnaire — the
/// parent can ignore this entirely and just tap Add. Age-relevant prompts
/// surface first within each category; a manual "used" mark (never
/// inferred from memory content) moves an idea to the bottom, greyed out.
class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key, required this.book, this.bookRepository});

  final Book book;
  final BookRepository? bookRepository;

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
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

  void _openAddMemory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryFormScreen(
          bookId: widget.book.bookId,
          childGender: widget.book.childGender,
        ),
      ),
    );
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
    final ageMonths = _childAgeMonths;
    final isHebrew = widget.book.language == 'he';

    return Scaffold(
      appBar: AppBar(title: const Text('Ideas')),
      body: StreamBuilder<Book?>(
        stream: _bookStream,
        initialData: widget.book,
        builder: (context, snapshot) {
          final usedIdeaIds = (snapshot.data ?? widget.book).usedIdeaIds;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ideaCategories.length,
            itemBuilder: (context, categoryIndex) {
              final category = ideaCategories[categoryIndex];
              final ideas =
                  ideaPrompts.where((idea) => idea.category == category).toList()
                    ..sort((a, b) {
                      final aUsed = usedIdeaIds.contains(a.id);
                      final bUsed = usedIdeaIds.contains(b.id);
                      if (aUsed != bUsed) return aUsed ? 1 : -1;

                      final aRelevant = _isRelevantNow(a, ageMonths);
                      final bRelevant = _isRelevantNow(b, ageMonths);
                      if (aRelevant != bRelevant) return aRelevant ? -1 : 1;

                      return 0;
                    });

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    ...ideas.map((idea) {
                      final used = usedIdeaIds.contains(idea.id);
                      final text = isHebrew ? idea.textHe : idea.textEn;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          text,
                          style: used
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.outline,
                                  decoration: TextDecoration.lineThrough,
                                )
                              : null,
                        ),
                        leading: IconButton(
                          icon: Icon(
                            used
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                            color: used
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          tooltip: used ? 'Mark as not done' : 'Mark as done',
                          onPressed: () => _toggleUsed(idea, !used),
                        ),
                        onTap: _openAddMemory,
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
