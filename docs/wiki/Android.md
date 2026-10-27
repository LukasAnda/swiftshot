Swiftshot renders Google Play screenshots from your Jetpack Compose `@Preview`s for phones,
foldables, tablets and Wear OS, in every language and appearance, without an emulator. It runs on
a Mac or on Linux (CI).

## Requirements

- JDK 21 or later (Android Studio's bundled one is found automatically)
- An Android app or library module with Compose `@Preview`s
- `androidx.compose.ui:ui-tooling` on the debug classpath, as Android Studio's previews need too:

```kotlin
debugImplementation("androidx.compose.ui:ui-tooling")
```

Nothing else is added to the project: Swiftshot adds its Gradle task for its own run only.

## Install

On a Mac, the regular install includes Android support ([[Installation]]). On Linux:

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
export PATH="$HOME/.swiftshot/bin:$PATH"
```

## Quick start

In the folder with `gradlew`:

```
swiftshot init      # writes swiftshot.json: modules, languages, Play devices
swiftshot           # renders everything
open screenshots/screenshots.html
```

`swiftshot list` prints the previews it found, `swiftshot devices` the devices.

## Configuration

`swiftshot.json` uses the same keys as on iOS where they mean the same thing:

```json
{
  "modules": [":app", ":wear"],
  "devices": ["Pixel 10 Pro", "Pixel 9 Pro Fold", "Pixel 9 Pro Fold (folded)", "Pixel Tablet"],
  "watch_devices": ["Wear OS Large Round"],
  "languages": ["en-US", "de-DE", "ja", "ar"],
  "appearances": ["light", "dark"],
  "font_scales": [1, 1.3],
  "output_directory": "fastlane/metadata/android",
  "layout": "fastlane",
  "screens": [
    { "preview": "Stats", "full_length": true },
    { "preview": "Debug*", "skip": true }
  ]
}
```

| key | default | |
|---|---|---|
| `project_dir` | `.` | the Gradle project |
| `modules` | every Android module | e.g. `[":app", ":wear"]` |
| `variant` | `debug` | build variant |
| `gradle_args` | `[]` | extra Gradle arguments |
| `devices` | Pixel 10 Pro, Pixel Tablet | phones, foldables, tablets (`swiftshot devices`) |
| `watch_devices` | Wear OS Large Round | for Wear OS modules |
| `languages` | `["en-US"]` | BCP 47 tags |
| `appearances` | `["light"]` | `light`, `dark` |
| `font_scales` | `[1]` | e.g. `[1, 1.3, 2]` |
| `previews` | all | names or `*` globs |
| `output_directory` | `screenshots` | |
| `layout` | `swiftshot` | `fastlane`: `<locale>/images/phoneScreenshots/…` for `fastlane supply` |
| `clear_previous_screenshots` | `false` | |
| `html` | `true` | write `screenshots.html` |
| `full_length` | `false` | grow scrolling screens to their whole content |
| `delay` | `0` | seconds to advance the clock before capture |
| `system_ui` | `preview` | status and navigation bars: as `showSystemUi` says, `always`, `never` |
| `frame` | `none` | `plain`: the device around the screenshot |
| `round_corners` | `black` | outside round watch screens; Play rejects transparency |
| `parallel` | from cores and memory | renderer processes |
| `java_home` | | JDK for the renderer |
| `screens` | `[]` | per-screenshot settings, as on iOS, with `font_scales` |

## Previews

Each `@Preview` renders as in Android Studio:

- `showSystemUi = true`: the whole screen with the status bar and gesture handle. Apps that
  target API 35 or later are edge-to-edge, as Android enforces: the content gets the system bar
  insets and draws behind them.
- Without it: the composable at its own size (a component).
- `device`, `widthDp`/`heightDp`, `locale`, `uiMode` (dark), `fontScale`: the preview's own value
  wins over the matrix, so `@Preview(device = Devices.PIXEL_TABLET)` renders only on that tablet.
- Multipreviews (`@PreviewLightDark`, `@PreviewScreenSizes`, `@PreviewFontScale`,
  `@WearPreviewDevices`, your own) expand like in the IDE, named `Function - Name`.
- `@PreviewParameter`: one screenshot per value, `Name_1.png`, `Name_2.png`…
- Dialogs, bottom sheets and popups shown in the preview are captured, as real windows.

## Devices

The device list is Android Studio's own catalog, generated into Swiftshot: every Pixel, the
reference phones and tablets, foldables unfolded and folded (`Pixel 9 Pro Fold (folded)` is the
outer screen) and Wear OS round and square screens. Wear OS modules (those using Wear Compose)
render on `watch_devices`, once, dark (Wear OS has no light mode).

## Output

```
<output_directory>/<language>/<device>-<preview>[-<appearance>][-<font scale>x].png
<output_directory>/screenshots.html
<output_directory>/swiftshot-report.json
```

With `"layout": "fastlane"`, screenshots go where `fastlane supply` uploads them from:
`<locale>/images/phoneScreenshots`, `sevenInchScreenshots`, `tenInchScreenshots` and
`wearScreenshots`.

## CI

Linux runners are enough:

```yaml
jobs:
  screenshots:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v5
        with: { distribution: temurin, java-version: 21 }
      - uses: LukasAnda/swiftshot@v0.4.0
      - uses: actions/upload-artifact@v7
        with: { name: screenshots, path: screenshots }
```

## How it works

```mermaid
flowchart LR
  cli["swiftshot"] -->|"init script"| gradle["Gradle<br/>swiftshotPrepare"]
  gradle -->|"classes, classpath,<br/>resources"| scan["@Preview scan<br/>(bytecode)"]
  scan --> plan["matrix<br/>devices × languages ×<br/>appearances × font scales"]
  plan --> r1["renderer 1<br/>layoutlib"]
  plan --> r2["renderer 2<br/>layoutlib"]
  plan --> rn["renderer n<br/>layoutlib"]
  r1 & r2 & rn --> out["PNGs, gallery,<br/>report, frames"]
```

Renderer processes start while Gradle is still building, from the previous run's classpath, and
are kept when it is unchanged.

1. **Build.** Swiftshot runs `./gradlew swiftshotPrepare` with an init script: the variant is
   compiled as usual and the task writes the module's classes, runtime classpath, resources and
   assets to a JSON file. Nothing in the project changes.
2. **Find previews.** `@Preview` is invisible to reflection (binary retention), so Swiftshot reads
   the compiled class files directly, resolving multipreview annotations from the project and its
   libraries.
3. **Render.** Renderer processes load the app's classpath together with layoutlib, the rendering
   engine of Android Studio's previews, through Paparazzi's SDK. Each process starts once and then
   renders whole groups of screenshots (one device, language, appearance and font scale) by
   swapping only the composable. Several processes run in parallel; a class-data-sharing archive
   makes each one start faster after the first run.
4. **System UI.** On a device the status bar and gesture handle are system windows above the app,
   so Swiftshot hands the content real insets and draws the bars over the finished frame.

Paparazzi and Roborazzi run screenshots as unit tests: Gradle compiles a test source set and a
test task renders one screenshot per test, one at a time per JVM. Swiftshot skips the test
machinery and renders in parallel processes that stay up for the whole run.

## Limitations

- `apiLevel` in `@Preview` is ignored: every preview renders with layoutlib's Android version.
- Foldables render flat (no hinge posture), as in Android Studio.
- Android TV and Automotive devices render, but get no system bars.
