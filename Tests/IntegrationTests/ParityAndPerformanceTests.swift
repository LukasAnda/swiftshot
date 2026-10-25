// End-to-end tests on Example/DemoApp with the built tool (`make` first). They need Xcode with an
// iOS 27.0 runtime and boot one simulator (for the reference), so they only run when asked:
//   make && SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
// SWIFTSHOT_IT_DEVICES / SWIFTSHOT_IT_IOS pick other devices / a runtime.

import AppKit
import XCTest

final class ParityAndPerformanceTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let tool = root.appendingPathComponent("bin/swiftshot").path
    static let app = root.appendingPathComponent("Example/DemoApp")
    static let env = ProcessInfo.processInfo.environment
    static let devices = env["SWIFTSHOT_IT_DEVICES"].flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone 18 Pro,iPhone 17,iPad Pro 13-inch (M5)"
    static let ios = env["SWIFTSHOT_IT_IOS"] ?? "27.0"
    static var work = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIFTSHOT_IT_OUT"] ?? FileManager.default.temporaryDirectory.path)
        .appendingPathComponent("swiftshot-it-\(ProcessInfo.processInfo.processIdentifier)")

    /// Previews whose every pixel below the status bar must equal the booted simulator's
    /// framebuffer (Root is added per test: on the Duo its rail is excluded).
    static let parityPreviews = ["Welcome", "Habit list", "History", "Stats", "Settings", "New habit sheet", "Delete alert", "Share dialog"]

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.env["SWIFTSHOT_INTEGRATION"] == "1", "set SWIFTSHOT_INTEGRATION=1 (needs Xcode, an iOS runtime, `make`)")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.tool), "run `make` first")
    }

    /// The reference simulators stay booted after a device run; on a CI runner the next test's
    /// boot then fails on the user process limit ("insufficient system resources").
    override func tearDown() {
        guard Self.env["SWIFTSHOT_INTEGRATION"] == "1" else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); p.arguments = ["simctl", "shutdown", "all"]
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    func swiftshot(_ args: [String], extraEnv: [String: String] = [:]) throws -> (output: String, seconds: Double) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.tool)
        p.currentDirectoryURL = Self.app
        let config = Self.work.appendingPathComponent("empty.json")
        try? FileManager.default.createDirectory(at: Self.work, withIntermediateDirectories: true)
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        p.arguments = ["run", "--config", config.path, "--project", "DemoApp.xcodeproj", "--scheme", "DemoApp", "--no-html", "--clear"] + args
        p.environment = Self.env.merging(extraEnv) { $1 }
        // Also to a log next to the output (uploaded with it), in case the job runs out of time.
        let output = args.firstIndex(of: "--output").map { args[$0 + 1] } ?? Self.work.path
        let logPath = output + ".log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: logPath)
        defer { try? log?.close() }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let t = Date()
        try p.run()
        var data = Data()
        while case let chunk = pipe.fileHandleForReading.availableData, !chunk.isEmpty {
            data.append(chunk); log?.write(chunk)
        }
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(p.terminationStatus, 0, "swiftshot \(args.joined(separator: " ")) failed:\n\(out.suffix(4000))")
        return (out, Date().timeIntervalSince(t))
    }

    // MARK: pixel parity

    struct Diff { var max = 0; var pixels = 0 }

    /// Max channel difference outside the rows (`skipTop`) and rectangles (`skip`) left out. A
    /// pixel counts as equal when it equals any of the references: the booted simulator itself
    /// flips a few glass pixels by 1/255 between runs.
    func diff(_ a: URL, _ refs: [URL], skipTop: Int, skip: [CGRect] = []) throws -> Diff {
        let x = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: a)))
        let ys = try refs.map { try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: $0))) }
        XCTAssertEqual(x.bitsPerSample, 8, "\(a.lastPathComponent): 8-bit like the framebuffer")
        for y in ys { XCTAssertEqual(x.pixelsWide, y.pixelsWide); XCTAssertEqual(x.pixelsHigh, y.pixelsHigh) }
        guard ys.allSatisfy({ $0.pixelsWide == x.pixelsWide && $0.pixelsHigh == x.pixelsHigh }), let bx = x.bitmapData else { return Diff(max: 255, pixels: -1) }
        var d = Diff()
        let px = x.bitsPerPixel / 8
        for r in skipTop..<x.pixelsHigh {
            for c in 0..<x.pixelsWide where !skip.contains(where: { $0.contains(CGPoint(x: c, y: r)) }) {
                var best = Int.max
                for y in ys {
                    guard let by = y.bitmapData else { continue }
                    let py = y.bitsPerPixel / 8
                    var m = 0
                    for k in 0..<3 { m = max(m, abs(Int(bx[r * x.bytesPerRow + c * px + k]) - Int(by[r * y.bytesPerRow + c * py + k]))) }
                    best = min(best, m)
                }
                if best > 0 { d.pixels += 1; d.max = max(d.max, best) }
            }
        }
        return d
    }

    /// Renders `previews` without a simulator and twice on booted simulators, and requires every
    /// pixel (outside `skip`) to equal a booted one.
    func assertParity(devices: String, ios: String, previews: [String], skipTop: Int, skip: [CGRect] = [], tag: String) throws {
        let list = previews.joined(separator: ",")
        let virtual = Self.work.appendingPathComponent("\(tag)virtual")
        let refs = (1...2).map { Self.work.appendingPathComponent("\(tag)device\($0)") }
        try swiftshot(["--devices", devices, "--ios", ios, "--previews", list, "--output", virtual.path])
        var logs: [String] = []
        for ref in refs { logs.append(try swiftshot(["--devices", devices, "--ios", ios, "--previews", list, "--mode", "device", "--output", ref.path]).output) }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: refs[0].appendingPathComponent("en-US").path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(files.count, previews.count * devices.split(separator: ",").count, "device run wrote \(files.count) files:\n\(logs[0].suffix(4000))")
        var report: [String] = []
        for file in files {
            let d = try diff(virtual.appendingPathComponent("en-US/\(file)"), refs.map { $0.appendingPathComponent("en-US/\(file)") }, skipTop: skipTop, skip: skip)
            report.append("\(file): max \(d.max)/255, \(d.pixels) px")
            XCTAssertEqual(d.max, 0, "\(file) differs from the booted simulator: max \(d.max)/255 on \(d.pixels) px")
        }
        print(report.joined(separator: "\n"))
        // The device runs' warnings (a grabber that never hid, a retried launch) explain a mismatch.
        if report.contains(where: { !$0.contains("max 0/255") }) {
            for (i, log) in logs.enumerated() { print("device run \(i + 1) warnings:\n" + log.split(separator: "\n").filter { $0.contains("!") || $0.contains("✘") }.joined(separator: "\n")) }
        }
    }

    func testNoBootMatchesBootedFramebuffer() throws {
        // The whole frame: status bar and the home indicator's band.
        try assertParity(devices: Self.devices, ios: Self.ios, previews: Self.parityPreviews + ["Root", "UIKit habit list"], skipTop: 0, tag: "")
    }

    /// iPhone Duo (status bar in a rail on the right, floating sheets, per-corner radii): every
    /// pixel but the status capsule, Root included.
    func testDuoMatchesBootedFramebuffer() throws {
        let runtimes = Process(); runtimes.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); runtimes.arguments = ["simctl", "list", "devicetypes"]
        let pipe = Pipe(); runtimes.standardOutput = pipe; try runtimes.run(); runtimes.waitUntilExit()
        try XCTSkipUnless(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("iPhone Duo"), "no iPhone Duo device type (Xcode 27.1)")
        let ios = Self.env["SWIFTSHOT_IT_DUO_IOS"] ?? "27.1"
        try assertParity(devices: "iPhone Duo", ios: ios, previews: Self.parityPreviews + ["Root"], skipTop: 0,
                         skip: [CGRect(x: 1160, y: 50, width: 186, height: 441)], tag: "duo-")
    }

    /// Apple Watch: no-boot against a booted watch's framebuffer, below the clock (80 px).
    func testWatchMatchesBootedFramebuffer() throws {
        let watch = Self.env["SWIFTSHOT_IT_WATCH"] ?? "Apple Watch Series 11 (46mm)"
        let runtimes = Process(); runtimes.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun"); runtimes.arguments = ["simctl", "list", "runtimes"]
        let pipe = Pipe(); runtimes.standardOutput = pipe; try runtimes.run(); runtimes.waitUntilExit()
        try XCTSkipUnless(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("watchOS"), "no watchOS runtime installed")
        let previews = "Watch list,Watch progress,Watch week"
        let virtual = Self.work.appendingPathComponent("watch-virtual"), device = Self.work.appendingPathComponent("watch-device")
        try swiftshot(["--watch-scheme", "DemoWatch", "--devices", watch, "--previews", previews, "--output", virtual.path])
        try swiftshot(["--watch-scheme", "DemoWatch", "--devices", watch, "--previews", previews, "--mode", "device", "--output", device.path])
        for name in previews.split(separator: ",") {
            let file = "en-US/\(watch)-\(name).png"
            let d = try diff(virtual.appendingPathComponent(file), [device.appendingPathComponent(file)], skipTop: 80)
            print("\(watch)-\(name): max \(d.max)/255, \(d.pixels) px")
            // Both servers draw with the same renderer settings (NoBoot.swift, WatchAgent's
            // pinServerRendering), so the booted watch gives the same bytes every run.
            XCTAssertEqual(d.max, 0, "\(file) differs from the booted watch: max \(d.max)/255 on \(d.pixels) px")
        }
    }

    /// Two no-boot runs give the same bytes.
    func testDeterministic() throws {
        let a = Self.work.appendingPathComponent("det-a"), b = Self.work.appendingPathComponent("det-b")
        for out in [a, b] { try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--output", out.path]) }
        let files = try FileManager.default.contentsOfDirectory(atPath: a.appendingPathComponent("en-US").path).filter { $0.hasSuffix(".png") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertEqual(try Data(contentsOf: a.appendingPathComponent("en-US/\(file)")), try Data(contentsOf: b.appendingPathComponent("en-US/\(file)")), file)
        }
    }

    // MARK: performance

    /// Budgets on a warm machine (app built, dyld cache present): rendering every DemoApp preview
    /// on two iPhones without a simulator, and the in-app time per screenshot.
    func testNoBootPerformanceBudget() throws {
        try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--output", Self.work.appendingPathComponent("warmup").path])
        let out = Self.work.appendingPathComponent("perf")
        let run = try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--output", out.path])
        let shots = try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("en-US").path).filter { $0.hasSuffix(".png") }.count
        XCTAssertGreaterThanOrEqual(shots, 20)
        let inApp = run.output.range(of: #"in-app (\d+) ms"#, options: .regularExpression).flatMap { Double(run.output[$0].dropFirst(7).dropLast(3)) } ?? .infinity
        for line in run.output.split(separator: "\n") where line.contains("slow capture") { print(line) }
        print("perf: \(shots) shots in \(String(format: "%.1f", run.seconds)) s wall, \(Int(inApp)) ms in-app (\(Int(inApp) / max(shots, 1)) ms/shot)")
        // Budgets for a Mac; a CI VM (paravirtual GPU) is several times slower, and the bar there
        // is fastlane on the same runner: ~80 s per screenshot (bench/, README).
        let ci = Self.env["CI"] != nil
        XCTAssertLessThan(run.seconds, ci ? 300 : 30, "wall time for \(shots) shots (incl. the incremental build)")
        XCTAssertLessThan(inApp / Double(shots), ci ? 5000 : 400, "in-app ms per screenshot")
    }

    func testNoSimulatorIsBooted() throws {
        let before = try booted()
        try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--previews", "Welcome", "--output", Self.work.appendingPathComponent("noboot").path])
        XCTAssertEqual(try booted(), before, "no-boot rendering must not boot or create simulators")
    }

    private func booted() throws -> Set<String> {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: [[String: Any]]]]
        return Set((json?["devices"] ?? [:]).values.flatMap { $0 }.compactMap { $0["udid"] as? String })
    }
}
