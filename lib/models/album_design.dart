/// Which visual design an album is rendered with — see PRODUCT_SPEC.md §14.
/// Deliberately separate from [AlbumPage]: the layout builder decides *what*
/// goes on each page (content), a design decides *how it looks* (palette,
/// typography, spacing, decoration).
///
/// All three current cases share the same Soft Pastel color palette (see
/// [AlbumDesignTheme]) and differ only in [coverDecoration] — kept as
/// separate cases rather than a toggle so the picker can show them as
/// distinct, named choices.
enum AlbumDesign {
  softPastel,
  softPastelMinimal,
  softPastelFramed;

  /// User-facing name shown in the design picker.
  String get displayName {
    switch (this) {
      case AlbumDesign.softPastel:
        return 'Soft Pastel';
      case AlbumDesign.softPastelMinimal:
        return 'Soft Pastel — Minimal';
      case AlbumDesign.softPastelFramed:
        return 'Soft Pastel — Framed';
    }
  }

  AlbumCoverDecoration get coverDecoration {
    switch (this) {
      case AlbumDesign.softPastel:
        return AlbumCoverDecoration.none;
      case AlbumDesign.softPastelMinimal:
        return AlbumCoverDecoration.minimalAccents;
      case AlbumDesign.softPastelFramed:
        return AlbumCoverDecoration.framed;
    }
  }
}

/// How the cover page is decorated beyond the base palette. Scoped to the
/// cover only for now — extending this to memory/divider pages is a later
/// step once the cover treatment itself is confirmed.
enum AlbumCoverDecoration {
  /// No extra decoration — the original plain cover.
  none,

  /// Small corner accents (star/sparkle icons).
  minimalAccents,

  /// A scalloped border plus an accent-colored photo frame and name badge.
  framed,
}
