import XCTest
@testable import swiftshot

/// The files and workflow commands each CI gets (docs/wiki/Baseline-format.md, "Native CI output").
final class NativeOutputTests: XCTestCase {
    var tmp: URL!
    var lines: [String] = []
    var console = Console(capture: true)
    override func setUp() { tmp = temporaryDirectory("swiftshot-native"); lines = []; console = Console(capture: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func ci(_ provider: String) -> Ci {
        Ci(provider: provider, commit: nil, branch: nil, pullRequest: nil, fork: nil, buildUrl: nil, repository: nil, isCi: true)
    }

    func entry(_ status: String, _ id: String, _ message: String? = nil) -> [String: JSON] {
        var e: [String: JSON] = ["id": .string(id), "status": .string(status)]
        if let message { e["message"] = .string(message) }
        return e
    }

    func verification(_ ci: Ci, _ entries: [[String: JSON]]) -> Verification {
        let errors = entries.filter { $0["status"] == .string("error") }.map { JSON.object(["id": $0["id"]!, "message": $0["message"]!]) }
        return Verification(entries: entries, errors: errors, unattributed: [], fingerprint: [:], mismatches: [], localBaseline: false, strays: 0,
                            env: BaselineEnv(git: GitInfo(commit: nil, branch: nil), version: "1.0.0-test", ci: ci), configHash: "hash")
    }

    /// The report directory of `v` as verify writes it, with one more file.
    func report(_ v: Verification) throws -> URL {
        let r = tmp.appendingPathComponent("report")
        try BaselineReport.write(v, report: r)
        try FileManager.default.createDirectory(at: r.appendingPathComponent("images/new/en-US"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: r.appendingPathComponent("images/new/en-US/A.png"))
        return r
    }

    let failed: [[String: JSON]] = [["id": .string("en-US/A"), "status": .string("changed")], ["id": .string("en-US/B"), "status": .string("added")], ["id": .string("en-US/C"), "status": .string("unchanged")]]

    func run(_ v: Verification, _ env: [String: String], _ r: URL? = nil) throws {
        NativeOutput.write(v, ci: v.env.ci, reportDir: try r ?? report(v), env: env, out: { self.lines.append($0) }, log: console)
    }

    func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testGithubAppendsTheSummaryAndAnnotatesTheFirstTen() throws {
        let entries = (1...12).map { entry("added", String(format: "en-US/N%02d", $0)) } + [entry("error", "en-US/E", "50% bad: a,b\nnext")]
        let v = verification(ci("github"), entries)
        let step = tmp.appendingPathComponent("step.md")
        try "before\n".write(to: step, atomically: true, encoding: .utf8)
        try run(v, ["GITHUB_STEP_SUMMARY": step.path])
        XCTAssertEqual(try text(step), "before\n" + Summary.markdown(v, ci: v.env.ci))
        XCTAssertEqual(lines, ["::error title=Render error::en-US/E: 50%25 bad: a,b%0Anext"] + (1...9).map { String(format: "::error title=added screenshot::en-US/N%02d", $0) })
    }

    func testGithubDataEscapes() throws {
        try run(verification(ci("github"), [entry("changed", "en-US/100%\r\nx")]), [:])
        XCTAssertEqual(lines, ["::error title=changed screenshot::en-US/100%25%0D%0Ax"])
    }

    func testGithubWithoutStepSummaryOnlyAnnotates() throws {
        try run(verification(ci("github"), failed), [:])
        XCTAssertEqual(lines, ["::error title=changed screenshot::en-US/A", "::error title=added screenshot::en-US/B"])
    }

    func testAzurePrintsPublishSummaryAndIssue() throws {
        let v = verification(ci("azure"), failed)
        let r = try report(v)
        try run(v, [:], r)
        XCTAssertEqual(lines, [
            "##vso[results.publish type=JUnit;mergeResults=false;runTitle=swiftshot;resultFiles=\(r.standardizedFileURL.path)/junit.xml]",
            "##vso[task.uploadsummary]\(r.standardizedFileURL.path)/summary.md",
            "##vso[task.logissue type=error]Screenshots: 1 changed · 1 added · 0 removed · 0 errors · 1 unchanged",
        ])
    }

    func testAzurePassedHasNoIssue() throws {
        try run(verification(ci("azure"), [entry("unchanged", "en-US/C")]), [:])
        XCTAssertEqual(lines.count, 2)
    }

    func testBitbucketCopiesJunit() throws {
        let v = verification(ci("bitbucket"), failed)
        let r = try report(v)
        try run(v, ["BITBUCKET_CLONE_DIR": tmp.appendingPathComponent("clone").path], r)
        XCTAssertEqual(try text(tmp.appendingPathComponent("clone/test-results/swiftshot/junit.xml")), try text(r.appendingPathComponent("junit.xml")))
        XCTAssertEqual(lines, [])
    }

    /// The names in a zip's central directory, in order.
    func zipNames(_ url: URL) throws -> [String] {
        let b = [UInt8](try Data(contentsOf: url))
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let eocd = b.count - 22
        var names: [String] = []
        var p = u32(eocd + 16)
        for _ in 0..<u16(eocd + 10) {
            let n = u16(p + 28)
            names.append(String(decoding: b[(p + 46)..<(p + 46 + n)], as: UTF8.self))
            p += 46 + n + u16(p + 30) + u16(p + 32)
        }
        return names
    }

    func testBitriseWritesTestResultsAndZip() throws {
        let v = verification(ci("bitrise"), failed)
        let r = try report(v)
        try run(v, ["BITRISE_TEST_RESULT_DIR": tmp.appendingPathComponent("tests").path, "BITRISE_DEPLOY_DIR": tmp.appendingPathComponent("deploy").path], r)
        XCTAssertEqual(try text(tmp.appendingPathComponent("tests/swiftshot/junit.xml")), try text(r.appendingPathComponent("junit.xml")))
        XCTAssertEqual(try text(tmp.appendingPathComponent("tests/swiftshot/test-info.json")), #"{"test-name":"swiftshot"}"#)
        let names = try zipNames(tmp.appendingPathComponent("deploy/swiftshot-report.zip"))
        XCTAssertEqual(names, names.sorted(by: utf8Less))
        XCTAssertTrue(names.contains("manifest.json") && names.contains("summary.md") && names.contains("index.html") && names.contains("images/new/en-US/A.png"), "\(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("/") || $0.hasSuffix("/") })
    }

    func testBitriseZipIsDeterministic() throws {
        let v = verification(ci("bitrise"), failed)
        let r = try report(v)
        try run(v, ["BITRISE_DEPLOY_DIR": tmp.appendingPathComponent("d1").path], r)
        try run(v, ["BITRISE_DEPLOY_DIR": tmp.appendingPathComponent("d2").path], r)
        XCTAssertEqual(bytes(tmp.appendingPathComponent("d1/swiftshot-report.zip")), bytes(tmp.appendingPathComponent("d2/swiftshot-report.zip")))
    }

    func testZipRefusesMoreEntriesThanItCanName() throws {
        var archive = ZipArchive()
        for i in 0..<ZipArchive.maxEntries { try archive.add("\(i)", Data()) }
        XCTAssertThrowsError(try archive.add("one more", Data())) { XCTAssertTrue($0.localizedDescription.contains("65535 files"), $0.localizedDescription) }
        XCTAssertNoThrow(try archive.finish())
    }

    func testNothingWithoutTheVariableOrForOtherProviders() throws {
        let env = ["GITHUB_STEP_SUMMARY": tmp.appendingPathComponent("step.md").path, "BITRISE_DEPLOY_DIR": tmp.appendingPathComponent("deploy").path, "BITBUCKET_CLONE_DIR": tmp.appendingPathComponent("clone").path]
        for p in ["gitlab", "codemagic", "circleci", "jenkins"] { try run(verification(ci(p), failed), env) }
        try run(verification(ci("bitbucket"), failed), [:])
        try run(verification(ci("bitrise"), failed), [:])
        XCTAssertEqual(lines, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path), ["report"])
        NativeOutput.write(verification(ci("github"), failed), ci: nil, reportDir: tmp.appendingPathComponent("report"), env: env, out: { self.lines.append($0) }, log: console)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("step.md").path))
    }

    func testNativeOutputFailureIsWarning() throws {
        try run(verification(ci("github"), failed), ["GITHUB_STEP_SUMMARY": tmp.appendingPathComponent("no/such/dir/step.md").path])
        XCTAssertEqual(console.text.split(separator: "\n").count, 1, console.text)
        XCTAssertTrue(console.text.hasPrefix("Could not write the github CI output: "), console.text)
    }

    func testVerifyExitCodeIsUnchangedByAFailingNativeOutput() throws {
        let c = fixtures.appendingPathComponent("changed-pixels")
        let vars = ["SWIFTSHOT_COMMIT": "0123456789abcdef0123456789abcdef01234567", "SWIFTSHOT_BRANCH": "feature/x", "GITHUB_ACTIONS": "true"]
        let env = BaselineEnv.detect(tmp, env: vars, readFile: { _ in nil }, version: "1.0.0-test")
        let config = CompareConfig.from(try Options.parse(["verify", "--config", c.appendingPathComponent("config.json").path]))
        let code = try Baseline.verify(output: c.appendingPathComponent("output"), baseline: c.appendingPathComponent("baseline"), report: tmp.appendingPathComponent("verify-report"),
                                       config: config, env: env, log: console, processEnv: ["GITHUB_STEP_SUMMARY": tmp.appendingPathComponent("no/such/dir/step.md").path], out: { self.lines.append($0) })
        XCTAssertEqual(code, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("verify-report/summary.md").path))
        XCTAssertEqual(lines, ["::error title=changed screenshot::en-US/Pixel 9-Home"])
    }
}
