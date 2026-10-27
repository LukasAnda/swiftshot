import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../app/frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme.dart';

/*
 * Shared pieces for the widget previews. Everything an annotation refers to is public and
 * top level, so it can be used as a constant tear-off.
 */

/// Wraps a full screen in the app's frame (theme, localizations, navigator).
Widget screenWrapper(Widget child) => HabitsFrame(child: child);

/// Wraps a component in the app's frame on the warm canvas, aligned to the top.
Widget canvasWrapper(Widget child) => HabitsFrame(
  child: Builder(
    builder: (context) => ColoredBox(
      color: context.colors.surface,
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  ),
);

/// The app's localizations in Arabic, a right-to-left locale.
PreviewLocalizationsData arabicLocalizations() => const PreviewLocalizationsData(
  locale: Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
);

/// The brand theme for the previewer's own theme switch.
PreviewThemeData habitsPreviewTheme() =>
    PreviewThemeData(materialLight: habitsTheme(Brightness.light), materialDark: habitsTheme(Brightness.dark));

/// One preview in light and one in dark, like Compose's `@PreviewLightDark`.
final class LightDarkPreview extends MultiPreview {
  const LightDarkPreview({required this.name, this.size, this.wrapper = canvasWrapper});

  final String name;
  final Size? size;
  final WidgetWrapper wrapper;

  @override
  List<Preview> get previews => [
    Preview(name: '$name (light)', size: size, wrapper: wrapper, brightness: Brightness.light, theme: habitsPreviewTheme),
    Preview(name: '$name (dark)', size: size, wrapper: wrapper, brightness: Brightness.dark, theme: habitsPreviewTheme),
  ];
}
