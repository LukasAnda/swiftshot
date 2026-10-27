# Habits for Compose Multiplatform

The multiplatform twin of `../AndroidDemo`: the same habit tracker (persimmon accent, warm
neutrals, Material 3 Expressive) with all UI in `commonMain`, running on Android, iOS and desktop.
It is the sample project for rendering shared `@Preview` functions to screenshots, so the previews
are the product.

- `:shared` - Kotlin Multiplatform + Compose Multiplatform. Targets: Android (AGP's
  `com.android.kotlin.multiplatform.library`, `kotlin { android {} }`), `iosArm64`,
  `iosSimulatorArm64` (static framework `Shared`, entry point `MainViewController()`), and
  `jvm("desktop")`.
- `:androidApp` - the Android application (`MainActivity` shows `App()` edge to edge).
- `:desktopApp` - the desktop application (`main()` opens a window with `App()`).

Everything on screen is fixed data: the same five habits as the other demos, "today" is
1 790 000 000 epoch seconds (Monday 21 September 2026), and times are formatted in UTC with each
platform's ICU/CLDR data (android.icu, Foundation, ICU4J). No clocks, randomness, network or
remote images. Dynamic color is off; the brand palette has light and dark schemes. Navigation
follows the available width: a navigation bar below 600 dp, a navigation rail above.

Strings are Compose resources (`shared/src/commonMain/composeResources`) in English (default),
German, Slovak, Arabic (RTL) and Japanese, taken from the Android demo. Icons are the Material
Rounded/Outlined paths the app uses, bundled as `ImageVector`s (`ui/icons/AppIcons.kt`).

## Previews

All use `androidx.compose.ui.tooling.preview.Preview` (from `org.jetbrains.compose.ui:ui-tooling-preview`)
in `commonMain` and take no parameters.

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
| Habit card | `ui.today.HabitCardKt.HabitCardPreview` |

Packages are relative to `com.swiftshot.demo`. Full-screen previews draw edge to edge and pad
for system bars and safe areas themselves.

## Build

```sh
./gradlew :androidApp:assembleDebug :desktopApp:jar :shared:compileKotlinDesktop \
  :shared:linkDebugFrameworkIosSimulatorArm64
```

Requires JDK 21, the Android SDK (compile SDK 37) and, for the iOS framework, Xcode.
