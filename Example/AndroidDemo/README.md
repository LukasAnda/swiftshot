# Habits for Android

The Android twin of the iOS demo in `../DemoApp`: a habit tracker with a persimmon accent and warm
neutrals, built with Jetpack Compose and Material 3 Expressive. It is the sample project for
rendering `@Preview` functions to screenshots, so the previews are the product.

- `:app` — phone, tablet and foldable. `NavigationSuiteScaffold` gives compact widths a bottom
  navigation bar and wider ones a navigation rail; Today becomes list-detail on expanded widths.
- `:wear` — the Wear OS app (Wear Compose Material 3): today's habits with a time text, progress
  rings and an edge button.

Everything on screen is fixed data: the same five habits as iOS, "today" is 1 790 000 000 epoch
seconds (Monday 21 September 2026), and times are formatted in UTC. No clocks, randomness, network
or remote images, so every render is identical. Dynamic color is off; the brand palette has light
and dark schemes.

Localizations: English (default), German, Slovak, Arabic (RTL) and Japanese, taken from the iOS
String Catalog.

## Previews

| Name | Function |
| --- | --- |
| Welcome | `ui.welcome.WelcomeScreenKt.WelcomePreview` |
| Root | `ui.HabitsAppKt.RootPreview` |
| Habit list | `ui.HabitsAppKt.HabitListPreview` |
| Stats | `ui.HabitsAppKt.StatsPreview` |
| History | `ui.HabitsAppKt.HistoryPreview` |
| Settings | `ui.HabitsAppKt.SettingsPreview` |
| Add habit sheet | `ui.today.HabitDialogsKt.AddHabitSheetPreview` |
| Delete dialog | `ui.today.HabitDialogsKt.DeleteDialogPreview` |
| Stats long | `ui.stats.StatsScreenKt.StatsLongPreview` |
| Habit card | `ui.today.HabitCardKt.HabitCardPreview` |
| Habit card states | `ui.today.HabitCardKt.HabitCardStatesPreview` (`@PreviewParameter`, one per habit) |
| (font scales) | `ui.today.HabitCardKt.HabitCardFontScalePreview` (`@PreviewFontScale`) |
| (light / dark) | `ui.today.TodayCardsKt.TodaySummaryPreview` (`@PreviewLightDark`) |
| Watch list | `wear.WatchScreensKt.WatchListPreview` |
| Watch habit | `wear.WatchScreensKt.WatchHabitPreview` |
| (Wear devices) | `wear.WatchScreensKt.WatchListDevicesPreview` (`@WearPreviewDevices`) |

Packages are relative to `com.swiftshot.demo`. Full-screen previews set no device, so the
renderer picks one.

## Build

```sh
./gradlew :app:assembleDebug :wear:assembleDebug
```

Requires JDK 21 and the Android SDK (compile SDK 37).
