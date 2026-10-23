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
                    if let corners = device.display?.cornerInsets, corners.count == 8 { corners.withUnsafeBufferPointer { swiftshot_set_corner_insets($0.baseAddress) } } else { swiftshot_set_corner_insets(nil) }
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
                    if ProcessInfo.processInfo.environment["SWIFTSHOT_DEBUG"] != nil { dumpPresentation(vc, window) }
                    if preview.layout.kind.isDevice && job.fullLength(for: preview.name) {
                        geo.size = growToContent(of: vc, in: window, size: geo.size, scale: device.scale, name: preview.name)
                    }
                    // The system status bar over the app, as a device shows it.
                    let statusBar = preview.layout.kind.isDevice && geo.size.width < geo.size.height ? SystemChrome.statusBar(width: geo.size.width, height: window.safeAreaInsets.top) : nil
                    if let statusBar {
                        window.addSubview(statusBar)
                        SystemChrome.apply?(statusBar)
                        // Its data update is applied (aggregated) on the next run-loop passes.
                        let until = Date().addingTimeInterval(0.25)
                        while Date() < until && statusBar.subviews.first?.subviews.allSatisfy({ $0.subviews.isEmpty }) ?? true { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
                        statusBar.layoutIfNeeded()
                    }
                    defer { statusBar?.removeFromSuperview() }
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
                    window.isHidden = true
                    window.rootViewController = nil
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
                  }
                }
            }
        }
    }

    func dumpPresentation(_ root: UIViewController, _ window: UIWindow) {
        func tree(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(tree) }
        log("window \(window.frame) safe \(window.safeAreaInsets) screen \(window.screen.bounds) subviews \(window.subviews.map { "\(type(of: $0)) \($0.frame) safe \($0.safeAreaInsets)" })")
        for c in tree(root) { guard let p = c.presentedViewController else { continue }
            var v: UIView? = p.view
            while let view = v { log("  \(type(of: view)) frame \(view.frame) safe \(view.safeAreaInsets)"); v = view.superview }
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
@MainActor
enum SystemChrome {
    typealias Apply = @convention(c) (UIView) -> Void
    static let apply: Apply? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_apply_status_bar_data").map { unsafeBitCast($0, to: Apply.self) }

    typealias MakeSpec = @convention(c) (NSDictionary, CGRect, UIScreen) -> UIView?
    static let makeSpec: MakeSpec? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swiftshot_make_status_bar_spec").map { unsafeBitCast($0, to: MakeSpec.self) }
    static let spec: NSDictionary? = ProcessInfo.processInfo.environment["SWIFTSHOT_STATUSBAR"].flatMap { try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: $0))) as? NSDictionary }

    static func statusBar(width: CGFloat, height: CGFloat) -> UIView? {
        guard NoBoot.enabled, let spec, let makeSpec else { return nil }
        let h = (spec["height"] as? CGFloat) ?? height
        return makeSpec(spec, CGRect(x: 0, y: 0, width: width, height: h), UIScreen.main)
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
    static var display: NSObject?
    static var started = false
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
        if context == nil { log("server capture: no context") }
        self.display = display
        return context
    }

    /// Sizes the display to the capture, like a device's panel (blurs and shadows clamp at its edges).
    static func fit(width: Int, height: Int) -> Bool {
        guard let display, let resize, resize(0, UInt32(width), UInt32(height)) else { return false }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let b = (display.value(forKey: "bounds") as? NSValue)?.cgRectValue, Int(b.width) == width, Int(b.height) == height { return true }
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
        guard start(width: w, height: h) != nil, fit(width: w, height: h) else { return nil }
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
        guard var bytes = settled(window, w, h, scale, background: nil),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
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

    /// One composited frame of the window (BGRA rows, w × h).
    static func pixels(of window: UIWindow, _ w: Int, _ h: Int, _ scale: CGFloat, background: UIColor?) -> [UInt8]? {
        guard let context, let wait else { return nil }
        // The window's layer under a pixel-sized root, at the device's scale, for the capture.
        let layer = window.layer
        let saved = (layer.superlayer, layer.anchorPoint, layer.position, layer.affineTransform())
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = background?.cgColor
        root.addSublayer(layer)
        layer.anchorPoint = .zero; layer.position = .zero
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        defer {
            context.setValue(nil, forKey: "layer")
            CATransaction.flush()
            layer.removeFromSuperlayer()
            layer.setAffineTransform(saved.3); layer.anchorPoint = saved.1; layer.position = saved.2
            saved.0?.addSublayer(layer)
        }
        var seen: UInt64 = 0
        _ = wait(0, UInt64.max - 1, 0, &seen)
        context.setValue(root, forKey: "layer")
        CATransaction.flush()
        // The first frame with the commit, then the last one before the server goes idle
        // (implicit animations, materials settling), as a device would show it.
        let shown = Date()
        guard var surface = frame(after: &seen, width: w, height: h, timeout: 2) else { log("server capture: no frame"); return nil }
        let first = Date()
        var frames = 1
        var quiet = 0
        let idle = Date().addingTimeInterval(1)
        while quiet < 3 && Date() < idle {
            if let next = frame(after: &seen, width: w, height: h, timeout: 0.016) { surface = next; quiet = 0; frames += 1 } else { quiet += 1 }
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
            barPosition: barPosition())
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
                guard screen?.display?.statusBarAxis != nil, var insets = (w as? DeviceWindow)?.forcedSafeArea else { return original(w, fullSel, statusBar, axis, visibility) }
                if statusBar { insets.top = max(insets.top, screen?.display?.statusBarFrameHeight ?? 0) }
                return insets
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        // The scene's own per-orientation insets (a booted scene resolves the status bar rail into them).
        func profileInsets(_ orientation: Int) -> UIEdgeInsets? {
            guard screen?.display?.statusBarAxis != nil, let p = screen else { return nil }
            let i = orientation >= 3 ? p.landscapeSafeArea : p.safeArea
            return UIEdgeInsets(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
        }
        for name in ["_safeAreaInsetsForInterfaceOrientation:", "_safeAreaInsetsForInterfaceOrientation:statusBarHidden:", "_safeAreaInsetsForInterfaceOrientation:statusBarHidden:statusBarAxis:"] {
            let sel = NSSelectorFromString(name)
            guard let m = class_getInstanceMethod(UIWindowScene.self, sel) else { continue }
            typealias Get = @convention(c) (AnyObject, Selector, Int, Bool, Int) -> UIEdgeInsets
            let original = unsafeBitCast(method_getImplementation(m), to: Get.self)
            let block: @convention(block) (AnyObject, Int, Bool, Int) -> UIEdgeInsets = { scene, o, hidden, axis in profileInsets(o) ?? original(scene, sel, o, hidden, axis) }
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
        guard let overrides = window.value(forKey: "traitOverrides") as AnyObject? else { return }
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
        installStatusBar()
        swiftshot_install_corner_insets()
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
        // CARenderer draws into a bottom-up texture; the window server doesn't.
        if getenv("CA_FORCE_LOCAL_SERVER") == nil { swiftshot_flip_layer_drawing() }
        guard let global = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "UIApp")?.assumingMemoryBound(to: UnsafeMutableRawPointer?.self),
              global.pointee == nil, let app = class_createInstance(UIApplication.self, 0) as? NSObject else { return }
        global.pointee = Unmanaged.passRetained(app).toOpaque()
        _ = app.perform(NSSelectorFromString("init"))
    }
}

/// A window that reports the *target* device's safe area instead of the host simulator's.
final class DeviceWindow: UIWindow {
    var forcedSafeArea: UIEdgeInsets = .zero {
        // UIKit caches which edges are aligned with the scene's safe area (bars lay out by it).
        didSet { if responds(to: NSSelectorFromString("_updateSceneSafeAreaAlignedEdges")) { perform(NSSelectorFromString("_updateSceneSafeAreaAlignedEdges")) } }
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
