final _hebrewPattern = RegExp('[֐-׿]');

/// Whether [text] contains Hebrew script — used where nothing has actually
/// set a reliable per-book language yet (see the album-generation direction
/// bug in PRODUCT_SPEC.md's implementation notes).
bool containsHebrew(String text) => _hebrewPattern.hasMatch(text);
