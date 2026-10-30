import XCTest
@testable import swiftshot

/// `verify` and `record` against the shared fixtures in Shared/testdata/baseline (docs/wiki/Baseline-format.md):
/// every case gives exactly the expected result.json, junit.xml, manifest.json, images and exit code.
final class BaselineTests: XCTestCase {
    var tmp: URL!
    let env = BaselineEnv(git: GitInfo(commit: "0123456789abcdef0123456789abcdef01234567", branch: "feature/x"), version: "1.0.0-test", ci: false)
    override func setUp() { tmp = temporaryDirectory("swiftshot-baseline") }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func fixture(_ name: String) -> URL { fixtures.appendingPathComponent(name) }

    func config(_ c: URL) throws -> CompareConfig {
        CompareConfig.from(try Options.parse(["verify", "--config", c.appendingPathComponent("config.json").path]))
    }

    @discardableResult
    func verify(_ c: URL, report: URL? = nil) throws -> Verification {
        try Baseline.evaluate(output: c.appendingPathComponent("output"), baseline: c.appendingPathComponent("baseline"),
                              report: report ?? tmp.appendingPathComponent(c.lastPathComponent), config: try config(c), env: env)
    }

    func ids(_ dir: URL) throws -> [String] {
        try readJSON(dir.appendingPathComponent("result.json"))["screenshots"]!.array!.map { $0["id"]!.string! }
    }

    func testEveryFixtureCaseMatchesByteForByte() throws {
        let all = fixtureCases()
        XCTAssertEqual(all.count, 22, "fixture cases")
        var problems: [String] = []
        var passed: [String] = []
        for c in all {
            let report = tmp.appendingPathComponent(c.lastPathComponent)
            let v = try verify(c, report: report)
            var ok = true
            for name in ["result.json", "junit.xml", "manifest.json"] {
                let want = try String(contentsOf: c.appendingPathComponent("expected/\(name)"), encoding: .utf8)
                let got = try? String(contentsOf: report.appendingPathComponent(name), encoding: .utf8)
                if got != want { ok = false; problems.append("\(c.lastPathComponent)/\(name) differs:\n--- want\n\(want)--- got\n\(got ?? "nil")") }
            }
            let wantImages = files(c.appendingPathComponent("expected/images")), gotImages = files(report.appendingPathComponent("images"))
            if Set(wantImages.keys) != Set(gotImages.keys) { ok = false; problems.append("\(c.lastPathComponent): images \(wantImages.keys.sorted()) != \(gotImages.keys.sorted())") }
            for (k, f) in wantImages where gotImages[k].map({ bytes($0) != bytes(f) }) == true { ok = false; problems.append("\(c.lastPathComponent): image \(k) bytes differ") }
            let status = try readJSON(c.appendingPathComponent("expected/result.json"))["status"]!.string!
            let code: Int32 = ["passed": 0, "failed": 1, "error": 2][status]!
            if v.exitCode != code { ok = false; problems.append("\(c.lastPathComponent): exit \(v.exitCode), want \(code)") }
            if ok { passed.append(c.lastPathComponent) }
        }
        print("fixture cases passed: \(passed.joined(separator: ", "))")
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testOutOfScopeBaselineImagesAreNotRemoved() throws {
        let v = try verify(fixture("out-of-scope"))
        XCTAssertEqual(v.counts["removed"], 0)
        XCTAssertEqual(try ids(tmp.appendingPathComponent("out-of-scope")), ["en-US/iPhone 17 Pro-Home One"])
    }

    func testSplitRunVerifiesOnlyItsOwnPlatform() throws {
        try verify(fixture("split-run-android"))
        XCTAssertTrue(try ids(tmp.appendingPathComponent("split-run-android")).allSatisfy { $0.contains("Pixel 9") })
        try verify(fixture("split-run-ios"))
        XCTAssertEqual(try ids(tmp.appendingPathComponent("split-run-ios")), ["en-US/iPhone 17 Pro-Home", "en-US/iPhone 17 Pro-Settings"])
    }

    func testFingerprintMismatchIsSaidFirst() throws {
        let v = try verify(fixture("fingerprint-mismatch"))
        XCTAssertEqual(v.exitCode, 0)
        let lines = BaselineReport.summary(v, report: tmp.appendingPathComponent("fingerprint-mismatch"))
        XCTAssertTrue(lines.first!.1.contains("android host: baseline linux-x64, this run macos-arm64"), "\(lines)")
        XCTAssertEqual(lines.first!.0, "warn")
    }

    func testLocalBaselineWarnsAndPasses() throws {
        let v = try verify(fixture("local-baseline"))
        XCTAssertEqual(v.exitCode, 0)
        XCTAssertTrue(v.localBaseline)
        XCTAssertTrue(BaselineReport.summary(v, report: tmp.appendingPathComponent("local-baseline")).contains { $0.0 == "warn" && $0.1.contains("outside CI") })
    }

    func testStaleReportFilesAreReplaced() throws {
        let report = tmp.appendingPathComponent("reuse")
        try verify(fixture("changed-pixels"), report: report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.appendingPathComponent("images/diff/en-US/Pixel 9-Home.png").path))
        try verify(fixture("unchanged"), report: report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: report.appendingPathComponent("images").path))
    }

    /// A run's output dir: the fixture's output, copied (record writes into the baseline only).
    func output(_ name: String) throws -> URL {
        let out = tmp.appendingPathComponent("out-\(name)")
        try copyTree(fixture(name).appendingPathComponent("output"), out)
        return out
    }

    func baselineJson(_ dir: URL) throws -> JSON { try readJSON(dir.appendingPathComponent("baseline.json")) }

    func testRecordWritesBaselineWithFingerprintsAndLocal() throws {
        let out = try output("fingerprint-mismatch")
        let base = tmp.appendingPathComponent("base")
        XCTAssertEqual(try Baseline.record(output: out, baseline: base, ci: false, log: Console(capture: true)), 0)
        let json = try baselineJson(base)
        XCTAssertEqual(json["schema"], .int(1))
        let images = json["images"]!.object!
        XCTAssertEqual(Set(images.keys), ["en-US/iPhone 17 Pro-Home", "en-US/Pixel 9-Home"])
        let fps = json["fingerprints"]!.object!
        XCTAssertEqual(fps.count, 2)
        for (id, fp) in fps { XCTAssertEqual(id, Fingerprints.id(fp)) }
        let ios = images["en-US/iPhone 17 Pro-Home"]!
        XCTAssertEqual(ios["local"], .bool(true))
        XCTAssertEqual(ios["textSize"], .string("default"))
        XCTAssertEqual(ios["runtime"], .string("26.0"))
        XCTAssertEqual(fps[ios["fingerprint"]!.string!]!["platform"], .string("ios"))
        // The image fingerprint: its own runtime's build, not the run's runtimes.
        XCTAssertEqual(fps[ios["fingerprint"]!.string!]!["runtime"], .string("23A343"))
        XCTAssertNil(fps[ios["fingerprint"]!.string!]!["runtimes"])
        let android = images["en-US/Pixel 9-Home"]!
        XCTAssertEqual(android["module"], .string(":app"))
        XCTAssertEqual(android["fontScale"], .int(1))
        XCTAssertEqual(bytes(base.appendingPathComponent("en-US/Pixel 9-Home.png")), bytes(out.appendingPathComponent("en-US/Pixel 9-Home.png")))
        XCTAssertEqual(json.pretty(), try String(contentsOf: base.appendingPathComponent("baseline.json"), encoding: .utf8))

        XCTAssertEqual(try Baseline.record(output: out, baseline: base, ci: true, log: Console(capture: true)), 0)
        XCTAssertEqual(try baselineJson(base)["images"]!["en-US/Pixel 9-Home"]!["local"], .bool(false))
        let v = try Baseline.evaluate(output: out, baseline: base, report: tmp.appendingPathComponent("after-record"), config: CompareConfig(tolerance: nil, rules: []), env: env)
        XCTAssertEqual(v.exitCode, 0)
        XCTAssertTrue(v.mismatches.isEmpty)
        XCTAssertFalse(v.localBaseline)
    }

    func testRecordReplacesInScopeImagesAndKeepsOthers() throws {
        let base = tmp.appendingPathComponent("base-removed")
        try copyTree(fixture("removed").appendingPathComponent("baseline"), base)
        _ = try Baseline.record(output: try output("removed"), baseline: base, ci: true, log: Console(capture: true))
        XCTAssertEqual(Set(try baselineJson(base)["images"]!.object!.keys), ["en-US/Pixel 9-Home"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("en-US/Pixel 9-Legacy.png").path))
        let shared = tmp.appendingPathComponent("base-split")
        try copyTree(fixture("split-run-ios").appendingPathComponent("baseline"), shared)
        _ = try Baseline.record(output: try output("split-run-ios"), baseline: shared, ci: true, log: Console(capture: true))
        XCTAssertEqual(Set(try baselineJson(shared)["images"]!.object!.keys), ["en-US/Pixel 9-Home", "en-US/Pixel 9-Settings", "en-US/iPhone 17 Pro-Home"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.appendingPathComponent("en-US/Pixel 9-Settings.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.appendingPathComponent("en-US/iPhone 17 Pro-Settings.png").path))
    }

    func testRecordWithRenderErrorsKeepsTheirImagesAndExits2() throws {
        let base = tmp.appendingPathComponent("base-error")
        try copyTree(fixture("render-error").appendingPathComponent("baseline"), base)
        XCTAssertEqual(try Baseline.record(output: try output("render-error"), baseline: base, ci: true, log: Console(capture: true)), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.appendingPathComponent("en-US/Pixel 9-Broken.png").path))
        XCTAssertNotNil(try baselineJson(base)["images"]!["en-US/Pixel 9-Broken"])
    }

    func testRecordWithNothingRenderedLeavesTheBaselineAlone() throws {
        let base = tmp.appendingPathComponent("base-build-error")
        try copyTree(fixture("build-error").appendingPathComponent("baseline"), base)
        let before = files(base).mapValues(bytes)
        XCTAssertEqual(try Baseline.record(output: try output("build-error"), baseline: base, ci: true, log: Console(capture: true)), 2)
        XCTAssertEqual(files(base).mapValues(bytes), before)
    }

    /// A report directory holding an earlier verify's files; the options of a verify into it.
    func staleRun(_ command: String = "verify") throws -> (URL, Options) {
        let report = tmp.appendingPathComponent("report")
        try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true)
        for f in ["result.json", "manifest.json", "junit.xml"] { try Data("stale".utf8).write(to: report.appendingPathComponent(f)) }
        let o = try Options.parse([command, "--output", tmp.appendingPathComponent("out").path, "--baseline-directory", tmp.appendingPathComponent("base").path,
                                   "--report-directory", report.path])
        return (report, o)
    }

    func testRunErrorIsAFreshFailureReport() async throws {
        let (report, o) = try staleRun()
        let code = await Command.baseline(o) { _ in throw CLIError("boom") }
        XCTAssertEqual(code, 2)
        let r = try readJSON(report.appendingPathComponent("result.json"))
        XCTAssertEqual(r["status"], .string("error"))
        XCTAssertTrue(r["errors"]!.text.contains("boom"), r.text)
        XCTAssertFalse(String(decoding: try Data(contentsOf: report.appendingPathComponent("junit.xml")), as: UTF8.self).contains("stale"))
    }

    func testComparisonErrorExits2WithoutStaleReport() async throws {
        let (report, o) = try staleRun()
        let out = tmp.appendingPathComponent("out")
        let code = await Command.baseline(o) { _ in
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try Data("{\"screenshots\": [".utf8).write(to: out.appendingPathComponent("swiftshot-report.json"))
        }
        XCTAssertEqual(code, 2)
        for f in ["result.json", "manifest.json", "junit.xml"] { XCTAssertFalse(FileManager.default.fileExists(atPath: report.appendingPathComponent(f).path), f) }
    }

    func testMultiRuntimeMismatchIsOnlyForTheChangedRuntime() throws {
        let v = try verify(fixture("multi-runtime"))
        XCTAssertEqual(v.mismatches, ["ios runtime: baseline 23F77, this run 23F80"])
        let base = tmp.appendingPathComponent("base-multi")
        _ = try Baseline.record(output: try output("multi-runtime"), baseline: base, ci: true, log: Console(capture: true))
        let json = try baselineJson(base)
        func build(_ id: String) -> JSON? { json["fingerprints"]![json["images"]![id]!["fingerprint"]!.string!]!["runtime"] }
        XCTAssertEqual(build("en-US/iPhone 17 Pro-Home-iOS26.0"), .string("23A343"))
        XCTAssertEqual(build("en-US/iPhone 17 Pro-Settings-iOS26.5"), .string("23F80"))
    }

    func testConfigHashIsTheNormalizedConfigs() throws {
        let c = try config(fixture("tolerance"))
        let normalized = #"{"screens":[{"preview":"clock*","tolerance":{"max_channel_delta":2,"pixels":0}}],"tolerance":{"max_channel_delta":1,"pixels":5}}"#
        XCTAssertEqual(c.hash(), CanonicalJson.sha256(normalized))
    }

    func testDeviceModeDefaultsToChannelDeltaOne() {
        let c = CompareConfig(tolerance: nil, rules: [])
        XCTAssertEqual(c.forShot(preview: "Glass", mode: "device", scale: 3).0, Tolerance(pixels: 0, maxChannelDelta: 1))
        XCTAssertEqual(c.forShot(preview: "Glass", mode: "no-boot", scale: 3).0, Tolerance(pixels: 0, maxChannelDelta: 0))
        XCTAssertEqual(CompareConfig(tolerance: Tolerance(pixels: 2), rules: []).forShot(preview: "Glass", mode: "device", scale: 3).0, Tolerance(pixels: 2, maxChannelDelta: 0))
        // A rule's tolerance counts as set, too.
        let ruled = CompareConfig(tolerance: nil, rules: [CompareRule(preview: "Gl*", tolerance: Tolerance(pixels: 3))])
        XCTAssertEqual(ruled.forShot(preview: "Glass", mode: "device", scale: 3).0, Tolerance(pixels: 3, maxChannelDelta: 0))
    }

    func testGlobIsAsciiCaseInsensitive() {
        XCTAssertTrue(Baseline.glob("clock*", "Clock Large"))
        XCTAssertTrue(Baseline.glob("*a*b*", "xAyBz"))
        XCTAssertFalse(Baseline.glob("über", "ÜBER"))
        XCTAssertFalse(Baseline.glob("ab*ba", "aba"))
        XCTAssertTrue(Baseline.glob("Feed", "feed"))
    }

    // MARK: canonical JSON

    func testCanonicalJson() throws {
        let v: JSON = .object(["b": .array([.int(1), .double(2.625), .double(1.0), .double(1.3), .double(0.00001)]), "a": .object([:]), "é": .string("\"\\\n\r\t\u{1}/ü"), "c": .array([]), "Z": .null])
        XCTAssertEqual(v.compact(), #"{"Z":null,"a":{},"b":[1,2.625,1,1.3,0.00001],"c":[],"é":"\"\\\n\r\t\u0001/ü"}"#)
        XCTAssertEqual(JSON.object(["k": .array([.int(1)])]).pretty(), "{\n  \"k\": [\n    1\n  ]\n}\n")
        XCTAssertEqual(try JSON.parse(#"{"a": [1, 1.0, -2.5e3, true, null, "xé"]}"#), .object(["a": .array([.int(1), .double(1), .double(-2500), .bool(true), .null, .string("xé")])]))
        XCTAssertThrowsError(try JSON.parse("[1,"))
        XCTAssertThrowsError(try JSON.parse("{} x"))
        // Keys by UTF-8 bytes: U+FFFD before U+1F600 (UTF-16 order would say otherwise).
        XCTAssertEqual(JSON.object(["\u{1F600}": .int(1), "\u{FFFD}": .int(2)]).compact(), "{\"\u{FFFD}\":2,\"\u{1F600}\":1}")
        XCTAssertEqual(JSON.number(123456789012.5), "123456789012.5")
        XCTAssertEqual(JSON.number(1e-7), "0.0000001")
    }
}
