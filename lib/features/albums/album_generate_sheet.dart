import 'package:flutter/material.dart';

import '../../models/album_design.dart';
import '../../models/album_page.dart';
import '../../models/book.dart';
import '../../models/memory.dart';
import '../../services/album_layout_builder.dart';
import '../../services/photo_storage_service.dart';
import 'album_page_widget.dart';
import 'album_viewer_screen.dart';

/// The "Album" entry's picker — a modal sheet, not a navigation push, so
/// choosing a design and seeing its preview stays one interaction (matches
/// the AI Editor panel: no dead-end navigation while you're still deciding).
Future<void> showAlbumGenerateSheet(
  BuildContext context, {
  required Book book,
  required List<Memory> memories,
  required PhotoStorageService photoStorage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => _AlbumGenerateSheetContent(
        book: book,
        memories: memories,
        photoStorage: photoStorage,
        scrollController: scrollController,
      ),
    ),
  );
}

class _AlbumGenerateSheetContent extends StatefulWidget {
  const _AlbumGenerateSheetContent({
    required this.book,
    required this.memories,
    required this.photoStorage,
    required this.scrollController,
  });

  final Book book;
  final List<Memory> memories;
  final PhotoStorageService photoStorage;
  final ScrollController scrollController;

  @override
  State<_AlbumGenerateSheetContent> createState() =>
      _AlbumGenerateSheetContentState();
}

class _AlbumGenerateSheetContentState
    extends State<_AlbumGenerateSheetContent> {
  AlbumDesign _selectedDesign = AlbumDesign.softPastel;
  List<AlbumPage>? _generatedPages;
  late final _builder = AlbumLayoutBuilder();
  late final _isRtl = _builder.detectIsRtl(
    book: widget.book,
    memories: widget.memories,
  );

  /// Real content when there's a real memory to show; otherwise a
  /// preview-only placeholder that is never written anywhere.
  Memory get _sampleMemory {
    final visible = widget.memories.where(
      (memory) => !memory.hiddenFromBook && memory.text.trim().isNotEmpty,
    );

    if (visible.isNotEmpty) return visible.first;

    return Memory(
      memoryId: 'sample',
      memoryDate: DateTime.now(),
      text: _isRtl
          ? 'כאן יופיע טקסט הזיכרון שלכם.'
          : 'Your memory text will appear here.',
      photoRefs: const [],
      createdBy: 'sample',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      hiddenFromBook: false,
      schemaVersion: 1,
    );
  }

  void _generate() {
    final pages = _builder.build(book: widget.book, memories: widget.memories);

    setState(() => _generatedPages = pages);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _generatedPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Album', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: pages == null
                  ? _buildPicker(context)
                  : _buildSummary(context, pages),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final sampleMemory = _sampleMemory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose a design', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final design in AlbumDesign.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(design.displayName),
                    selected: _selectedDesign == design,
                    onSelected: (_) =>
                        setState(() => _selectedDesign = design),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Cover', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 0.72,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: AlbumPageWidget(
              page: AlbumCoverPage(
                childName: widget.book.childName,
                birthDate: widget.book.birthDate,
                coverPhoto: widget.book.coverPhoto,
              ),
              design: _selectedDesign,
              isRtl: _isRtl,
              photoStorage: widget.photoStorage,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Sample page', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 0.72,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: AlbumPageWidget(
              page: AlbumMemoryPage(
                memories: [sampleMemory],
                arrangement: sampleMemory.photoRefs.isEmpty
                    ? AlbumPageArrangement.textOnly
                    : AlbumPageArrangement.singlePhoto,
              ),
              design: _selectedDesign,
              isRtl: _isRtl,
              photoStorage: widget.photoStorage,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _generate,
          child: const Text('Generate Album'),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, List<AlbumPage> pages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${pages.length} pages',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          "Printing options are coming soon — you'll be able to see "
          'recommended page size, margins, and how to print or order a '
          'copy from here.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlbumViewerScreen(
                  book: widget.book,
                  pages: pages,
                  design: _selectedDesign,
                  isRtl: _isRtl,
                  photoStorage: widget.photoStorage,
                ),
              ),
            );
          },
          child: const Text('View Album'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _generatedPages = null),
          child: const Text('Choose a different design'),
        ),
      ],
    );
  }
}
