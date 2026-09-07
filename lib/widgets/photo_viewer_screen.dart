import 'package:flutter/material.dart';

/// Full-screen, swipeable photo viewer — modeled on the page-by-page chrome
/// in `AlbumViewerScreen` (PageController + counter), but generic over how
/// each page's image is actually built so it works for both an
/// already-uploaded [PhotoReference] (fetched via [StoredPhotoImage] at full
/// resolution, not the thumbnail everywhere else uses) and a freshly-picked
/// local file that hasn't been uploaded yet.
///
/// Deliberately a black background, breaking from the app's pastel theme —
/// standard for a dedicated photo viewer, and it makes photos of any aspect
/// ratio look intentional rather than floating on a mismatched background.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.itemCount,
    required this.initialIndex,
    required this.imageBuilder,
  });

  final int itemCount;
  final int initialIndex;
  final Widget Function(BuildContext context, int index) imageBuilder;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.itemCount > 1
            ? Text('${_currentIndex + 1} / ${widget.itemCount}')
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.itemCount,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: widget.imageBuilder(context, index)),
        ),
      ),
    );
  }
}
