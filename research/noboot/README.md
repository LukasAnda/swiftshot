# Rendering without booting a simulator (prototype, 2026-10-22)

An iOS-simulator binary can run directly on the Mac, without a booted device, if it gets the
environment the simulator's launchd would give it (`env.sh`: `DYLD_ROOT_PATH`/`SIMULATOR_ROOT` =
the runtime root, `HOME` = a migrated data container, e.g. a swiftshot boot template, and the
`SIMULATOR_*` device variables). `render.swift` renders a SwiftUI screen that way.

    xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator -O render.swift -o render
    WORK=… ; source env.sh; NOBOOT_PATCH_DISPLAYS=1 NOBOOT_SAFE=1 ./render out layer

Findings (iOS 27.0 runtime, iPhone 17 Pro Max geometry):

* Starts and renders in ~0.55 s per process. Two patches are needed: `+[CADisplay displays]`
  (otherwise QuartzCore polls ~5.7 s for a render server) and `UIScreen` scale/bounds (otherwise
  scale 1 and blurry text).
* Client-side `layer.render(in:)` output is **pixel-identical (0.000 %)** to the same call in a
  booted simulator.
* But client-side rendering has no Liquid Glass / blur / backdrop effects: those are drawn by the
  render server (or `CARenderer`, which needs Metal). On the DemoApp, `layer.render` vs the
  `drawHierarchy` swiftshot uses: 15/55 screenshots differ > 1 % (glass tab bar and toolbar
  buttons missing), 37 more by 0.01–1 % (color management).
* `drawHierarchy` renders blank, `ImageRenderer` traps ("no current update"), and
  `MTLCreateSystemDefaultDevice()` returns nil: simulator Metal goes through `SimMetalHost`, an
  XPC service CoreSimulatorService wires into a *booted* device's launchd
  (`com.apple.metal.simulator`).

So no-boot rendering is exact for UIKit/SwiftUI content without materials, and wrong for glass.
Getting glass would mean providing Metal (re-creating CoreSimulator's SimMetalHost bridge) so that
`CARenderer` can draw the layer tree in-process.
