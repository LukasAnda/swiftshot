import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Locale-aware formatting pinned to UTC, so the fixed dates read the same on every device and
/// in every time zone a renderer might use. The skeletons match the other demos; intl picks
/// each locale's own order from its CLDR data.
enum DateStyle {
  weekdayDayMonth,
  weekdayDayMonthYear,
  monthYear,
  day,
  weekdayShort,
  weekdayNarrow,
  time,
}

extension Formatting on BuildContext {
  String get _locale => AppLocalizations.of(this).localeName;

  /// [epochSeconds] in UTC, formatted in the UI's locale.
  String formatDate(int epochSeconds, DateStyle style) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true);
    final locale = _locale;
    final format = switch (style) {
      DateStyle.weekdayDayMonth => DateFormat.MMMMEEEEd(locale),
      DateStyle.weekdayDayMonthYear => DateFormat.yMMMMEEEEd(locale),
      DateStyle.monthYear => DateFormat.yMMMM(locale),
      DateStyle.day => DateFormat.d(locale),
      DateStyle.weekdayShort => DateFormat.E(locale),
      DateStyle.weekdayNarrow => DateFormat('EEEEE', locale),
      DateStyle.time => DateFormat.jm(locale),
    };
    return format.format(date);
  }

  String formatPercent(double value) => NumberFormat.percentPattern(_locale).format(value);

  String formatNumber(int value) => NumberFormat.decimalPattern(_locale).format(value);
}
