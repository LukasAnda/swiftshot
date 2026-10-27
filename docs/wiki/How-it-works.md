On iOS, Swiftshot runs your simulator app as a plain Mac process, gives it a virtual screen with
the target device's exact geometry, and lets Core Animation render each preview into it. No
simulator is created or booted. This page explains each step and how the output is kept identical
to a booted simulator. On Android, it renders Compose previews with layoutlib, the engine of
Android Studio's previews, in parallel processes: see [Android](#android).

- [Overview](#overview)
- [1. Build once](#1-build-once)
- [2. Launch without a simulator](#2-launch-without-a-simulator)
- [3. Find the previews](#3-find-the-previews)
- [4. Pretend to be the device](#4-pretend-to-be-the-device)
- [5. Render and capture](#5-render-and-capture)
- [6. Status bar](#6-status-bar)
- [7. Previews, sheets and options](#7-previews-sheets-and-options)
- [8. Apple Watch](#8-apple-watch)
- [9. Device mode, the reference](#9-device-mode-the-reference)
- [10. Proving it's pixel identical](#10-proving-its-pixel-identical)
- [11. Device table](#11-device-table)
- [Why it's faster than fastlane](#why-its-faster-than-fastlane)
- [Android](#android)

## Overview

```mermaid
flowchart LR
    CLI["swiftshot"] -->|"xcodebuild, once"| APP["MyApp.app<br/>simulator build, Debug"]
    APP --> FAN{"one job per<br/>device × language,<br/>in parallel"}
    FAN --> P1["simhost → MyApp process<br/>iPhone 17 Pro Max · en-US"]
    FAN --> P2["simhost → MyApp process<br/>iPhone 17 Pro Max · de-DE"]
    FAN --> P3["simhost → MyApp process<br/>iPad Pro 13-inch · en-US"]
    P1 -->|"every preview ×<br/>appearance × text size"| OUT[("screenshots/&lt;lang&gt;/*.png<br/>screenshots.html<br/>swiftshot-report.json")]
    P2 --> OUT
    P3 --> OUT
```

The jobs run in parallel, up to half the Mac's cores. A job starts in about a second and then
renders each screenshot in well under a second.

## 1. Build once

Swiftshot runs one `xcodebuild build` for the iOS simulator (`arm64`, no code signing) and reads
the `.app` path from the build settings. The same build serves every device, iOS version and
language. It must be a Debug build, because the compiler only includes `#Preview` code in Debug.
`--app` skips the build and uses a prebuilt `.app`.

## 2. Launch without a simulator

A simulator app is an ordinary arm64 Mac binary linked against the simulator runtime's
frameworks. It runs as a normal process once it gets what `launchd_sim` in a booted simulator
would give it, plus the services a booted device provides.

```mermaid
flowchart LR
    SH["<b>swiftshot-simhost</b><br/>Mac program"]
    RT[("Simulator<br/>runtime")]
    subgraph PROC["MyApp process: the simulator binary, run directly on the Mac"]
        direction TB
        AG["<b>swiftshot agent</b><br/>finds previews · fakes device geometry<br/>status bar · capture"]
        A["your previews"]
        UI["UIKit · SwiftUI"]
        CA["Core Animation render server<br/>(in-process)"]
        FD["<b>virtual display</b><br/>replaces SimFramebufferClient"]
        SHIM["<b>NoBoot shim</b><br/>routes system XPC to simhost"]
        AG --> A --> UI --> CA --> FD
        CA -.- SHIM
    end
    SH -->|"starts app,<br/>injects agent + shim"| AG
    SHIM <-.->|"Metal · IOSurface ·<br/>shader compiler"| SH
    RT -.->|"frameworks"| UI
    FD -->|"IOSurface"| PNG[("PNG")]
```

**Environment.** The CLI sets what a booted device's launchd would: `SIMULATOR_ROOT` and
`IPHONE_SIMULATOR_ROOT` pointing at the runtime's `RuntimeRoot`, a fresh `HOME` and `TMPDIR` per
job, and the device variables (`SIMULATOR_MODEL_IDENTIFIER`, `SIMULATOR_CAPABILITIES`,
`SIMULATOR_MAINSCREEN_WIDTH/HEIGHT/SCALE`, …). The language is passed as `-AppleLanguages` and
`-AppleLocale`, as on a device.

**swiftshot-simhost** is a small Mac program that starts the app. It sets the `DYLD_*` variables
itself, because System Integrity Protection strips them from anything started through a system
binary:

- `DYLD_ROOT_PATH` loads every framework from the simulator runtime instead of macOS.
- `DYLD_INSERT_LIBRARIES` injects the NoBoot shim and the swiftshot agent.
- `DYLD_SHARED_CACHE_DIR` points at the runtime's dyld cache. Swiftshot builds that cache once if
  the runtime has none.

It also turns off the crash reporter for the child, so a crashing preview never opens a dialog.

**Services.** In a booted simulator, Metal, IOSurface and the shader compiler are XPC services
that CoreSimulator provides from the Mac. simhost provides the same three itself, using the
Mac's own private implementations (`MTLSimImplementation.framework` and `IOSurfaceRemoteServer`).
Each shader compile request gets a new `MTLCompilerService` from the runtime. simhost hands the
services to the app as registered Mach ports.

**NoBoot shim.** The shim intercepts `xpc_connection_create_mach_service` and
`xpc_connection_create` inside the app. Connections to `com.apple.metal.simulator*`,
`com.apple.IOSurface.Remote` and `com.apple.MTLCompilerService` go to simhost's ports. Everything
else passes through unchanged.

**Agent start.** The agent's constructor runs before the app's `main`. It creates the
`UIApplication` by hand and starts rendering. The app's own `@main` and scene setup never run, so
only the previews are rendered.

## 3. Find the previews

`#Preview` expands to a type that conforms to `PreviewRegistry` (from `DeveloperToolsSupport`).
Legacy previews conform to `PreviewProvider`. The agent finds both the way the Swift runtime
finds protocol conformances:

1. Walk the `__TEXT,__swift5_proto` section of every image in the app bundle.
2. Keep the records that conform to `PreviewRegistry` or `PreviewProvider`.
3. Call each type's metadata accessor to get the type, then `makePreview()`.
4. Read the display name, traits (orientation, `.sizeThatFitsLayout`, `.fixedLayout`) and the body
   closure from the result.

Previews are ordered by file and line. Unnamed previews are called `<File>_<line>`.
`swiftshot list` prints what was found.

## 4. Pretend to be the device

UIKit asks the screen, the device and MobileGestalt what it runs on. The agent answers every
question with the target device's measured values:

| what | how |
|---|---|
| screen size, scale, corner radii | `UIScreen` getters, from the device type's `capabilities.plist` |
| idiom (phone, pad) | `UIDevice.userInterfaceIdiom` |
| safe areas, Dynamic Island area | `_UIDisplayInfoProvider` getters and `UIScreen._exclusionArea`, from the [device table](#11-device-table) |
| status bar height and axis | `UIStatusBarManager` getters |
| size classes, display scale, P3 gamut, layout direction | trait overrides on the window |
| large-phone content margins | the MobileGestalt answer for that model |

That's also why each device model gets its own process: some of these values are read once per
process.

## 5. Render and capture

**Virtual display.** UIKit draws through Core Animation, which on a simulator presents frames to
the simulator's framebuffer through `SimFramebufferClient`. The agent replaces that framework's
functions with a virtual display. It reports the device's exact display modes and shows every
swap like a booted simulator's display: a frame that redrew only part of the screen updates
only that rect. With `CA_FORCE_LOCAL_SERVER=1`, the Core Animation render
server (`CAWindowServer`) runs inside the app process, and the app's window is hosted into it
with a `CALayerHost`, the way SpringBoard hosts apps.

**Deterministic rendering.** Three render server options are pinned, because without them pixels
depend on the machine's speed:

| option | without it |
|---|---|
| `CA_DISABLE_GENERIC_SHADERS` | the first frames use a generic shader while the specialized one compiles, so glass differs with compile speed |
| `CA_DISABLE_OCCLUSION_CULLING` | antialiased edges depend on what the reused display buffers held before |
| `CA_DISABLE_SDF_CACHE` | glass edges freeze as first drawn, depending on frame timing |

**Capture.**

```mermaid
sequenceDiagram
    participant Agent as swiftshot agent
    participant UI as UIKit / SwiftUI
    participant RS as Render server (in-process)
    participant FB as Virtual display
    Agent->>UI: put the preview in a device-sized window
    Agent->>RS: purge cached resources
    Agent->>RS: commit window, status bar and root in one transaction
    Agent->>RS: waitForCommitId
    RS->>FB: render and present the frame
    loop until 3 identical frames (5 if any two differed, at most 12)
        Agent->>RS: force a redraw (no visible change)
        RS->>FB: present
        FB-->>Agent: newest IOSurface
    end
    Agent->>Agent: write the PNG
```

Each redraw damages the frame without changing what it shows, so a frame that's still settling
(an animation, glass adapting to the content behind it) shows up as a difference. iOS 26 also
waits for its glass brightness loop to go quiet. On iOS 27 iPhones with a Dynamic Island, the
server then redraws the rect SpringBoard's system aperture redraws on a device once an app is
up (from the top-left corner to just past the island), as partial frames: a blurred backdrop cut
by that rect comes out a step different inside it, as on the device. Previews that aren't full screen are rendered
over black and over white, and the alpha channel is computed from the two.

## 6. Status bar

Full-screen shots use the status bar component SpringBoard itself uses (`STUIStatusBar` from
`SystemStatusUI.framework`). It gets the same data `simctl status_bar override` sets: 9:41, full
Wi-Fi and cellular signal, and a charged battery. It's laid out around the Dynamic Island,
picks light or dark from the content under it like on a device, and follows the device language
for direction and digits. It lives in its own window above the app. `--no-status-bar` leaves it
out.

## 7. Previews, sheets and options

| feature | how |
|---|---|
| Sheets, alerts, dialogs | animations are turned off, so presentations land in their final state before capture |
| `.sizeThatFitsLayout` | measured with `sizeThatFits`; no safe area |
| `.fixedLayout(width:height:)` | rendered at that size |
| landscape traits | landscape window, safe areas and size classes |
| `--full-length` | the window grows to the largest scroll view's content, up to 16384 px |
| text sizes | a `preferredContentSizeCategory` override per screenshot |
| dark mode | `overrideUserInterfaceStyle` per screenshot |
| languages | one process per language, started with `-AppleLanguages` and `-AppleLocale`; right-to-left layout for RTL languages |
| UIKit previews | `UIViewController` and `UIView` bodies are hosted directly |

## 8. Apple Watch

watchOS previews use the same approach. The app runs without a simulator, the agent answers
`UIScreen` and `WKInterfaceDevice` with the watch's geometry, and each preview is hosted in a
window on the in-process render server. One process runs per model, text size and language.

## 9. Device mode, the reference

`--mode device` renders the same previews in real booted simulators, and is what no-boot output
is checked against.

```mermaid
sequenceDiagram
    participant CLI as swiftshot CLI
    participant Sim as Booted simulator
    participant Agent as agent in the app
    CLI->>Sim: create, boot, install, status_bar override
    CLI->>Sim: simctl launch (agent injected)
    Agent->>Sim: pin the same three render options
    Agent->>CLI: launch.ready
    CLI->>CLI: wait until SpringBoard hides the home indicator
    CLI->>Agent: launch.done
    loop every screenshot
        Agent->>Agent: show the preview
        Agent->>CLI: N.ready
        CLI->>Sim: simctl io screenshot, until two grabs match
        CLI->>Agent: N.done
    end
```

The agent and the CLI talk through files in a shared folder. If the home indicator never hides or
a screenshot command hangs, the simulator is rebooted and the run is repeated, up to 3 times. On
machines with little memory, simulators take turns.

## 10. Proving it's pixel identical

```mermaid
flowchart LR
    DEMO["Example/DemoApp"] --> NB["no-boot render"]
    DEMO --> D1["--mode device, run 1"]
    DEMO --> D2["--mode device, run 2"]
    NB --> CMP{"every pixel equal<br/>to run 1 or run 2?"}
    D1 --> CMP
    D2 --> CMP
    CMP -->|"yes"| PASS["pass"]
    CMP -->|"any pixel off"| FAIL["fail"]
```

The integration tests render the demo app both ways and require a difference of 0 on every pixel
of every channel. The booted simulator itself flips a few glass pixels by 1/255 between runs, so
each pixel may match either of two device runs. The tests cover iPhone 18 Pro, iPhone 17,
iPad Pro 13-inch, iPhone Duo and Apple Watch, with sheets, alerts, glass and the status bar.
Other tests check that two no-boot runs are byte-identical, that no simulator gets booted, and
a time budget per screenshot.

## 11. Device table

Screen size, scale and corner radii come from each device type's `capabilities.plist` in Xcode.
Safe areas, the Dynamic Island area and status bar metrics can only be measured on a booted
device. `swiftshot calibrate` boots each device once and records them, and the results ship
inside swiftshot. A weekly workflow measures any device type the table doesn't have yet on the
GitHub runners and opens a pull request, so new devices work without booting anything on your
machine.

## Why it's faster than fastlane

```mermaid
flowchart TB
    subgraph SS["swiftshot"]
        direction TB
        S1["build app"] --> S2["for each device × language, in parallel:<br/>start one process (~1 s)"]
        S2 --> S3["for each preview: render one frame"]
    end
    subgraph FL["fastlane snapshot"]
        direction TB
        F1["build app + UI tests"] --> F2["for each device: boot simulator"]
        F2 --> F3["for each language: install test runner,<br/>launch the app"]
        F3 --> F4["for each screen: relaunch,<br/>tap to the screen, wait, capture"]
    end
```

| | fastlane snapshot | swiftshot |
|---|---|---|
| builds | app and UI tests | app |
| simulators booted | one per device | none |
| app launches | one per screen, device and language | one per device and language |
| getting to a screen | XCUITest taps | the preview is the screen |
| per screenshot, free GitHub runner | 103 s | 1.2–1.9 s, build included |

## Android

```mermaid
flowchart LR
    CLI["swiftshot"] -->|"init script"| G["Gradle<br/>swiftshotPrepare"]
    G -->|"module.json:<br/>classes, classpath,<br/>resources, assets"| SCAN["@Preview scan<br/>(bytecode)"]
    SCAN --> PLAN["groups:<br/>device × language ×<br/>appearance × font scale"]
    PLAN --> R1["renderer 1<br/>layoutlib"]
    PLAN --> R2["renderer 2<br/>layoutlib"]
    PLAN --> RN["renderer n<br/>layoutlib"]
    R1 --> OUT[("PNGs, gallery,<br/>report, frames")]
    R2 --> OUT
    RN --> OUT
```

**Build.** Swiftshot runs `./gradlew -I <init script> swiftshotPrepare -Pswiftshot.variant=debug`.
The init script adds the task to every Android application and library module for this one
invocation; nothing in the project changes. The task compiles the variant as usual, resolves its
runtime classpath together with Paparazzi's layoutlib SDK, and writes the module's classes,
classpath, resources and assets to `build/intermediates/swiftshot/<variant>/module.json`. The
task holds no reference to the project and the script sits at a fixed path in the cache, so the
project's configuration cache stays valid: a warm Gradle step takes about a second.

**Find previews.** `@Preview` has binary retention, so reflection can't see it. Swiftshot reads
the compiled class files with ASM and resolves multipreview annotations (`@PreviewLightDark`,
`@WearPreviewDevices`, your own) through the project's classes and its libraries.

**Render.** Each renderer is a JVM with the app's classpath and layoutlib, loaded through
Paparazzi's SDK. It inflates Compose's own `ComposeViewAdapter`, as Android Studio does, so
`@PreviewParameter`, inspection mode and the preview wrappers behave as in the IDE. A process
starts once and then renders whole groups of screenshots that share a device, language,
appearance and font scale, swapping only the composable. Groups go to whichever process is free.

```mermaid
sequenceDiagram
    participant CLI as swiftshot
    participant G as Gradle
    participant R as renderer processes
    CLI->>R: start, with the previous run's classpath
    CLI->>G: swiftshotPrepare
    R->>R: load layoutlib, apply its patches
    G-->>CLI: module.json
    CLI->>CLI: scan previews, plan groups
    alt classpath unchanged
        CLI->>R: send groups
    else classpath changed
        CLI->>R: start new processes, send groups
    end
    R-->>CLI: one line per screenshot
    CLI->>R: stop
```

Renderer processes start while Gradle builds, and are used when the classpath comes out the
same. The first process writes a class-data-sharing archive of the classpath, which makes every
later start faster. Several processes run in parallel: one per core and 1.5 GB of memory, at most
8, or `--parallel`.

**System bars.** On a device the status bar and gesture handle are system windows above the app
(and above a dialog's scrim). Apps that target API 35 or later are edge-to-edge, so the content
gets the device's real insets (a status bar sized to the camera cutout, the gesture area at the
bottom) and draws behind them. Swiftshot then draws the bars over the finished frame: 9:30, full
Wi-Fi, signal and battery, and the gesture handle. Older apps keep layoutlib's own bars.

**Wear OS.** Watch devices render with the watch UI mode and, for round screens, a round screen
configuration. Wear OS has no light mode, so they render once, dark. Outside the circle the image
is black (Play rejects transparency), or transparent with `round_corners`.

**Full length.** With `full_length`, Swiftshot reads how far the preview's vertical scroll
containers can still scroll from Compose's semantics (the vertical scroll range that
`verticalScroll` and `LazyColumn` report), grows the screen by that much and renders again, until
nothing scrolls.

**Encoding.** PNG encoding, and framing, run on separate threads beside the next render, at a
fast deflate level instead of ImageIO's slowest one.

### Why it's faster than Paparazzi and Roborazzi

They run screenshots as unit tests: Gradle compiles a test source set, and a test task renders
one screenshot per test, one at a time per JVM. Swiftshot has no test sources to compile and no
test task, and keeps parallel renderers up for the whole run.

The same 470 screenshots on a free 4-core `ubuntu-latest` runner
([`bench/android`](https://github.com/LukasAnda/swiftshot/tree/main/bench/android)):

| | swiftshot | Paparazzi 2.0.0-alpha05.1 | Roborazzi 1.77.0 |
|---|---:|---:|---:|
| first run | **57.7 s** | 87.4 s | 93.0 s |
| warm run | **38.0 s** | 66.1 s | 70.8 s |
