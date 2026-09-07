import 'package:kosher_dart/kosher_dart.dart';

/// Short numeric date, e.g. "5/3/2026".
///
/// Centralized so there is one place to switch to locale-aware formatting
/// when RTL/Hebrew date support is built.
String formatShortDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

/// Hebrew-calendar equivalent of [date], e.g. "כ״ט אלול תשפ״ו".
String formatHebrewDate(DateTime date) {
  final jewishDate = JewishDate.fromDateTime(date);
  final formatter = HebrewDateFormatter()..hebrewFormat = true;

  return formatter.format(jewishDate);
}

/// Formats [date] per a book's `dateDisplay` setting (spec §7.1/§13) —
/// `'gregorian'` (default), `'hebrew'`, or `'both'`. Never affects how a date
/// is *picked* (`showDatePicker` stays Gregorian everywhere), only how an
/// already-picked date is displayed afterward.
String formatDate(DateTime date, String dateDisplay) {
  switch (dateDisplay) {
    case 'hebrew':
      return formatHebrewDate(date);
    case 'both':
      return '${formatShortDate(date)} · ${formatHebrewDate(date)}';
    case 'gregorian':
    default:
      return formatShortDate(date);
  }
}
