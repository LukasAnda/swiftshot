# Swiftshot

App Store screenshots straight from your SwiftUI and UIKit `#Preview`s, without booting a simulator.

- Renders `#Preview`s directly. No UI tests, no `SnapshotHelper.swift`, no simulator to boot.
- Every device, iOS version, language, appearance and text size from one command.
- Pixel identical to a booted simulator's framebuffer, status bar included.
- iPhone, iPad, iPhone Duo and Apple Watch.
- Output in the fastlane/deliver layout, so `fastlane deliver` uploads it unchanged.

## Install

Requires an Apple silicon Mac with Xcode 26.6 or 27.x.

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
export PATH="$HOME/.swiftshot/bin:$PATH"
```

This installs the latest release into `~/.swiftshot/bin` (set `SWIFTSHOT_PREFIX` to change it).
To build from source instead: `git clone https://github.com/LukasAnda/swiftshot && cd swiftshot && make install`.

## Quick start

Run `swiftshot init` in your project to generate `swiftshot.json`. It detects the project or
workspace, the app scheme (and a watchOS app scheme), the languages from the project's known
regions, and App Store devices installed on this Mac (the newest Pro Max iPhone, the 13-inch iPad
if the app runs on iPad, an Apple Watch Ultra for a watch app). Then run `swiftshot`.

Or pass everything on the command line:

```
swiftshot --project MyApp.xcodeproj --scheme MyApp \
  --devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5)" \
  --languages "en-US,de-DE" --appearances light,dark
```

This builds the app once, finds every `#Preview` and renders each one for every combination of
device, language and appearance. You get:

- `screenshots/<language>/<device>-<preview>.png`
- `screenshots/screenshots.html`, a gallery to review them
- `screenshots/swiftshot-report.json`, a machine-readable report

`swiftshot list --project MyApp.xcodeproj --scheme MyApp` prints the previews it found.
`swiftshot devices` lists the installed runtimes and devices.

Build with the Debug configuration (the default). The compiler only includes `#Preview` code in
Debug builds.

## CI

Swiftshot needs a Mac with Xcode and the runtimes you render. No simulators and no GUI session.
It runs on the free GitHub-hosted `macos-26` and `xcode-27` runners.

GitHub Actions:

```yaml
jobs:
  screenshots:
    runs-on: xcode-27
    steps:
      - uses: actions/checkout@v4
      - uses: LukasAnda/swiftshot@v0.1.2
        with:
          version: 0.1.2      # or "latest"
          # args: --devices "iPhone 17 Pro Max" --languages en-US,de-DE
      - uses: actions/upload-artifact@v4
        with:
          name: screenshots
          path: fastlane/screenshots
```

The action installs the release and runs `swiftshot run` with your `swiftshot.json`, or with `args`.
Use `working-directory` if the project is not at the repo root.

Other CI:

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=0.1.2 sh
~/.swiftshot/bin/swiftshot run --download-missing-runtimes
```

The release archive is `swiftshot-macos-arm64.tar.gz` on the
[releases page](https://github.com/LukasAnda/swiftshot/releases); the installer checks its SHA-256.
The exit code is non-zero if any screenshot failed.

### Visual review tools

The output is plain PNGs with stable names, so screenshot review services can take it as is:

```
npx @argos-ci/cli upload fastlane/screenshots   # Argos, needs ARGOS_TOKEN
npx @percy/cli upload fastlane/screenshots      # Percy, needs PERCY_TOKEN
```

## Configuration

Put a `swiftshot.json` next to your project. Keys follow fastlane's `Snapfile`, and every key is
also a flag (see `swiftshot run --help`).

```json
{
  "project": "MyApp.xcodeproj",
  "scheme": "MyApp",
  "devices": ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"],
  "ios_versions": ["27.0"],
  "languages": ["en-US", "de-DE", "ja"],
  "appearances": ["light", "dark"],
  "output_directory": "fastlane/screenshots",
  "clear_previous_screenshots": true
}
```

Then just run `swiftshot`.

### Per-screenshot settings

Override settings for previews that match a name or `*` glob. The first match wins.

```
swiftshot --screen "Welcome: appearances=light,dark" \
          --screen "Stats: languages=de-DE,ja devices=iPad*" \
          --screen "Debug*: skip=true"
```

Or in `swiftshot.json`:

```json
"screens": [
  { "preview": "Welcome", "appearances": ["light", "dark"] },
  { "preview": "History", "full_length": true },
  { "preview": "Debug*", "skip": true }
]
```

Keys: `appearances`, `languages`, `devices`, `ios_versions` (`ios` on the command line),
`text_sizes`, `full_length`, `delay`, `skip`.

### Features

- **UIKit.** Preview bodies can be SwiftUI views, `UIViewController`s or `UIView`s.
- **Partial views.** `.sizeThatFitsLayout` and `.fixedLayout(width:height:)` previews render at
  their own size, like in Xcode:
  `#Preview("Habit row", traits: .sizeThatFitsLayout) { HabitRow(habit: .sample) }`
- **Full-length.** `--full-length` grows a screen until its scroll view shows all of its content.
  iOS only.
- **Sheets and alerts.** Present them in the preview and they are captured fully presented:
  `HabitListView().sheet(isPresented: .constant(true)) { NewHabitView() }`
- **Text sizes.** `--text-sizes default,XXXL,AX5`. Non-default sizes get a `-<size>` file suffix.
- **Status bar.** Full-screen shots show 9:41, full signal and a charged battery.
  `--no-status-bar` leaves it out.
- **Apple Watch.** Add watch models to `--devices`; use `--watch-scheme` if the watch app has its
  own scheme.
- **Slow content.** `--delay <seconds>` waits before each capture, e.g. for async images.

## Swiftshot vs fastlane

Measured with this repo's `Example/DemoApp` on the free GitHub-hosted `xcode-27` runner, from a
cold start. The workflow is `.github/workflows/benchmark.yml`, so anyone can re-run it.

| tool | screenshots | wall clock |
|---|---:|---:|
| `fastlane snapshot` | 45 | 3256 s (54 min) |
| swiftshot | 73 | 45–59 s |

fastlane boots a simulator per device and runs a UI-test session per device and language, which
installs a test runner, relaunches the app and taps to each screen. Swiftshot boots nothing and
navigates nothing: it renders the previews directly. It starts one app process per language and
renders every device inside it, after a single build.

## How it works

1. Swiftshot builds the app once for the iOS simulator.
2. It runs the app directly on the Mac against the simulator runtime, with a small injected
   library. No simulator is booted.
3. The library finds every `#Preview` in the built app.
4. The app's windows go to a render server running inside the same process, on a fake display
   with the target device's exact size. Its frame is the screenshot.
5. Every device, appearance and text size is rendered in that one process. Each language gets its
   own process, so localization is real.
6. The status bar is drawn by the system's own status bar component.

`--mode device` renders in real booted simulators instead and serves as the reference. Output is
verified pixel identical against booted simulators in CI.

## Requirements

- Apple silicon Mac
- Xcode 26.6 or 27.x with the simulator runtimes you want to render (Xcode > Settings > Components)
- An app target with `#Preview`s (iOS 17+). Nothing has to be added to your project.

## Development

```
make                                                   # builds bin/
swift test                                             # unit tests
SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
```

The integration tests render `Example/DemoApp` and compare the output pixel by pixel with booted
simulators.

## License

AGPL-3.0 — see [LICENSE](LICENSE).
