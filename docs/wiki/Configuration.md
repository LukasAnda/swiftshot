`swiftshot init` writes a `swiftshot.json` for the project in the current folder. `--force`
overwrites an existing file.

- iOS: the project or workspace, the app scheme, a watchOS scheme, the languages from the
  project's known regions, and App Store devices installed on the Mac.
- Android: the Android modules from `settings.gradle(.kts)`, the languages the app has
  `values-*/strings*.xml` for, Play devices (Pixel 10 Pro, Pixel 9 Pro Fold, Pixel Tablet), a
  watch device if a module uses Wear OS, and the `fastlane` layout if the project has a `fastlane`
  folder. Nothing is built.

Swiftshot reads `./swiftshot.json` automatically, or the file given with `--config`. Command-line
flags override the file.

iOS and Android each have their own keys, below; a key that only the other platform knows is an
error on Android. A file with `project`, `workspace` or `scheme` is an iOS configuration.

- [iOS](#example)
- [Android](#android)

## Example

iOS:

```json
{
  "project": "MyApp.xcodeproj",
  "scheme": "MyApp",
  "devices": ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)", "Apple Watch Ultra 3 (49mm)"],
  "watch_scheme": "MyWatchApp",
  "ios_versions": ["27.0"],
  "languages": ["en-US", "de-DE", "ja"],
  "appearances": ["light", "dark"],
  "output_directory": "fastlane/screenshots",
  "clear_previous_screenshots": true,
  "screens": [
    { "preview": "Welcome", "appearances": ["light", "dark"] },
    { "preview": "History", "full_length": true },
    { "preview": "Debug*", "skip": true }
  ]
}
```

## Keys

iOS:

| key | default | |
|---|---|---|
| `project` / `workspace` | | Xcode project or workspace |
| `scheme` | | scheme that builds the app |
| `configuration` | `Debug` | must include `#Preview` code, so Debug |
| `app` | | prebuilt simulator `.app` instead of building |
| `derived_data` | `.swiftshot/DerivedData` | |
| `xcodebuild_args` | `[]` | extra `xcodebuild` arguments |
| `devices` | iPhone 17 Pro Max, iPad Pro 13-inch (M5) | iPhone, iPad and Apple Watch models |
| `ios_versions` | newest installed | iOS runtimes |
| `watch_scheme` | | scheme of the watchOS app |
| `watch_app` | | prebuilt watchOS simulator `.app` |
| `watchos_versions` | newest installed | watchOS runtimes |
| `languages` | `["en-US"]` | |
| `appearances` | `["light"]` | `light`, `dark` |
| `text_sizes` | `["default"]` | `XS` … `XXXL`, `AX1` … `AX5`, `default` |
| `content_size` | | changes the default text size itself, no file suffix |
| `previews` | all | only previews matching these names or `*` globs |
| `full_length` | `false` | grow screens to their scroll view's whole content (iOS) |
| `output_directory` | `screenshots` | |
| `format` | `png` | `png`, `jpeg` |
| `clear_previous_screenshots` | `false` | |
| `html` | `true` | write `screenshots.html` |
| `status_bar` | `true` | draw the 9:41 status bar |
| `delay` | `0` | seconds to wait before each capture |
| `settle_frames` | `3` | run-loop frames to wait before capture |
| `mode` | `virtual` | `virtual` (no simulator) or `device` (booted reference) |
| `parallel_languages` | `1` | language processes per iOS version at once |
| `timeout` | `600` | seconds before an app launch is killed |
| `download_missing_runtimes` | `false` | download requested runtimes that are missing |
| `allow_unsupported_devices` | `false` | render devices the runtime can't boot (best effort) |
| `shutdown_simulators` | `false` | shut down simulators afterwards |
| `device_set` | | isolated CoreSimulator device set |
| `template_cache` | `~/Library/Caches/swiftshot/templates.noindex` | boot templates for booted modes |
| `frame` | `none` | `plain` or `appstore`, see [[Device frames]] |
| `frame_color` | per model | bezel colour, e.g. `"Deep Blue"` or `{"iPad Pro 13-inch (M5)": "Silver"}` |
| `framefile` | found like frameit | frameit `Framefile.json` |
| `frame_background` | grey | App Store background: `#RRGGBB` or an image |
| `frame_output` | `<output>-framed` | where plain frames go |
| `frame_cache` | `~/Library/Caches/swiftshot/frames` | downloaded bezels |
| `accept_bezel_license` | `false` | accept Apple's Design Resources License without a prompt (CI) |
| `screens` | `[]` | per-screenshot settings, below |

## Per-screenshot settings

Each rule matches previews by name or `*` glob. The first matching rule wins. iOS keys:

| key | |
|---|---|
| `preview` | name or glob |
| `appearances`, `languages`, `devices`, `ios_versions`, `text_sizes` | replace the global list for this preview |
| `full_length` | `true` / `false` |
| `delay` | seconds |
| `skip` | `true` leaves the preview out |
| `frame` | `plain`, `appstore` or `none` for this preview |

On the command line:

```
swiftshot --screen "Welcome: appearances=light,dark" \
          --screen "Stats: languages=de-DE,ja devices=iPad*" \
          --screen "Debug*: skip=true"
```

## Previews

Swiftshot renders each `#Preview` as Xcode would (for `@Preview` see [[Android]]):

- Full screen by default.
- `.sizeThatFitsLayout` and `.fixedLayout(width:height:)` render at their own size.
- `.landscapeLeft` / `.landscapeRight` render in landscape.
- Sheets, alerts and confirmation dialogs presented in the preview are captured fully presented.
- The body can be a SwiftUI view, a `UIViewController` or a `UIView`.

```swift
#Preview("Welcome") { WelcomeView() }
#Preview("Habit row", traits: .sizeThatFitsLayout) { HabitRow(habit: .sample) }
#Preview("New habit") { HabitListView().sheet(isPresented: .constant(true)) { NewHabitView() } }
```

## Output

```
<output_directory>/<language>/<device>-<preview>[-<appearance>][-<text size>][-iOS<version>].png
<output_directory>/screenshots.html
<output_directory>/swiftshot-report.json
```

- `-<appearance>` unless only light is rendered (watch screenshots have none)
- `-<text size>` for non-default text sizes
- `-iOS<version>` when more than one runtime is rendered

The layout is fastlane/deliver's,
so `fastlane deliver` uploads it unchanged.

## Android

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
  "clear_previous_screenshots": true,
  "screens": [
    { "preview": "Stats", "full_length": true },
    { "preview": "Debug*", "skip": true }
  ]
}
```

| key | default | |
|---|---|---|
| `project_dir` | `.` | the Gradle project, relative to the config file |
| `modules` | every Android module | e.g. `[":app", ":wear"]` |
| `variant` | `debug` | build variant; needs `ui-tooling` on its classpath |
| `gradle_args` | `[]` | extra Gradle arguments |
| `java_home` | | JDK 21+ for Gradle and the renderer, see [[Installation]] |
| `devices` | Pixel 10 Pro, Pixel Tablet | phones, foldables, tablets: names, ids or `*` globs (`swiftshot devices`) |
| `watch_devices` | Wear OS Large Round | for Wear OS modules |
| `languages` | `["en-US"]` | BCP 47 tags |
| `appearances` | `["light"]` | `light`, `dark` |
| `font_scales` | `[1]` | 0.5 to 3, e.g. `[1, 1.3, 2]` |
| `previews` | all | only previews matching these names or `*` globs |
| `full_length` | `false` | grow scrolling screens to their whole content |
| `delay` | `0` | seconds to advance the clock before capture |
| `output_directory` | `screenshots` | |
| `layout` | `swiftshot` | `swiftshot` or `fastlane` (below) |
| `clear_previous_screenshots` | `false` | |
| `html` | `true` | write `screenshots.html` |
| `system_ui` | `preview` | status bar and gesture handle: as `showSystemUi` says, `always`, `never` |
| `frame` | `none` | `plain` or `none`, see [[Device frames]] |
| `round_corners` | `black` | outside round watch screens: `black`, `transparent` |
| `android_theme` | the app's theme | window theme; default: the `<application>` theme in the module's manifest, else Material's |
| `parallel` | from cores and memory | renderer processes |
| `screens` | `[]` | per-screenshot settings |

`screens` on Android: `preview`, `appearances`, `languages`, `devices`, `font_scales`,
`full_length`, `delay` and `skip`, as above. `font_scales` takes the place of iOS's `text_sizes`;
there are no `ios_versions` and no per-screen `frame`.

```
swiftshot --screen "Stats: languages=de-DE,ja devices=Pixel*" --screen "Debug*: skip=true"
```

A preview's own `device`, `locale`, `uiMode` and `fontScale` win over the matrix, see [[Android]].

### Android output

```
<output_directory>/<language>/<device>-<preview>[-<appearance>][-<font scale>x].png
<output_directory>/screenshots.html
<output_directory>/swiftshot-report.json
```

- `-light` / `-dark` when both are rendered, `-dark` also when only dark is; none on Wear OS or
  when the preview sets `uiMode`
- `-<scale>x` (e.g. `-1.3x`) for a font scale other than 1, or when several are rendered
- `_1`, `_2`… for each `@PreviewParameter` value

With `"layout": "fastlane"` the language folder holds the folders `fastlane supply` uploads:

```
fastlane/metadata/android/en-US/images/phoneScreenshots/Pixel 10 Pro-Welcome-light.png
fastlane/metadata/android/en-US/images/tenInchScreenshots/Pixel Tablet-Welcome-light.png
fastlane/metadata/android/en-US/images/wearScreenshots/Wear OS Large Round-Watch list.png
```

Tablets and foldables up to 9" go to `sevenInchScreenshots`, TVs to `tvScreenshots`.
