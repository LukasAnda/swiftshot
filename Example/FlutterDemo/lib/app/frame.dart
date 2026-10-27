import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme.dart';

/// Everything a screen needs around it: the theme, the app's localizations (and with them the
/// text direction), a navigator for sheets and dialogs, and the canvas.
///
/// Unlike [MaterialApp] it keeps the [MediaQuery] it is given, so a preview's size, text scale
/// and brightness reach the screen unchanged. It also follows the ambient locale and
/// brightness unless [locale] or [brightness] are set.
class HabitsFrame extends StatelessWidget {
  const HabitsFrame({super.key, required this.child, this.locale, this.brightness});

  final Widget child;

  /// The UI locale; defaults to the ambient [Localizations] locale, then English.
  final Locale? locale;

  /// Light or dark; defaults to the ambient platform brightness.
  final Brightness? brightness;

  static Locale resolve(Locale? requested) {
    if (requested == null) return const Locale('en');
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == requested.languageCode) return supported;
    }
    return const Locale('en');
  }

  @override
  Widget build(BuildContext context) {
    final mode = brightness ?? MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    Widget content = Theme(
      data: habitsTheme(mode),
      child: _Canvas(
        child: Navigator(
          pages: [MaterialPage<void>(child: child)],
          onDidRemovePage: (_) {},
        ),
      ),
    );
    content = Localizations(
      locale: resolve(locale ?? Localizations.maybeLocaleOf(context)),
      delegates: AppLocalizations.localizationsDelegates,
      child: content,
    );
    if (MediaQuery.maybeOf(context) == null) {
      content = MediaQuery.fromView(view: View.of(context), child: content);
    }
    return content;
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.surface,
      child: DefaultTextStyle(
        style: context.text.bodyMedium!.copyWith(color: context.colors.onSurface),
        child: child,
      ),
    );
  }
}
