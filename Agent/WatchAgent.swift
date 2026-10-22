// watchOS flavour of the agent. watchOS has no public window API and ImageRenderer can't draw
// watchOS platform views (List, NavigationStack…), so each preview is made the root of the app's
// real window (watchOS' private UIKit) and the host captures the watch screen. Discovery, the
// job/result protocol and file naming are shared with iOS.

#if os(watchOS)
import Foundation
import SwiftUI
import WatchKit
import Darwin
import ImageIO
import ObjectiveC

@_cdecl("SwiftshotAgentStart")
public func SwiftshotAgentStart() {
    guard let jobPath = ProcessInfo.processInfo.environment["SWIFTSHOT_JOB"] else { return }
    // No-boot (see the iOS agent): no booted watch, no app lifecycle; render right away.
    if ProcessInfo.processInfo.environment["SWIFTSHOT_NOBOOT"] == "1" {
        WatchNoBoot.install()
        MainActor.assumeIsolated { WatchAgent.startOnce(jobPath: jobPath) }
        return
    }
    _ = NotificationCenter.default.addObserver(forName: WKApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
        // Start outside SwiftUI's launch transaction: swapping the root view mid-update asserts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated { WatchAgent.startOnce(jobPath: jobPath) }
        }
    }
}

@MainActor
final class WatchAgent {
    private static var started = false
    static func startOnce(jobPath: String) {
        guard !started else { return }
        started = true
        WatchAgent().run(jobPath: jobPath)
    }

    let started = now()
    /// Replaced root controllers stay alive until exit: tearing down a SwiftUI graph that holds
    /// watchOS platform views outside an update asserts ("no current update to enqueue action to").
    var hostingControllers: [NSObject] = []

    func run(jobPath: String) {
        guard let job = try? JSONDecoder().decode(Job.self, from: Data(contentsOf: URL(fileURLWithPath: jobPath))) else {
            log("cannot read job"); exit(2)
        }
        let previews = discoverPreviews().filter { preview in job.previewFilter.isEmpty || job.previewFilter.contains { globMatch($0, preview.name) } }
        var result = JobResult(previews: previews.map(\.name), shots: [], errors: [], calibration: nil, totalMs: 0)
        log("discovered \(previews.count) previews")

        switch job.mode {
        case .calibrate:
            let device = WKInterfaceDevice.current()
            let b = device.screenBounds
            // The status bar (clock) is part of the window's safe area on watchOS.
            let insets = (keyWindow?.value(forKey: "safeAreaInsets") as? NSValue).map { v -> Insets in
                var e = (top: CGFloat(0), left: CGFloat(0), bottom: CGFloat(0), right: CGFloat(0))
                withUnsafeMutableBytes(of: &e) { v.getValue($0.baseAddress!, size: $0.count) }
                return Insets(top: e.top, left: e.left, bottom: e.bottom, right: e.right)
            } ?? .zero
            result.calibration = DeviceProfile(name: job.devices.first?.name ?? device.name, idiom: "watch",
                                               width: b.width, height: b.height, scale: device.screenScale,
                                               safeArea: insets, landscapeSafeArea: .zero, cornerRadius: 0)
            let app = (NSClassFromString("UIApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject
            result.calibration?.contentSizeCategory = app?.value(forKey: "preferredContentSizeCategory") as? String
        case .virtual, .device:
            // ImageRenderer can't draw watchOS platform views (List, NavigationStack…), so watch
            // previews are shown in a real window: on the booted watch's screen (captured by the
            // host), or without a simulator rendered by the agent itself.
            if WatchNoBoot.enabled { renderNoBoot(previews, job: job, result: &result) } else { showOnScreen(previews, job: job, result: &result) }
        case .list:
            break
        }

        result.totalMs = (now() - started) * 1000
        job.writeResult(result)
        exit(0)
    }
}

// MARK: - On-screen rendering through watchOS' private UIKit

extension WatchAgent {
    /// `UIHostingController<AnyView>(rootView:)`, called through SwiftUI's exported (but not
    /// SDK-declared) symbols: the generic metadata accessor and the allocating initializer.
    func makeHostingController(_ view: AnyView) -> NSObject? {
        // Accessor for UIHostingController<Content: View>: (request, Content metadata, Content: View witness table).
        typealias MetadataAccessor = @convention(c) (Int, UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer
        guard let accessorSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "$s7SwiftUI19UIHostingControllerCMa"),
              let initSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "$s7SwiftUI19UIHostingControllerC8rootViewACyxGx_tcfC") else {
            log("UIHostingController symbols not found"); return nil
        }
        let anyViewMetadata = unsafeBitCast(AnyView.self, to: UnsafeRawPointer.self)
        // An `any View` existential is [3-word buffer][type metadata][View witness table].
        let existential: any View = view
        let witnessTable = withUnsafeBytes(of: existential) { $0.load(fromByteOffset: 4 * MemoryLayout<Int>.size, as: UnsafeRawPointer.self) }
        let classMetadata = unsafeBitCast(accessorSym, to: MetadataAccessor.self)(0, anyViewMetadata, witnessTable)
        typealias Trampoline = @convention(c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer) -> UnsafeRawPointer
        guard let trampolineSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_call_swiftself") else { return nil }
        let callWithSelf = unsafeBitCast(trampolineSym, to: Trampoline.self)
        let storage = UnsafeMutablePointer<AnyView>.allocate(capacity: 1)
        storage.initialize(to: view)               // consumed (__owned) by the initializer
        defer { storage.deallocate() }
        // Allocating initializer: rootView (generic, so passed indirectly) in x0, metatype in x20.
        let object = callWithSelf(UnsafeRawPointer(initSym), classMetadata, UnsafeMutableRawPointer(storage))
        return Unmanaged<NSObject>.fromOpaque(object).takeRetainedValue()
    }

    var keyWindow: NSObject? {
        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type,
              let app = appClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject,
              let windows = app.perform(NSSelectorFromString("windows"))?.takeUnretainedValue() as? [NSObject] else { return nil }
        return windows.first
    }

    /// No-boot: every requested watch model in this one process, each in its own window.
    func renderNoBoot(_ previews: [DiscoveredPreview], job: Job, result: inout JobResult) {
        var index = 0
        for device in job.devices {
            WatchNoBoot.screen = device
            for preview in previews where job.wants(preview.name) && job.wants(preview.name, device: device.name) {
              for textSize in job.textSizes(for: preview.name) {
                let t0 = now()
                guard let view = swiftUIView(fromBody: preview.body()), let vc = makeHostingController(view) else {
                    result.errors.append("\(preview.name): watchOS previews must be SwiftUI views"); continue
                }
                guard let window = swiftshot_watch_make_window(device.width, device.height) as? NSObject else {
                    result.errors.append("\(preview.name): no window"); continue
                }
                hostingControllers.append(vc); hostingControllers.append(window)
                // Like iOS: a preview can ask for its own size instead of the full screen.
                var size = CGSize(width: device.width, height: device.height)
                switch preview.layout.kind {
                case .device:
                    // No status bar without a booted watch: give the content the device's safe area.
                    let a = device.safeArea
                    swiftshot_watch_set_safe_area(vc, a.top, a.left, a.bottom, a.right)
                case .fixed(let w, let h): size = CGSize(width: w, height: h)
                case .sizeThatFits:
                    // Measured inside the window, so it sees the window's text size.
                    swiftshot_watch_show(window, vc)
                    let fit = swiftshot_watch_fitting_size(vc, device.width)
                    size = CGSize(width: ceil(min(fit.width, device.width)), height: ceil(fit.height))
                }
                swiftshot_watch_resize(window, size.width, size.height)
                swiftshot_watch_show(window, vc)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3 + job.delay(for: preview.name)))
                dumpLayers(window, suffix: "-\(index)"); index += 1
                guard let image = swiftshot_watch_capture(window, size.width, size.height, device.scale)?.takeRetainedValue() else {
                    result.errors.append("\(preview.name) \(device.name): capture failed"); continue
                }
                let file = job.fileName(preview: preview.name, device: device.name, appearance: "", textSize: textSize)
                let out = URL(fileURLWithPath: job.outputDir).appendingPathComponent(job.language).appendingPathComponent(file)
                try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, image, nil)
                guard CGImageDestinationFinalize(dest) else { result.errors.append("\(out.path): write failed"); continue }
                result.shots.append(ShotRecord(
                    preview: preview.name, device: device.name, appearance: "dark",
                    textSize: contentSizeCategory(textSize) == nil ? nil : textSize, language: job.language, runtime: job.runtime,
                    file: "\(job.language)/\(file)", width: image.width, height: image.height, renderMs: (now() - t0) * 1000))
              }
            }
        }
    }

    /// Debug: write the window's layer tree ($SWIFTSHOT_LAYER_DUMP) to compare booted vs no-boot.
    func dumpLayers(_ window: NSObject, suffix: String) {
        guard let path = ProcessInfo.processInfo.environment["SWIFTSHOT_LAYER_DUMP"], let layer = window.value(forKey: "layer") as? NSObject else { return }
        func describe(_ l: NSObject, _ depth: Int) -> String {
            let subs = (l.value(forKey: "sublayers") as? [NSObject]) ?? []
            let delegate = l.value(forKey: "delegate").map { "\(type(of: $0 as AnyObject))" } ?? "-"
            let me = "\(String(repeating: " ", count: depth))\(type(of: l)) d=\(delegate) frame=\(l.value(forKey: "frame") ?? "?") flipped=\(l.value(forKey: "geometryFlipped") ?? "?") contents=\(l.value(forKey: "contents").map { "\(type(of: $0 as AnyObject))" } ?? "-") t=\(l.value(forKey: "transform").map { "\($0)" } ?? "?")"
            return ([me] + subs.map { describe($0, depth + 1) }).joined(separator: "\n")
        }
        let traits = (window.value(forKey: "traitCollection") as? NSObject).map { "\($0)" } ?? "?"
        let app = (NSClassFromString("UIApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject
        let category = app?.value(forKey: "preferredContentSizeCategory").map { "\($0)" } ?? "?"
        var screenInfo = ""
        if let screen = (NSClassFromString("UIScreen") as? NSObject.Type)?.value(forKey: "mainScreen") as? NSObject {
            for key in ["_displayCornerRadius", "scale", "bounds", "_peripheryInsets", "gamut", "_screenType", "_isEmbeddedScreen", "_pointsPerInch"] where screen.responds(to: NSSelectorFromString(key)) {
                screenInfo += " \(key)=\(screen.value(forKey: key) ?? "nil")"
            }
            if screen.responds(to: NSSelectorFromString("_displayInfoProvider")), let info = screen.value(forKey: "_displayInfoProvider") as? NSObject {
                for key in ["safeAreaInsetsPortrait", "peripheryInsets", "homeAffordanceOverlayAllowance", "systemMinimumMargin"] where info.responds(to: NSSelectorFromString(key)) {
                    screenInfo += " info.\(key)=\(info.value(forKey: key) ?? "nil")"
                }
            }
        }
        try? ("app category=\(category)\nscreen\(screenInfo)\ntraits=\(traits)\n" + describe(layer, 0)).write(toFile: path + suffix, atomically: true, encoding: .utf8)
    }

    func showOnScreen(_ previews: [DiscoveredPreview], job: Job, result: inout JobResult) {
        guard let controlDir = job.controlDir, let device = job.devices.first, let window = keyWindow else {
            result.errors.append("watchOS: no window to present previews in"); return
        }
        let screen = WKInterfaceDevice.current()
        var index = 0
        for preview in previews where job.wants(preview.name) && job.wants(preview.name, device: device.name) {
            let t0 = now()
            guard let view = swiftUIView(fromBody: preview.body()), let vc = makeHostingController(view) else {
                result.errors.append("\(preview.name): watchOS previews must be SwiftUI views"); continue
            }
            hostingControllers.append(vc)
            window.perform(NSSelectorFromString("setRootViewController:"), with: vc)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6 + job.delay(for: preview.name)))
            dumpLayers(window, suffix: "-\(index)")

            let file = job.fileName(preview: preview.name, device: device.name, appearance: "")
            let out = URL(fileURLWithPath: job.outputDir).appendingPathComponent(job.language).appendingPathComponent(file)
            try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            let ready = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).ready")
            let done = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).done")
            try? JSONSerialization.data(withJSONObject: ["path": out.path, "landscape": false]).write(to: ready)
            let deadline = Date(timeIntervalSinceNow: 30)
            while !FileManager.default.fileExists(atPath: done.path) && Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            }
            result.shots.append(ShotRecord(
                preview: preview.name, device: device.name, appearance: "dark", language: job.language, runtime: job.runtime,
                file: "\(job.language)/\(file)", width: Int(screen.screenBounds.width * screen.screenScale),
                height: Int(screen.screenBounds.height * screen.screenScale), renderMs: (now() - t0) * 1000))
            index += 1
        }
    }
}

/// No-boot on watchOS: like the iOS agent's NoBoot, the screen (and WatchKit's view of it)
/// reports the rendered watch model, since there is no display.
enum WatchNoBoot {
    static let enabled = ProcessInfo.processInfo.environment["SWIFTSHOT_NOBOOT"] == "1"
    nonisolated(unsafe) static var screen: DeviceProfile?

    static func install() {
        if let cls = NSClassFromString("CADisplay"), let m = class_getClassMethod(cls, NSSelectorFromString("displays")) {
            let none: @convention(block) (AnyObject) -> NSArray = { _ in NSArray() }
            method_setImplementation(m, imp_implementationWithBlock(none))
        }
        let scale: @convention(block) (AnyObject) -> CGFloat = { _ in screen?.scale ?? 2 }
        let bounds: @convention(block) (AnyObject) -> CGRect = { _ in CGRect(x: 0, y: 0, width: screen?.width ?? 208, height: screen?.height ?? 248) }
        let native: @convention(block) (AnyObject) -> CGRect = { _ in
            let s = screen?.scale ?? 2
            return CGRect(x: 0, y: 0, width: (screen?.width ?? 208) * s, height: (screen?.height ?? 248) * s)
        }
        let corner: @convention(block) (AnyObject) -> CGFloat = { _ in screen?.cornerRadius ?? 0 }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        let no: @convention(block) (AnyObject) -> Bool = { _ in false }
        let gamut: @convention(block) (AnyObject) -> Int = { _ in 1 }   // P3, like the watch display
        let getters: [(String, String, Any)] = [
            ("UIScreen", "gamut", gamut),
            ("UIScreen", "scale", scale), ("UIScreen", "nativeScale", scale), ("UIScreen", "_scale", scale),
            ("UIScreen", "bounds", bounds), ("UIScreen", "nativeBounds", native), ("UIScreen", "_displayCornerRadius", corner),
            ("UIScreen", "_isEmbeddedScreen", yes), ("UIScreen", "_isExternal", no),
            ("WKInterfaceDevice", "screenBounds", bounds), ("WKInterfaceDevice", "screenScale", scale),
        ]
        for (cls, name, block) in getters {
            if let c = NSClassFromString(cls), let m = class_getInstanceMethod(c, NSSelectorFromString(name)) {
                method_setImplementation(m, imp_implementationWithBlock(block))
            }
        }
        // watchOS text layout asks the application for status-bar metrics (navigation title
        // baselines); without a booted device no application object exists. Create the
        // watch's application class (the UIApplication subclass providing those metrics).
        let app = swiftshot_watch_make_application().map { $0.takeUnretainedValue() as String } ?? "not created"
        log("no-boot: application \(app)")
        swiftshot_flip_layer_drawing()
        // See the iOS agent: after-commit bookkeeping asserts without an app; it draws nothing.
        if let cls = NSClassFromString("_UIAppCACommitFuture"), let m = class_getInstanceMethod(cls, NSSelectorFromString("_invoke")) {
            let skip: @convention(block) (AnyObject) -> Void = { _ in }
            method_setImplementation(m, imp_implementationWithBlock(skip))
        }
    }
}

@_silgen_name("swiftshot_watch_make_application") func swiftshot_watch_make_application() -> Unmanaged<NSString>?
@_silgen_name("swiftshot_watch_fitting_size") func swiftshot_watch_fitting_size(_ controller: AnyObject, _ width: Double) -> CGSize
@_silgen_name("swiftshot_watch_resize") func swiftshot_watch_resize(_ window: AnyObject, _ width: Double, _ height: Double)
@_silgen_name("swiftshot_watch_set_safe_area") func swiftshot_watch_set_safe_area(_ controller: AnyObject, _ top: Double, _ left: Double, _ bottom: Double, _ right: Double)
@_silgen_name("swiftshot_watch_make_window") func swiftshot_watch_make_window(_ width: Double, _ height: Double) -> AnyObject?
@_silgen_name("swiftshot_watch_show") func swiftshot_watch_show(_ window: AnyObject, _ controller: AnyObject)
@_silgen_name("swiftshot_watch_capture") func swiftshot_watch_capture(_ window: AnyObject, _ width: Double, _ height: Double, _ scale: Double) -> Unmanaged<CGImage>?

#endif
