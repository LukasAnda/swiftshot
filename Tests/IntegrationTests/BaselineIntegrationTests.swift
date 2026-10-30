// Screenshot testing end to end on a copy of Example/DemoApp in its own git repository (`make`
// first; no simulator is booted):
//   make && SWIFTSHOT_INTEGRATION=1 swift test --filter BaselineIntegrationTests
// record, verify passes, one colour changed (Welcome's glow) makes verify fail with exactly the
// Welcome screenshots, accept applies the report, verify passes again, and a report from an older
// commit is refused. The comparison takes under 5 % of the render time (the run's own timings).

import XCTest

final class BaselineIntegrationTests: XCTestCase {
    static let root = ParityAndPerformanceTests.root
    static let tool = ParityAndPerformanceTests.tool
    static let env = ProcessInfo.processInfo.environment
    static let device = ParityAndPerformanceTests.devices.split(separator: ",").first.map(String.init) ?? "iPhone 18 Pro"
    static let work = URL(fileURLWithPath: env["SWIFTSHOT_IT_OUT"] ?? FileManager.default.temporaryDirectory.path)
        .appendingPathComponent("swiftshot-it-baseline-\(ProcessInfo.processInfo.processIdentifier)")

    var project: URL { Self.work.appendingPathComponent("DemoApp") }
    var output: URL { Self.work.appendingPathComponent("out") }
    var baseline: URL { project.appendingPathComponent("screenshots-baseline") }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.env["SWIFTSHOT_INTEGRATION"] == "1", "set SWIFTSHOT_INTEGRATION=1 (needs Xcode, an iOS runtime, `make`)")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.tool), "run `make` first")
    }

    /// Runs a program in the project copy; its exit code and output (also appended to a log the CI job follows).
    @discardableResult
    func exec(_ program: String, _ args: [String], log: String) throws -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: program)
        p.arguments = args
        p.currentDirectoryURL = project
        // Real git: accept checks the report's commit against HEAD.
        p.environment = Self.env.filter { $0.key != "SWIFTSHOT_COMMIT" && $0.key != "SWIFTSHOT_BRANCH" }
        let logURL = Self.work.appendingPathComponent("\(log).log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        var data = Data()
        while case let chunk = pipe.fileHandleForReading.availableData, !chunk.isEmpty { data.append(chunk); handle.write(chunk) }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func git(_ args: String...) throws {
        let r = try exec("/usr/bin/git", ["-c", "user.name=swiftshot-test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + args, log: "git")
        XCTAssertEqual(r.code, 0, "git \(args.joined(separator: " ")): \(r.output)")
    }

    /// One device, language and appearance keep it quick; the comparison covers Welcome and Settings.
    func swiftshot(_ command: String, report: String) throws -> (code: Int32, output: String) {
        try exec(Self.tool, [command, "--devices", Self.device, "--ios", ParityAndPerformanceTests.ios, "--languages", "en-US", "--appearances", "light",
                             "--previews", "Welcome,Settings", "--output", output.path, "--report-directory", Self.work.appendingPathComponent(report).path],
                 log: command)
    }

    func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], url.path)
    }

    func screenshots(_ report: String) throws -> [[String: Any]] {
        try XCTUnwrap(json(Self.work.appendingPathComponent("\(report)/result.json"))["screenshots"] as? [[String: Any]])
    }

    /// The comparison's share of the render time: timings.json in the report, totalSeconds in the run's report.
    func assertOverhead(_ report: String) throws {
        let compare = try XCTUnwrap(json(Self.work.appendingPathComponent("\(report)/timings.json"))["compareSeconds"] as? Double)
        let render = try XCTUnwrap(json(output.appendingPathComponent("swiftshot-report.json"))["totalSeconds"] as? Double)
        print(String(format: "overhead (%@): compare %.3f s of render %.1f s = %.2f %%", report, compare, render, 100 * compare / render))
        XCTAssertLessThan(compare, 0.05 * render, "\(report): the comparison took over 5 % of the render time")
    }

    func testRecordVerifyAccept() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.work)
        try fm.createDirectory(at: Self.work, withIntermediateDirectories: true)
        // The copy: sources and project, not earlier output.
        let source = Self.root.appendingPathComponent("Example/DemoApp")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(atPath: source.path) where ![".swiftshot", "screenshots", "fastlane"].contains(item) {
            try fm.copyItem(at: source.appendingPathComponent(item), to: project.appendingPathComponent(item))
        }
        try "{\"project\": \"DemoApp.xcodeproj\", \"scheme\": \"DemoApp\"}\n".write(to: project.appendingPathComponent("swiftshot.json"), atomically: true, encoding: .utf8)
        try git("init", "-q", "-b", "main")
        try git("add", "-A"); try git("commit", "-q", "-m", "Demo app")

        var r = try swiftshot("record", report: "unused")
        XCTAssertEqual(r.code, 0, "record:\n\(r.output.suffix(4000))")
        let recorded = try fm.contentsOfDirectory(atPath: baseline.appendingPathComponent("en-US").path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(recorded.count, 2, "baseline: \(recorded)")
        try git("add", "-A"); try git("commit", "-q", "-m", "Baseline")

        r = try swiftshot("verify", report: "report-same")
        XCTAssertEqual(r.code, 0, "verify on the recorded state:\n\(r.output.suffix(4000))")
        try assertOverhead("report-same")
        let welcome = try screenshots("report-same").filter { $0["preview"] as? String == "Welcome" }.compactMap { $0["id"] as? String }
        XCTAssertFalse(welcome.isEmpty)

        // One colour in the copy: Welcome's second glow becomes blue.
        let file = project.appendingPathComponent("Sources/WelcomeView.swift")
        let swift = try String(contentsOf: file, encoding: .utf8)
        let colour = "Color(red: 1.0, green: 0.70, blue: 0.35)"
        XCTAssertTrue(swift.contains(colour), "the colour to change is not in WelcomeView.swift")
        try swift.replacingOccurrences(of: colour, with: "Color(red: 0.18, green: 0.42, blue: 1.0)").write(to: file, atomically: true, encoding: .utf8)
        try git("commit", "-q", "-am", "Blue glow")

        r = try swiftshot("verify", report: "report-changed")
        XCTAssertEqual(r.code, 1, "verify after the colour change:\n\(r.output.suffix(4000))")
        let differing = try screenshots("report-changed").filter { $0["status"] as? String != "unchanged" }
        print("changed: \(differing.map { "\($0["id"] ?? "") \($0["status"] ?? "")" })")
        XCTAssertEqual(differing.compactMap { $0["id"] as? String }, welcome, "exactly the Welcome screenshots differ")
        XCTAssertEqual(Set(differing.compactMap { $0["status"] as? String }), ["changed"])
        let manifest = try json(Self.work.appendingPathComponent("report-changed/manifest.json"))
        XCTAssertEqual((manifest["ids"] as? [String: [String]])?["changed"], welcome)
        try assertOverhead("report-changed")

        r = try exec(Self.tool, ["accept", "--from", Self.work.appendingPathComponent("report-changed").path], log: "accept")
        XCTAssertEqual(r.code, 0, "accept:\n\(r.output)")
        for id in welcome {
            XCTAssertEqual(try Data(contentsOf: baseline.appendingPathComponent("\(id).png")),
                           try Data(contentsOf: Self.work.appendingPathComponent("report-changed/images/new/\(id).png")), "accept did not copy \(id)")
        }
        try git("add", "-A"); try git("commit", "-q", "-m", "Accept the blue glow")

        r = try swiftshot("verify", report: "report-accepted")
        XCTAssertEqual(r.code, 0, "verify after accept:\n\(r.output.suffix(4000))")

        // A report from an older commit: an unrelated commit since, so accept refuses it and changes nothing.
        try "unrelated\n".write(to: project.appendingPathComponent("NOTES.txt"), atomically: true, encoding: .utf8)
        try git("add", "NOTES.txt"); try git("commit", "-q", "-m", "Unrelated")
        let before = try baselineFiles()
        r = try exec(Self.tool, ["accept", "--from", Self.work.appendingPathComponent("report-changed").path], log: "stale")
        print("stale accept: exit \(r.code): \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        XCTAssertEqual(r.code, 1, "accept of a stale report:\n\(r.output)")
        XCTAssertTrue(r.output.contains("commit"), "the refusal names the commit")
        XCTAssertEqual(try baselineFiles(), before, "the refused accept changed the baseline")
    }

    private func baselineFiles() throws -> [String: Data] {
        var files: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: baseline, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = e?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files[url.path] = try Data(contentsOf: url) }
        }
        return files
    }
}
