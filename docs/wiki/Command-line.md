`swiftshot <command> [options]`. `run` is the default command. Run `swiftshot --help` for the same text.

```
USAGE
  swiftshot [run|list|devices|calibrate|emit-table|init] [options]
  swiftshot frame [<dir>] [frame options]

COMMANDS
  run         Build, render every preview for every device × iOS × language × appearance (default)
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
