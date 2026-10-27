Swiftshot renders the `@Preview`s of a Flutter app for iPhones, iPads and Android devices, in
every language and appearance, from one command. It runs on a Mac or on Linux (CI).

## Requirements

- Flutter 3.35 or later, with widget previews (`package:flutter/widget_previews.dart`)
- `flutter_test` among the dev dependencies (the default for new projects)
- JDK 21 or later, as for [[Android]]
- For exact iPhone and iPad screenshots: a Mac with Xcode and the project's `ios/` folder

Nothing is added to the project. `flutter_localizations`, if the project has it, gives every
language its Material localizations and right-to-left layout.

## Quick start

In the folder with `pubspec.yaml`:

```
swiftshot init      # writes swiftshot.json: languages, devices, light and dark
swiftshot           # renders everything
open screenshots/screenshots.html
```

`init` takes the languages from the gen-l10n ARB files (`arb-dir` in `l10n.yaml`) and picks
iPhone 17 Pro Max, iPad Pro 13-inch (M5), Pixel 10 Pro and Pixel Tablet. Or on the command line:

```
swiftshot --devices "iPhone 17 Pro Max,Pixel 10 Pro" \
  --languages "en-US,de,ar" --appearances light,dark
```

`swiftshot list` prints the previews, `swiftshot devices` the devices.

## SDK

Swiftshot uses the first of:

1. `--flutter-root` or `"flutter_root"`
2. `FLUTTER_ROOT`
3. the project's fvm version (`.fvmrc` or `.fvm/flutter_sdk`)
4. `flutter` on the `PATH`

## Previews

```dart
@Preview(name: 'Welcome')
Widget welcome() => const WelcomeScreen();

@Preview(name: 'Habit card', size: Size(360, 120), brightness: Brightness.dark)
Widget habitCard() => HabitCard(habit: Habit.sample);
```

- Public top-level functions, static methods and widget constructors. Private ones are skipped
  with a warning.
- `name`, `size`, `textScaleFactor`, `wrapper`, `theme`, `brightness` and `localizations`.
- `MultiPreview` and your own `Preview` subclasses, with `transform()`.
- Previews are found in `lib/` without building.

A preview with a `size` is a component: it renders at that size, without system bars. Without
one, it fills the device's screen.

## Devices

- iPhones and iPads by their iOS names, with the sizes, scale and safe areas measured on the
  simulator.
- Android phones, foldables and tablets from the [[Android]] catalog.

Default: iPhone 17 Pro Max and Pixel 10 Pro.

## Renderers

**Headless** (Mac and Linux):

- `flutter test` with Impeller (Skia where Impeller isn't available), one process per language.
- Each preview gets its wrapper, theme, size, brightness, text scale and localizations, as in
  Flutter's previewer.
- Full screens get system bars: the Android status bar and gesture handle, an iPhone-style status
  bar on iOS devices.

**Exact iOS** (Mac with Xcode and an `ios/` folder, the default there):

- iPhones and iPads render on Flutter's iOS engine: the app's Flutter bundle, built for the
  simulator (skipped when nothing changed), in a generated SwiftUI host app.
- Through the no-boot iOS renderer: pixel identical to a booted simulator, with the real status
  bar.
- Components render at their declared or measured size.

`--flutter-ios headless` renders iOS devices headless too: faster, and the same on every machine.

## Fonts

Android devices use Roboto. Scripts Roboto lacks (Arabic, Hebrew, CJK, Thai, Devanagari) use a
system font that has the script and Latin: Arial Unicode or Hiragino on macOS, DejaVu Sans,
FreeSans or Noto Sans CJK on Linux. On Debian and Ubuntu:

```
sudo apt install fonts-dejavu-core fonts-noto-cjk
```

## Configuration

```json
{
  "devices": ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)", "Pixel 10 Pro", "Pixel Tablet"],
  "languages": ["en-US", "de", "ar"],
  "appearances": ["light", "dark"],
  "output_directory": "screenshots",
  "clear_previous_screenshots": true
}
```

| key | flag | default | |
|---|---|---|---|
| `flutter_root` | `--flutter-root` | see [SDK](#sdk) | Flutter SDK |
| `flutter_ios` | `--flutter-ios` | `exact` | `exact` or `headless` for iPhones and iPads |
| `accept_bezel_license` | `--accept-bezel-license` | `false` | Apple's bezel license, for iPhone and iPad frames |

`devices`, `languages`, `appearances`, `font_scales`, `previews`, `screens`, `full_length`,
`delay`, `system_ui`, `frame`, `layout`, `output_directory`, `clear_previous_screenshots`, `html`
and `parallel` work as on [[Android]]:

- `screens`: per-preview devices, languages, appearances, font scales, delay, full length, skip.
- `full_length`: a screen grows until its main scrollable shows everything (on iPhones and iPads
  up to 8192 pixels, Metal's limit).
- `"frame": "plain"`: full screens in their device, in `<output>-framed/`: Android Studio's device
  art for Android devices, Apple's bezels for iPhones and iPads (on a Mac).
- `"layout": "fastlane"`: Android devices in `<language>/images/<type>Screenshots/`.

A layout overflow is a warning, not a failure: the screenshot shows Flutter's overflow stripes.

## Output

```
<output_directory>/<language>/<device>-<preview>[-light|-dark].png
<output_directory>/screenshots.html
<output_directory>/swiftshot-report.json
```

Screenshots are byte identical between runs.

## Speed

`Example/FlutterDemo`, 12 previews in five languages, light and dark:

- 204 screenshots (iPhone and Pixel) headless in about 11 s on an Apple silicon Mac
- the same on a 4-core Linux runner in about 45 s
- exact iOS adds about 1 s per process and 0.8 s per screenshot, in parallel per language and
  device

## Limitations

- Headless, plugins' native code doesn't run.
- Exact iOS needs a Mac with Xcode and an `ios/` folder; elsewhere iOS devices render headless.
- `--mode device` (booted simulators) is the iOS tool's, not Flutter's.
- iPhone and iPad frames need a Mac (Apple's bezels).
