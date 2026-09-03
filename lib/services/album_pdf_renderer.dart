import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/album_design.dart';
import '../models/album_design_theme.dart';
import '../models/album_page.dart';
import '../models/photo_reference.dart';
import '../utils/date_format.dart';
import 'photo_storage_service.dart';

/// Renders an [AlbumPage] plan to an actual PDF, entirely on-device — no
/// server involved, matching the "keep this light and free to run" goal.
///
/// Only ever calls [PhotoStorageService.downloadPhoto], never a concrete
/// provider, so the Cloudflare R2 migration (PRODUCT_SPEC.md §9.3) touches
/// this file zero times.
class AlbumPdfRenderer {
  const AlbumPdfRenderer();

  Future<Uint8List> render({
    required List<AlbumPage> pages,
    required AlbumDesign design,
    required bool isRtl,
    required PhotoStorageService photoStorage,
  }) async {
    final theme = AlbumDesignTheme.forDesign(design);
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansHebrew-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansHebrew-Bold.ttf'),
    );
    final icons = await _AlbumIcons.load(theme);

    final direction = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final textAlign = isRtl ? pw.TextAlign.right : pw.TextAlign.left;

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    for (final page in pages) {
      final photos = await _loadPhotosForPage(page, photoStorage);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: page is AlbumMonthDividerPage
              ? pw.EdgeInsets.zero
              : const pw.EdgeInsets.all(28),
          build: (context) => pw.Directionality(
            textDirection: direction,
            child: pw.Container(
              color: PdfColor.fromInt(
                page is AlbumMonthDividerPage
                    ? theme.dividerBackgroundColor
                    : theme.backgroundColor,
              ),
              child: switch (page) {
                AlbumCoverPage p => _buildCoverPage(
                  p,
                  theme,
                  design.coverDecoration,
                  textAlign,
                  photos,
                  icons,
                ),
                AlbumMonthDividerPage p => _buildMonthDivider(
                  p,
                  theme,
                  photos,
                ),
                AlbumMemoryPage p => pw.Padding(
                  padding: const pw.EdgeInsets.all(28),
                  child: _buildMemory(p, theme, textAlign, photos),
                ),
              },
            ),
          ),
        ),
      );
    }

    return doc.save();
  }

  Future<Map<String, Uint8List>> _loadPhotosForPage(
    AlbumPage page,
    PhotoStorageService photoStorage,
  ) async {
    // Thumbnail-resolution for now on purpose — good enough to prove the
    // renderer out; print-resolution asset selection is a follow-up (see
    // the photo-loading-performance note in the album design discussion).
    final refs = switch (page) {
      AlbumCoverPage(:final coverPhoto) =>
        coverPhoto == null ? const <PhotoReference>[] : [coverPhoto],
      AlbumMonthDividerPage(:final representativePhoto) =>
        representativePhoto == null
            ? const <PhotoReference>[]
            : [representativePhoto],
      AlbumMemoryPage(:final memories) => [
        for (final memory in memories) ...memory.photoRefs,
      ],
    };

    final bytesByFileId = <String, Uint8List>{};

    for (final ref in refs) {
      final fileId = ref.thumbnailFileId ?? ref.originalFileId;
      bytesByFileId[fileId] = await photoStorage.downloadPhoto(fileId);
    }

    return bytesByFileId;
  }

  /// A photo at its own aspect ratio instead of a fixed-height cover-crop —
  /// see the matching `_FramedPhoto` comment in album_page_widget.dart for
  /// why: a fixed box crops whatever doesn't match its shape.
  pw.Widget _framedPhoto(
    PhotoReference ref,
    Uint8List? bytes,
    AlbumDesignTheme theme,
  ) {
    if (bytes == null) return pw.SizedBox();

    final width = ref.width;
    final height = ref.height;
    final aspectRatio = (width != null && height != null && height > 0)
        ? width / height
        : 4 / 3;

    return pw.AspectRatio(
      aspectRatio: aspectRatio,
      child: pw.ClipRRect(
        horizontalRadius: theme.photoCornerRadius,
        verticalRadius: theme.photoCornerRadius,
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
      ),
    );
  }

  pw.Widget _buildCoverPage(
    AlbumCoverPage page,
    AlbumDesignTheme theme,
    AlbumCoverDecoration decoration,
    pw.TextAlign textAlign,
    Map<String, Uint8List> photos,
    _AlbumIcons icons,
  ) {
    switch (decoration) {
      case AlbumCoverDecoration.none:
        return pw.Padding(
          padding: const pw.EdgeInsets.all(28),
          child: _coverCore(page, theme, textAlign, photos),
        );

      case AlbumCoverDecoration.minimalAccents:
        return pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Stack(
            children: [
              pw.Positioned(top: 0, left: 0, child: icons.accentSparkle(22)),
              pw.Positioned(top: 0, right: 0, child: icons.accentStar(22)),
              pw.Positioned(bottom: 0, left: 0, child: icons.accentStar(22)),
              pw.Positioned(
                bottom: 0,
                right: 0,
                child: icons.accentSparkle(22),
              ),
              pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    _coverCore(page, theme, textAlign, photos),
                    pw.SizedBox(height: 8),
                    icons.accentStar(14),
                  ],
                ),
              ),
            ],
          ),
        );

      case AlbumCoverDecoration.framed:
        final coverPhoto = page.coverPhoto;
        final coverBytes = coverPhoto == null
            ? null
            : photos[coverPhoto.thumbnailFileId ?? coverPhoto.originalFileId];

        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.CustomPaint(
                painter: (canvas, size) {
                  const scallopRadius = 9.0;
                  final count = (size.x / (scallopRadius * 2)).floor();
                  if (count == 0) return;
                  final spacing = size.x / count;

                  for (final y in [scallopRadius, size.y - scallopRadius]) {
                    for (var i = 0; i < count; i++) {
                      canvas
                        ..setFillColor(PdfColor.fromInt(theme.accentColor))
                        ..drawEllipse(
                          spacing * i + spacing / 2,
                          y,
                          scallopRadius,
                          scallopRadius,
                        )
                        ..fillPath();
                    }
                  }
                },
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(24, 40, 24, 40),
              child: pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    if (coverPhoto != null)
                      pw.ConstrainedBox(
                        constraints: const pw.BoxConstraints(maxHeight: 300),
                        child: pw.Container(
                          decoration: pw.BoxDecoration(
                            borderRadius: pw.BorderRadius.circular(
                              theme.photoCornerRadius,
                            ),
                            border: pw.Border.all(
                              color: PdfColor.fromInt(theme.accentColor),
                              width: 3,
                            ),
                          ),
                          child: _framedPhoto(coverPhoto, coverBytes, theme),
                        ),
                      ),
                    pw.SizedBox(height: 20),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(theme.accentColor),
                        borderRadius: pw.BorderRadius.circular(20),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(
                            page.childName,
                            style: pw.TextStyle(
                              fontSize: theme.titleFontSize - 4,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          icons.badgeFootprints(16),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Born ${formatShortDate(page.birthDate)}',
                      textAlign: textAlign,
                      style: pw.TextStyle(
                        fontSize: theme.captionFontSize,
                        color: PdfColor.fromInt(theme.secondaryTextColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }

  pw.Widget _coverCore(
    AlbumCoverPage page,
    AlbumDesignTheme theme,
    pw.TextAlign textAlign,
    Map<String, Uint8List> photos,
  ) {
    final coverPhoto = page.coverPhoto;
    final coverBytes = coverPhoto == null
        ? null
        : photos[coverPhoto.thumbnailFileId ?? coverPhoto.originalFileId];

    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (coverPhoto != null)
          pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxHeight: 300),
            child: _framedPhoto(coverPhoto, coverBytes, theme),
          ),
        pw.SizedBox(height: 24),
        pw.Text(
          page.childName,
          textAlign: textAlign,
          style: pw.TextStyle(
            fontSize: theme.titleFontSize,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(theme.bodyTextColor),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: 48,
          height: 3,
          color: PdfColor.fromInt(theme.accentColor),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Born ${formatShortDate(page.birthDate)}',
          textAlign: textAlign,
          style: pw.TextStyle(
            fontSize: theme.captionFontSize,
            color: PdfColor.fromInt(theme.secondaryTextColor),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildMonthDivider(
    AlbumMonthDividerPage page,
    AlbumDesignTheme theme,
    Map<String, Uint8List> photos,
  ) {
    final photo = page.representativePhoto;
    final photoBytes = photo == null
        ? null
        : photos[photo.thumbnailFileId ?? photo.originalFileId];

    return pw.Center(
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (photo != null)
            pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxHeight: 240, maxWidth: 300),
              child: _framedPhoto(photo, photoBytes, theme),
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Month ${page.monthNumber + 1}',
            style: pw.TextStyle(
              fontSize: theme.titleFontSize + 4,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(theme.dividerTextColor),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMemory(
    AlbumMemoryPage page,
    AlbumDesignTheme theme,
    pw.TextAlign textAlign,
    Map<String, Uint8List> photos,
  ) {
    final memory = page.memories.first;

    final photoWidgets = memory.photoRefs.map((ref) {
      final fileId = ref.thumbnailFileId ?? ref.originalFileId;
      return _framedPhotoSquare(ref, photos[fileId], theme);
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          formatShortDate(memory.memoryDate),
          textAlign: textAlign,
          style: pw.TextStyle(
            fontSize: theme.captionFontSize,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(theme.accentColor),
          ),
        ),
        pw.SizedBox(height: 12),
        switch (page.arrangement) {
          AlbumPageArrangement.textOnly => pw.SizedBox(),
          AlbumPageArrangement.singlePhoto => memory.photoRefs.isEmpty
              ? pw.SizedBox()
              : _framedPhoto(
                  memory.photoRefs.first,
                  photos[memory.photoRefs.first.thumbnailFileId ??
                      memory.photoRefs.first.originalFileId],
                  theme,
                ),
          // pw.GridView doesn't take a width the way Flutter's does — cells
          // ran off the page edge under a fixed-height SizedBox. Building
          // rows of pw.Expanded + pw.AspectRatio instead makes each cell's
          // width an explicit fraction of the actual available width.
          AlbumPageArrangement.photoGrid => pw.Column(
            children: [
              for (var i = 0; i < photoWidgets.length; i += 2)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    children: [
                      pw.Expanded(child: photoWidgets[i]),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: i + 1 < photoWidgets.length
                            ? photoWidgets[i + 1]
                            : pw.SizedBox(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        },
        pw.SizedBox(height: 12),
        if (memory.text.trim().isNotEmpty)
          pw.Text(
            memory.text,
            textAlign: textAlign,
            style: pw.TextStyle(
              fontSize: theme.bodyFontSize,
              color: PdfColor.fromInt(theme.bodyTextColor),
              lineSpacing: 3,
            ),
          ),
      ],
    );
  }

  /// Grid cells stay square-cropped on purpose — a grid of mismatched
  /// aspect ratios looks messy in a way a single hero photo doesn't; see
  /// the album-design discussion for the follow-up on masonry-style grids.
  pw.Widget _framedPhotoSquare(
    PhotoReference ref,
    Uint8List? bytes,
    AlbumDesignTheme theme,
  ) {
    if (bytes == null) return pw.SizedBox();

    return pw.AspectRatio(
      aspectRatio: 1,
      child: pw.ClipRRect(
        horizontalRadius: theme.photoCornerRadius,
        verticalRadius: theme.photoCornerRadius,
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
      ),
    );
  }
}

/// Loads the Lucide icon SVGs (`assets/icons/`, ISC license — see
/// `assets/icons/LICENSE.txt`) once per render and pre-colors them, since
/// the `pdf` package's SVG support has no colorFilter concept the way
/// flutter_svg does on the widget side — recoloring means substituting
/// `currentColor` in the raw markup before handing it to [pw.SvgImage].
class _AlbumIcons {
  const _AlbumIcons({
    required this.accentStarSvg,
    required this.accentSparkleSvg,
    required this.badgeFootprintsSvg,
  });

  final String accentStarSvg;
  final String accentSparkleSvg;
  final String badgeFootprintsSvg;

  static Future<_AlbumIcons> load(AlbumDesignTheme theme) async {
    final accentHex = _toHex(theme.accentColor);

    Future<String> loadColored(String asset, String colorHex) async {
      final raw = await rootBundle.loadString('assets/icons/$asset');
      return raw.replaceAll('currentColor', colorHex);
    }

    return _AlbumIcons(
      accentStarSvg: await loadColored('star.svg', accentHex),
      accentSparkleSvg: await loadColored('sparkle.svg', accentHex),
      badgeFootprintsSvg: await loadColored('footprints.svg', '#FFFFFF'),
    );
  }

  static String _toHex(int argb) {
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  pw.Widget accentStar(double size) =>
      pw.SvgImage(svg: accentStarSvg, width: size, height: size);

  pw.Widget accentSparkle(double size) =>
      pw.SvgImage(svg: accentSparkleSvg, width: size, height: size);

  pw.Widget badgeFootprints(double size) =>
      pw.SvgImage(svg: badgeFootprintsSvg, width: size, height: size);
}
