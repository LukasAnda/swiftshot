// swiftshot agent: injected into the app under test with DYLD_INSERT_LIBRARIES.
// Once the app's first scene is active it takes the job described by $SWIFTSHOT_JOB,
// renders every requested preview, writes the images straight to the host file system
// (simulator processes share the Mac's file system) and terminates the app.

#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import ObjectiveC


@_cdecl("SwiftshotAgentStart")
public func SwiftshotAgentStart() {
    guard let jobPath = ProcessInfo.processInfo.environment["SWIFTSHOT_JOB"] else { return }
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
        result.calibration = DeviceProfile(
            name: job.devices.first?.name ?? UIDevice.current.name, idiom: isPad ? "pad" : "phone",
            width: width, height: height, scale: screen.scale,
            safeArea: portrait, landscapeSafeArea: landscape, cornerRadius: corner)
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

    func applyTraits(_ window: UIWindow, device: DeviceProfile, appearance: String, size: CGSize) {
        window.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        window.traitOverrides.displayScale = device.scale
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

    func fileName(preview: String, device: String, appearance: String) -> String {
        job.fileName(preview: preview, device: device, appearance: appearance)
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
        let useLayerRender = ProcessInfo.processInfo.environment["SWIFTSHOT_CAPTURE"] == "layer"
        // Off-screen so the window inherits no system safe area; we supply the device's instead.
        let offscreenOrigin = CGPoint(x: scene.screen.bounds.width * 4, y: scene.screen.bounds.height * 4)

        for preview in previews where job.wants(preview.name) {
            for device in job.devices where job.wants(preview.name, device: device.name) {
                for appearance in job.appearances(for: preview.name) {
                    let t0 = now()
                    DeviceIdiom.current = device.idiom == "pad" ? .pad : .phone
                    defer { DeviceIdiom.current = nil }
                    guard let vc = controller(fromBody: preview.body()) else {
                        result.errors.append("\(preview.name): could not build preview body"); continue
                    }
                    var geo = geometry(for: preview, on: device)
                    let window = DeviceWindow(windowScene: scene)
                    applyTraits(window, device: device, appearance: appearance, size: geo.size)

                    switch preview.layout.kind {
                    case .device:
                        window.forcedSafeArea = geo.safeArea
                    case .fixed(let w, let h):
                        geo.size = CGSize(width: w, height: h)
                    case .sizeThatFits:
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
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = device.scale
                    format.opaque = preview.layout.kind.isDevice
                    let bounds = CGRect(origin: .zero, size: geo.size)
                    let image = UIGraphicsImageRenderer(size: geo.size, format: format).image { ctx in
                        if useLayerRender {
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

                    let file = fileName(preview: preview.name, device: device.name, appearance: appearance)
                    store(image: output, record: ShotRecord(
                        preview: preview.name, device: device.name, appearance: appearance, language: job.language,
                        runtime: job.runtime, file: "\(job.language)/\(file)",
                        width: Int(output.size.width * output.scale), height: Int(output.size.height * output.scale),
                        renderMs: (now() - t0) * 1000))
                }
            }
        }
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
