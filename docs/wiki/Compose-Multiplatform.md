Swiftshot renders the `@Preview`s of a Compose Multiplatform module for Android, desktop and iOS
in one run: Play Store, desktop and App Store screenshots from the same shared code.

## Requirements

- A module with `org.jetbrains.kotlin.multiplatform` and Compose Multiplatform
- Previews in `commonMain` with `androidx.compose.ui.tooling.preview.Preview`
  (`org.jetbrains.compose.ui:ui-tooling-preview`)
- JDK 21 or later
- Android target: `ui-tooling` on its runtime classpath, as for [[Android]]. With the
  `com.android.kotlin.multiplatform.library` plugin:

```kotlin
dependencies {
    "androidRuntimeClasspath"("androidx.compose.ui:ui-tooling")
}
```

- iOS target: an Apple silicon Mac with Xcode and an `iosSimulatorArm64()` target
- The Android SDK only for the Android target: `--platforms ios` or `desktop` runs without it

Nothing else is added to the project.

## Quick start

In the folder with `gradlew`:

```
swiftshot --devices "Pixel 10 Pro,Pixel Tablet" \
  --desktop-devices "Desktop 1440×900 @2x" \
  --ios-devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5)" \
  --languages "en-US,ar" --appearances light,dark
```

`swiftshot list` prints the previews per target, e.g. `:shared (android)` and `:shared (desktop)`.

## Targets

| target | renders with | devices |
|---|---|---|
| Android (`android {}` or `androidTarget()`) | layoutlib, as for Android modules | `devices` |
| desktop (the first `jvm()` target) | Compose's `ImageComposeScene` (Skia, headless, no window) | `desktop_devices` |
| iOS (`iosSimulatorArm64()`) | Swiftshot's iOS renderer, no simulator booted | `ios_devices` |

All targets present are rendered. Pick some with `--platforms android,desktop` or
`"platforms": ["android", "ios"]`. On Linux, or on a Mac without Xcode, iOS is skipped with a
warning.

Desktop devices: `Desktop 1280×800`, `Desktop 1366×768`, `Desktop 1440×900`, `Desktop 1920×1080`,
and `@2x` versions of 1280×800, 1440×900 and 1920×1080. Default: `Desktop 1440×900 @2x`.

## Configuration

```json
{
  "modules": [":shared"],
  "platforms": ["android", "desktop", "ios"],
  "devices": ["Pixel 10 Pro", "Pixel Tablet"],
  "desktop_devices": ["Desktop 1440×900 @2x"],
  "ios_devices": ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"],
  "ios_versions": ["27.0"],
  "languages": ["en-US", "ar"],
  "appearances": ["light", "dark"],
  "output_directory": "screenshots"
}
```

| key | flag | default |
|---|---|---|
| `platforms` | `--platforms` | every target the module has |
| `desktop_devices` | `--desktop-devices` | Desktop 1440×900 @2x |
| `ios_devices` | `--ios-devices` | iPhone 17 Pro Max, iPad Pro 13-inch (M5) |
| `ios_versions` | `--ios` | newest installed |

The other keys are the [[Android]] ones.

## Output

Android and desktop screenshots are named as on [[Android]], iOS ones as on iOS, all in one
`output_directory`, gallery and report. With `"layout": "fastlane"`, desktop screenshots go to
`<locale>/images/desktopScreenshots`.

## How the iOS target works

- Previews are found on the module's JVM target.
- Swiftshot's Gradle init script adds a `SwiftshotHost` framework to the iOS simulator target,
  with a generated Kotlin wrapper per preview (`ComposeUIViewController`).
- Private previews are made internal in copies of the sources; your sources are not changed.
- A small SwiftUI host app gets a `#Preview` per preview and is rendered by the iOS no-boot
  renderer.
- Component previews (no `showSystemUi`) render at the size the desktop renderer measured.

The output is pixel identical to a booted simulator.

## Speed

`Example/MultiplatformDemo`, 9 previews in English and Arabic, on an Apple silicon Mac:

- 90 screenshots (Android phone and tablet, desktop, iPhone and iPad) in 19 s
- iOS alone: 72 screenshots (2 devices × 2 languages × light and dark) in about 17 s, including
  the Kotlin/Native framework link

## Limitations

- iOS needs a Mac with Xcode.
