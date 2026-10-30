import XCTest
@testable import swiftshot

/// swiftshot-report.json as docs/wiki/Baseline-format.md extends it: ids, platform, scale, errors with ids,
/// the run's scope and fingerprint, canonical JSON.
final class ReportTests: XCTestCase {
    var tmp: URL!
    override func setUp() { tmp = temporaryDirectory("swiftshot-report") }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func shot(_ preview: String, appearance: String = "light", textSize: String? = nil, runtime: String = "26.0", scale: Double? = 3) -> ShotRecord {
        let suffix = (appearance == "light" ? "" : "-\(appearance)") + (textSize.map { "-\($0)" } ?? "")
        return ShotRecord(preview: preview, device: "iPhone 17 Pro", appearance: appearance, textSize: textSize, language: "en-US", runtime: runtime,
                          file: "en-US/iPhone 17 Pro-\(preview)\(suffix).png", width: 40, height: 80, renderMs: 12.5, scale: scale)
    }

    func testScreenshotsCarryIdPlatformAndScale() throws {
        let json = Report.shotJSON(shot("Home", textSize: "AX5"))
        XCTAssertEqual(json["id"], .string("en-US/iPhone 17 Pro-Home-AX5"))
        XCTAssertEqual(json["platform"], .string("ios"))
        XCTAssertEqual(json["scale"], .int(3))
        XCTAssertEqual(json["textSize"], .string("AX5"))
        XCTAssertEqual(json["runtime"], .string("26.0"))
        XCTAssertNil(Report.shotJSON(shot("Home"))["textSize"], "absent = default")
        XCTAssertEqual(Report.shotJSON(shot("Mini", scale: 2.88))["scale"], .double(2.88))
    }

    func testFingerprintOfAnIosRun() {
        let fp = Fingerprints.ios(mode: "no-boot", xcode: "17A400", runtimes: ["23A343"], host: "macos-arm64", version: "1.0.0-test")
        XCTAssertEqual(fp, .object(["host": .string("macos-arm64"), "mode": .string("no-boot"), "platform": .string("ios"), "runtime": .string("23A343"),
                                    "swiftshot": .string("1.0.0-test"), "xcode": .string("17A400")]))
        // Several runtimes: their builds, sorted and joined.
        XCTAssertEqual(Fingerprints.ios(mode: "device", xcode: nil, runtimes: ["23B5", "23A343", "23A343"], host: "macos-x64", version: "1")["runtime"], .string("23A343, 23B5"))
        XCTAssertNil(Fingerprints.ios(mode: "device", xcode: nil, runtimes: [], host: "macos-x64", version: "1")["xcode"])
        XCTAssertEqual(Fingerprints.xcodeBuild("Xcode 27.2\nBuild version 27B52\n"), "27B52")
        XCTAssertNil(Fingerprints.xcodeBuild("nothing"))
        XCTAssertEqual(Fingerprints.hostOf(os: "macos", arch: "arm64"), "macos-arm64")
        XCTAssertEqual(Fingerprints.hostOf(os: "macos", arch: "x86_64"), "macos-x64")
    }

    func testScopeIsRequestedUnionRendered() {
        var scope = RunScope(previewFilter: ["Home*"])
        scope.devices = ["iPhone 17 Pro Max"]; scope.languages = ["en-US", "de-DE"]; scope.appearances = ["light"]; scope.textSizes = ["default"]; scope.runtimes = ["26.0"]
        scope.add(shot("Home", appearance: "dark", textSize: "AX5"))
        scope.previews.insert("Home Two")
        XCTAssertEqual(scope.json(), .object([
            "platforms": .array([.string("ios")]), "modules": .array([]),
            "devices": .array([.string("iPhone 17 Pro"), .string("iPhone 17 Pro Max")]),
            "languages": .array([.string("de-DE"), .string("en-US")]),
            "appearances": .array([.string("dark"), .string("light")]),
            "textSizes": .array([.string("AX5"), .string("default")]),
            "runtimes": .array([.string("26.0")]),
            "previews": .array([.string("Home"), .string("Home Two")]),
            "previewFilter": .array([.string("Home*")]),
        ]))
    }

    func testReportIsCanonicalWithErrorObjects() throws {
        let fp = Fingerprints.ios(mode: "no-boot", xcode: "17A400", runtimes: ["23A343"], host: "macos-arm64", version: "1.0.0-test")
        var scope = RunScope(previewFilter: [])
        let shots = [shot("Settings"), shot("Home")]
        for s in shots { scope.add(s) }
        try Report.write(shots: shots, errors: [RunError(id: "en-US/iPhone 17 Pro-Broken", message: "no image"), RunError(id: nil, message: "iOS 26.0 · launch failed")],
                         scope: scope, fingerprint: ["ios": fp], to: tmp.path, html: false, timings: [("build", 1.25)], total: 2.5)
        let text = try String(contentsOf: tmp.appendingPathComponent("swiftshot-report.json"), encoding: .utf8)
        let json = try JSON.parse(text)
        XCTAssertEqual(json.pretty(), text)
        XCTAssertEqual(json["screenshots"]!.array!.map { $0["id"]!.string! }, ["en-US/iPhone 17 Pro-Home", "en-US/iPhone 17 Pro-Settings"])
        XCTAssertEqual(json["errors"], .array([.object(["id": .string("en-US/iPhone 17 Pro-Broken"), "message": .string("no image")]), .object(["message": .string("iOS 26.0 · launch failed")])]))
        XCTAssertEqual(json["fingerprint"]!["ios"], fp)
        XCTAssertEqual(json["scope"]!["textSizes"], .array([.string("default")]))
        XCTAssertEqual(json["platform"], .string("ios"))
    }

    /// A report this binary writes, recorded and verified: passes; the device mode's tolerance applies by default.
    func testRecordThenVerifyASwiftRun() throws {
        let out = tmp.appendingPathComponent("out"), base = tmp.appendingPathComponent("base")
        let png = fixtures.appendingPathComponent("device-mode/baseline/en-US/iPhone 17 Pro-Glass.png")
        let changed = fixtures.appendingPathComponent("device-mode/output/en-US/iPhone 17 Pro-Glass.png")
        try FileManager.default.createDirectory(at: out.appendingPathComponent("en-US"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: png, to: out.appendingPathComponent("en-US/iPhone 17 Pro-Glass.png"))
        var scope = RunScope(previewFilter: [])
        scope.add(shot("Glass"))
        let fp = Fingerprints.ios(mode: "device", xcode: "17A400", runtimes: ["23A343"], host: "macos-arm64", version: "1.0.0-test")
        try Report.write(shots: [shot("Glass")], errors: [], scope: scope, fingerprint: ["ios": fp], to: out.path, html: false, timings: [], total: 1)
        XCTAssertEqual(try Baseline.record(output: out, baseline: base, ci: true, log: Console(capture: true)), 0)
        // The next run differs by at most 1 per channel (the device's glass noise).
        try FileManager.default.removeItem(at: out.appendingPathComponent("en-US/iPhone 17 Pro-Glass.png"))
        try FileManager.default.copyItem(at: changed, to: out.appendingPathComponent("en-US/iPhone 17 Pro-Glass.png"))
        let env = BaselineEnv(git: GitInfo(commit: nil, branch: nil), version: "1.0.0-test", ci: false)
        let v = try Baseline.evaluate(output: out, baseline: base, report: tmp.appendingPathComponent("report"), config: CompareConfig(tolerance: nil, rules: []), env: env)
        XCTAssertEqual(v.exitCode, 0)
        XCTAssertEqual(v.entries.first?["status"], .string("unchanged"))
        // Exact when the config sets a tolerance: then the same run is a change.
        let exact = try Baseline.evaluate(output: out, baseline: base, report: tmp.appendingPathComponent("report2"), config: CompareConfig(tolerance: Tolerance(), rules: []), env: env)
        XCTAssertEqual(exact.entries.first?["status"], .string("changed"))
    }
}
