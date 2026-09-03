import 'album_design.dart';

/// The visual values one [AlbumDesign] resolves to — colors as plain
/// 0xAARRGGBB ints and sizes as plain doubles, deliberately with no
/// dependency on `dart:ui`/Flutter or the `pdf` package's own color type.
/// Both the in-app widget renderer and the PDF renderer read this same
/// object and do their own one-line conversion (`Color(...)` /
/// `PdfColor.fromInt(...)`) — the goal is that a design can only be defined
/// once, here, never duplicated per renderer.
class AlbumDesignTheme {
  final int backgroundColor;
  final int accentColor;
  final int bodyTextColor;
  final int secondaryTextColor;
  final double titleFontSize;
  final double bodyFontSize;
  final double captionFontSize;
  final double photoCornerRadius;

  /// Month-divider pages get their own full-bleed background (usually
  /// [accentColor] itself) so the timeline actually reads as chapters
  /// rather than another memory page with a big number on it.
  final int dividerBackgroundColor;
  final int dividerTextColor;

  const AlbumDesignTheme({
    required this.backgroundColor,
    required this.accentColor,
    required this.bodyTextColor,
    required this.secondaryTextColor,
    required this.titleFontSize,
    required this.bodyFontSize,
    required this.captionFontSize,
    required this.photoCornerRadius,
    required this.dividerBackgroundColor,
    required this.dividerTextColor,
  });

  // Matches the app's own seed color (see main.dart _seedColor) so the
  // album feels like an extension of the app, not a bolted-on export. A
  // visibly warm peach wash, not the near-white the first pass used —
  // that read as "no color at all" rather than pastel.
  static const _softPastel = AlbumDesignTheme(
    backgroundColor: 0xFFFFE9DC,
    accentColor: 0xFFFF9E80,
    bodyTextColor: 0xFF4A3B33,
    secondaryTextColor: 0xFFA6786A,
    titleFontSize: 26,
    bodyFontSize: 13,
    captionFontSize: 11,
    photoCornerRadius: 18,
    dividerBackgroundColor: 0xFFFF9E80,
    dividerTextColor: 0xFFFFFFFF,
  );

  /// All three [AlbumDesign] cases currently share this same palette —
  /// they differ only in [AlbumDesign.coverDecoration], not color/type/
  /// spacing, so there is exactly one set of values to keep in sync.
  static AlbumDesignTheme forDesign(AlbumDesign design) => _softPastel;
}
