- [fastlane snapshot (iOS)](#fastlane-snapshot-ios)
- [fastlane screengrab (Android)](#fastlane-screengrab-android)
- [Paparazzi and Roborazzi](#paparazzi-and-roborazzi)

## fastlane snapshot (iOS)

### What changes

| fastlane snapshot | swiftshot |
|---|---|
| UI test target, `SnapshotHelper.swift`, `snapshot("name")` calls | your existing `#Preview`s |
| launch arguments to navigate to each screen | none, each preview is a screen |
| `Snapfile` | `swiftshot.json` |
| a booted simulator per device | no simulator |
| a UI test session per device and language | one app process per language |

The output layout is the same, so `fastlane deliver` and `frameit` keep working.

### Snapfile keys

| Snapfile | swiftshot.json |
|---|---|
| `project` / `workspace` | `project` / `workspace` |
| `scheme` | `scheme` (the app scheme, not the UI test scheme) |
| `devices` | `devices` |
| `languages` | `languages` |
| `ios_version` | `ios_versions` |
| `dark_mode` | `appearances: ["dark"]` |
| `output_directory` | `output_directory` |
| `clear_previous_screenshots` | `clear_previous_screenshots` |
| `override_status_bar` | `status_bar` (on by default) |
| `skip_open_summary` | `html: false` |
| `concurrent_simulators` | not needed |
| `launch_arguments` | set state in the preview |
| `erase_simulator`, `reinstall_app` | not needed |

### Steps

1. Make sure each screen you capture has a `#Preview`, with the sample data it needs.
2. Run `swiftshot init`, then compare its `swiftshot.json` with your `Snapfile`.
3. Run `swiftshot` and review `screenshots/screenshots.html`.
4. Replace `capture_ios_screenshots` / `snapshot` in your lane:
   `sh("swiftshot run --config ../swiftshot.json")`
5. Delete the UI test target and `SnapshotHelper.swift` if nothing else uses them.

Preview names become screenshot names: `#Preview("01 Welcome")` gives `<device>-01 Welcome.png`,
which keeps App Store order.

## fastlane screengrab (Android)

### What changes

| fastlane screengrab | swiftshot |
|---|---|
| instrumentation tests, `Screengrab.screenshot("name")` calls | your existing `@Preview`s |
| `androidTest` APK, Espresso or UI Automator to reach each screen | none, each preview is a screen |
| `Screengrabfile` | `swiftshot.json` |
| a running emulator or device | no emulator |
| `assembleDebug` and `assembleAndroidTest` | one Gradle task, the debug variant |

With `"layout": "fastlane"`, the output is where `fastlane supply` uploads from:
`metadata/android/<locale>/images/phoneScreenshots`, `sevenInchScreenshots`,
`tenInchScreenshots`, `tvScreenshots` and `wearScreenshots`.

### Screengrabfile keys

| Screengrabfile | swiftshot.json |
|---|---|
| `app_package_name`, `tests_package_name` | not needed; `modules` picks the Gradle modules |
| `app_apk_path`, `tests_apk_path` | not needed, Swiftshot builds `variant` |
| `locales` | `languages` |
| `output_directory` | `output_directory` with `"layout": "fastlane"` |
| `clear_previous_screenshots` | `clear_previous_screenshots` |
| `device_type` (`phone`, `sevenInch`, `tenInch`, `tv`, `wear`) | `devices`, `watch_devices`; the folder follows the device |
| `specific_device` | not needed |
| `use_tests_in_classes`, `use_tests_in_packages` | `previews` or `screens` with `skip` |
| `launch_arguments` | set state in the preview |
| `skip_open_summary` | `html: false` |
| `use_timestamp_suffix` | not needed, names are stable |
| `reinstall_app`, `exit_on_test_failure` | not needed |

### Steps

1. Make sure each screen you capture has a `@Preview` with `showSystemUi = true` and the sample
   data it needs, and the module has `debugImplementation("androidx.compose.ui:ui-tooling")`.
2. Run `swiftshot init`. With a `fastlane` folder it sets
   `"output_directory": "fastlane/metadata/android"` and `"layout": "fastlane"`.
3. Run `swiftshot` and review `fastlane/metadata/android/screenshots.html`.
4. Replace `capture_android_screenshots` / `screengrab` in your lane:
   `sh("swiftshot run --config ../swiftshot.json")`
5. Delete the screenshot tests and the screengrab dependency if nothing else uses them.

`supply` uploads every image in an `images/<type>Screenshots` folder, in name order. Render one
appearance for upload (`"appearances": ["light"]` or `["dark"]`), and name previews in the order
you want: `@Preview(name = "01 Welcome", showSystemUi = true)` gives
`Pixel 10 Pro-01 Welcome.png`.

## Paparazzi and Roborazzi

Swiftshot uses the same layoutlib renderer, through Paparazzi's SDK, but renders `@Preview`s
instead of tests:

- No plugin, test source set or snapshot tests to write: the previews are the input.
- Screens that only exist in a Paparazzi or Roborazzi test need a `@Preview`.
- Swiftshot doesn't record or verify golden images. Keep those tests for that, or upload the
  output to a review tool ([[CI]]).
- Output is named for the store, by language and device, not by test class.
