// swiftshot agent: injected into the app under test with DYLD_INSERT_LIBRARIES.
// Once the app's first scene is active it takes the job described by $SWIFTSHOT_JOB,
// renders every requested preview, writes the images straight to the host file system
// (simulator processes share the Mac's file system) and terminates the app.

#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import ObjectiveC
import Metal


@_cdecl("SwiftshotAgentStart")
public func SwiftshotAgentStart() {
    guard let jobPath = ProcessInfo.processInfo.environment["SWIFTSHOT_JOB"] else { return }
    // No-boot mode (experimental): the process runs straight on the Mac against the runtime, with
    // no simulator, so there is no app scene to wait for. Render right away, before the app's main.
    if NoBoot.enabled {
        NoBoot.install()
        MainActor.assumeIsolated { AgentRunner.startOnce(jobPath: jobPath) }
        return
    }
    // Fires once the app's first scene is in the foreground; the agent then owns the process.
    _ = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { AgentRunner.startOnce(jobPath: jobPath) }
    }
}

@MainActor
final class AgentRunner {
    let jobPath: String
    let started = now()
    var job: Job!
    var result = JobResult(previews: [], shots: [], errors: [], calibration: nil, totalMs: 0)
    let writeQueue = DispatchQueue(label: "swiftshot.write", qos: .userInitiated, attributes: .concurrent)
    let writeGroup = DispatchGroup()
    let writes = WriteSink()

    init(jobPath: String) { self.jobPath = jobPath }

    private static var started = false
    static func startOnce(jobPath: String) {
        guard !started else { return }
        started = true
        AgentRunner(jobPath: jobPath).run()
    }

    var scene: UIWindowScene {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes[0]
    }

    /// A window for off-screen rendering: in the app's scene, or scene-less without a simulator.
    func makeWindow() -> DeviceWindow {
        guard NoBoot.enabled else { return DeviceWindow(windowScene: scene) }
        if let scene = NoBoot.screenScene { return DeviceWindow(windowScene: scene) }
        return DeviceWindow(frame: .zero)
    }

    func run() {
        do {
            job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: URL(fileURLWithPath: jobPath)))
        } catch {
            log("cannot read job: \(error)"); exit(2)
        }
        DeviceIdiom.install()
        let previews = discoverPreviews().filter(matchesFilter)
        result.previews = previews.map(\.name)
        log("discovered \(previews.count) previews in \(Int((now() - started) * 1000)) ms")

        switch job.mode {
        case .list: finish()
        case .calibrate: calibrate(); finish()
        case .virtual: renderVirtual(previews); finish()
        case .device: renderOnDevice(previews); finish()
        }
    }

    func matchesFilter(_ preview: DiscoveredPreview) -> Bool {
        job.previewFilter.isEmpty || job.previewFilter.contains { globMatch($0, preview.name) }
    }

    func finish() {
        writeGroup.wait()
        result.shots += writes.shots
        result.errors += writes.errors
        result.totalMs = (now() - started) * 1000
        job.writeResult(result)
        exit(0)
    }

    // MARK: Calibration

    func calibrate() {
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.layoutIfNeeded()
        let screen = scene.screen
        let insets = window.safeAreaInsets
        let corner = (screen.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 0
        let portrait = Insets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let landscape = isPad
            ? Insets(top: portrait.top, left: 0, bottom: portrait.bottom, right: 0)
            : (portrait.top > 24 ? Insets(top: 0, left: portrait.top, bottom: min(portrait.bottom, 21), right: portrait.top) : Insets.zero)
        let width = min(screen.bounds.width, screen.bounds.height)
        let height = max(screen.bounds.width, screen.bounds.height)
        let display = NoBoot.readDisplayInfo(of: screen)
        result.calibration = DeviceProfile(
            name: job.devices.first?.name ?? UIDevice.current.name, idiom: isPad ? "pad" : "phone",
            width: width, height: height, scale: screen.scale,
            safeArea: portrait, landscapeSafeArea: landscape, cornerRadius: corner)
        result.calibration?.display = display
        window.isHidden = true
    }

    // MARK: Shared helpers

    struct Geometry { var size: CGSize; var safeArea: UIEdgeInsets; var landscape: Bool }

    func geometry(for preview: DiscoveredPreview, on device: DeviceProfile) -> Geometry {
        let landscape = preview.layout.landscape
        let size = landscape ? CGSize(width: device.height, height: device.width) : CGSize(width: device.width, height: device.height)
        let s = landscape ? device.landscapeSafeArea : device.safeArea
        return Geometry(size: size, safeArea: UIEdgeInsets(top: s.top, left: s.left, bottom: s.bottom, right: s.right), landscape: landscape)
    }

    func applyTraits(_ window: UIWindow, device: DeviceProfile, appearance: String, textSize: String = "default", size: CGSize) {
        window.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        if let category = contentSizeCategory(textSize) {
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(rawValue: category)
        }
        window.traitOverrides.displayScale = device.scale
        if NoBoot.enabled {
            // No display to inherit these from. The corner radius trait (private) decides e.g. how far
            // the floating tab bar sits above the bottom edge.
            window.traitOverrides.displayGamut = .P3
            NoBoot.setDisplayCornerRadius(device.cornerRadius, on: window)
            // A booted app takes the layout direction from UIApplication (none here).
            let rtl = Locale.Language(identifier: job.language).characterDirection == .rightToLeft
            window.traitOverrides.layoutDirection = rtl ? .rightToLeft : .leftToRight
        }
        // Rendering an iPad on an iPhone host (runtimes that can't boot an iPad): override the idiom.
        let hostIdiom = DeviceIdiom.host
        if device.idiom == "pad" && hostIdiom != .pad { window.traitOverrides.userInterfaceIdiom = .pad }
        if device.idiom == "phone" && hostIdiom != .phone { window.traitOverrides.userInterfaceIdiom = .phone }
        if device.idiom == "pad" {
            window.traitOverrides.horizontalSizeClass = .regular
            window.traitOverrides.verticalSizeClass = .regular
        } else if size.width > size.height {
            window.traitOverrides.horizontalSizeClass = size.width >= 896 ? .regular : .compact
            window.traitOverrides.verticalSizeClass = .compact
        } else {
            window.traitOverrides.horizontalSizeClass = .compact
            window.traitOverrides.verticalSizeClass = .regular
        }
    }

    /// Let SwiftUI/UIKit commit layout and rendering: spin the run loop for a few frames.
    func settle(frames: Int, delay: Double) {
        for _ in 0..<max(frames, 1) {
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120.0))
        }
        if delay > 0 { RunLoop.main.run(until: Date(timeIntervalSinceNow: delay)) }
    }

    func fileName(preview: String, device: String, appearance: String, textSize: String = "default") -> String {
        job.fileName(preview: preview, device: device, appearance: appearance, textSize: textSize)
    }

    func outputURL(_ file: String) -> URL {
        URL(fileURLWithPath: job.outputDir).appendingPathComponent(job.language).appendingPathComponent(file)
    }

    func store(image: UIImage, record: ShotRecord) {
        let url = URL(fileURLWithPath: job.outputDir).appendingPathComponent(record.file)
        let jpeg = job.format == "jpeg"
        writeGroup.enter()
        let sink = writes
        let group = writeGroup
        writeQueue.async {
            defer { group.leave() }
            let data = jpeg ? image.jpegData(compressionQuality: 0.92) : image.pngData()
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data?.write(to: url)
                sink.add(shot: record)
            } catch {
                sink.add(error: "\(record.file): \(error)")
            }
        }
    }

    // MARK: Virtual mode — every device rendered off-screen in this one process

    func renderVirtual(_ previews: [DiscoveredPreview]) {
        let capture = NoBoot.enabled ? "carenderer" : ProcessInfo.processInfo.environment["SWIFTSHOT_CAPTURE"] ?? "hierarchy"
        // Off-screen so the window inherits no system safe area; we supply the device's instead.
        let offscreenOrigin = NoBoot.enabled ? .zero : CGPoint(x: scene.screen.bounds.width * 4, y: scene.screen.bounds.height * 4)

        // Screenshots want end states: sheets, alerts and other presentations appear at once.
        UIView.setAnimationsEnabled(false)
        for preview in previews where job.wants(preview.name) {
            for device in job.devices where job.wants(preview.name, device: device.name) {
                for appearance in job.appearances(for: preview.name) {
                  for textSize in job.textSizes(for: preview.name) {
                    let t0 = now()
                    DeviceIdiom.current = device.idiom == "pad" ? .pad : .phone
                    NoBoot.screen = device
                    defer { DeviceIdiom.current = nil }
                    guard let vc = controller(fromBody: preview.body()) else {
                        result.errors.append("\(preview.name): could not build preview body"); continue
                    }
                    var geo = geometry(for: preview, on: device)
                    let window = makeWindow()
                    applyTraits(window, device: device, appearance: appearance, textSize: textSize, size: geo.size)

                    switch preview.layout.kind {
                    case .device:
                        window.forcedSafeArea = geo.safeArea
                    case .fixed(let w, let h):
                        geo.size = CGSize(width: w, height: h)
                    case .sizeThatFits:
                        // Measured inside the window, so it sees the window's traits (text size).
                        window.rootViewController = vc
                        window.isHidden = false
                        settle(frames: 1, delay: 0)
                        let proposal = CGSize(width: geo.size.width, height: .greatestFiniteMagnitude)
                        let fitting: CGSize
                        if let hosting = vc as? UIHostingController<AnyView> {
                            fitting = hosting.sizeThatFits(in: proposal)
                        } else {
                            fitting = vc.view.systemLayoutSizeFitting(proposal)
                        }
                        geo.size = CGSize(width: ceil(min(fitting.width, geo.size.width)), height: ceil(fitting.height))
                    }

                    if !preview.layout.kind.isDevice, let hosting = vc as? UIHostingController<AnyView> {
                        hosting.safeAreaRegions = []   // like Xcode: component previews have no safe area
                    }
                    window.frame = CGRect(origin: offscreenOrigin, size: geo.size)
                    window.rootViewController = vc
                    window.isHidden = false
                    window.layoutIfNeeded()
                    if preview.layout.kind.isDevice { correctSafeArea(of: vc, to: geo.safeArea, in: window) }
                    if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil {
                        log("\(preview.name) \(device.name): UIDevice idiom \(UIDevice.current.userInterfaceIdiom.rawValue) window safe \(window.safeAreaInsets) view safe \(vc.view.safeAreaInsets) additional \(vc.additionalSafeAreaInsets) frame \(window.frame) vcframe \(vc.view.frame)")
                    }
                    settle(frames: job.settleFrames, delay: job.delay(for: preview.name))
                    if NoBoot.enabled { NoBoot.finishPresentations(of: vc, in: window, settle: { self.settle(frames: 2, delay: 0) }) }
                    if preview.layout.kind.isDevice && job.fullLength(for: preview.name) {
                        geo.size = growToContent(of: vc, in: window, size: geo.size, scale: device.scale, name: preview.name)
                    }
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = device.scale
                    format.opaque = preview.layout.kind.isDevice
                    let bounds = CGRect(origin: .zero, size: geo.size)
                    let rendered = capture == "carenderer" ? GPUCapture.shared.image(of: window, size: geo.size, scale: device.scale, opaque: format.opaque) : nil
                    let image = rendered ?? UIGraphicsImageRenderer(size: geo.size, format: format).image { ctx in
                        if capture == "layer" {
                            window.layer.render(in: ctx.cgContext)
                        } else {
                            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
                        }
                    }
                    window.isHidden = true
                    window.rootViewController = nil
                    let output = device.panelWidth.flatMap { w in device.panelHeight.map { h in
                        // Like the real "mini" phones: lay out at @3x, then downsample to the panel.
                        let landscape = geo.size.width > geo.size.height && preview.layout.kind.isDevice
                        let target = CGSize(width: landscape ? h : w, height: landscape ? w : h)
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                            ctx.cgContext.interpolationQuality = .high
                            image.draw(in: CGRect(origin: .zero, size: target))
                        }
                    } } ?? image

                    let file = fileName(preview: preview.name, device: device.name, appearance: appearance, textSize: textSize)
                    store(image: output, record: ShotRecord(
                        preview: preview.name, device: device.name, appearance: appearance,
                        textSize: contentSizeCategory(textSize) == nil ? nil : textSize, language: job.language,
                        runtime: job.runtime, file: "\(job.language)/\(file)",
                        width: Int(output.size.width * output.scale), height: Int(output.size.height * output.scale),
                        renderMs: (now() - t0) * 1000))
                  }
                }
            }
        }
    }

    /// Full-length screenshots: make the window tall enough that the main vertical scroll view
    /// shows all of its content (repeated, lazy stacks grow as they are revealed). Capped at what
    /// one Metal texture holds.
    func growToContent(of vc: UIViewController, in window: UIWindow, size: CGSize, scale: CGFloat, name: String) -> CGSize {
        let maxHeight = floor(16384 / scale)
        var size = size
        for _ in 0..<8 {
            func scrollViews(_ v: UIView) -> [UIScrollView] { (v as? UIScrollView).map { [$0] } ?? v.subviews.flatMap(scrollViews) }
            guard let scroll = scrollViews(vc.view).filter({ !$0.isHidden && $0.bounds.height > 0 })
                    .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { break }
            let inset = scroll.adjustedContentInset
            let hidden = ceil(scroll.contentSize.height + inset.top + inset.bottom - scroll.bounds.height)
            guard hidden > 0.5 else { break }
            let target = min(size.height + hidden, maxHeight)
            guard target > size.height else {
                log("warning: \(name): full length capped at \(Int(maxHeight)) pt"); break
            }
            size.height = target
            window.frame.size = size
            scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: -inset.top)
            window.setNeedsLayout(); window.layoutIfNeeded()
            settle(frames: job.settleFrames, delay: 0)
        }
        return size
    }

    /// UIKit can add host-specific insets (status bar) on top of the window's. Measure what the
    /// root view really gets and compensate with additionalSafeAreaInsets until it matches.
    func correctSafeArea(of vc: UIViewController, to target: UIEdgeInsets, in window: UIWindow) {
        for _ in 0..<3 {
            let actual = vc.view.safeAreaInsets
            if actual == target { return }
            let a = vc.additionalSafeAreaInsets
            vc.additionalSafeAreaInsets = UIEdgeInsets(top: a.top + target.top - actual.top, left: a.left + target.left - actual.left,
                                                       bottom: a.bottom + target.bottom - actual.bottom, right: a.right + target.right - actual.right)
            window.setNeedsLayout(); window.layoutIfNeeded()
        }
        if vc.view.safeAreaInsets != target { log("warning: safe area \(vc.view.safeAreaInsets) != wanted \(target)") }
    }

    // MARK: Device mode — show on the real screen, let the host grab the framebuffer

    var deviceWindow: UIWindow?

    func renderOnDevice(_ previews: [DiscoveredPreview]) {
        guard let controlDir = job.controlDir, let device = job.devices.first else { return }
        let combos = previews.filter { job.wants($0.name) && job.wants($0.name, device: device.name) }
            .flatMap { p in job.appearances(for: p.name).map { (p, $0) } }
        // The simulator screen stays portrait. Rotating a live simulator from inside the app is
        // not reliable, so landscape previews go through the (pixel-identical) virtual renderer.
        if scene.effectiveGeometry.interfaceOrientation.isLandscape {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            settle(frames: 2, delay: 0.5)
        }
        let landscape = previews.filter { $0.layout.landscape }
        if !landscape.isEmpty { renderVirtual(landscape) }
        for (index, (preview, appearance)) in combos.filter({ !$0.0.layout.landscape }).enumerated() {
            showAndHandOver(preview: preview, appearance: appearance, index: index, device: device, controlDir: controlDir)
        }
    }

    func showAndHandOver(preview: DiscoveredPreview, appearance: String, index: Int, device: DeviceProfile, controlDir: String) {
        let t0 = now()

        // Take over the app's own window, so none of the app's UI (or system chrome attached to it,
        // like a tab bar rail) shows around the preview.
        if deviceWindow == nil {
            deviceWindow = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first ?? UIWindow(windowScene: scene)
        }
        let window = deviceWindow!
        window.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        guard let vc = controller(fromBody: preview.body()) else {
            result.errors.append("\(preview.name): could not build preview body"); return
        }
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = vc
        window.isHidden = false
        window.layoutIfNeeded()
        settle(frames: job.settleFrames, delay: job.delay(for: preview.name))

        let file = fileName(preview: preview.name, device: device.name, appearance: appearance)
        let out = outputURL(file)
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ready = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).ready")
        let done = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).done")
        let info: [String: Any] = ["path": out.path, "landscape": false]
        try? JSONSerialization.data(withJSONObject: info).write(to: ready)

        // Wait for the host to take the framebuffer screenshot, keeping the run loop alive.
        let deadline = Date(timeIntervalSinceNow: 30)
        while !FileManager.default.fileExists(atPath: done.path) && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        let px = scene.screen.nativeBounds.size
        result.shots.append(ShotRecord(
            preview: preview.name, device: device.name, appearance: appearance, language: job.language,
            runtime: job.runtime, file: "\(job.language)/\(file)",
            width: Int(min(px.width, px.height)), height: Int(max(px.width, px.height)),
            renderMs: (now() - t0) * 1000))
    }
}

/// Renders a window's layer tree with Core Animation's own renderer into a Metal texture: the
/// same engine the render server uses (materials, Liquid Glass), but in-process, so it also works
/// without a booted simulator (see NoBoot).
@MainActor
final class GPUCapture {
    static let shared = GPUCapture()
    let device = MTLCreateSystemDefaultDevice()
    lazy var queue = device?.makeCommandQueue()

    func image(of window: UIWindow, size: CGSize, scale: CGFloat, opaque: Bool) -> UIImage? {
        guard let device, let queue else { log("carenderer: no Metal device"); return nil }
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        // The window's layer goes under a flipped pixel-sized root (UIKit layers expect a flipped
        // parent) for the capture and back afterwards.
        let layer = window.layer
        let saved = (layer.superlayer, layer.anchorPoint, layer.position, layer.affineTransform())
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.isGeometryFlipped = true
        root.addSublayer(layer)
        layer.anchorPoint = .zero; layer.position = .zero
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        defer {
            layer.removeFromSuperlayer()
            layer.setAffineTransform(saved.3); layer.anchorPoint = saved.1; layer.position = saved.2
            saved.0?.addSublayer(layer)
        }
        // Composite in 8-bit sRGB like the render server (a colorspace option or a float target
        // changes the result), convert to 16-bit Display P3 when writing like drawHierarchy.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.frame
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let done = queue.makeCommandBuffer(); done?.commit(); done?.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = (opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst).rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let raw = ctx.makeImage() else { return nil }
        // Metal rows are top-down; draw into a UIKit context to get an upright image. Like
        // drawHierarchy on a P3 screen, the result is a 16-bit Display P3 image.
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = opaque; format.preferredRange = .extended
        return UIGraphicsImageRenderer(size: size, format: format).image { c in
            c.cgContext.draw(raw, in: CGRect(origin: .zero, size: size))
        }
    }
}

/// No-boot mode: the app runs as a plain process on the Mac against the simulator runtime, with
/// swiftshot-simhost providing Metal, IOSurface and the shader compiler (see Agent/NoBoot.c).
/// There is no display, so UIScreen reports the device being rendered.
enum NoBoot {
    static let enabled = ProcessInfo.processInfo.environment["SWIFTSHOT_NOBOOT"] == "1"
    nonisolated(unsafe) static var screen: DeviceProfile?

    /// UIKit's scene for a bare UIScreen (no FrontBoard). Windows in it get scene-provided layout
    /// (home affordance, …) like in a booted simulator; scene-less windows don't.
    @MainActor static let screenScene: UIWindowScene? = {
        guard ProcessInfo.processInfo.environment["SWIFTSHOT_NOBOOT_SCENE"] != "0",
              let cls = NSClassFromString("_UIScreenBasedWindowScene") else { return nil }
        let selector = NSSelectorFromString("_unassociatedWindowSceneForScreen:create:")
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        typealias Make = @convention(c) (AnyClass, Selector, UIScreen, Bool) -> UIWindowScene?
        return unsafeBitCast(method_getImplementation(method), to: Make.self)(cls, selector, UIScreen.main, true)
    }()

    static func insets(_ value: Any?) -> Insets {
        let e = (value as? NSValue)?.uiEdgeInsetsValue ?? .zero
        return Insets(top: e.top, left: e.left, bottom: e.bottom, right: e.right)
    }

    /// Reads the display data of a booted device (calibration).
    @MainActor static func readDisplayInfo(of screen: UIScreen) -> DisplayInfo? {
        guard let info = screen.value(forKey: "_displayInfoProvider") as AnyObject? else { return nil }
        func get(_ key: String) -> Any? { info.responds(to: NSSelectorFromString(key)) ? info.value(forKey: key) : nil }
        return DisplayInfo(
            safeAreaPortrait: insets(get("safeAreaInsetsPortrait")),
            safeAreaPortraitUpsideDown: insets(get("safeAreaInsetsPortraitUpsideDown")),
            safeAreaLandscapeLeft: insets(get("safeAreaInsetsLandscapeLeft")),
            safeAreaLandscapeRight: insets(get("safeAreaInsetsLandscapeRight")),
            periphery: insets(get("peripheryInsets")),
            homeAffordanceOverlayAllowance: (get("homeAffordanceOverlayAllowance") as? Double) ?? 0,
            systemMinimumMargin: (get("systemMinimumMargin") as? Double) ?? 0,
            artworkSubtype: (get("artworkSubtype") as? Int) ?? 0,
            screenPeriphery: insets(screen.value(forKey: "_peripheryInsets")),
            screenDisplayPeriphery: insets(screen.value(forKey: "_displayPeripheryInsets")))
    }

    /// Reports the rendered device's display data from UIKit's display info provider and screen.
    static func installDisplayInfo() {
        func edge(_ i: Insets?) -> UIEdgeInsets { UIEdgeInsets(top: i?.top ?? 0, left: i?.left ?? 0, bottom: i?.bottom ?? 0, right: i?.right ?? 0) }
        typealias InsetsGetter = @convention(block) (AnyObject) -> UIEdgeInsets
        let insetGetters: [(AnyClass?, String, InsetsGetter)] = [
            (NSClassFromString("_UIDisplayInfoProvider"), "safeAreaInsetsPortrait", { _ in edge(screen?.display?.safeAreaPortrait) }),
            (NSClassFromString("_UIDisplayInfoProvider"), "safeAreaInsetsPortraitUpsideDown", { _ in edge(screen?.display?.safeAreaPortraitUpsideDown) }),
            (NSClassFromString("_UIDisplayInfoProvider"), "safeAreaInsetsLandscapeLeft", { _ in edge(screen?.display?.safeAreaLandscapeLeft) }),
            (NSClassFromString("_UIDisplayInfoProvider"), "safeAreaInsetsLandscapeRight", { _ in edge(screen?.display?.safeAreaLandscapeRight) }),
            (NSClassFromString("_UIDisplayInfoProvider"), "peripheryInsets", { _ in edge(screen?.display?.periphery) }),
            (UIScreen.self, "_peripheryInsets", { _ in edge(screen?.display?.screenPeriphery) }),
            (UIScreen.self, "_displayPeripheryInsets", { _ in edge(screen?.display?.screenDisplayPeriphery) }),
        ]
        for (cls, name, block) in insetGetters {
            if let cls, let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) { method_setImplementation(m, imp_implementationWithBlock(block)) }
        }
        let allowance: @convention(block) (AnyObject) -> Double = { _ in screen?.display?.homeAffordanceOverlayAllowance ?? 0 }
        let margin: @convention(block) (AnyObject) -> Double = { _ in screen?.display?.systemMinimumMargin ?? 0 }
        let subtype: @convention(block) (AnyObject) -> UInt = { _ in UInt(screen?.display?.artworkSubtype ?? 0) }
        for (name, block) in [("homeAffordanceOverlayAllowance", allowance as Any), ("systemMinimumMargin", margin), ("artworkSubtype", subtype)] {
            if let cls = NSClassFromString("_UIDisplayInfoProvider"), let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) {
                method_setImplementation(m, imp_implementationWithBlock(block))
            }
        }
    }

    @MainActor static func setDisplayCornerRadius(_ radius: CGFloat, on window: UIWindow) {
        guard let trait = NSClassFromString("UITraitDisplayCornerRadius"),
              let overrides = window.value(forKey: "traitOverrides") as AnyObject? else { return }
        let selector = NSSelectorFromString("setCGFloatValue:forTrait:")
        guard let method = class_getInstanceMethod(type(of: overrides), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat, AnyClass) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(overrides, selector, radius, trait)
    }

    static func install() {
        // QuartzCore polls ~5 s for a render server's displays that will never appear.
        if let cls = NSClassFromString("CADisplay"), let m = class_getClassMethod(cls, NSSelectorFromString("displays")) {
            let none: @convention(block) (AnyObject) -> NSArray = { _ in NSArray() }
            method_setImplementation(m, imp_implementationWithBlock(none))
        }
        // Without a display UIScreen describes an external screen of scale 1. Report the rendered
        // device's built-in panel instead (values as a booted simulator of that model reports them).
        let scale: @convention(block) (AnyObject) -> CGFloat = { _ in screen?.scale ?? 3 }
        let bounds: @convention(block) (AnyObject) -> CGRect = { _ in
            CGRect(x: 0, y: 0, width: screen?.width ?? 390, height: screen?.height ?? 844)
        }
        let native: @convention(block) (AnyObject) -> CGRect = { _ in
            let s = screen?.scale ?? 3
            return CGRect(x: 0, y: 0, width: (screen?.width ?? 390) * s, height: (screen?.height ?? 844) * s)
        }
        let corner: @convention(block) (AnyObject) -> CGFloat = { _ in screen?.cornerRadius ?? 0 }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        let no: @convention(block) (AnyObject) -> Bool = { _ in false }
        // Plus/Max-size phones get wider layout margins.
        let wideMargins: @convention(block) (AnyObject) -> Bool = { _ in screen.map { $0.idiom == "phone" && $0.width >= 414 } ?? false }
        let touchRadius: @convention(block) (AnyObject) -> CGFloat = { _ in screen?.height ?? 844 }
        let fps: @convention(block) (AnyObject) -> Int = { _ in 60 }
        let refresh: @convention(block) (AnyObject) -> Double = { _ in 1.0 / 60 }
        let gamut: @convention(block) (AnyObject) -> Int = { _ in 1 }   // P3
        let orientation: @convention(block) (AnyObject) -> Int = { _ in 0 }
        let brightness: @convention(block) (AnyObject) -> CGFloat = { _ in 0.5 }
        let getters: [(String, Any)] = [
            ("scale", scale), ("nativeScale", scale), ("_scale", scale), ("_nativeScale", scale), ("_maximumSupportedScale", scale),
            ("bounds", bounds), ("nativeBounds", native),
            ("_displayCornerRadius", corner), ("_displayCornerRadiusIgnoringZoom", corner), ("_traitCollectionDisplayCornerRadius", corner),
            ("_isEmbeddedScreen", yes), ("_isRotatable", yes), ("_isExternal", no),
            ("_wantsWideContentMargins", wideMargins), ("_touchRadiusScaleFactor", touchRadius),
            ("maximumFramesPerSecond", fps), ("_maximumFramesPerSecond", fps), ("_refreshRate", refresh),
            ("gamut", gamut), ("_interfaceOrientation", orientation), ("brightness", brightness),
        ]
        for (name, block) in getters {
            if let m = class_getInstanceMethod(UIScreen.self, NSSelectorFromString(name)) { method_setImplementation(m, imp_implementationWithBlock(block)) }
        }
        // UIKit defers some bookkeeping to "after the next CA commit" (scene mirroring evaluation,
        // transition-coordinator completions). Without a booted device those only run when
        // CARenderer's local context commits, and iOS 26 asserts in them (no UIApplication). They
        // don't affect what is drawn, so skip them.
        if let cls = NSClassFromString("_UIAppCACommitFuture"), let m = class_getInstanceMethod(cls, NSSelectorFromString("_invoke")) {
            let skip: @convention(block) (AnyObject) -> Void = { _ in }
            method_setImplementation(m, imp_implementationWithBlock(skip))
        }
        installDisplayInfo()
        makeApplication()
        // A booted host scene is portrait (landscape previews are just landscape-sized windows);
        // a screen-based scene would report "unknown", which changes e.g. the tab bar's layout.
        let portrait: @convention(block) (AnyObject) -> Int = { _ in UIInterfaceOrientation.portrait.rawValue }
        for (cls, name) in [(UIWindowScene.self as AnyClass, "interfaceOrientation"), (UIWindowScene.self, "_interfaceOrientation"),
                            (UIWindow.self, "interfaceOrientation"), (UIWindow.self, "_windowInterfaceOrientation"),
                            (UIApplication.self, "statusBarOrientation"), (UIApplication.self, "_safeInterfaceOrientationForNoWindow"),
                            (UIApplication.self, "activeInterfaceOrientation"), (UIApplication.self, "_currentExpectedInterfaceOrientation")] {
            if let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) { method_setImplementation(m, imp_implementationWithBlock(portrait)) }
        }
    }

    /// Without a display, nothing runs the layout pass a device would after a presentation: the
    /// presented controller (sheet, alert, dialog) keeps its initial frame and SwiftUI never builds
    /// its content. Lay the window out until presentations have settled.
    static func finishPresentations(of root: UIViewController, in window: UIWindow, settle: () -> Void) {
        func tree(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(tree) }
        guard tree(root).contains(where: { $0.presentedViewController != nil }) else { return }
        for _ in 0..<3 {
            window.setNeedsLayout(); window.layoutIfNeeded()
            for view in window.subviews { view.setNeedsLayout(); view.layoutIfNeeded() }
            settle()
        }
    }

    /// No UIApplicationMain runs without a simulator, but UIKit schedules work (presentation
    /// transitions…) through the shared application. Register one like UIApplicationMain does
    /// (UIApp must be set before -init). Its windows would ask the render server for a context
    /// (there is none; CARenderer draws the layers directly), and the blocks it runs after Core
    /// Animation commits would wait for a run-loop observer only UIApplicationMain installs: run
    /// them on the main queue instead. With an application, drawing layers expect the flipped
    /// context orientation (like watchOS).
    static func makeApplication() {
        if let binder = NSClassFromString("_UIContextBinder"), let m = class_getInstanceMethod(binder, NSSelectorFromString("attachBindable:")) {
            let skip: @convention(block) (AnyObject, AnyObject) -> Void = { _, _ in }
            method_setImplementation(m, imp_implementationWithBlock(skip))
        }
        typealias Block = @convention(block) () -> Void
        let later: @convention(block) (AnyObject, @escaping Block) -> Void = { _, block in DispatchQueue.main.async { block() } }
        for name in ["_performBlockAfterCATransactionCommits:", "_performBlockAfterCATransactionCommitSynchronizes:"] {
            if let m = class_getInstanceMethod(UIApplication.self, NSSelectorFromString(name)) { method_setImplementation(m, imp_implementationWithBlock(later)) }
        }
        let legacy: @convention(block) (AnyObject, Bool, @escaping Block) -> Void = { _, _, block in DispatchQueue.main.async { block() } }
        if let m = class_getInstanceMethod(UIApplication.self, NSSelectorFromString("_performAfterCATransactionCommitsWithLegacyRunloopObserverBasedTiming:block:")) {
            method_setImplementation(m, imp_implementationWithBlock(legacy))
        }
        swiftshot_flip_layer_drawing()
        guard let global = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "UIApp")?.assumingMemoryBound(to: UnsafeMutableRawPointer?.self),
              global.pointee == nil, let app = class_createInstance(UIApplication.self, 0) as? NSObject else { return }
        global.pointee = Unmanaged.passRetained(app).toOpaque()
        _ = app.perform(NSSelectorFromString("init"))
    }
}

/// A window that reports the *target* device's safe area instead of the host simulator's.
final class DeviceWindow: UIWindow {
    var forcedSafeArea: UIEdgeInsets = .zero
    override var safeAreaInsets: UIEdgeInsets { forcedSafeArea }
}

extension PreviewLayoutSpec.Kind {
    var isDevice: Bool { if case .device = self { return true } else { return false } }
}

/// App code that branches on `UIDevice.current.userInterfaceIdiom` (instead of the trait
/// collection) must see the device being rendered, not the host simulator's model.
enum DeviceIdiom {
    nonisolated(unsafe) static var current: UIUserInterfaceIdiom?
    nonisolated(unsafe) static var host: UIUserInterfaceIdiom = .unspecified

    static func install() {
        host = UIDevice.current.userInterfaceIdiom
        let selector = #selector(getter: UIDevice.userInterfaceIdiom)
        guard let method = class_getInstanceMethod(UIDevice.self, selector) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let replacement: @convention(block) (AnyObject) -> Int = { device in
            current?.rawValue ?? original(device, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}

#endif
