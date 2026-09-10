import 'package:flutter/material.dart';

import '../utils/date_format.dart';

/// Drop-in alternative to [showDatePicker] that also shows the live
/// Hebrew-calendar equivalent of whatever day is currently highlighted,
/// updating as the user browses/taps — for books whose `dateDisplay`
/// preference includes Hebrew (spec §7.1/§13). The calendar grid itself
/// stays the plain Gregorian [CalendarDatePicker] Flutter already ships —
/// only an extra header line is added, so this never becomes its own
/// custom calendar implementation to maintain.
Future<DateTime?> showDatePickerWithHebrew({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool isHebrew = false,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _HebrewAwareDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      isHebrew: isHebrew,
    ),
  );
}

class _HebrewAwareDatePickerDialog extends StatefulWidget {
  const _HebrewAwareDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.isHebrew,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool isHebrew;

  @override
  State<_HebrewAwareDatePickerDialog> createState() =>
      _HebrewAwareDatePickerDialogState();
}

class _HebrewAwareDatePickerDialogState
    extends State<_HebrewAwareDatePickerDialog> {
  late DateTime _selected = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    // showDialog uses the root navigator, above any Directionality a caller
    // might declare — without one here, the Hebrew header would shape
    // correctly but still align/order itself per the app-wide LTR default.
    return Directionality(
      textDirection: widget.isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        child: SizedBox(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    formatHebrewDate(_selected),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Flexible(
                child: CalendarDatePicker(
                  initialDate: _selected,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: (date) => setState(() => _selected = date),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(widget.isHebrew ? 'ביטול' : 'Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: Text(widget.isHebrew ? 'אישור' : 'OK'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
