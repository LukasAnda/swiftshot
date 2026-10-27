import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habits/app/frame.dart';
import 'package:habits/previews/locale_previews.dart';
import 'package:habits/previews/preview_support.dart';
import 'package:habits/ui/habits_root.dart';
import 'package:habits/ui/today/habit_card.dart';
import 'package:habits/ui/today/habit_dialogs.dart';
import 'package:habits/ui/today/today_cards.dart';
import 'package:habits/ui/welcome/welcome_screen.dart';

/// Builds every preview the way the previewer does (wrapper around the preview function) in
/// each locale and in light and dark, and fails on any build or layout error.
void main() {
  final screens = <String, Widget Function()>{
    'Welcome': welcomePreview,
    'Root': rootPreview,
    'Habit list': habitListPreview,
    'Stats': statsPreview,
    'History': historyPreview,
    'Settings': settingsPreview,
    'Add habit sheet': addHabitSheetPreview,
    'Delete dialog': deleteDialogPreview,
  };
  const locales = ['en', 'de', 'ar', 'ja', 'sk'];

  for (final size in const [Size(412, 915), Size(1280, 800)]) {
    for (final entry in screens.entries) {
      for (final locale in locales) {
        for (final brightness in Brightness.values) {
          testWidgets('${entry.key} $locale ${brightness.name} ${size.width.toInt()}', (tester) async {
            tester.view.physicalSize = size * 3;
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              HabitsFrame(locale: Locale(locale), brightness: brightness, child: entry.value()),
            );
          });
        }
      }
    }
  }

  testWidgets('Habit card and summary previews', (tester) async {
    tester.view.physicalSize = const Size(400, 400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(canvasWrapper(habitCardPreview()));
    expect(find.byType(HabitCard), findsOneWidget);
    await tester.pumpWidget(canvasWrapper(todaySummaryPreview()));
    expect(find.byType(TodaySummary), findsOneWidget);
  });

  testWidgets('Arabic preview lays out right to left', (tester) async {
    final data = arabicLocalizations();
    await tester.pumpWidget(
      Localizations(
        locale: data.locale!,
        delegates: data.localizationsDelegates!.toList(),
        child: screenWrapper(rootArabicPreview()),
      ),
    );
    final context = tester.element(find.byType(HabitsRoot));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  test('light/dark multi-preview expands to two previews', () {
    final previews = const LightDarkPreview(name: 'X').transform();
    expect(previews.map((p) => p.name), ['X (light)', 'X (dark)']);
  });
}
