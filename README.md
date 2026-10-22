# Swiftshot

App Store screenshots **straight from your SwiftUI `#Preview`s** — every iPhone, iPad and Apple
Watch, iOS/watchOS version, language and appearance — without UI tests, without
`SnapshotHelper.swift`, and without booting one simulator per device. A replacement for
`fastlane snapshot` / `capture_ios_screenshots`. Settings can be overridden **per screenshot**.

```
swiftshot --project MyApp.xcodeproj --scheme MyApp \
  --devices "iPhone 17 Pro Max,iPhone SE (3rd generation),iPad Pro 13-inch (M5)" \
  --ios "26.5,27.0" --languages "en-US,de-DE,ar,ja" --appearances light,dark

# Apple Watch: add watch models and the watch app's scheme
swiftshot --project MyApp.xcodeproj --scheme MyApp --watch-scheme MyWatchApp \
  --devices "iPhone 17 Pro Max,Apple Watch Series 11 (46mm),Apple Watch Ultra 3 (49mm)"
```

Output uses the fastlane/deliver layout (`screenshots/<language>/<device>-<preview>.png`), so
`fastlane deliver` uploads it unchanged. A `screenshots.html` gallery and a machine-readable
`swiftshot-report.json` are written next to it.

## Benchmark (measured on this repo's `Example/DemoApp`, Apple Silicon, Xcode 27.1)

### Cold CI run (nothing booted, brand-new simulators)

iPhone 17 Pro Max + iPhone SE + iPad Pro 13-inch (M5) on iOS 26.5, Apple Watch Series 11 on
watchOS 27.0, en-US/de-DE/ar, per-screen rules. Non-GUI launchd session, empty device set,
wall clock including both builds (warm DerivedData) and all boots.

| tool | what | time |
|---|---|---:|
| `fastlane snapshot` 2.240 | 45 iOS screenshots (can't do watch or per-screen rules) | **455 s** |
| swiftshot | 64 screenshots (55 iOS + 9 watch), no caches at all | **137 s** |
| swiftshot | same, boot templates restored from a CI cache (`--template-cache`) | **89 s** |
| swiftshot (before boot templates / scale-shared hosts) | same 64 | 182 s |

Where the cold time goes: a never-booted simulator spends ~25 s of its ~31 s first boot in
CoreSimulator's data migration, and concurrent first boots slow each other down a lot (on the
measurement machine also because endpoint-security software inspects every one of the ~400
processes a simulator boot spawns — load averages of 150–350 during boots; a clean CI runner is
quieter). swiftshot therefore (1) needs only one simulator per runtime *per scale*, (2) pays the
first boot once per runtime and clones the migrated state into every other new simulator
(*Boot templates* below; a cloned simulator boots in ~8 s), (3) runs first boots one at a time,
and (4) boots while `xcodebuild` is still building.

**On GitHub-hosted runners:** `.github/workflows/benchmark.yml` runs the same matrix on fresh
runners (`bench/run.sh`): swiftshot cold (empty DerivedData and simulators), with cached
templates, and warm, plus fastlane cold on a separate runner. Results land in the job summary.
Run it from the Actions tab (*benchmark → Run workflow*) or locally with `bench/run.sh swiftshot`.

### Warm runs

Same app, same 5 screens, iPhone 17 Pro Max + iPad Pro 13-inch (M5), iOS 26.5,
5 languages (en-US, de-DE, sk, ar, ja) → 50 screenshots. Wall clock includes the build.

| tool | run | time | speed-up |
|---|---|---:|---:|
| `fastlane snapshot` 2.238 | first run | 626 s | |
| `fastlane snapshot` 2.238 | warm re-run | **557 s** | 1× |
| swiftshot (virtual) | simulators shut down | 38.9 s | 14× |
| swiftshot (virtual) | warm | **17.2 s** | 32× |
| swiftshot (virtual) | warm, `--parallel-languages 3` | 13.7 s | 41× |
| swiftshot (device mode, real framebuffer + status bar) | warm | 48.0 s | 12× |

* Light **and** dark in one run (100 screenshots): **18.0 s** — fastlane needs a second full run
  with `dark_mode`.
* Full matrix, headless, from shut-down simulators: 5 devices × 3 iOS versions (26.5, 27.0,
  27.1) × 5 languages × light/dark = 910 screenshots in 150 s, Simulator.app never launched
  (sampled every 0.5 s), all simulators shut down afterwards (`--shutdown`). *Correction:* that
  run rendered iPhone 17 Pro/Pro Max/SE on iOS 27.1, whose runtime here only supports iPhone Duo;
  those images inherited the Duo's side-rail layout and were wrong. Such combinations are now
  skipped by default (see *Device support per runtime*).
* Apple Watch: 3 watch previews × 3 models (42 mm, 46 mm, Ultra 49 mm) × 5 languages =
  45 screenshots in 83 s including two first boots.
* fastlane additionally needed a UI-test target, `SnapshotHelper.swift`, a `Snapfile` and app
  code to route a launch argument to each screen (see `Example/DemoApp/UITests`). swiftshot
  needs nothing but the `#Preview`s that already exist.

Why fastlane is slow: per device × language it runs a separate `xcodebuild test` session
(≈50 s each here: test-runner install, XCUITest bootstrap, app relaunch per screenshot,
`XCUIScreen` capture, image copy-out) and drives Simulator.app.

## Verification

* **CI simulation** — a launchd job in a non-GUI `Background` session, a brand-new empty
  CoreSimulator device set (`--device-set`), nothing pre-booted: built the iOS and watchOS apps,
  created and booted its simulators itself, rendered iPhone 17 Pro Max, iPhone SE, iPad Pro
  13″ and Apple Watch Series 11 × en-US/de-DE/ar with per-screen rules → **64 screenshots in
  137 s (89 s with cached boot templates), exit 0**, Simulator.app never seen (sampled every
  0.5 s), 0 simulators left booted.
* **Shared hosts are pixel-identical**: iPhone SE rendered on the iPad Pro 13″ host (both @2x)
  vs. on its own iPhone SE host: 0.000 % pixels differ in all 55 screenshots of the CI matrix.
  `UIDevice.current.userInterfaceIdiom` reports the rendered device's idiom while it renders.
* **Seeded simulators are equivalent**: the 55 iOS screenshots of the CI run from template-seeded
  simulators vs. the run from normally first-booted ones: 55/55 identical (cached templates) and
  53/55 (templates made in the same run; 2 images with 0.003–0.013 % of pixels — 30–90 px in a
  glass tab bar / progress ring — differ, settle timing under a load average of ~180). Watch
  screenshots differ only in the clock (real time).
* **iPhone 18 Pro / 18 Pro Max** (iOS 27.0, the runtime that supports them): virtual vs. the real
  device framebuffer, en-US + ar, light + dark, all screens: 0.000 % pixels differ below the
  status bar (40 of 40).
* **Every device's geometry is measured, not guessed**: `swiftshot calibrate` booted 26 device
  models on iOS 26.5 / 27.0 / 27.1 (at most 3 at a time) and recorded their real safe areas; they
  ship in `BuiltInDevices.swift` (values were identical on 26.5 and 27.0). Virtual renders of
  devices that are *not* the host vs. each device's real screen: iPhone SE 0.000 %, iPhone 16 Plus
  0.000 %, iPad (A16) / iPad mini 0.01 % (system corner + home indicator only), iPhone 13 mini
  0.4–0.9 % (the system's panel downsampling filter vs. ours; mean difference < 0.5/255). Hosts
  are shared by devices of the same **native scale** only: a 3× device on a 2× host rasterizes
  text, SF Symbols and glass at 2× (measured 1–3 % of pixels; re-rasterizing text layers at 3×
  got it to 0.1–4.7 % but glass and image layers stay at host scale), so that is never done.
* **Virtual vs. real device framebuffer** (`--mode device`, iPhone 17 Pro Max, light+dark, all
  screens): 0.000 % pixels differ (threshold 8/255) for every screen outside the status bar;
  the only difference anywhere is the system home indicator, which exists only on a real screen.
* **Virtual vs. fastlane's own screenshots** (en-US, de-DE, ar; iPhone + iPad; below the status
  bar): 0.000 % (iPhone) / 0.009 % (iPad) pixels differ.
* Output sizes are the App Store Connect sizes: 1320×2868 (6.9″), 2064×2752 (13″ iPad),
  1206×2622 (17 Pro), 750×1334 (SE), landscape 2868×1320. PNGs carry the Display P3 profile like
  real device screenshots.
* Localization is genuine per process: String Catalog lookups, `NSLocalizedString`, number and
  date formatting (`1.234,5` / `87,3 %` in German), RTL mirroring in Arabic.
* **Apple Watch vs. the app's own screen** (the watch app launched normally on the same screen,
  captured with `simctl io screenshot`): 0.000 % pixels differ below the clock for all three
  screens. Sizes: 374×446 (42 mm), 416×496 (46 mm), 422×514 (Ultra 49 mm).
* **Per-screenshot rules**: `Welcome: appearances=light,dark`, `Stats: languages=de-DE devices=iPad*`,
  `Habit row: skip=true` produced exactly Welcome light+dark everywhere, Stats only for de-DE on
  iPad, no Habit row, everything else light only.

## How it works

```
 host (macOS)                                     simulator (one per iOS version × idiom)
 ─────────────                                    ───────────────────────────────────────
 swiftshot ── xcodebuild (once, generic sim) ─▶ YourApp.app
             ── simctl boot (headless) ─────────▶ SimDevice
             ── simctl launch  ─────────────────▶ YourApp  +  DYLD_INSERT_LIBRARIES=SwiftshotAgent.dylib
                -AppleLanguages (de-DE)                │
                -AppleLocale de_DE                     ├─ scan __swift5_proto → every #Preview / PreviewProvider
                SWIFTSHOT_JOB=job.json               ├─ for preview × device × appearance:
                                                       │     window with device size, scale, size classes,
                                                       │     safe area, light/dark → drawHierarchy → PNG
 screenshots/de-DE/*.png  ◀──── written directly ──────┘  (simulator processes share the Mac file system)
```

1. **One build.** The app is built once for `generic/platform=iOS Simulator`. No
   `build-for-testing`, no UI test runner, no test bundle.
2. **No project changes.** A tiny agent dylib is injected with `DYLD_INSERT_LIBRARIES` when the
   app is launched. Once the app's scene is active, the agent walks the Swift runtime's protocol
   conformance records (`__TEXT,__swift5_proto`) of every image inside the app bundle and finds
   all types conforming to `DeveloperToolsSupport.PreviewRegistry` (that's what `#Preview`
   expands to) and `SwiftUI.PreviewProvider`. It calls `makePreview()`, reflects out the
   preview's name, traits (`.sizeThatFitsLayout`, `.fixedLayout`, `.landscapeLeft`, …) and body
   closure, and renders the body — SwiftUI views, `UIViewController`s and `UIView`s.
3. **Virtual devices (default `--mode virtual`).** Instead of booting a simulator per device,
   each preview is rendered in an off-screen window that *is* the target device: exact point size
   and scale (read from Xcode's device-type bundles), size classes, and the device's measured safe
   area (a `UIWindow` subclass reports the target insets, then `additionalSafeAreaInsets` fixes up
   whatever the host adds). Devices of the same native scale share one simulator: every 3× iPhone
   (17, 17 Pro, 17 Pro Max, Air, 18 Pro, …) renders inside one iPhone simulator, every iPad *and*
   the 2× iPhone SE inside one iPad simulator (idiom, size classes and `UIDevice`'s idiom are
   overridden per render).
4. **One launch per language.** Languages need a fresh process (`-AppleLanguages`/`-AppleLocale`
   so `NSLocalizedString`, String Catalogs, number/date formatting and RTL are all genuine).
   Everything else — previews × devices × appearances — happens inside that one process. PNG
   encoding runs on background queues while the main thread renders the next frame.
5. **All iOS versions in parallel.** Each runtime/idiom host runs concurrently; simulators are
   created on demand (`swiftshot <device> (<version>)`) and kept warm between runs.

Total app launches = `iOS versions × scales × languages` (usually × 2), independent of the number of devices,
previews or appearances. fastlane needs `devices × languages` UI-test launches, each relaunching
the app per screenshot, plus one booted simulator per device.

### Apple Watch

watchOS has no public window API, and SwiftUI's `ImageRenderer` draws watchOS platform views
(`List`, `NavigationStack`, …) as a placeholder, so watch previews are captured from the **real
watch screen**: the same injected agent (watchOS build) creates a `UIHostingController<AnyView>`
for each preview — through SwiftUI's exported metadata accessor and initializer, with a 10-line
arm64 trampoline that passes the metatype in the Swift `self` register — makes it the root of the
app's window (watchOS runs on a private UIKit) and the host grabs the screen with
`simctl io screenshot`. One simulator per watch model; one app launch per language.

* Watch apps are separate schemes: pass `--watch-scheme` (or `--watch-app <path>`), and
  `--watchos` for runtime versions. Watch devices go in the same `--devices` list.
* watchOS is always dark; `--appearances` doesn't apply. The clock shows the actual time
  (watchOS simulators don't support `simctl status_bar`).

### Boot templates (cold CI)

A simulator's first boot populates its empty data container ("data migration": LaunchServices,
keyboards, Safari… migrators); that result depends on the runtime, not on the device model. So
the first new simulator of a runtime is booted once, shut down, and its migrated `data` container
becomes the runtime's template; every other new simulator of that runtime gets an APFS clone of it
(`clonefile`: copy-on-write, ~0.1 s, no extra disk) before its first boot and boots like a warm
device (~8 s alone instead of ~31 s, and without the slow-down of parallel first boots).

* Templates live in `~/Library/Caches/swiftshot/templates.noindex/<runtime>-<build>/` (keyed by
  runtime build; `.noindex` keeps Spotlight from crawling ~15k files). `--template-cache <dir>`
  moves them, e.g. into a CI cache — then even the first simulator skips the migration (89 s vs
  137 s above). `--no-templates` turns the mechanism off.
* A runtime that needs only one new simulator (e.g. a single watch) just boots it; a template only
  pays off for ≥ 2 (or when it's persisted with `--template-cache`).
* First boots run one at a time; cheap boots run in parallel.

### `--no-boot` (experimental): iOS without any simulator

The app is a simulator binary, but nothing forces it to run *inside* a booted simulator: started
directly on the Mac with the environment a booted device's launchd would give it
(`DYLD_ROOT_PATH` = the runtime, an empty home directory, `SIMULATOR_*` device variables) UIKit and
SwiftUI work. What a booted device adds for rendering is provided by `swiftshot-simhost`:

* **Metal** — macOS' `MTLSimImplementation` (what CoreSimulator's `SimMetalHost` loads) on an XPC
  listener in the simulator wire format;
* **IOSurface** — macOS' `IOSurfaceRemoteServer` on a second listener;
* **shader compiler** — the runtime's `MTLCompilerService`, started by simhost instead of launchd.

Their Mach ports reach the app as registered task ports, and `SwiftshotNoBoot.dylib` routes the
app's `com.apple.metal.simulator` / `com.apple.IOSurface.Remote` / `com.apple.MTLCompilerService`
connections to them. The agent then captures with Core Animation's own renderer (`CARenderer` into
a Metal texture — the render server's engine, Liquid Glass included) and, without a display,
reports each rendered device's screen (scale, bounds, corner radius, embedded panel, P3) itself.
Because every device gets its own scale, one process renders all devices of a runtime: one app
launch (~1 s) per language, no device set, no boot, no template.

Measured on `Example/DemoApp` (iOS 27.0, 3 devices × 3 languages + per-screen rules = 55 shots,
warm DerivedData): **8–9 s** vs 46–52 s warm / 136 s cold booted. Against the booted
`drawHierarchy` output: **52/55 identical** (0 pixels off by > 8/255); `CARenderer` itself matches
`drawHierarchy` 55/55 in a booted simulator. Known difference: the floating tab bar on Face ID
iPhones sits 13 pt higher (UIKit takes its bottom padding from display/scene data that only a
booted device provides). Not supported yet: Apple Watch (still booted), `--mode device`.

### `--mode device` (pixel-exact, with status bar)

Boots a real simulator per device, overrides the status bar (9:41, full battery, Wi-Fi), shows
each preview full-screen and grabs the framebuffer with `simctl io screenshot` — the same image
fastlane produces. The preview becomes the root of the app's own window, so none of the app's UI
shows around it. Slower, but useful when you want the system status bar / home indicator in the
picture. The screen stays portrait; landscape previews are rendered through the virtual renderer
in that mode. Virtual mode is verified to be **pixel-identical** to device mode everywhere except the
status bar and home indicator (see *Verification*).

### Device support per runtime

A device is rendered on a runtime only if that runtime supports the device type; anything else is
reported as `Skipped: … does not support …` (exit code stays 0). A host of another model can carry
model-specific chrome: on the device-specific iOS 27.1 runtime (iPhone Duo only), the Duo's side
rail leaked into every other model rendered on it. `--allow-unsupported-devices` renders those
combinations anyway on another host of the same runtime (iPads on an iPhone host get a
`userInterfaceIdiom` override; on iOS 26.5 that is layout-identical to a real iPad host, with
0.2–0.7 % of pixels differing in glyph anti-aliasing) — best effort, with a warning.

## Per-screenshot settings

Every global setting can be narrowed per preview (name or `*` glob, first match wins):

```
swiftshot … --appearances light \
  --screen "Welcome: appearances=light,dark" \
  --screen "Stats: languages=de-DE,ja devices=iPad*" \
  --screen "Paywall: ios=27 delay=1.5" \
  --screen "Debug*: skip=true"
```

or in `swiftshot.json`:

```json
"screens": [
  { "preview": "Welcome", "appearances": ["light", "dark"] },
  { "preview": "Stats", "languages": ["de-DE", "ja"], "devices": ["iPad*"] },
  { "preview": "Paywall", "ios_versions": ["27"], "delay": 1.5 },
  { "preview": "Debug*", "skip": true }
]
```

Keys: `appearances`, `languages`, `devices` (globs), `ios_versions` (prefix: `27` = 27.x),
`delay`, `skip`. A rule may also *add* an appearance that isn't in the global list.

## CI / headless

* Never opens Simulator.app — booting, installing, launching and capturing all go through
  CoreSimulator (`simctl`).
* Verified in a **non-GUI launchd session** (`launchctl bootstrap user/<uid>` with
  `LimitLoadToSessionType=Background`; `launchctl managername` reports `Background`, not `Aqua`)
  against an **empty, isolated device set** (`--device-set`) — i.e. a machine with no simulators
  at all — see *Verification*.
* Simulators are created on demand; nothing has to be pre-provisioned. `--device-set <dir>` keeps
  everything in a private CoreSimulator set (per CI job), never touching the machine's own
  simulators.
* At most `max(2, cores/4)` simulators boot at the same time; unbounded parallel first boots
  saturate a machine (and make system apps such as Calendar crash inside the simulators).
* Missing runtimes can be fetched with `--download-missing-runtimes`
  (`xcodebuild -downloadPlatform iOS -buildVersion …`).
* Device safe areas ship built-in (measured with `swiftshot calibrate`), so CI never boots a
  device just to learn its geometry. Virtual mode boots at most one simulator per iOS version per
  native scale (typically two: a 3× iPhone and a 2× iPad).
* The first boot of a never-booted simulator costs ~30 s alone (much more when several run at
  once); swiftshot pays it once per runtime and seeds every other simulator from it (*Boot
  templates*). Cache `--template-cache` between jobs (see `ci/github-actions.yml`) to skip it
  entirely. On ephemeral runners keep `--parallel-languages 1` (each extra lane is another
  simulator to boot).
* Simulators start booting while `xcodebuild` builds; each platform starts rendering as soon as
  its own app is built.
* `--shutdown` shuts the simulators down at the end; `--timeout` kills a hung launch.
* Exit code is non-zero if any screenshot failed.

> An iOS/watchOS **simulator runtime** must be installed (or downloadable with
> `--download-missing-runtimes`): it *is* the UIKit/SwiftUI that renders your views. Running
> without a CoreSimulator device isn't possible either: an iOS-simulator binary started directly
> on macOS against the runtime root (`DYLD_ROOT_PATH`) is killed by the kernel before `main`
> (exit 137) — tested. So the requirement is "runtime present"; no GUI, no Simulator.app and no
> prepared devices are needed.

See `ci/github-actions.yml`.

## Install

```
make            # bin/swiftshot (macOS), bin/SwiftshotAgent.dylib (iOS sim, arm64+x86_64),
                # bin/SwiftshotAgent-watchOS.dylib (watchOS sim)
make install    # PREFIX=/usr/local
```

Requires Xcode 16+ (tested with Xcode 27.1, iOS 26.5 / 27.0 / 27.1 runtimes). The app's
deployment target must be ≤ the oldest runtime you render on; previews need iOS 17+ (`#Preview`).

## Usage

```
swiftshot [run|list|devices|calibrate] [options]

  run         Build, render every preview for every device × iOS × language × appearance (default)
  list        Build and print the previews that were discovered
  devices     Show installed iOS runtimes and the geometry used for each device
  calibrate   Boot the given devices once and measure their real safe areas (cached)
```

| option | fastlane `Snapfile` equivalent | default |
|---|---|---|
| `--project` / `--workspace`, `--scheme`, `--configuration` | `project`, `workspace`, `scheme`, `configuration` | `Debug` |
| `--app <path>` | – (use a prebuilt simulator `.app`) | |
| `--devices "A,B"` | `devices` | `iPhone 17 Pro Max,iPad Pro 13-inch (M5)` |
| `--ios "26.5,27.0"` | `ios_version` (single) | newest installed |
| `--languages "en-US,de-DE"` | `languages` | `en-US` |
| `--appearances light,dark` | `dark_mode` (one or the other) | `light` |
| `--previews "Welcome,Onboarding*"` | `only_testing` | all |
| `--output dir` | `output_directory` | `./screenshots` |
| `--clear` | `clear_previous_screenshots` | |
| `--mode virtual\|device` | – | `virtual` |
| `--delay s`, `--settle-frames n` | – | `0`, `3` |
| `--parallel-languages n` | `concurrent_simulators` | `1` |
| `--download-missing-runtimes` | – | |
| `--shutdown` | – | keep warm |
| `--format png\|jpeg` | – | `png` |
| `--screen "<preview>: key=v …"` | – | |
| `--watch-scheme`, `--watch-app`, `--watchos` | – | |
| `--content-size L` (Dynamic Type) | – | iOS `L`, watch default |
| `--device-set <dir>` | – | system set |
| `--no-boot` | Experimental: render iOS previews without any simulator (see *--no-boot*) |
| `--template-cache <dir>` / `--no-templates` | – | `~/Library/Caches/swiftshot/templates.noindex` |
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
  "output_directory": "fastlane/screenshots",
  "clear_previous_screenshots": true
}
```

### Naming

`<output>/<language>/<device>-<preview name>[-light|-dark][-iOS<version>].png`. The preview
name is the `#Preview("Name")` title, or `<File>_<line>` for unnamed previews; the appearance
suffix appears when more than one appearance is requested, the iOS suffix when more than one iOS
version is requested.

### Writing previews for screenshots

Build with the Debug configuration (the default): the compiler only emits `#Preview` code into
Debug builds, and swiftshot stops with an explanatory error if it finds no previews.

Anything you can put in `#Preview` works — mock data, environment objects, `.environment(\.locale)`
is not needed (the real locale is set per launch). Use `--delay` if a view loads images
asynchronously. Component previews (`.sizeThatFitsLayout`, `.fixedLayout`) are rendered at their
own size with no safe area, like Xcode does.

## Layout

```
Sources/swiftshot/   macOS CLI (orchestration, simctl, xcodebuild, device catalog, report)
Agent/                 injected dylib: discovery (shared), iOS renderer, watchOS renderer, trampoline
Shared/JobModel.swift  host ⇄ agent job/result model
Example/DemoApp/       iOS + watchOS sample app (5 languages incl. RTL) + an equivalent fastlane setup
```
