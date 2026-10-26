## What changes

| fastlane snapshot | swiftshot |
|---|---|
| UI test target, `SnapshotHelper.swift`, `snapshot("name")` calls | your existing `#Preview`s |
| launch arguments to navigate to each screen | none, each preview is a screen |
| `Snapfile` | `swiftshot.json` |
| a booted simulator per device | no simulator |
| a UI test session per device and language | one app process per language |

The output layout is the same, so `fastlane deliver` and `frameit` keep working.

## Snapfile keys

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

## Steps

1. Make sure each screen you capture has a `#Preview`, with the sample data it needs.
2. Run `swiftshot init`, then compare its `swiftshot.json` with your `Snapfile`.
3. Run `swiftshot` and review `screenshots/screenshots.html`.
4. Replace `capture_ios_screenshots` / `snapshot` in your lane:
   `sh("swiftshot run --config ../swiftshot.json")`
5. Delete the UI test target and `SnapshotHelper.swift` if nothing else uses them.

Preview names become screenshot names: `#Preview("01 Welcome")` gives `<device>-01 Welcome.png`,
which keeps App Store order.
