# Swiftshot

App Store screenshots **straight from your SwiftUI `#Preview`s**: every iPhone, iPad and Apple
Watch, every iOS/watchOS version, language, appearance and Dynamic Type size. No UI tests, no
`SnapshotHelper.swift`, and **no simulator to boot**. It replaces `fastlane snapshot` /
`capture_ios_screenshots`, and settings can be overridden **per screenshot**.

```
swiftshot --project MyApp.xcodeproj --scheme MyApp \
  --devices "iPhone 17 Pro Max,iPhone SE (3rd generation),iPad Pro 13-inch (M5)" \
  --ios "26.5,27.0" --languages "en-US,de-DE,ar,ja" --appearances light,dark

# Apple Watch: add watch models and the watch app's scheme
swiftshot --project MyApp.xcodeproj --scheme MyApp --watch-scheme MyWatchApp \
  --devices "iPhone 17 Pro Max,Apple Watch Series 11 (46mm),Apple Watch Ultra 3 (49mm)"
```

The output uses the fastlane/deliver layout (`screenshots/<language>/<device>-<preview>.png`), so
`fastlane deliver` uploads it unchanged. A `screenshots.html` gallery and a machine-readable
`swiftshot-report.json` are written next to it.

## Swiftshot vs fastlane

Measured with this repo's `Example/DemoApp`: the same screens, devices and languages, on **free
GitHub-hosted runners** (Apple M1 VM, 3 cores, 7 GB) from a cold start (empty DerivedData, no
simulators). It's `.github/workflows/benchmark.yml`, so anyone can re-run it.

| runner | tool | screenshots | wall clock |
|---|---|---:|---:|
| `macos-26` (Xcode 26.6, iOS 26.5) | `fastlane snapshot` | 45 (iOS) | **4683 s** (78 min) |
| `macos-26` | swiftshot, booted simulators (`--boot`) | 64 (iOS + watch) | 990 s |
| `macos-26` | swiftshot, no boot (default) | 55 (iOS) | **38 s** warm |
| `xcode-27` (Xcode 27, iOS 27.0) | `fastlane snapshot` | 45 (iOS) | **3583 s** (60 min) |
| `xcode-27` | swiftshot, no boot (default) | 55 (iOS) | **61 s** cold, **34 s** warm |
| `xcode-27` | swiftshot, no boot, iOS + Apple Watch | 70 | 48 s |

On the same `xcode-27` run, swiftshot produced more screenshots **59× faster** than fastlane from a
cold start (105× warm).

On an Apple Silicon laptop (warm DerivedData), the same 55 iOS screenshots take **8–9 s**; with the
watch, 70 take 17 s.

fastlane runs with the setup its `snapshot` docs recommend (`Example/DemoApp/fastlane/Snapfile`):
one simulator per device, created once and reused for every language and screenshot
(`concurrent_simulators` on, no erase or reinstall between runs), `override_status_bar`, and the
app built once with `xcodebuild build-for-testing` and then run with `test_without_building`, so no
language pays for a build (`bench/run.sh fastlane`; the build is counted in its time).

### Why fastlane is slow, and why swiftshot isn't

fastlane drives your app through **UI tests on booted simulators**:

1. It boots one simulator **per device**. A never-booted simulator spends ~30 s on its first boot
   (most of it CoreSimulator's data migration), and several first boots at once slow each other
   down badly on a small CI machine.
2. For every **device × language** it runs a separate `xcodebuild test` session: it installs the
   test runner, bootstraps XCUITest, relaunches the app for each screenshot, navigates to the
   screen, captures with `XCUIScreen` and copies the image out. That's about 50 s per
   device-language pair before anything is even slow.
3. You have to maintain a UI-test target, `SnapshotHelper.swift`, a `Snapfile`, and app code that
   routes launch arguments to each screen (see `Example/DemoApp/UITests`). Dark mode means a second
   full run.

swiftshot does none of that:

1. **No simulator.** The app runs directly on the Mac against the simulator runtime, so there is
   nothing to boot, no data migration and no device set (*How it works*).
2. **No UI tests, no navigation.** The screens are your `#Preview`s. Swiftshot finds them in the
   built app and renders each one directly, so nothing has to tap through the app to reach a screen.
3. **One process per language**, not per device × language. Within it, every device, preview,
   appearance and text size is just another off-screen window with that device's exact geometry.
   Total app launches = `runtimes × languages`.
4. **One build**, for `generic/platform=iOS Simulator`, with no `build-for-testing` and no test
   bundle.

## How it works

```
 host (macOS)                                   one process per runtime × language, on the Mac itself
 ─────────────                                  ─────────────────────────────────────────────────────
 swiftshot ── xcodebuild (once) ──────────────▶ YourApp.app (simulator build)
           ── swiftshot-simhost ───────────────▶ YourApp, DYLD_ROOT_PATH=<iOS runtime>
                Metal, IOSurface,                 + SwiftshotNoBoot.dylib  (routes Metal/IOSurface/compiler
                shader compiler services                                    connections to simhost)
                                                  + SwiftshotAgent.dylib   ├─ scan __swift5_proto → every #Preview
                                                                           ├─ preview × device × appearance × text size:
                                                                           │   window with the device's size, scale,
                                                                           │   safe area, display data
                                                  + in-process CAWindowServer on a stand-in display
                                                    (the compositor backboardd runs) → framebuffer
 screenshots/de-DE/*.png  ◀──────────── written directly ──────────────────┘   → PNG
```

### 1. Finding the previews

A tiny agent dylib is injected with `DYLD_INSERT_LIBRARIES`; your project doesn't change. The
agent walks the Swift runtime's protocol-conformance records (`__TEXT,__swift5_proto`) of every
image in the app bundle. It finds all types conforming to `DeveloperToolsSupport.PreviewRegistry`
(what `#Preview` expands to) and to `SwiftUI.PreviewProvider`. For each one it calls
`makePreview()` and reflects out the name, the traits (`.sizeThatFitsLayout`, `.fixedLayout`,
`.landscapeLeft`, …) and the body closure. Bodies can be SwiftUI views, `UIViewController`s or
`UIView`s.

### 2. Running a simulator app without a simulator

A simulator app is an ordinary arm64 macOS process linked against the runtime's frameworks;
CoreSimulator only gives it an environment and a few services. swiftshot provides those itself:

* **Environment.** `DYLD_ROOT_PATH` points at the runtime (`…/iOS 27.0.simruntime/…/RuntimeRoot`),
  with an empty home directory and the `SIMULATOR_*` variables a booted device's launchd would set
  (model, screen size and scale, pixel pitch). Runtimes without their own dyld shared cache
  (iOS 26.x) use the one CoreSimulator builds on the host; swiftshot builds it once with
  `simctl runtime dyld_shared_cache update` if it's missing.
* **GPU.** `swiftshot-simhost` hosts the same macOS components CoreSimulator uses:
  `MTLSimImplementation` for Metal, `IOSurfaceRemoteServer` for IOSurfaces, and the runtime's
  `MTLCompilerService`, started one per connection like launchd's `_MultipleInstances`. Their Mach
  ports reach the app as registered task ports, and `SwiftshotNoBoot.dylib` routes the app's
  `com.apple.metal.simulator`, `com.apple.IOSurface.Remote` and `com.apple.MTLCompilerService`
  connections to them.
* **App and display.** There is no `UIApplicationMain` and no display, so the agent registers a
  `UIApplication` itself. It also runs the after-commit work UIKit schedules through it (that's how
  sheets and alerts get presented), and reports each rendered device's screen to UIKit: scale,
  bounds, corner radius, P3 gamut, and the display data UIKit derives layout from (safe areas,
  home-affordance allowance, system margins). Without that data, for example, the floating tab bar
  would sit at the wrong height.
* **Capture.** A booted simulator's screen is composited by backboardd with Core Animation's
  window server (`CAWindowServer`), drawing into displays that CoreSimulator's framebuffer service
  provides. swiftshot runs that same window server inside the app process:
  `Agent/FakeDisplay.c` stands in for the framebuffer client (`SimFramebufferClient`, ~20 C
  functions) and gives it a display with the rendered device's pixel size, resized per screenshot.
  Each window reaches it through a remote context, the way an app's windows reach backboardd
  (`CA_FORCE_LOCAL_SERVER` makes remote contexts connect to the in-process server). The frame it
  presents is the screenshot: the same 8-bit BGRA bytes `simctl io screenshot` saves, written
  as is. Every window is shown once before the capture, so materials that adapt to what's behind
  them (Liquid Glass) have settled, as on a device where the screen has been visible for a moment.
  Previews with a transparent background (`.sizeThatFitsLayout`) are composited over black and
  over white, and their alpha comes from the difference.

### 3. Rendering every device in one process

Each preview is rendered in an off-screen window that *is* the target device: exact point size and
scale, size classes, idiom, safe area, corner radius and display data. The device data comes from
a **built-in table** (`Sources/swiftshot/BuiltInDisplays.swift`) that we measure on our side by
booting every device type on every runtime (`swiftshot calibrate --emit-table`). A weekly workflow
(`.github/workflows/device-table.yml`) re-measures it on the macos-15, macos-26 and xcode-27 images
and opens a PR when Apple changes anything. Users never boot a device to learn its geometry.

Languages need a fresh process (`-AppleLanguages` / `-AppleLocale`), so String Catalogs,
`NSLocalizedString`, number and date formatting and RTL mirroring are all genuine. Everything else
happens inside that one process, and PNG encoding runs in the background while the next frame
renders.

### 4. Apple Watch

The same approach, with the watchOS runtime and a watchOS build of the agent. watchOS has no public
window API, so the agent creates the hosting controllers through SwiftUI's exported metadata
accessors (with a small arm64 trampoline) and captures PepperUICore windows through the same
in-process window server as iOS (started before any UI, so SwiftUI's display timing finds it).
watchOS reads some screen answers once per process, so each watch model gets its own short process.
Text size defaults follow the model (L on small cases, XL from 44 mm up), like a real watch.

## Fidelity

Checked pixel by pixel against the framebuffer of a booted simulator (`--mode device`), below the
status bar. `swift test` runs this comparison (see [Tests](#tests)).

* **iOS 27.0** (iPhone 18 Pro, iPhone 17) and **iOS 26.5** (iPhone 17): every DemoApp screen is
  **byte-identical** (0/255) to the booted framebuffer, including sheets, alerts, confirmation
  dialogs, Liquid Glass, gradients and blurs. That includes the dimmed, blurred backdrop behind
  sheets and alerts, because it's composited by the same window server code as on a device.
* **A real iPhone 14 Pro (iOS 26.5)**, DemoApp launched on the phone and captured with
  `devicectl device capture screenshot`: Welcome, Stats and Settings within 2/255 of swiftshot's
  no-boot output below the status bar (GPU rounding of a real A16 versus the simulator), Habit list
  within 10/255 (the glass "+" under the real status bar).
* **System chrome is not drawn.** A device shows SpringBoard's status bar (and sometimes the home
  indicator) over the app; swiftshot's output has neither, like Xcode previews. Glass controls
  that sit right under them blur them in on a device, so those few hundred pixels differ (up to
  10/255 on the "+" button under the battery, and the tab bar over the home indicator on Root).
  An in-process status bar (UIKit's own `_UIStatusBar`) is in progress (`SWIFTSHOT_STATUSBAR`).
  The small black mark a simulator's screen has over its top-left 3¼ px in portrait (in every
  screenshot, home screen included) is reproduced.
* **iPhone Duo (iOS 27.1):** every DemoApp screen, Root and the floating sheet included, is
  **byte-identical** to a booted Duo outside the status capsule in the rail and the home
  indicator. That takes the Duo's display data: the status bar rail (status bar axis, vertical
  bar traits, scene corner insets, bar position and exclusion area), the scene's "system provides
  vertical bars" flag that switches sheets to their floating, 8 pt-inset metrics, and the panel's
  per-corner radii (8 pt on the hinge side, 59 pt outside) that the sheet's corners follow.
* **Landscape** previews render the landscape window like a booted host does (its scene stays
  portrait); `--mode device` doesn't rotate the simulator, so there's no framebuffer reference for
  them yet.
* **Apple Watch** (Series 11 42 mm and 46 mm, Ultra 4): byte-identical to a booted watch below the
  clock, except a few pixels of the week chart at 1/255, where the booted watch itself differs by
  as much between two of its own runs.
* **Dynamic Type:** each `--text-sizes` value is pixel-identical (0/255) to a process started at
  that system text size, on iOS and watchOS.
* **Determinism:** repeated runs produce byte-identical files (tested).

## Features

### The matrix

`--devices`, `--ios`, `--watchos`, `--languages`, `--appearances light,dark` and
`--text-sizes default,XXXL,AX5`: every combination is rendered. Text sizes are `XS S M L XL XXL
XXXL AX1…AX5` or `default` (the device's own). Non-default sizes get a `-<size>` file name suffix.

### Per-screenshot settings

Every setting can be narrowed per preview (exact name or `*` glob, first match wins):

```
swiftshot … --appearances light \
  --screen "Welcome: appearances=light,dark" \
  --screen "Stats: languages=de-DE,ja devices=iPad*" \
  --screen "Onboarding: text_sizes=default,AX3" \
  --screen "History: full_length=true" \
  --screen "Paywall: ios=27 delay=1.5" \
  --screen "Debug*: skip=true"
```

or in `swiftshot.json`:

```json
"screens": [
  { "preview": "Welcome", "appearances": ["light", "dark"] },
  { "preview": "Stats", "languages": ["de-DE", "ja"], "devices": ["iPad*"] },
  { "preview": "Onboarding", "text_sizes": ["default", "AX3"] },
  { "preview": "History", "full_length": true },
  { "preview": "Paywall", "ios_versions": ["27"], "delay": 1.5 },
  { "preview": "Debug*", "skip": true }
]
```

Keys: `appearances`, `languages`, `devices` (globs), `ios_versions` (prefix: `27` = 27.x),
`text_sizes`, `full_length`, `delay`, `skip`.

### Partial views

Previews with `.sizeThatFitsLayout` are rendered at their own size; `.fixedLayout(width:height:)`
previews at exactly that size. Both get no safe area, like in Xcode, on iOS and on Apple Watch.

```swift
#Preview("Habit row", traits: .sizeThatFitsLayout) { HabitRow(habit: .sample).padding() }
```

### Full-length screenshots

`--full-length` (or `full_length=true` per screen) grows a full-screen preview until its main
scroll view shows all of its content: long lists, forms, settings pages. Lazy content is re-measured
as it appears. Height is capped at one Metal texture (16384 px; 5461 pt at 3×). iOS only for now.

### Sheets, alerts and dialogs

Present them in the preview the way the app does, and they're captured fully presented (no
animation in flight):

```swift
#Preview("New habit sheet") {
    HabitListView().sheet(isPresented: .constant(true)) { NewHabitView().presentationDetents([.medium]) }
}
#Preview("Delete alert") {
    HabitListView().alert("Delete “Drink water”?", isPresented: .constant(true)) {
        Button("Delete", role: .destructive) { }
        Button("Cancel", role: .cancel) { }
    }
}
```

## Tests

```
swift test                                                  # unit tests, seconds, no simulator
make && SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
```

The integration tests run on `Example/DemoApp` with the built tool:

* **Parity:** renders 8 screens on iPhone 18 Pro and iPhone 17 without a simulator, renders the
  same screens twice on booted simulators (`--mode device`), and requires every pixel outside the
  system status bar and home indicator to equal a booted one. (Two references, because a booted
  simulator itself flips a few glass pixels by 1/255 between runs.)
* **iPhone Duo parity:** the same on iOS 27.1 with Root, excluding only the status capsule in the
  rail and the home indicator (skipped without an iPhone Duo device type).
* **Watch parity:** the same against a booted Apple Watch.
* **Determinism:** two runs give byte-identical files.
* **Performance:** all 22 DemoApp screenshots (two iPhones, warm) in under 30 s wall time and
  under 400 ms per screenshot inside the app (currently ~12 s and ~330 ms on an M-series Mac).
* **No boot:** a no-boot run leaves the set of booted simulators unchanged.

`SWIFTSHOT_IT_DEVICES` and `SWIFTSHOT_IT_IOS` pick other devices or a runtime. To compare one
screen by hand, `SWIFTSHOT_TREE=<file>` dumps every view's frame, safe area and margins, in both
modes.

## CI

* Needs a Mac with Xcode and the simulator runtimes you render. It needs **no simulators, no GUI
  session and no Simulator.app**. It runs on the free GitHub-hosted `macos-26` and `xcode-27` images
  (`.github/workflows/benchmark.yml` is a working example).
* Missing runtimes can be fetched with `--download-missing-runtimes`.
* Exit code is non-zero if any screenshot failed. Crashes are reported with the app's output;
  macOS crash reporting is turned off for the rendering processes, so a CI machine doesn't pile up
  crash dialogs.
* `bench/run.sh` reproduces the benchmark locally (`bench/run.sh noboot`, `bench/run.sh fastlane`).

## Booted modes (`--boot`, `--mode device`)

The pre-no-boot engine is still there:

* `--boot` renders the same virtual devices inside booted simulators: one per runtime and native
  scale, seeded from a per-runtime **boot template** (an APFS clone of a migrated data container,
  so new simulators boot in ~8 s instead of ~30 s), booting while `xcodebuild` builds.
  `--template-cache <dir>` persists templates between CI jobs.
* `--mode device` boots a real simulator per device, overrides the status bar (9:41), shows each
  preview full-screen and grabs the framebuffer with `simctl io screenshot`, for when you want the
  system status bar and home indicator in the picture.
* `--device-set <dir>` keeps booted simulators in a private CoreSimulator set; `--shutdown` shuts
  them down afterwards.

## Install

```
make            # bin/swiftshot, bin/swiftshot-simhost (macOS), the iOS and watchOS agent and
                # no-boot dylibs
make install    # PREFIX=/usr/local
```

Tested with Xcode 26.6 and 27.x, and no-boot rendering with the iOS 26.5, iOS 27.0 and watchOS 27.0
runtimes. Previews need iOS 17+ (`#Preview`), and the app's deployment target must be ≤ the oldest
runtime you render on.

## Usage

```
swiftshot [run|list|devices|calibrate|emit-table] [options]

  run         Build, render every preview for every device × runtime × language × appearance × text size
  list        Build and print the previews that were discovered
  devices     Show installed runtimes and the geometry used for each device
  calibrate   Boot the given devices once and measure their display data (maintainers)
  emit-table  Merge calibration files into Sources/swiftshot/BuiltInDisplays.swift (maintainers)
```

| option | fastlane `Snapfile` equivalent | default |
|---|---|---|
| `--project` / `--workspace`, `--scheme`, `--configuration` | `project`, `workspace`, `scheme`, `configuration` | `Debug` |
| `--app <path>` | – (prebuilt simulator `.app`) | |
| `--devices "A,B"` | `devices` | `iPhone 17 Pro Max,iPad Pro 13-inch (M5)` |
| `--ios "26.5,27.0"` | `ios_version` (single) | newest installed |
| `--languages "en-US,de-DE"` | `languages` | `en-US` |
| `--appearances light,dark` | `dark_mode` (one or the other) | `light` |
| `--text-sizes default,AX3` | – | `default` |
| `--full-length` | – | off |
| `--previews "Welcome,Onboarding*"` | `only_testing` | all |
| `--screen "<preview>: key=v …"` | – | |
| `--output dir` | `output_directory` | `./screenshots` |
| `--clear` | `clear_previous_screenshots` | |
| `--delay s`, `--settle-frames n` | – | `0`, `3` |
| `--watch-scheme`, `--watch-app`, `--watchos` | – | |
| `--content-size L` (base Dynamic Type, no suffix) | – | iOS `L`, watch per model |
| `--format png\|jpeg` | – | `png` |
| `--boot`, `--mode device`, `--device-set`, `--template-cache`, `--shutdown` | – | no boot |
| `--download-missing-runtimes` | – | |
| `--allow-unsupported-devices` | – | skip |
| `--config file.json` | `Snapfile` | `./swiftshot.json` |

`swiftshot.json` uses fastlane-style keys:

```json
{
  "scheme": "MyApp",
  "project": "MyApp.xcodeproj",
  "devices": ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"],
  "ios_versions": ["26.5"],
  "languages": ["en-US", "de-DE", "ja"],
  "appearances": ["light", "dark"],
  "text_sizes": ["default", "AX3"],
  "output_directory": "fastlane/screenshots",
  "clear_previous_screenshots": true
}
```

### Naming

`<output>/<language>/<device>-<preview name>[-light|-dark][-<text size>][-iOS<version>].png`. The
preview name is the `#Preview("Name")` title, or `<File>_<line>` for unnamed previews. The
appearance suffix appears when more than one appearance is requested, and the iOS suffix when more
than one iOS version is.

### Writing previews for screenshots

Build with the Debug configuration (the default): the compiler only emits `#Preview` code into
Debug builds, and swiftshot stops with an explanatory error if it finds no previews. Anything you
can put in a `#Preview` works: mock data, environment objects, presented sheets. You don't need
`.environment(\.locale)`, because the real locale is set per process. Use `--delay` (or a per-screen
`delay`) if a view loads images asynchronously.

## Device support per runtime

A device is rendered on a runtime only if that runtime supports the device type. Anything else is
reported as `Skipped: … does not support …` and the exit code stays 0.
`--allow-unsupported-devices` renders those combinations anyway, best effort and with a warning.

## Layout

```
Sources/swiftshot/   macOS CLI: orchestration, no-boot launcher, simctl/xcodebuild, device table, report
Agent/               injected dylibs: discovery, iOS and watchOS renderers, no-boot shim (NoBoot.c),
                     swiftshot-simhost (SimHost.m)
Shared/JobModel.swift  host ⇄ agent job/result model
Example/DemoApp/     iOS + watchOS sample app (5 languages incl. RTL) + an equivalent fastlane setup
bench/               benchmark and device-table scripts used by the workflows
```
