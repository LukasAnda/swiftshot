// watchOS flavour of the agent. watchOS has no public window API and ImageRenderer can't draw
// watchOS platform views (List, NavigationStack…), so each preview is made the root of the app's
// real window (watchOS' private UIKit) and the host captures the watch screen. Discovery, the
// job/result protocol and file naming are shared with iOS.

#if os(watchOS)
import Foundation
import SwiftUI
import WatchKit
import Darwin

@_cdecl("SwiftshotAgentStart")
public func SwiftshotAgentStart() {
    guard let jobPath = ProcessInfo.processInfo.environment["SWIFTSHOT_JOB"] else { return }
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
            result.calibration = DeviceProfile(name: job.devices.first?.name ?? device.name, idiom: "watch",
                                               width: b.width, height: b.height, scale: device.screenScale,
                                               safeArea: job.devices.first?.safeArea ?? .zero, landscapeSafeArea: .zero, cornerRadius: 0)
        case .virtual, .device:
            // ImageRenderer can't draw watchOS platform views (List, NavigationStack…), so watch
            // previews are always shown on the real watch screen and captured by the host.
            showOnScreen(previews, job: job, result: &result)
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

#endif
