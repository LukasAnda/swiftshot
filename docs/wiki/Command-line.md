`swiftshot <command> [options]`. `run` is the default command. Run `swiftshot --help` for the same text.

## Platform

One `swiftshot` binary covers both platforms. It renders Android when:

- `--platform android` is given, or
- the project folder (the current one, or `--project-dir`) has `gradlew` and a
  `settings.gradle(.kts)`, no `.xcodeproj` or `.xcworkspace`, no `--project`, `--workspace` or
  `--app`, and no `project`, `workspace` or `scheme` in `swiftshot.json`, or
- it has a `pubspec.yaml` on the Flutter SDK: a [[Flutter]] project.

Otherwise it renders iOS. `--platform ios` forces iOS.

On Linux (and with the Android-only package) `swiftshot` is the Android renderer, with the same
`run`, `list`, `devices` and `init` commands. `--platform android` is accepted. `--platform ios`,
a folder with an Xcode project, and the Mac-only `frame`, `calibrate` and `emit-table` stop with
a message that iOS needs a Mac with Xcode. Compose Multiplatform iOS targets are skipped.

- [iOS](#ios)
- [Android](#android): `swiftshot --platform android --help`

## iOS

```
USAGE
  swiftshot [run|verify|record|accept|list|devices|calibrate|emit-table|init] [options]
  swiftshot frame [<dir>] [frame options]

COMMANDS
  run         Build, render every preview for every device × iOS × language × appearance (default)
  verify      Render as run does (PNG, no frames), then compare with the baseline: exit 0 same,
              1 differences, 2 errors, 64 usage error; the report goes to <output>-report
  record      Render as run does and write the screenshots into the baseline
  accept      Apply a verify report to the baseline without rendering: exit 0 applied (or nothing
              to do), 1 refused (report not from HEAD, push failed), 64 usage or invalid report
  list        Build and print the previews that were discovered
  devices     Show installed iOS runtimes and the geometry used for each device
  calibrate   Boot the given devices once and measure their real safe areas (cached)
  emit-table  Merge calibration.json files into the built-in device table (maintainers)
  init        Write a swiftshot.json for the project here: scheme, watch scheme, languages and
              App Store devices detected (alias auto-setup; --force overwrites an existing one)
  frame       Put existing screenshots (<dir>, default --output) into device frames, like
              `fastlane frameit`. Plain unless --frame appstore.

BUILD
  --project <path> | --workspace <path>   Xcode project or workspace
  --scheme <name>                         Scheme that builds the app
  --configuration <name>                  Default: Debug
  --app <path>                            Use an already-built simulator .app instead of building
  --derived-data <path>                   Default: .swiftshot/DerivedData
  --xcodebuild-arg <arg>                  Extra xcodebuild argument (repeatable)

MATRIX
  --devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5),Apple Watch Ultra 3 (49mm)"
  --ios "26.5,27.1"                       iOS runtime versions (default: newest installed)
  --languages "en-US,de-DE"               Default: en-US
  --appearances "light,dark"              Default: light
  --text-sizes "default,XXXL,AX5"         Dynamic Type sizes to render every preview at: XS S M L XL XXL XXXL
                                          AX1…AX5, or default (the device's own: iOS L, watch L/XL by case
                                          size). Non-default sizes get a "-<size>" file name suffix.
  --full-length                           Grow full-screen previews to their scroll view's whole content
                                          (long lists, forms); per screen: full_length=true
  --previews "Welcome,Onboarding*"        Only these previews (glob); default: all

APPLE WATCH (add watch devices to --devices)
  --watch-scheme <name>                   Scheme of the watchOS app (default: --scheme if only watches are requested)
  --watch-app <path>                      Prebuilt watchOS simulator .app instead of building
  --watchos "27.0"                        watchOS runtime versions (default: newest installed)

OUTPUT
  --output <dir>                          Default: ./screenshots (fastlane/deliver layout: <dir>/<lang>/<device>-<preview>.png)
  --format png|jpeg                       Default: png
  --clear                                 Delete previous screenshots first
  --no-html                               Do not write screenshots.html
  --no-status-bar                         Leave out the system status bar (9:41, full battery), which is
                                          drawn like on a device by default

DEVICE FRAMES (Apple's Product Bezels, downloaded on first use)
  --frame [plain|appstore|none]           plain: the device with the screenshot in it, transparent, in
                                          <output>-framed/<lang>/<name>_framed.png.
                                          appstore: App Store size with background and localized title
                                          (title.strings / Framefile.json), as <lang>/<name>_framed.png
                                          next to the original, which fastlane deliver uploads instead.
  --frame-color "Deep Blue,iPad Pro 13-inch (M5)=Silver"
                                          Bezel colour, for all devices or per device (default per model)
  --framefile <path>                      frameit Framefile.json (default: found like frameit does)
  --frame-background <#RRGGBB|image>      App Store background (default: light or dark grey by appearance)
  --frame-output <dir>                    Where plain frames go (default <output>-framed)
  --frame-cache <dir>                     Bezel cache (default ~/Library/Caches/swiftshot/frames)
  --accept-bezel-license                  Accept Apple's Design Resources License without the prompt (CI)

RENDERING
  --mode virtual|device                   virtual (default): every device rendered without booting a simulator.
                                          device: a booted simulator per device, framebuffer capture (the
                                          reference virtual is checked against).
  --content-size <size>                   Change the default text size itself (no file name suffix)
  --delay <seconds>                       Extra settle time before each capture (async images, animations)
  --settle-frames <n>                     Run-loop frames to wait before capture (default 3)
  --parallel-languages <n>                Run n language processes concurrently per iOS version (clones)
  --allow-unsupported-devices             Also render devices a runtime can't boot, on another host of the
                                          same runtime (best effort; skipped by default)
  --download-missing-runtimes             Download requested iOS runtimes that are not installed
  --shutdown                              Shut simulators down afterwards (default: keep warm)
  --timeout <seconds>                     Kill an app launch that takes longer (default 600)

PER SCREENSHOT
  --screen "<preview>: key=v1,v2 key=v"     Override settings for previews matching <preview> (glob), repeatable.
                                          keys: appearances, languages, devices, ios, text_sizes, full_length,
                                          delay, skip, frame
                                          e.g. --screen "Welcome: appearances=light,dark languages=en-US"
                                          (or a "screens" array in the JSON config; first match wins)

BASELINE (verify, record; PNG only, no frames)
  --baseline-directory <dir>              Default: screenshots-baseline
  --report-directory <dir>                Default: <output>-report
  (swiftshot.json: "tolerance": {"pixels": n, "max_channel_delta": d}, default exact, or 1 channel
   step with --mode device; per screen also "tolerance" and "ignore_regions": [[x, y, w, h]] in points)

ACCEPT
  --from <dir|zip|url>                    A verify report directory, a zip of one, or an http(s) URL of
                                          the zip (repeatable; SWIFTSHOT_ARTIFACT_TOKEN is sent as a
                                          Bearer token to that host only)
  --only "<id>,<id>"                      Only these screenshot ids (repeatable)
  --push                                  Commit the baseline ("Update screenshot baseline (…)") and git push
  --author "Name <email>"                 Commit author (default: swiftshot <swiftshot@users.noreply.github.com>)

CI
  --device-set <dir>                      Use an isolated CoreSimulator device set (simctl --set); created
                                          from scratch, never touches the machine's own simulators
  --template-cache <dir>                  Where per-runtime boot templates live (default ~/Library/Caches/
                                          swiftshot/templates.noindex). Cache it between CI jobs and even the
                                          first boot is skipped.
  --no-templates                          Boot every new simulator from scratch (~35 s each, slow in parallel)
  --boot                                  Render previews in booted simulators. The default renders iOS and
                                          watchOS previews without any simulator: the app runs directly on the
                                          Mac against the runtime (swiftshot-simhost provides Metal/IOSurface).
                                          --mode device always uses booted simulators.

  --config <file>                         JSON config (default ./swiftshot.json if present)
  --verbose
```

Exit code: 0 when every screenshot was rendered, non-zero otherwise. Errors are listed at the end of the run and in `swiftshot-report.json`.
`verify` exits 0 (same), 1 (differences), 2 (errors) or 64 (usage error); `accept` 0, 1 (refused) or 64. See [[Baseline format]].

## Android

```
USAGE
  swiftshot [run|verify|record|accept|list|devices|init] [options]

COMMANDS
  run       Build, render every preview for every device × language × appearance (default)
  verify    Render as run does, then compare with the baseline: exit 0 same, 1 differences,
            2 errors, 64 usage error; the report goes to <output>-report
  record    Render as run does and write the screenshots into the baseline
  accept    Apply a verify report to the baseline without rendering: exit 0 applied (or nothing
            to do), 1 refused (report not from HEAD, push failed), 64 usage or invalid report
  list      Build and print the previews that were found
  devices   List the devices and their screens
  init      Write a swiftshot.json for the project here: modules, languages and Play devices
            detected; with Paparazzi or Roborazzi, the devices of their tests and a
            swiftshot-migration.md report (alias auto-setup; --force overwrites an existing one)

PROJECT
  --project-dir <path>                  Gradle project (default: .)
  --platform android                    Accepted as on the Mac (iOS projects need the Mac tool)
  --modules ":app,:wear"                Modules to render (default: every Android module with previews)
  --variant <name>                      Build variant (default: debug)
  --gradle-arg <arg>                    Extra Gradle argument (repeatable)
  --java-home <path>                    JDK 21+ for the renderer (default: JAVA_HOME, then Android Studio's)
  --flutter-root <path>                 Flutter SDK for Flutter projects (default: FLUTTER_ROOT, fvm, then flutter on PATH)
  --flutter-ios exact|headless          Flutter on iPhones and iPads: Flutter's iOS engine on a Mac with Xcode
                                        (exact, the default) or the headless renderer (faster, any OS)

MATRIX
  --devices "Pixel 10 Pro,Pixel 9 Pro Fold,Pixel Tablet"   Phones, foldables, tablets (default: Pixel 10 Pro, Pixel Tablet)
  --watch-devices "Wear OS Large Round"                    For Wear OS modules (default: Wear OS Large Round)
  --desktop-devices "Desktop 1440×900 @2x"                 Window sizes for Compose Multiplatform desktop
  --ios-devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5)" Compose Multiplatform iOS devices (macOS)
  --ios "27.0"                          iOS runtimes for Compose Multiplatform (default: newest installed)
  --platforms android,desktop,ios       Compose Multiplatform targets to render (default: all the project has)
  --languages "en-US,de-DE"             Default: en-US
  --appearances "light,dark"            Default: light
  --font-scales "1,1.3,2"               Default: 1
  --previews "Welcome,Stats*"           Only previews matching these names or * globs
  --screen "<preview>: key=value …"     Per-screenshot settings (repeatable), e.g.
                                        --screen "Stats: languages=de-DE devices=Pixel*"

OUTPUT
  --output <dir>                        Default: screenshots
  --layout swiftshot|fastlane           fastlane: <output>/<locale>/images/<type>Screenshots
  --clear                               Delete existing screenshots first
  --no-html                             Do not write screenshots.html
  --full-length                         Grow scrolling screens to their whole content
  --delay <seconds>                     Advance the clock before capture (animations)
  --system-ui preview|always|never      Status and navigation bars (default: as the preview says)
  --frame plain|none                    Put each screenshot in its device (Android Studio's device art)
  --round-corners black|transparent     Outside round watch screens (default: black, as Play requires)
  --parallel <n>                        Renderer processes (default: from cores and memory)

BASELINE (verify, record; PNG only, no frames)
  --baseline-directory <dir>            Default: screenshots-baseline
  --report-directory <dir>              Default: <output>-report

ACCEPT
  --from <dir|zip|url>                  A verify report directory, a zip of one, or an http(s) URL of the zip
                                        (repeatable; SWIFTSHOT_ARTIFACT_TOKEN is sent as a Bearer token)
  --only "<id>,<id>"                    Only these screenshot ids (repeatable)
  --push                                Commit the baseline ("Update screenshot baseline (…)") and git push
  --author "Name <email>"               Commit author (default: swiftshot <swiftshot@users.noreply.github.com>)

  --config <file>                       Default: ./swiftshot.json
  -v, --verbose
```

The same exit codes as on iOS; `verify`, `record` and `accept` as above, see [[Baseline format]]. `swiftshot devices` lists every device with its size in px and dp
and density; `--devices` takes these names, ids (`pixel_9`) or `*` globs. Compose Multiplatform
flags: [[Compose Multiplatform]]. In a Flutter project `--devices` also takes iPhones and iPads,
see [[Flutter]].
