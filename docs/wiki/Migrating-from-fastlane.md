# Migrating

From fastlane snapshot and screengrab, Paparazzi and Roborazzi.

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
4. Add the [fastlane plugin](https://github.com/LukasAnda/fastlane-plugin-swiftshot)
   (`fastlane add_plugin swiftshot`) and replace `capture_ios_screenshots` / `snapshot` in your
   lane with `swiftshot`. It takes the same `devices`, `languages`, `dark_mode`,
   `output_directory` and `clear_previous_screenshots`:
   `swiftshot(devices: ["iPhone 17 Pro Max"], languages: ["en-US", "de-DE"])`
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

In a lane, `swiftshot(platform: "android", languages: ["en-US", "de-DE"])` from the
[fastlane plugin](https://github.com/LukasAnda/fastlane-plugin-swiftshot) replaces
`capture_android_screenshots` and writes the supply layout by default.

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

Swiftshot renders `@Preview`s with layoutlib, the renderer Paparazzi uses (Roborazzi renders with
Robolectric), so a screenshot test that calls a previewed composable can be replaced by the preview,
on the same device and settings.

Run `swiftshot init` in the project. It never runs Gradle and removes nothing: Paparazzi and
Roborazzi stay in the project, and only `swiftshot.json` and `swiftshot-migration.md` are written.

### What init reads

- Modules that use either tool: the plugin, a version-catalog alias, a convention plugin
  (`build-logic`, `buildSrc`, included builds) or test imports.
- Each test's device: Paparazzi `DeviceConfig` presets and custom configs, Robolectric and
  Roborazzi qualifier strings (`@Config(qualifiers = ...)`, `setQualifiers`),
  `RobolectricDeviceQualifiers` and `robolectric.properties`. A device it can't read is reported,
  never guessed.
- Languages, only what the tests set. If none do, `en-US`, and the app's other string-resource
  languages are listed for you to add.

### What it writes

A `screens` rule per tested preview (by fully qualified function), so each preview renders only
on the devices and settings of its tests (`override_preview` where a test replaces the preview's
own). A final rule skips the previews no test covers. See [[Configuration]].

### swiftshot-migration.md

The same report is printed and saved. It lists:

- the modules found and the device each test uses (labelled "tool default", "from @Preview" or
  "unresolved" when it was not read from the test)
- tests without a matching `@Preview` (add a `@Preview` with the same arguments to include them),
  and tests it couldn't read
- previews whose screenshot size differs from the old tool's (Paparazzi renders the full screen;
  Swiftshot crops to the content unless the `@Preview` sets `showSystemUi`)
- previews no test covers, which are skipped

### Side by side

Keep the Paparazzi or Roborazzi tests while you check the output, and delete them when you are
ready.

### Baselines

Swiftshot doesn't compare images yet (planned for 1.0.0). Its first baseline will come from CI,
not from the images Paparazzi or Roborazzi recorded, because the renderer differs.
