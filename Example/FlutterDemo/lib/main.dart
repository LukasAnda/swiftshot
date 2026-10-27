import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'theme/theme.dart';
import 'ui/habits_root.dart';

void main() => runApp(const HabitsApp());

/// Habits: the Flutter twin of the Swiftshot demo apps. Fixed data, no clock, no network.
class HabitsApp extends StatelessWidget {
  const HabitsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: habitsTheme(Brightness.light),
      darkTheme: habitsTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HabitsRoot(),
    );
  }
}
