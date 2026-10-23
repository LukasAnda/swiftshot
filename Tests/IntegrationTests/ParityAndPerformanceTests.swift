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
    static let devices = env["SWIFTSHOT_IT_DEVICES"] ?? "iPhone 18 Pro,iPhone 17"
    static let ios = env["SWIFTSHOT_IT_IOS"] ?? "27.0"
    static var work = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-it-\(ProcessInfo.processInfo.processIdentifier)")

    /// Previews whose every pixel below the status bar must equal the booted simulator's
    /// framebuffer. Root is left out: its Liquid Glass tab bar and button blur the system status
    /// bar and home indicator, which SpringBoard draws on a device and swiftshot doesn't (yet).
    static let parityPreviews = ["Welcome", "Habit list", "History", "Stats", "Settings", "New habit sheet", "Delete alert", "Share dialog"]

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.env["SWIFTSHOT_INTEGRATION"] == "1", "set SWIFTSHOT_INTEGRATION=1 (needs Xcode, an iOS runtime, `make`)")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.tool), "run `make` first")
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
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let t = Date()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(p.terminationStatus, 0, "swiftshot \(args.joined(separator: " ")) failed:\n\(out.suffix(4000))")
        return (out, Date().timeIntervalSince(t))
    }

    // MARK: pixel parity

    struct Diff { var max = 0; var pixels = 0 }

    /// Max channel difference outside the system chrome a booted simulator composites over the
    /// app and swiftshot doesn't draw: the status bar (top `skipTop` rows) and the home indicator
    /// (a pill centred at the bottom, which SpringBoard shows or hides depending on timing).
    func diff(_ a: URL, _ b: URL, skipTop: Int, scale: Int = 3) throws -> Diff {
        let x = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: a))), y = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: b)))
        XCTAssertEqual(x.pixelsWide, y.pixelsWide); XCTAssertEqual(x.pixelsHigh, y.pixelsHigh)
        XCTAssertEqual(x.bitsPerSample, 8, "\(a.lastPathComponent): 8-bit like the framebuffer")
        guard x.pixelsWide == y.pixelsWide, x.pixelsHigh == y.pixelsHigh, let bx = x.bitmapData, let by = y.bitmapData else { return Diff(max: 255, pixels: -1) }
        var d = Diff()
        let px = x.bitsPerPixel / 8, py = y.bitsPerPixel / 8
        let pill = (x.pixelsWide / 2 - 80 * scale)...(x.pixelsWide / 2 + 80 * scale), pillTop = x.pixelsHigh - 21 * scale
        for r in skipTop..<x.pixelsHigh {
            for c in 0..<x.pixelsWide where !(r >= pillTop && pill.contains(c)) {
                var m = 0
                for k in 0..<3 { m = max(m, abs(Int(bx[r * x.bytesPerRow + c * px + k]) - Int(by[r * y.bytesPerRow + c * py + k]))) }
                if m > 0 { d.pixels += 1; d.max = max(d.max, m) }
            }
        }
        return d
    }

    func testNoBootMatchesBootedFramebuffer() throws {
        let previews = Self.parityPreviews.joined(separator: ",")
        let virtual = Self.work.appendingPathComponent("virtual"), device = Self.work.appendingPathComponent("device")
        try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--previews", previews, "--output", virtual.path])
        try swiftshot(["--devices", Self.devices, "--ios", Self.ios, "--previews", previews, "--mode", "device", "--output", device.path])
        let files = try FileManager.default.contentsOfDirectory(atPath: device.appendingPathComponent("en-US").path).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(files.count, Self.parityPreviews.count * Self.devices.split(separator: ",").count)
        var report: [String] = []
        for file in files {
            let d = try diff(virtual.appendingPathComponent("en-US/\(file)"), device.appendingPathComponent("en-US/\(file)"), skipTop: 186)
            report.append("\(file): max \(d.max)/255, \(d.pixels) px")
            XCTAssertEqual(d.max, 0, "\(file) differs from the booted simulator: max \(d.max)/255 on \(d.pixels) px")
        }
        print(report.joined(separator: "\n"))
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
        print("perf: \(shots) shots in \(String(format: "%.1f", run.seconds)) s wall, \(Int(inApp)) ms in-app (\(Int(inApp) / max(shots, 1)) ms/shot)")
        XCTAssertLessThan(run.seconds, 30, "wall time for \(shots) shots (incl. the incremental build)")
        XCTAssertLessThan(inApp / Double(shots), 400, "in-app ms per screenshot")
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
