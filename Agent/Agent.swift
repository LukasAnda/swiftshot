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
import IOSurface


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
            NoBoot.setVerticalBar(of: device.display, on: window)
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
        SystemChrome.job = job
        let capture = NoBoot.enabled ? "carenderer" : ProcessInfo.processInfo.environment["SWIFTSHOT_CAPTURE"] ?? "hierarchy"
        // Off-screen so the window inherits no system safe area; we supply the device's instead.
        let offscreenOrigin = NoBoot.enabled ? .zero : CGPoint(x: scene.screen.bounds.width * 4, y: scene.screen.bounds.height * 4)

        // Screenshots want end states: sheets, alerts and other presentations appear at once.
        UIView.setAnimationsEnabled(false)
        for preview in previews where job.wants(preview.name) {
            for device in job.devices where job.wants(preview.name, device: device.name) {
                for appearance in job.appearances(for: preview.name) {
                  for textSize in job.textSizes(for: preview.name) { autoreleasepool {
                    let t0 = now()
                    DeviceIdiom.current = device.idiom == "pad" ? .pad : .phone
                    NoBoot.screen = device
                    let ex = device.display?.exclusionArea
                    swiftshot_set_exclusion_rect(ex.flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil } ?? .null)
                    if let corners = device.display?.cornerInsets, corners.count == 8 { corners.withUnsafeBufferPointer { swiftshot_set_corner_insets($0.baseAddress) } } else { swiftshot_set_corner_insets(nil) }
                    defer { DeviceIdiom.current = nil }
                    guard let vc = controller(fromBody: preview.body()) else {
                        result.errors.append("\(preview.name): could not build preview body"); return
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
                    if NoBoot.enabled { NoBoot.finishLayout(of: vc, in: window, settle: { self.settle(frames: 2, delay: 0) }) }
                    if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { dumpPresentation(vc, window) }
                    if preview.layout.kind.isDevice && job.fullLength(for: preview.name) {
                        geo.size = growToContent(of: vc, in: window, size: geo.size, scale: device.scale, name: preview.name)
                    }
                    if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil {
                        func animated(_ l: CALayer) -> [String] { ((l.animationKeys() ?? []).isEmpty ? [] : ["\(type(of: l.delegate as AnyObject? ?? l)):\(l.animationKeys()!)"]) + (l.sublayers ?? []).flatMap(animated) }
                        log("animations before capture: \(animated(window.layer).prefix(12))")
                    }
                    // The system status bar over the app, as a device shows it.
                    // SpringBoard's status bar and home indicator, in their own window composited over
                    // the app's (as on a device, the app's materials don't see them).
                    let chrome = preview.layout.kind.isDevice && job.statusBar != false ? SystemChrome.chrome(over: window, root: vc, size: geo.size) : nil
                    ServerCapture.chrome = chrome
                    defer { ServerCapture.chrome = nil; chrome?.isHidden = true }
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = device.scale
                    format.opaque = preview.layout.kind.isDevice
                    let bounds = CGRect(origin: .zero, size: geo.size)
                    let rendered = capture == "carenderer" ? (ServerCapture.enabled ? ServerCapture.image(of: window, size: geo.size, scale: device.scale, opaque: format.opaque) : GPUCapture.shared.image(of: window, size: geo.size, scale: device.scale, opaque: format.opaque)) : nil
                    let image = rendered ?? UIGraphicsImageRenderer(size: geo.size, format: format).image { ctx in
                        if capture == "layer" {
                            window.layer.render(in: ctx.cgContext)
                        } else {
                            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
                        }
                    }
                    // A presentation's teardown finishes on later run-loop passes; until then the
                    // next preview's floating bar (iPhone Duo) still sees it in its glass.
                    func tree(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(tree) }
                    let presented = tree(vc).first(where: { $0.presentedViewController != nil })
                    presented?.dismiss(animated: false)
                    window.isHidden = true
                    window.rootViewController = nil
                    if presented != nil, (device.display?.verticalBarAllowed ?? 0) != 0 { settle(frames: 1, delay: 0.05) }
                    let output = device.panelWidth.flatMap { w in device.panelHeight.map { h in
                        // Like the real "mini" phones: lay out at @3x, then downsample to the panel.
                        let landscape = geo.size.width > geo.size.height && preview.layout.kind.isDevice
                        let target = CGSize(width: landscape ? h : w, height: landscape ? w : h)
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
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
                  } }
                }
            }
        }
    }

    func dumpPresentation(_ root: UIViewController, _ window: UIWindow) {
        func tree(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(tree) }
        log("window \(window.frame) safe \(window.safeAreaInsets) screen \(window.screen.bounds) subviews \(window.subviews.map { "\(type(of: $0)) \($0.frame) safe \($0.safeAreaInsets)" })")
        let isel = NSSelectorFromString("valueForNSIntegerTrait:")
        typealias Trait = @convention(c) (AnyObject, Selector, AnyClass) -> Int
        func trait(_ name: String, _ tc: UITraitCollection) -> String {
            guard let c = NSClassFromString(name), let imp = class_getMethodImplementation(type(of: tc), isel) else { return "-" }
            return "\(unsafeBitCast(imp, to: Trait.self)(tc, isel, c))"
        }
        for c in tree(root) { guard let p = c.presentedViewController else { continue }
            var v: UIView? = p.view
            while let view = v { log("  \(type(of: view)) frame \(view.frame) safe \(view.safeAreaInsets)"); v = view.superview }
            if let pc = p.presentationController {
                var values: [String] = []
                for k in ["_preferredStatusBarAxisForPresentation", "_containerViewVerticalBarAllowed", "_verticalBarAllowedForPresentation"] where pc.responds(to: NSSelectorFromString(k)) { values.append("\(k)=\(pc.value(forKey: k) ?? "nil")") }
                for n in ["_UITraitSystemVerticalBarAllowed", "_UITraitVerticalBarAllowed", "_UITraitVerticalBarSuppressed"] { values.append("\(n)=\(trait(n, p.view.traitCollection))") }
                log("  presentation " + values.joined(separator: " "))
            }
            if let sheet = p.sheetPresentationController { log("  sheet detents \(sheet.detents) container \(sheet.containerView?.bounds ?? .zero) safe \(sheet.containerView?.safeAreaInsets ?? .zero) frameOfPresented \(sheet.frameOfPresentedViewInContainerView)") }
        }
        // SWIFTSHOT_TREE=<file>: every view's frame, safe area and margins, to diff a no-boot render
        // against the same preview in --mode device.
        if let path = ProcessInfo.processInfo.environment["SWIFTSHOT_TREE"] {
            func dump(_ v: UIView, _ depth: Int) -> [String] {
                ["\(depth) \(type(of: v)) f=\(v.frame) s=\(v.safeAreaInsets) m=\(v.layoutMargins)"] + v.subviews.flatMap { dump($0, depth + 1) }
            }
            try? dump(window, 0).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
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
        // End states, like the virtual renderer: a sheet's spring is still moving when the
        // framebuffer is grabbed otherwise.
        UIView.setAnimationsEnabled(false)
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
        if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { dumpPresentation(vc, window) }

        let file = fileName(preview: preview.name, device: device.name, appearance: appearance)
        let out = outputURL(file)
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ready = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).ready")
        let done = URL(fileURLWithPath: controlDir).appendingPathComponent("\(index).done")
        let info: [String: Any] = ["path": out.path, "landscape": false]
        try? JSONSerialization.data(withJSONObject: info).write(to: ready)

        // Wait for the host to take the framebuffer screenshot, keeping the run loop alive. Moving
        // on early would put the next screen in this file (simctl is slow on a CI VM); the job's
        // timeout covers a host that never answers.
        let deadline = Date(timeIntervalSinceNow: 600)
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
        // Composite in 8-bit sRGB like the render server: the simulator framebuffer is 8-bit BGRA
        // and that is what `simctl io screenshot` saves (a colorspace option or a float target
        // changes the result).
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
        // The flipped root renders bottom-up: reverse the rows (lossless).
        bytes.withUnsafeMutableBytes { buf in
            let row = w * 4; var tmp = [UInt8](repeating: 0, count: row)
            for y in 0..<(h / 2) {
                let a = buf.baseAddress! + y * row, b = buf.baseAddress! + (h - 1 - y) * row
                memcpy(&tmp, a, row); memcpy(a, b, row); memcpy(b, tmp, row)
            }
        }
        let info = (opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst).rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let raw = ctx.makeImage() else { return nil }
        // Written as is (8-bit sRGB): a conversion to another space or depth would round
        // the framebuffer's values.
        return UIImage(cgImage: raw, scale: scale, orientation: .up)
    }
}

/// System UI a device composites over the app (SpringBoard's status bar), drawn in-process with
/// UIKit's own views so materials behind it (Liquid Glass) see the same pixels.
@_silgen_name("swiftshot_set_exclusion_rect") func swiftshot_set_exclusion_rect(_ rect: CGRect)
@_silgen_name("swiftshot_install_exclusion_area") func swiftshot_install_exclusion_area()

@MainActor
enum SystemChrome {
    typealias Apply = @convention(c) (UIView) -> Void
    static let apply: Apply? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_apply_status_bar_data").map { unsafeBitCast($0, to: Apply.self) }

    typealias MakeSpec = @convention(c) (NSDictionary, CGRect, UIScreen) -> UIView?
    static let makeSpec: MakeSpec? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_make_status_bar_spec").map { unsafeBitCast($0, to: MakeSpec.self) }

    /// SpringBoard's own status bar (SystemStatusUI), with what `simctl status_bar override`
    /// shows in --mode device: 9:41, full Wi-Fi and cellular bars, a charged battery. Its visual
    /// provider is picked for the screen like on a device and lays out around the island.
    static var spec: NSDictionary { [
        "framework": "/System/Library/PrivateFrameworks/SystemStatusUI.framework/SystemStatusUI",
        "barClass": "STUIStatusBar", "dataClass": "STMutableStatusBarData", "avoidExclusionArea": true,
        "entries": [
            "timeEntry": ["class": "STStatusBarDataStringEntry", "stringValue": clock.time],
            "shortTimeEntry": ["class": "STStatusBarDataStringEntry", "stringValue": clock.time],
            "dateEntry": ["class": "STStatusBarDataStringEntry", "stringValue": clock.date],
            "cellularEntry": ["class": "STStatusBarDataCellularEntry", "status": 5, "rawValue": 4, "displayValue": 4, "type": 5],
            "wifiEntry": ["class": "STStatusBarDataWifiEntry", "status": 5, "rawValue": 3, "displayValue": 3, "type": 0],
            "mainBatteryEntry": ["class": "STStatusBarDataBatteryEntry", "capacity": 100, "state": 2],
        ] as NSDictionary,
    ] }

    /// 9:41 on Tuesday 9 January 2007 (what --mode device overrides the simulator to), formatted
    /// like SpringBoard does with the Mac's locale (a simulator's): "9:41" or "09:41", no AM/PM.
    static var job: Job?
    static var clock: (time: String, date: String) {
        let locale = Locale(identifier: job?.statusBarLocale ?? "en_US")
        let zone = job?.statusBarTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let date = cal.date(from: DateComponents(year: 2007, month: 1, day: 9, hour: 9, minute: 41))!
        let f = DateFormatter(); f.locale = locale; f.timeZone = zone
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "h:mm"
        f.dateFormat = pattern.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        let time = f.string(from: date)
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEdMMM", options: 0, locale: locale) ?? "EEE d MMM"
        return (time, f.string(from: date).replacingOccurrences(of: ",", with: ""))
    }

    /// The spec with the visual provider SpringBoard picks for the rendered screen (island,
    /// notch…), asked for each device: a bar would keep the first one it saw in this process.
    static func specForScreen() -> NSDictionary {
        dlopen(spec["framework"] as! String, RTLD_NOW)
        guard let cls = NSClassFromString("STUIStatusBarVisualProvider_iOS") else { return spec }
        let sel = NSSelectorFromString("visualProviderSubclassForScreen:visualProviderInfo:")
        guard let m = class_getClassMethod(cls, sel) else { return spec }
        typealias Pick = @convention(c) (AnyClass, Selector, UIScreen, NSDictionary?) -> AnyClass?
        guard let picked = unsafeBitCast(method_getImplementation(m), to: Pick.self)(cls, sel, UIScreen.main, nil) else { return spec }
        let result = spec.mutableCopy() as! NSMutableDictionary
        result["provider"] = NSStringFromClass(picked)
        return result
    }

    /// The status bar a device shows over this window, laid out and styled; nil where none shows
    /// (landscape iPhones) or the runtime has no SpringBoard status bar.
    /// A window like the app's (frame, traits, safe area) holding the status bar and home
    /// indicator; nil where a device shows neither.
    static func chrome(over window: UIWindow, root: UIViewController, size: CGSize) -> UIWindow? {
        guard NoBoot.enabled, NoBoot.screen?.idiom == "phone" else { return nil }
        let chrome = window.windowScene.map { DeviceWindow(windowScene: $0) } ?? DeviceWindow(frame: window.frame)
        chrome.frame = window.frame
        chrome.overrideUserInterfaceStyle = window.traitCollection.userInterfaceStyle
        chrome.forcedSafeArea = window.safeAreaInsets
        chrome.isHidden = false
        chrome.isUserInteractionEnabled = false
        let bar = statusBar(over: window, root: root, size: size, in: chrome)
        let pill = homeIndicator(over: window, size: size, in: chrome)
        guard bar != nil || pill != nil else { chrome.isHidden = true; return nil }
        chrome.layoutIfNeeded()
        return chrome
    }

    static func statusBar(over window: UIWindow, root: UIViewController, size: CGSize, in chrome: UIWindow) -> UIView? {
        // iPhones only for now: an iPad's bar also shows the date and the app's menu bar.
        guard size.width < size.height, let first = makeBar(over: chrome, width: size.width, height: window.safeAreaInsets.top) else { return nil }
        let container = UIView(frame: first.frame)
        container.isUserInteractionEnabled = false
        chrome.addSubview(container)
        container.addSubview(first)
        // 0: the default (dark glyphs in light mode, light in dark mode). Where the regions differ
        // (iOS 26), SpringBoard's automatic style is in charge and its default side is the
        // automatic dark one (3).
        let decided = self.styles(for: first, over: window, root: root)
        let split = Set(decided.map { $0 ?? 0 }).count > 1
        let styles = decided.map { $0 ?? (split ? (window.traitCollection.userInterfaceStyle == .dark ? 1 : 3) : 0) }
        if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { log("status bar styles \(decided) -> \(styles)") }
        first.setValue(styles.first ?? 0, forKey: "style"); first.layoutIfNeeded()
        if let leading = styles.first, let trailing = styles.last, leading != trailing, let second = makeBar(over: chrome, width: size.width, height: window.safeAreaInsets.top) {
            // iOS 26 styles the regions either side of the island on their own: a bar per style,
            // each shown on its side.
            container.addSubview(second)
            second.setValue(trailing, forKey: "style"); second.layoutIfNeeded()
            let mid = (NoBoot.screen?.display?.exclusionArea).flatMap { $0.count == 4 ? $0[0] + $0[2] / 2 : nil } ?? size.width / 2
            for (bar, rect) in [(first, CGRect(x: 0, y: 0, width: mid, height: container.bounds.height)),
                                (second, CGRect(x: mid, y: 0, width: size.width - mid, height: container.bounds.height))] {
                let mask = CALayer(); mask.frame = rect; mask.backgroundColor = UIColor.black.cgColor
                bar.layer.mask = mask
            }
        }
        for bar in container.subviews { bar.isHidden = false }
        // Style changes are applied on the next run-loop pass.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        for bar in container.subviews { bar.layoutIfNeeded() }
        return container
    }

    /// One SpringBoard status bar with its data applied, hidden, in the window.
    static func makeBar(over window: UIWindow, width: CGFloat, height: CGFloat) -> UIView? {
        guard let makeSpec, let bar = makeSpec(specForScreen(), CGRect(origin: .zero, size: CGSize(width: width, height: height)), UIScreen.main) else { return nil }
        bar.isHidden = true
        window.addSubview(bar)
        bar.layoutIfNeeded()
        // The style is decided here (styles(for:)); the bar's own luma tracking would decide late
        // and from a partly drawn screen.
        let pause = NSSelectorFromString("setPaused:")
        typealias Pause = @convention(c) (AnyObject, Selector, Bool) -> Void
        func pauseLuma(_ v: UIView) {
            if NSStringFromClass(type(of: v)).contains("LumaTracking"), v.responds(to: pause) { unsafeBitCast(class_getMethodImplementation(type(of: v), pause), to: Pause.self)(v, pause, true) }
            v.subviews.forEach(pauseLuma)
        }
        pauseLuma(bar)
        if let provider = bar.value(forKey: "visualProvider") as AnyObject?, provider.responds(to: NSSelectorFromString("lumaTrackingGroup")),
           let group = provider.value(forKey: "lumaTrackingGroup") as AnyObject?, group.responds(to: pause) {
            unsafeBitCast(class_getMethodImplementation(type(of: group), pause), to: Pause.self)(group, pause, true)
        }
        apply?(bar)
        // Its data update is applied (aggregated) on the next run-loop passes.
        let until = Date().addingTimeInterval(0.25)
        while Date() < until && bar.subviews.first?.subviews.allSatisfy({ $0.subviews.isEmpty }) ?? true { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        bar.layoutIfNeeded()
        if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { log("status bar provider \(bar.value(forKey: "visualProviderClassName") ?? "-")") }
        return bar
    }

    /// SpringBoard's home indicator (MaterialKit's luma-dodge pill) on screens that have one.
    static func homeIndicator(over window: UIWindow, size: CGSize, in chrome: UIWindow) -> UIView? {
        guard window.safeAreaInsets.bottom > 0 else { return nil }
        dlopen("/System/Library/PrivateFrameworks/MaterialKit.framework/MaterialKit", RTLD_NOW)
        guard let cls = NSClassFromString("MTLumaDodgePillView") as? UIView.Type else { return nil }
        let pill = cls.init(frame: .zero)
        // Sized and spaced like SpringBoard asks for (iOS 27 takes the screen, iOS 26 doesn't).
        typealias SizeForScreen = @convention(c) (AnyObject, Selector, CGFloat, UIScreen) -> CGSize
        typealias SizeFor = @convention(c) (AnyObject, Selector, CGFloat) -> CGSize
        typealias SpacingForScreen = @convention(c) (AnyObject, Selector, UIScreen) -> CGFloat
        typealias Spacing = @convention(c) (AnyObject, Selector) -> CGFloat
        let sizeScreenSel = NSSelectorFromString("suggestedSizeForContentWidth:screen:"), sizeSel = NSSelectorFromString("suggestedSizeForContentWidth:")
        let spaceScreenSel = NSSelectorFromString("suggestedEdgeSpacingForScreen:"), spaceSel = NSSelectorFromString("suggestedEdgeSpacing")
        let pillSize: CGSize, spacing: CGFloat
        if pill.responds(to: sizeScreenSel) { pillSize = unsafeBitCast(class_getMethodImplementation(cls, sizeScreenSel), to: SizeForScreen.self)(pill, sizeScreenSel, size.width, UIScreen.main) }
        else if pill.responds(to: sizeSel) { pillSize = unsafeBitCast(class_getMethodImplementation(cls, sizeSel), to: SizeFor.self)(pill, sizeSel, size.width) }
        else { return nil }
        if pill.responds(to: spaceScreenSel) { spacing = unsafeBitCast(class_getMethodImplementation(cls, spaceScreenSel), to: SpacingForScreen.self)(pill, spaceScreenSel, UIScreen.main) }
        else if pill.responds(to: spaceSel) { spacing = unsafeBitCast(class_getMethodImplementation(cls, spaceSel), to: Spacing.self)(pill, spaceSel) }
        else { return nil }
        let scale = UIScreen.main.scale   // centred on a whole pixel, like SpringBoard's
        pill.frame = CGRect(x: ((size.width - pillSize.width) / 2 * scale).rounded() / scale, y: size.height - spacing - pillSize.height, width: pillSize.width, height: pillSize.height)
        pill.setValue(3, forKey: "style")   // adaptive: the luma-dodge filter lightens or darkens what's under it
        chrome.addSubview(pill)
        return pill
    }

    /// The app's explicit status bar style, else SpringBoard's automatic one: light glyphs over
    /// dark content and dark over light, judged by the luma under the bar's luma regions with the
    /// bar's own transition boundaries (between them the default stays: nil). One style for the
    /// bar, or one per region (leading to trailing) where they differ (iOS 26).
    static func styles(for bar: UIView, over window: UIWindow, root: UIViewController) -> [Int?] {
        var vc = root
        while let next = vc.presentedViewController.flatMap({ $0.modalPresentationCapturesStatusBarAppearance ? $0 : nil }) ?? vc.childForStatusBarStyle { vc = next }
        switch vc.preferredStatusBarStyle {
        case .lightContent: return [1]
        case .darkContent: return [3]
        default: break
        }
        let auto = NSSelectorFromString("_useAutomaticStyle")
        typealias Flag = @convention(c) (AnyObject, Selector) -> Bool
        guard bar.responds(to: auto), unsafeBitCast(class_getMethodImplementation(type(of: bar), auto), to: Flag.self)(bar, auto),
              let provider = bar.value(forKey: "visualProvider") as AnyObject? else { return [nil] }
        let views = ["leadingBackgroundLumaView", "centerBackgroundLumaView", "trailingBackgroundLumaView"]
            .compactMap { provider.responds(to: NSSelectorFromString($0)) ? provider.value(forKey: $0) as? UIView : nil }
        guard !views.isEmpty else { return [nil] }
        var lower = 0.4, upper = 0.7
        if let bounds = views[0].value(forKey: "transitionBoundaries") as? NSValue {
            var pair = (0.0, 0.0); bounds.getValue(&pair, size: MemoryLayout<(Double, Double)>.size); (lower, upper) = pair
        }
        let lumas = views.map { luminance(of: window, in: $0.convert($0.bounds, to: window)) }
        if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { log("status bar luma \(lumas) bounds \(lower)…\(upper)") }
        func style(_ luma: Double) -> Int? { luma < lower ? 1 : luma > upper ? 3 : nil }
        // iOS 27 decides for the whole bar by the regions' mean; iOS 26 per region (measured
        // against booted simulators on both).
        let major = Int(job?.runtime.split(separator: ".").first ?? "27") ?? 27
        if major >= 27 { return [style(lumas.reduce(0, +) / Double(lumas.count))] }
        return lumas.map(style)
    }

    /// Average Rec. 709 luma (0…1) of what the window shows in `rect`.
    static func luminance(of window: UIWindow, in rect: CGRect) -> Double {
        let w = max(1, Int(rect.width)), h = max(1, Int(rect.height))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 1 }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        window.layer.render(in: ctx)
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) { sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2]) }
        return sum / Double(w * h) / 255
    }
}

/// Captures like a device: Core Animation's window server (the code backboardd composites the
/// screen with) runs inside this process on a display Agent/FakeDisplay.c provides, the window's
/// layer tree reaches it through a remote context like an app's windows do, and the frame it
/// presents is the framebuffer `simctl io screenshot` would save. The swiftshot CLI sets
/// CA_FORCE_LOCAL_SERVER so remote contexts connect to this in-process server.
@MainActor
enum ServerCapture {
    static let enabled = NoBoot.enabled && getenv("CA_FORCE_LOCAL_SERVER") != nil
    typealias Wait = @convention(c) (Int32, UInt64, Double, UnsafeMutablePointer<UInt64>?) -> Unmanaged<IOSurfaceRef>?
    typealias Resize = @convention(c) (Int32, UInt32, UInt32) -> Bool
    static let wait: Wait? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_fb_wait").map { unsafeBitCast($0, to: Wait.self) }
    static let resize: Resize? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_fb_resize").map { unsafeBitCast($0, to: Resize.self) }
    static var context: NSObject?
    static var windowContext: NSObject?
    /// Shown over the window being captured, from its own context (SpringBoard's status bar).
    static var chrome: UIWindow?
    static var chromeContext: NSObject?
    static var display: NSObject?
    static var started = false
    static var warmedUp = false
    static var timings: [String] = []

    static func constant(_ name: String) -> NSString? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { $0.assumingMemoryBound(to: NSString.self).pointee }
    }

    static func start(width: Int, height: Int) -> NSObject? {
        if started { return context }
        started = true
        setenv("SWIFTSHOT_DISPLAYS", "\(width)x\(height)@460", 1)
        guard let cls = NSClassFromString("CAWindowServer") as? NSObject.Type,
              let server = cls.perform(NSSelectorFromString("server"))?.takeUnretainedValue() as? NSObject,
              let display = (server.value(forKey: "displays") as? [NSObject])?.first,
              let id = display.value(forKey: "displayId") as? NSNumber,
              let contextClass = NSClassFromString("CAContext") as? NSObject.Type else { log("server capture: no window server"); return nil }
        let options: NSDictionary = [constant("kCAContextDisplayId") ?? "displayId": id, constant("kCAContextDisplayable") ?? "displayable": true]
        context = contextClass.perform(NSSelectorFromString("remoteContextWithOptions:"), with: options)?.takeUnretainedValue() as? NSObject
        // The window's own layer tree goes into a context that isn't shown; the shown one hosts
        // it scaled (CALayerHost), like SpringBoard hosts an app's windows. A scale transform on
        // the window's layer itself would reach UIKit's coordinate conversions.
        windowContext = contextClass.perform(NSSelectorFromString("remoteContextWithOptions:"), with: NSDictionary())?.takeUnretainedValue() as? NSObject
        chromeContext = contextClass.perform(NSSelectorFromString("remoteContextWithOptions:"), with: NSDictionary())?.takeUnretainedValue() as? NSObject
        if context == nil || windowContext == nil { log("server capture: no context") }
        self.display = display
        return context
    }

    /// Sizes the display to the capture, like a device's panel (blurs and shadows clamp at its edges).
    static func fit(width: Int, height: Int, scale: CGFloat) -> Bool {
        guard let display, let resize, resize(0, UInt32(width), UInt32(height)) else { return false }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let b = (display.value(forKey: "bounds") as? NSValue)?.cgRectValue,
               (Int(b.width) == width && Int(b.height) == height) || (Int((b.width * scale).rounded()) == width && Int((b.height * scale).rounded()) == height) {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        log("server capture: display did not resize to \(width)x\(height)")
        return false
    }

    /// The next presented frame of the capture's size, or nil after `timeout`.
    static func frame(after: inout UInt64, width: Int, height: Int, timeout: Double) -> IOSurfaceRef? {
        guard let wait else { return nil }
        var frame: UInt64 = 0
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let s = wait(0, after, 0.004, &frame) {
                after = frame
                let surface = s.takeRetainedValue()
                if IOSurfaceGetWidth(surface) == width && IOSurfaceGetHeight(surface) == height { return surface }
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        } while Date() < deadline
        return nil
    }

    static func image(of window: UIWindow, size: CGSize, scale: CGFloat, opaque: Bool) -> UIImage? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let t0 = Date()
        // The window server keeps material (Liquid Glass) adaptation on the display: an alert's
        // dimming would bleed into the next preview's glass for seconds, where a device's
        // screenshot shows it settled. Resizing the display starts each capture afresh.
        if started { _ = fit(width: w, height: h - 2, scale: scale) }
        guard start(width: w, height: h) != nil, fit(width: w, height: h, scale: scale) else { return nil }
        let tFit = Date()
        defer {
            // Slow captures point at the machine's GPU / window server (CI VMs): say where.
            let total = Date().timeIntervalSince(t0)
            if total > 0.5 { log("warning: slow capture \(w)x\(h): \(Int(total * 1000)) ms (display resize \(Int(tFit.timeIntervalSince(t0) * 1000)) ms, \(timings.map { "\($0)" }.joined(separator: ", ")))") }
            timings = []
        }
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard opaque else {
            // The framebuffer has no alpha: composite over black and over white, and take
            // coverage from the difference (out = colour + (1 - alpha) * background).
            guard var black = settled(window, w, h, scale, background: .black), let white = pixels(of: window, w, h, scale, background: .white) else { return nil }
            for i in stride(from: 0, to: black.count, by: 4) {
                let alpha = 255 - min(255, max(0, Int(white[i + 1]) - Int(black[i + 1])))
                black[i + 3] = UInt8(alpha)
                if alpha == 0 { black[i] = 0; black[i + 1] = 0; black[i + 2] = 0 } else {
                    for k in 0..<3 { black[i + k] = min(black[i + k], UInt8(alpha)) }
                }
            }
            let premultiplied = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let ctx = CGContext(data: &black, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: premultiplied),
                  let raw = ctx.makeImage() else { return nil }
            return UIImage(cgImage: raw, scale: scale, orientation: .up)
        }
        // Shown until two consecutive frames agree: materials (Liquid Glass) adapt to what the
        // server composited under them, as on a device where the screen has been visible for a
        // moment (one extra pass on a fast Mac, more on a slow CI GPU).
        // The process's first frame compiles shaders (half a second, more on CI); glass that
        // first saw the screen then settles a hair differently. Show the first window once
        // and start over from fresh display state.
        if !warmedUp {
            warmedUp = true
            _ = settled(window, w, h, scale, background: nil)
            _ = fit(width: w, height: h - 2, scale: scale); _ = fit(width: w, height: h, scale: scale)
        }
        guard var bytes = settled(window, w, h, scale, background: nil) else { return nil }
        if h > w, NoBoot.screen?.idiom == "phone", let area = NoBoot.screen?.display?.exclusionArea, area.count == 4, area[1] > 0 { addCornerMark(&bytes, width: w) }
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
              let raw = ctx.makeImage() else { return nil }
        // The framebuffer's bytes as they are: what `simctl io screenshot` saves.
        return UIImage(cgImage: raw, scale: scale, orientation: .up)
    }

    static func settled(_ window: UIWindow, _ w: Int, _ h: Int, _ scale: CGFloat, background: UIColor?) -> [UInt8]? {
        guard var last = pixels(of: window, w, h, scale, background: background) else { return nil }
        for _ in 0..<4 {
            guard let next = pixels(of: window, w, h, scale, background: background) else { return nil }
            if next == last { return next }
            last = next
        }
        return last
    }

    /// A portrait iPhone with a Dynamic Island (or the Duo's camera cut-out) has a black 3¼ px
    /// square over its top-left pixels in every simulator screenshot (home screen too; the system
    /// aperture's), blended in sRGB. Notch phones don't.
    static func addCornerMark(_ bytes: inout [UInt8], width w: Int) {
        for y in 0...3 { for x in 0...3 {
            let factor = x < 3 && y < 3 ? 0 : x == 3 && y == 3 ? 239 : 191
            let i = (y * w + x) * 4
            for k in 0..<3 { bytes[i + k] = UInt8((Int(bytes[i + k]) * factor + 127) / 255) }
        } }
    }

    /// One composited frame of the window (BGRA rows, w × h).
    static func pixels(of window: UIWindow, _ w: Int, _ h: Int, _ scale: CGFloat, background: UIColor?) -> [UInt8]? {
        guard let context, let windowContext, let wait, let hostClass = NSClassFromString("CALayerHost") as? CALayer.Type else { return nil }
        let layer = window.layer
        let saved = (layer.superlayer, layer.anchorPoint, layer.position)
        // The window's layer as the root of its own context, at its own geometry (points)…
        let windowRoot = CALayer()
        windowRoot.frame = CGRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        windowRoot.addSublayer(layer)
        layer.anchorPoint = .zero; layer.position = .zero
        windowContext.setValue(windowRoot, forKey: "layer")
        // …hosted at the device's scale on the display.
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = background?.cgColor
        let host = hostClass.init()
        host.setValue(windowContext.value(forKey: "contextId"), forKey: "contextId")
        host.anchorPoint = .zero; host.position = .zero
        host.bounds = windowRoot.frame
        host.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        root.addSublayer(host)
        // The chrome window the same way, above.
        let chromeLayer = chrome?.layer
        let chromeSaved = (chromeLayer?.superlayer, chromeLayer?.anchorPoint ?? .zero, chromeLayer?.position ?? .zero)
        if let chromeLayer, let chromeContext {
            let chromeRoot = CALayer()
            chromeRoot.frame = windowRoot.frame
            chromeRoot.addSublayer(chromeLayer)
            chromeLayer.anchorPoint = .zero; chromeLayer.position = .zero
            chromeContext.setValue(chromeRoot, forKey: "layer")
            let chromeHost = hostClass.init()
            chromeHost.setValue(chromeContext.value(forKey: "contextId"), forKey: "contextId")
            chromeHost.anchorPoint = .zero; chromeHost.position = .zero
            chromeHost.bounds = windowRoot.frame
            chromeHost.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            root.addSublayer(chromeHost)
        }
        defer {
            context.setValue(nil, forKey: "layer")
            windowContext.setValue(nil, forKey: "layer")
            if let chromeLayer {
                chromeContext?.setValue(nil, forKey: "layer")
                chromeLayer.removeFromSuperlayer()
                chromeLayer.anchorPoint = chromeSaved.1; chromeLayer.position = chromeSaved.2
                chromeSaved.0?.addSublayer(chromeLayer)
            }
            CATransaction.flush()
            layer.removeFromSuperlayer()
            layer.anchorPoint = saved.1; layer.position = saved.2
            saved.0?.addSublayer(layer)
        }
        var seen: UInt64 = 0
        _ = wait(0, UInt64.max - 1, 0, &seen)
        context.setValue(root, forKey: "layer")
        CATransaction.flush()
        // The first frame with the commit, then the last one before the server goes idle
        // (implicit animations, materials settling), as a device would show it.
        let shown = Date()
        // The first frame can take seconds on a CI VM's paravirtual GPU (shaders compiling).
        guard var surface = frame(after: &seen, width: w, height: h, timeout: 20) else { log("server capture: no frame"); return nil }
        let first = Date()
        var frames = 1
        // Idle = no new frame for three gaps of half the time this machine took to present the
        // first one (a CI VM's GPU can take far longer than a display frame).
        let gap = max(0.016, first.timeIntervalSince(shown) * 0.5)
        var quiet = 0
        let idle = Date().addingTimeInterval(max(1, gap * 10))
        while quiet < 3 && Date() < idle {
            if let next = frame(after: &seen, width: w, height: h, timeout: gap) { surface = next; quiet = 0; frames += 1 } else { quiet += 1 }
        }
        timings.append("pass: first frame \(Int(first.timeIntervalSince(shown) * 1000)) ms, idle after \(Int(Date().timeIntervalSince(first) * 1000)) ms, \(frames) frames")
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let stride = IOSurfaceGetBytesPerRow(surface), base = IOSurfaceGetBaseAddress(surface)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buf in for y in 0..<h { memcpy(buf.baseAddress! + y * w * 4, base + y * stride, w * 4) } }
        return bytes
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
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let statusBar = scene?.statusBarManager
        func cornerInsets() -> [Double]? {
            guard let window = scene?.windows.first, window.responds(to: NSSelectorFromString("_sceneSafeAreaCornerInsets")),
                  let value = window.value(forKey: "_sceneSafeAreaCornerInsets") as? NSValue else { return nil }
            var d = [Double](repeating: 0, count: 8)
            value.getValue(&d, size: 64)
            return d.allSatisfy { $0 == 0 } ? nil : d
        }
        func exclusionArea() -> [Double]? {
            guard screen.responds(to: NSSelectorFromString("_exclusionArea")), let shape = screen.value(forKey: "_exclusionArea") as AnyObject?,
                  shape.responds(to: NSSelectorFromString("rect")), let r = (shape.value(forKey: "rect") as? NSValue)?.cgRectValue, !r.isEmpty else { return nil }
            return [r.minX, r.minY, r.width, r.height]
        }
        func barPosition() -> [Double]? {
            guard let position = scene?.traitCollection.value(forKey: "_sceneBarPosition") as AnyObject?,
                  let insets = (position.value(forKey: "barAlignmentInsets") as? NSValue)?.uiEdgeInsetsValue, insets.top.isFinite else { return nil }
            let classes = ["topBarSizeClass", "bottomBarSizeClass", "leadingBarSizeClass", "trailingBarSizeClass"].map { (position.value(forKey: $0) as? Double) ?? 0 }
            return [insets.top, insets.left, insets.bottom, insets.right] + classes
        }
        func sceneTrait(_ name: String) -> Int? {
            guard let traits = scene?.traitCollection, let trait = NSClassFromString(name) else { return nil }
            let sel = NSSelectorFromString("valueForNSIntegerTrait:")
            guard traits.responds(to: sel) else { return nil }
            typealias Get = @convention(c) (AnyObject, Selector, AnyClass) -> Int
            return unsafeBitCast(class_getMethodImplementation(type(of: traits), sel), to: Get.self)(traits, sel, trait)
        }
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
            screenDisplayPeriphery: insets(screen.value(forKey: "_displayPeripheryInsets")),
            statusBarAxis: statusBar.flatMap { $0.responds(to: NSSelectorFromString("statusBarAxis")) ? ($0.value(forKey: "statusBarAxis") as? Int) : nil },
            statusBarFrameHeight: statusBar.map { Double($0.statusBarFrame.height) },
            statusBarHeight: statusBar.flatMap { $0.responds(to: NSSelectorFromString("statusBarHeight")) ? ($0.value(forKey: "statusBarHeight") as? Double) : nil },
            verticalBarAllowed: sceneTrait("_UITraitSystemVerticalBarAllowed"),
            verticalBarEdge: sceneTrait("_UITraitSystemVerticalBarHorizontalEdge"),
            cornerInsets: cornerInsets(),
            barPosition: barPosition(),
            exclusionArea: exclusionArea())
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

    /// Where the system status bar is (iPhone Duo on iOS 27.1: a side rail) changes navigation bar
    /// layout; report the rendered device's, as its booted simulator does.
    static func installStatusBar() {
        let axis: @convention(block) (AnyObject) -> Int = { _ in screen?.display?.statusBarAxis ?? -1 }
        if let m = class_getInstanceMethod(UIStatusBarManager.self, NSSelectorFromString("statusBarAxis")) { method_setImplementation(m, imp_implementationWithBlock(axis)) }
        let frame: @convention(block) (AnyObject) -> CGRect = { _ in
            guard let h = screen?.display?.statusBarFrameHeight else { return .zero }
            return CGRect(x: 0, y: 0, width: screen?.width ?? 0, height: h)
        }
        if let m = class_getInstanceMethod(UIStatusBarManager.self, #selector(getter: UIStatusBarManager.statusBarFrame)) { method_setImplementation(m, imp_implementationWithBlock(frame)) }
        let defaultSel = NSSelectorFromString("defaultStatusBarHeightInOrientation:")
        if let m = class_getInstanceMethod(UIStatusBarManager.self, defaultSel) {
            typealias Height = @convention(c) (AnyObject, Selector, Int) -> CGFloat
            let original = unsafeBitCast(method_getImplementation(m), to: Height.self)
            let block: @convention(block) (AnyObject, Int) -> CGFloat = { m, o in screen?.display?.statusBarFrameHeight.map { CGFloat($0) } ?? original(m, defaultSel, o) }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        let heightSel = NSSelectorFromString("statusBarHeight")
        if let m = class_getInstanceMethod(UIStatusBarManager.self, heightSel) {
            typealias Height = @convention(c) (AnyObject, Selector) -> CGFloat
            let original = unsafeBitCast(method_getImplementation(m), to: Height.self)
            let block: @convention(block) (AnyObject) -> CGFloat = { m in screen?.display?.statusBarHeight.map { CGFloat($0) } ?? original(m, heightSel) }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // The scene-level insets UIKit's bars lay out by (a booted scene resolves them per status
        // bar axis): the device window's safe area, plus the status bar when asked to include it.
        typealias Insets0 = @convention(c) (AnyObject, Selector) -> UIEdgeInsets
        typealias Insets1 = @convention(c) (AnyObject, Selector, Bool) -> UIEdgeInsets
        let normalizedSel = NSSelectorFromString("_normalizedSafeAreaInsets")
        if let m = class_getInstanceMethod(UIWindow.self, normalizedSel) {
            let original = unsafeBitCast(method_getImplementation(m), to: Insets0.self)
            let block: @convention(block) (AnyObject) -> UIEdgeInsets = { w in (w as? DeviceWindow)?.forcedSafeArea ?? original(w, normalizedSel) }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // A device window fills its scene, so all its edges line up with the scene's safe area.
        let alignedSel = NSSelectorFromString("_sceneSafeAreaAlignedEdgesForFrame:inSuperview:ignoreViewController:")
        if let m = class_getInstanceMethod(UIWindow.self, alignedSel) {
            typealias Aligned = @convention(c) (AnyObject, Selector, CGRect, AnyObject?, Bool) -> UInt
            let original = unsafeBitCast(method_getImplementation(m), to: Aligned.self)
            let block: @convention(block) (AnyObject, CGRect, AnyObject?, Bool) -> UInt = { w, frame, superview, ignore in
                w is DeviceWindow ? UIRectEdge.all.rawValue : original(w, alignedSel, frame, superview, ignore)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        let fullSel = NSSelectorFromString("_sceneSafeAreaInsetsIncludingStatusBar:statusBarAxis:statusBarVisibility:")
        if let m = class_getInstanceMethod(UIWindow.self, fullSel) {
            typealias Insets3 = @convention(c) (AnyObject, Selector, Bool, Int, Int) -> UIEdgeInsets
            let original = unsafeBitCast(method_getImplementation(m), to: Insets3.self)
            let block: @convention(block) (AnyObject, Bool, Int, Int) -> UIEdgeInsets = { w, statusBar, axis, visibility in
                guard let display = screen?.display, let railAxis = display.statusBarAxis, var insets = (w as? DeviceWindow)?.forcedSafeArea else { return original(w, fullSel, statusBar, axis, visibility) }
                // Asked for another axis (a sheet lays out with a horizontal status bar): the
                // display's own safe area, without the rail.
                if axis != railAxis {
                    let p = display.safeAreaPortrait
                    return UIEdgeInsets(top: p.top, left: p.left, bottom: p.bottom, right: p.right)
                }
                if statusBar { insets.top = max(insets.top, display.statusBarFrameHeight ?? 0) }
                return insets
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // The scene's own per-orientation insets (a booted scene resolves the status bar rail into them).
        func profileInsets(_ orientation: Int, hidden: Bool = false) -> UIEdgeInsets? {
            guard let display = screen?.display, display.statusBarAxis != nil, let p = screen else { return nil }
            // A hidden status bar takes its rail with it.
            if hidden { let d = display.safeAreaPortrait; return UIEdgeInsets(top: d.top, left: d.left, bottom: d.bottom, right: d.right) }
            let i = orientation >= 3 ? p.landscapeSafeArea : p.safeArea
            return UIEdgeInsets(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
        }
        for name in ["_safeAreaInsetsForInterfaceOrientation:", "_safeAreaInsetsForInterfaceOrientation:statusBarHidden:", "_safeAreaInsetsForInterfaceOrientation:statusBarHidden:statusBarAxis:"] {
            let sel = NSSelectorFromString(name)
            guard let m = class_getInstanceMethod(UIWindowScene.self, sel) else { continue }
            typealias Get = @convention(c) (AnyObject, Selector, Int, Bool, Int) -> UIEdgeInsets
            let original = unsafeBitCast(method_getImplementation(m), to: Get.self)
            let takesHidden = name.contains("statusBarHidden")
            let block: @convention(block) (AnyObject, Int, Bool, Int) -> UIEdgeInsets = { scene, o, hidden, axis in profileInsets(o, hidden: takesHidden && hidden) ?? original(scene, sel, o, hidden, axis) }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        let sceneSel = NSSelectorFromString("_sceneSafeAreaInsetsIncludingStatusBar:")
        if let m = class_getInstanceMethod(UIWindow.self, sceneSel) {
            let original = unsafeBitCast(method_getImplementation(m), to: Insets1.self)
            let block: @convention(block) (AnyObject, Bool) -> UIEdgeInsets = { w, statusBar in
                guard var insets = (w as? DeviceWindow)?.forcedSafeArea else { return original(w, sceneSel, statusBar) }
                if statusBar { insets.top = max(insets.top, screen?.display?.statusBarFrameHeight ?? 0) }
                return insets
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
    }

    @MainActor static func setVerticalBar(of display: DisplayInfo?, on window: UIWindow) {
        // The window's subtree, and the scene: system containers (the floating bar container)
        // take their traits from the scene.
        for holder in [window as NSObject, window.windowScene as NSObject?].compactMap({ $0 }) where holder.responds(to: NSSelectorFromString("traitOverrides")) {
            if let overrides = holder.value(forKey: "traitOverrides") as AnyObject? { applySceneTraits(of: display, to: overrides) }
        }
    }

    @MainActor static func applySceneTraits(of display: DisplayInfo?, to overrides: AnyObject) {
        let selector = NSSelectorFromString("setNSIntegerValue:forTrait:")
        guard let method = class_getInstanceMethod(type(of: overrides), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Int, AnyClass) -> Void
        let set = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        for (name, value) in [("_UITraitSystemVerticalBarAllowed", display?.verticalBarAllowed), ("_UITraitSystemVerticalBarHorizontalEdge", display?.verticalBarEdge)] {
            if let value, let trait = NSClassFromString(name) { set(overrides, selector, value, trait) }
        }
        // Where the scene's bars sit and how big they are (navigation bar metrics follow).
        let objectSelector = NSSelectorFromString("setObject:forTrait:")
        if let p = display?.barPosition, p.count == 8, let trait = NSClassFromString("_UITraitSceneBarPosition"),
           let cls = NSClassFromString("_UISceneBarResolvedPosition"), let objectSet = class_getInstanceMethod(type(of: overrides), objectSelector) {
            typealias Make = @convention(c) (AnyObject, Selector, UIEdgeInsets, Int, Int) -> AnyObject?
            let initSel = NSSelectorFromString("initWithAlignmentInsets:topBarSizeClass:bottomBarSizeClass:")
            guard let alloc = (cls as? NSObject.Type)?.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                  let position = unsafeBitCast(class_getMethodImplementation(cls, initSel), to: Make.self)(alloc, initSel, UIEdgeInsets(top: p[0], left: p[1], bottom: p[2], right: p[3]), Int(p[4]), Int(p[5])) else { return }
            typealias SetInt = @convention(c) (AnyObject, Selector, Int) -> Void
            for (name, value) in [("setLeadingBarSizeClass:", p[6]), ("setTrailingBarSizeClass:", p[7])] {
                let sel = NSSelectorFromString(name)
                unsafeBitCast(class_getMethodImplementation(cls, sel), to: SetInt.self)(position, sel, Int(value))
            }
            typealias SetObject = @convention(c) (AnyObject, Selector, AnyObject, AnyClass) -> Void
            unsafeBitCast(method_getImplementation(objectSet), to: SetObject.self)(overrides, objectSelector, position, trait)
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
        // Sheets switch to their vertical-bar metrics (floating, 8 pt margins…) when the scene's
        // bar-position component says the system provides vertical bars (iPhone Duo). That
        // component reads FrontBoard scene settings, which a scene without a simulator lacks.
        if let m = class_getInstanceMethod(UIScene.self, NSSelectorFromString("_barPositionClientComponent")) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> AnyObject?
            let original = unsafeBitCast(method_getImplementation(m), to: Getter.self), sel = method_getName(m)
            let block: @convention(block) (AnyObject) -> AnyObject? = { scene in
                (screen?.display?.verticalBarAllowed ?? 0) != 0 ? VerticalBarComponent.shared : original(scene, sel)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // Per-corner display radii come from the scene settings (FrontBoard fills them in); the
        // window's bounding path, and the sheets concentric with it, follow them.
        for name in ["UIApplicationSceneSettings", "UIMutableApplicationSceneSettings"] {
            guard let cls = NSClassFromString(name), let m = class_getInstanceMethod(cls, NSSelectorFromString("cornerRadiusConfiguration")),
                  let config = NSClassFromString("BSCornerRadiusConfiguration") else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> AnyObject?
            typealias Make = @convention(c) (AnyObject, Selector, Double, Double, Double, Double) -> AnyObject?
            let original = unsafeBitCast(method_getImplementation(m), to: Getter.self), sel = method_getName(m)
            let block: @convention(block) (AnyObject) -> AnyObject? = { settings in
                if let value = original(settings, sel) { return value }
                guard let r = screen?.cornerRadii, r.count == 4,
                      let alloc = (config as? NSObject.Type)?.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
                let initSel = NSSelectorFromString("initWithTopLeft:bottomLeft:bottomRight:topRight:")
                return unsafeBitCast(class_getMethodImplementation(config, initSel), to: Make.self)(alloc, initSel, r[0], r[1], r[2], r[3])
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
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
            ("_referenceBounds", bounds), ("_unjailedReferenceBounds", bounds), ("_mainSceneReferenceBounds", bounds), ("_nativeDisplayBounds", native),
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
        // End states, as --mode device captures them: presentations (sheets) land at their
        // detent instead of springing there.
        if ProcessInfo.processInfo.environment["SWIFTSHOT_ANIMATIONS"] == nil { UIView.setAnimationsEnabled(false) }
        installStatusBar()
        swiftshot_install_corner_insets()
        swiftshot_install_exclusion_area()
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
        let portraitFor: @convention(block) (AnyObject, AnyObject?) -> Int = { _, _ in UIInterfaceOrientation.portrait.rawValue }
        if let m = class_getInstanceMethod(UIApplication.self, NSSelectorFromString("_sceneInterfaceOrientationFromWindow:")) { method_setImplementation(m, imp_implementationWithBlock(portraitFor)) }
    }

    /// Without a display, nothing runs the layout passes a device would after its first frames: a
    /// presented controller (sheet, alert, dialog) keeps its initial frame and SwiftUI never builds
    /// its content, and the floating bar's buttons (iPhone Duo) only get their symbols on a later
    /// pass. Lay the window out until both have settled.
    static func finishLayout(of root: UIViewController, in window: UIWindow, settle: () -> Void) {
        func tree(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(tree) }
        let presenting = tree(root).filter { $0.presentedViewController != nil }
        // Presentation traits (vertical bar suppression…) were resolved before the container
        // settled; a device re-resolves them on its next scene update.
        for c in presenting {
            guard let pc = c.presentedViewController?.presentationController else { continue }
            let sel = NSSelectorFromString("_updateTraitsForPresentation")
            if pc.responds(to: sel) { pc.perform(sel) }
        }
        let floatingBar = (screen?.display?.verticalBarAllowed ?? 0) != 0
        for _ in 0..<(!presenting.isEmpty ? 3 : floatingBar ? 1 : 0) {
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
        // CARenderer draws into a bottom-up texture; the window server doesn't.
        if getenv("CA_FORCE_LOCAL_SERVER") == nil { swiftshot_flip_layer_drawing() }
        guard let global = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "UIApp")?.assumingMemoryBound(to: UnsafeMutableRawPointer?.self),
              global.pointee == nil, let app = class_createInstance(UIApplication.self, 0) as? NSObject else { return }
        global.pointee = Unmanaged.passRetained(app).toOpaque()
        _ = app.perform(NSSelectorFromString("init"))
    }
}

/// Stands in for a scene's bar-position component; UIKit only asks it this.
final class VerticalBarComponent: NSObject {
    static let shared = VerticalBarComponent()
    @objc func _systemProvidesVerticalBars() -> Bool { true }
}

/// A window that reports the *target* device's safe area instead of the host simulator's.
final class DeviceWindow: UIWindow {
    var forcedSafeArea: UIEdgeInsets = .zero {
        // UIKit caches which edges are aligned with the scene's safe area (bars and sheets lay out
        // by it) when the window's safe area is set; its updater is a direct method, so set it.
        didSet {
            let sel = NSSelectorFromString("setSafeAreaInsets:")
            typealias Set = @convention(c) (AnyObject, Selector, UIEdgeInsets) -> Void
            if let imp = class_getMethodImplementation(UIView.self, sel), responds(to: sel) { unsafeBitCast(imp, to: Set.self)(self, sel, forcedSafeArea) }
        }
    }
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
