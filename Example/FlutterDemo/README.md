# Habits for Flutter

The Flutter twin of `../MultiplatformDemo`: the same habit tracker (persimmon accent, warm neutrals, Material 3) with fixed data, "today" fixed at Monday 21 September 2026 (UTC) and strings in English, German, Slovak, Arabic (RTL) and Japanese (gen-l10n ARB files in `lib/l10n`).
It is the sample project for rendering Flutter widget previews (`package:flutter/widget_previews.dart`) to screenshots: Welcome, Root, Habit list, Stats, History, Settings, Add habit sheet, Delete dialog and Habit card, plus `Root (Arabic)` (preview `localizations`) and `Today summary (light/dark)` (a custom `MultiPreview`).
Flutter 3.41.7 (`.fvmrc`); `flutter pub get && flutter analyze && flutter test`.
