// Device frames end to end: downloads Apple's real bezels (iPhone 17 family, ~265 MB, into a
// temporary cache unless SWIFTSHOT_FRAME_CACHE points at one), renders Example/DemoApp without a
// simulator and frames the result in both modes. Opt-in, like the other integration tests:
//   make && SWIFTSHOT_INTEGRATION=1 swift test --filter FramesIntegrationTests

import AppKit
import XCTest

final class FramesIntegrationTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let tool = root.appendingPathComponent("bin/swiftshot").path
    static let env = ProcessInfo.processInfo.environment
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-frames-it-\(ProcessInfo.processInfo.processIdentifier)")

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.env["SWIFTSHOT_INTEGRATION"] == "1", "set SWIFTSHOT_INTEGRATION=1 (needs Xcode, an iOS runtime, `make`, network)")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.tool), "run `make` first")
    }

    @discardableResult
    func swiftshot(_ args: [String]) throws -> String {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let config = work.appendingPathComponent("empty.json")
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.tool)
        p.currentDirectoryURL = Self.root.appendingPathComponent("Example/DemoApp")
        p.arguments = args + ["--config", config.path]
        var env = Self.env
        if env["SWIFTSHOT_FRAME_CACHE"] == nil { env["SWIFTSHOT_FRAME_CACHE"] = work.appendingPathComponent("bezels").path }
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "swiftshot \(args.joined(separator: " ")):\n\(out.suffix(4000))")
        return out
    }

    func bitmap(_ url: URL) throws -> NSBitmapImageRep { try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)), url.path) }

    func testRealBezelsBothModes() throws {
        let shots = work.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: shots.appendingPathComponent("en-US"), withIntermediateDirectories: true)
        try "\"Welcome\" = \"Build habits that stick\";\n".write(to: shots.appendingPathComponent("en-US/title.strings"), atomically: true, encoding: .utf8)
        let out = try swiftshot(["run", "--project", "DemoApp.xcodeproj", "--scheme", "DemoApp", "--devices", "iPhone 17 Pro Max",
                                 "--previews", "Welcome,Stats landscape,Habit row", "--output", shots.path, "--no-html",
                                 "--frame", "appstore", "--accept-bezel-license"])
        XCTAssertTrue(out.contains("partial-size left unframed"), out)

        // App Store mode: 1320×2868 (6.9"), no alpha, next to the original.
        let lang = shots.appendingPathComponent("en-US")
        let store = try bitmap(lang.appendingPathComponent("iPhone 17 Pro Max-Welcome_framed.png"))
        XCTAssertEqual(store.pixelsWide, 1320); XCTAssertEqual(store.pixelsHigh, 2868)
        XCTAssertFalse(store.hasAlpha, "App Store Connect rejects alpha")
        let landscape = try bitmap(lang.appendingPathComponent("iPhone 17 Pro Max-Stats landscape_framed.png"))
        XCTAssertEqual(landscape.pixelsWide, 2868); XCTAssertEqual(landscape.pixelsHigh, 1320)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lang.appendingPathComponent("iPhone 17 Pro Max-Habit row_framed.png").path), "partial size")

        // Plain mode over the same folder: the bezel's size, transparent outside, the screen's
        // pixels exactly the screenshot's.
        try swiftshot(["frame", shots.path])
        let plainURL = work.appendingPathComponent("screenshots-framed/en-US/iPhone 17 Pro Max-Welcome_framed.png")
        let plain = try bitmap(plainURL)
        XCTAssertEqual(plain.pixelsWide, 1470); XCTAssertEqual(plain.pixelsHigh, 3000)
        XCTAssertTrue(plain.hasAlpha)
        XCTAssertEqual(plain.colorAt(x: 2, y: 2)?.alphaComponent, 0, "outside the device")
        let original = try bitmap(lang.appendingPathComponent("iPhone 17 Pro Max-Welcome.png"))
        // The opening of Apple's 17 Pro Max bezel starts at (75, 66).
        for (x, y) in [(660, 1434), (300, 2000), (1000, 600), (200, 2700)] {
            let a = try XCTUnwrap(plain.colorAt(x: x + 75, y: y + 66)?.usingColorSpace(.sRGB))
            let b = try XCTUnwrap(original.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.5 / 255, "\(x),\(y)")
            XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.5 / 255)
            XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.5 / 255)
        }
        // The App Store frames from the run are newer than the screenshots: still there.
        XCTAssertTrue(FileManager.default.fileExists(atPath: lang.appendingPathComponent("iPhone 17 Pro Max-Welcome_framed.png").path))
    }
}
