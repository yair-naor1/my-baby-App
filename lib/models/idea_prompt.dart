/// A tappable memory-capture prompt shown in the Ideas ((i)) screen.
///
/// Deliberately static, bundled content — not Firestore-backed, since it's
/// the same for every book and never changes at runtime. See
/// PRODUCT_SPEC.md §7.3 "Ideas (i)" and the age-tagging/soft-checklist
/// design discussed there.
class IdeaPrompt {
  const IdeaPrompt({
    required this.id,
    required this.category,
    required this.textEn,
    required this.textHe,
    this.minMonths,
    this.maxMonths,
  });

  final String id;

  /// English category heading, e.g. "Firsts & Milestones".
  final String category;

  final String textEn;
  final String textHe;

  /// Age window in months this prompt is most relevant for. Null on either
  /// end means unbounded in that direction. Used only to sort/surface
  /// what's relevant now — never to hide prompts entirely (spec: "capture
  /// first, organize later", never a forced questionnaire).
  final int? minMonths;
  final int? maxMonths;
}
