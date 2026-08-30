/// Short numeric date, e.g. "5/3/2026".
///
/// Centralized so there is one place to switch to locale-aware formatting
/// when RTL/Hebrew date support is built.
String formatShortDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
