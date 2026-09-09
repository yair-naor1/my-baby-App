import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/album_design.dart';
import '../../models/album_page.dart';
import '../../models/book.dart';
import '../../services/album_pdf_renderer.dart';
import '../../services/photo_storage_service.dart';
import '../../utils/error_messages.dart';
import 'album_page_widget.dart';

/// The full-screen, page-by-page in-app album — read-only for v1 (see the
/// album-design discussion in PRODUCT_SPEC.md §14): no per-page editing yet,
/// just browsing what was generated plus Export/Share.
class AlbumViewerScreen extends StatefulWidget {
  const AlbumViewerScreen({
    super.key,
    required this.book,
    required this.pages,
    required this.design,
    required this.isRtl,
    required this.photoStorage,
  });

  final Book book;
  final List<AlbumPage> pages;
  final AlbumDesign design;
  final bool isRtl;
  final PhotoStorageService photoStorage;

  @override
  State<AlbumViewerScreen> createState() => _AlbumViewerScreenState();
}

class _AlbumViewerScreenState extends State<AlbumViewerScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isExporting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);

    try {
      final bytes = await const AlbumPdfRenderer().render(
        pages: widget.pages,
        design: widget.design,
        isRtl: widget.isRtl,
        photoStorage: widget.photoStorage,
      );

      if (!mounted) return;

      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.book.childName}_album.pdf',
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showComingSoon(String feature, {required bool isRtl}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isRtl ? '$feature יגיע/תגיע בקרוב.' : '$feature is coming soon.',
        ),
      ),
    );
  }

  // Deliberately NOT wrapped in Directionality (unlike the Ideas screens):
  // the swipeable page content already gets correct RTL from widget.isRtl
  // at the AlbumPageWidget level, scoped per-page. Wrapping this whole
  // screen would also flip the PageView's swipe direction and the
  // prev/next chevrons' semantics — a real UX change nobody asked for and
  // nothing here has tested. Text below is translated on its own; Hebrew
  // glyphs shape correctly regardless of ambient Directionality.
  @override
  Widget build(BuildContext context) {
    final isRtl = widget.isRtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isRtl
              ? 'האלבום של ${widget.book.childName}'
              : "${widget.book.childName}'s Album",
        ),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'export') {
                  _exportPdf();
                } else if (value == 'share') {
                  _showComingSoon(isRtl ? 'השיתוף' : 'Sharing', isRtl: isRtl);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'export',
                  child: Text(isRtl ? 'ייצוא PDF' : 'Export PDF'),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Text(isRtl ? 'שיתוף' : 'Share'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pages.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: AlbumPageWidget(
                    page: widget.pages[index],
                    design: widget.design,
                    isRtl: widget.isRtl,
                    photoStorage: widget.photoStorage,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 0
                      ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_currentPage + 1} / ${widget.pages.length}'),
                IconButton(
                  onPressed: _currentPage < widget.pages.length - 1
                      ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
