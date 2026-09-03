import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/album_design.dart';
import '../../models/album_design_theme.dart';
import '../../models/album_page.dart';
import '../../models/photo_reference.dart';
import '../../services/photo_storage_service.dart';
import '../../utils/date_format.dart';
import '../../widgets/drive_image.dart';

/// Renders one [AlbumPage] as an in-app Flutter widget — the live/in-app
/// counterpart to `AlbumPdfRenderer`. Both read the same [AlbumDesignTheme]
/// values for a given [AlbumDesign], so a design looks the same here as it
/// does in the exported PDF; see that theme class's doc comment.
class AlbumPageWidget extends StatelessWidget {
  final AlbumPage page;
  final AlbumDesign design;

  /// Whether this album reads right-to-left — computed once by
  /// [AlbumLayoutBuilder.detectIsRtl] and passed down, not decided per page,
  /// so the whole book turns one consistent direction.
  final bool isRtl;
  final PhotoStorageService? photoStorage;

  const AlbumPageWidget({
    super.key,
    required this.page,
    required this.design,
    required this.isRtl,
    this.photoStorage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AlbumDesignTheme.forDesign(design);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: switch (page) {
        AlbumCoverPage p => _CoverPageContent(
          page: p,
          theme: theme,
          decoration: design.coverDecoration,
          photoStorage: photoStorage,
        ),
        AlbumMonthDividerPage p => _MonthDividerContent(
          page: p,
          theme: theme,
          photoStorage: photoStorage,
        ),
        AlbumMemoryPage p => Container(
          color: Color(theme.backgroundColor),
          padding: const EdgeInsets.all(24),
          alignment: Alignment.topCenter,
          child: _MemoryPageContent(
            page: p,
            theme: theme,
            photoStorage: photoStorage,
          ),
        ),
      },
    );
  }
}

/// A single photo shown at its own aspect ratio (from [PhotoReference]'s
/// stored width/height) instead of a fixed box — a fixed box + BoxFit.cover
/// crops whatever doesn't match its shape, which read as "photos are cut"
/// once real, varied-aspect-ratio photos were involved.
class _FramedPhoto extends StatelessWidget {
  const _FramedPhoto({
    required this.photoRef,
    required this.theme,
    required this.photoStorage,
  });

  final PhotoReference photoRef;
  final AlbumDesignTheme theme;
  final PhotoStorageService? photoStorage;

  @override
  Widget build(BuildContext context) {
    final width = photoRef.width;
    final height = photoRef.height;
    final aspectRatio = (width != null && height != null && height > 0)
        ? width / height
        : 4 / 3;

    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.photoCornerRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DriveImage(
          fileId: photoRef.thumbnailFileId ?? photoRef.originalFileId,
          photoStorage: photoStorage,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CoverPageContent extends StatelessWidget {
  const _CoverPageContent({
    required this.page,
    required this.theme,
    required this.decoration,
    required this.photoStorage,
  });

  final AlbumCoverPage page;
  final AlbumDesignTheme theme;
  final AlbumCoverDecoration decoration;
  final PhotoStorageService? photoStorage;

  Widget _accentIcon(String asset, {required double size}) {
    return SvgPicture.asset(
      'assets/icons/$asset',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        Color(theme.accentColor),
        BlendMode.srcIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (decoration) {
      case AlbumCoverDecoration.none:
        return Container(
          color: Color(theme.backgroundColor),
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          child: _CoverCore(page: page, theme: theme, photoStorage: photoStorage),
        );

      case AlbumCoverDecoration.minimalAccents:
        return Container(
          color: Color(theme.backgroundColor),
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                child: _accentIcon('sparkle.svg', size: 22),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: _accentIcon('star.svg', size: 22),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                child: _accentIcon('star.svg', size: 22),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: _accentIcon('sparkle.svg', size: 22),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CoverCore(page: page, theme: theme, photoStorage: photoStorage),
                    const SizedBox(height: 8),
                    _accentIcon('star.svg', size: 14),
                  ],
                ),
              ),
            ],
          ),
        );

      case AlbumCoverDecoration.framed:
        return Container(
          color: Color(theme.backgroundColor),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScallopedEdgesPainter(
                    color: Color(theme.accentColor),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (page.coverPhoto != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                theme.photoCornerRadius,
                              ),
                              border: Border.all(
                                color: Color(theme.accentColor),
                                width: 3,
                              ),
                            ),
                            child: _FramedPhoto(
                              photoRef: page.coverPhoto!,
                              theme: theme,
                              photoStorage: photoStorage,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Color(theme.accentColor),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              page.childName,
                              style: TextStyle(
                                fontSize: theme.titleFontSize - 4,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SvgPicture.asset(
                              'assets/icons/footprints.svg',
                              width: 16,
                              height: 16,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Born ${formatShortDate(page.birthDate)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: theme.captionFontSize,
                          color: Color(theme.secondaryTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// The undecorated core: photo, name, accent underline, birth date. Shared
/// by [AlbumCoverDecoration.none] and [AlbumCoverDecoration.minimalAccents]
/// — "framed" composes its own layout since the badge/frame treatment
/// changes more than just what surrounds this.
class _CoverCore extends StatelessWidget {
  const _CoverCore({
    required this.page,
    required this.theme,
    required this.photoStorage,
  });

  final AlbumCoverPage page;
  final AlbumDesignTheme theme;
  final PhotoStorageService? photoStorage;

  @override
  Widget build(BuildContext context) {
    final coverPhoto = page.coverPhoto;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (coverPhoto != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _FramedPhoto(
              photoRef: coverPhoto,
              theme: theme,
              photoStorage: photoStorage,
            ),
          ),
        const SizedBox(height: 24),
        Text(
          page.childName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: theme.titleFontSize,
            fontWeight: FontWeight.bold,
            color: Color(theme.bodyTextColor),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: Color(theme.accentColor),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Born ${formatShortDate(page.birthDate)}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: theme.captionFontSize,
            color: Color(theme.secondaryTextColor),
          ),
        ),
      ],
    );
  }
}

/// Rows of small filled circles along the top and bottom edges — a
/// hand-drawn-style scalloped border, fully vector and theme-colored so it
/// never needs a bundled asset.
class _ScallopedEdgesPainter extends CustomPainter {
  const _ScallopedEdgesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const scallopRadius = 9.0;
    final count = (size.width / (scallopRadius * 2)).floor();

    if (count == 0) return;

    final spacing = size.width / count;
    final paint = Paint()..color = color;

    for (final y in [scallopRadius, size.height - scallopRadius]) {
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(
          Offset(spacing * i + spacing / 2, y),
          scallopRadius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScallopedEdgesPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MonthDividerContent extends StatelessWidget {
  const _MonthDividerContent({
    required this.page,
    required this.theme,
    required this.photoStorage,
  });

  final AlbumMonthDividerPage page;
  final AlbumDesignTheme theme;
  final PhotoStorageService? photoStorage;

  @override
  Widget build(BuildContext context) {
    final photo = page.representativePhoto;

    return Container(
      color: Color(theme.dividerBackgroundColor),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (photo != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.photoCornerRadius),
                child: DriveImage(
                  fileId: photo.thumbnailFileId ?? photo.originalFileId,
                  photoStorage: photoStorage,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Month ${page.monthNumber + 1}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: theme.titleFontSize + 4,
              fontWeight: FontWeight.bold,
              color: Color(theme.dividerTextColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryPageContent extends StatelessWidget {
  const _MemoryPageContent({
    required this.page,
    required this.theme,
    required this.photoStorage,
  });

  final AlbumMemoryPage page;
  final AlbumDesignTheme theme;
  final PhotoStorageService? photoStorage;

  @override
  Widget build(BuildContext context) {
    final memory = page.memories.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatShortDate(memory.memoryDate),
          style: TextStyle(
            fontSize: theme.captionFontSize,
            fontWeight: FontWeight.w600,
            color: Color(theme.accentColor),
          ),
        ),
        const SizedBox(height: 12),
        switch (page.arrangement) {
          AlbumPageArrangement.textOnly => const SizedBox(),
          AlbumPageArrangement.singlePhoto => _FramedPhoto(
            photoRef: memory.photoRefs.first,
            theme: theme,
            photoStorage: photoStorage,
          ),
          AlbumPageArrangement.photoGrid => GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final ref in memory.photoRefs)
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    theme.photoCornerRadius,
                  ),
                  child: DriveImage(
                    fileId: ref.thumbnailFileId ?? ref.originalFileId,
                    photoStorage: photoStorage,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
        },
        const SizedBox(height: 12),
        if (memory.text.trim().isNotEmpty)
          Text(
            memory.text,
            style: TextStyle(
              fontSize: theme.bodyFontSize,
              color: Color(theme.bodyTextColor),
              height: 1.4,
            ),
          ),
      ],
    );
  }
}
