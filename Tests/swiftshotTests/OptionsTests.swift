import XCTest
@testable import swiftshot

final class OptionsTests: XCTestCase {
    func testDefaultsWithoutConfig() throws {
        let o = try Options.parse(["--config", emptyConfig()])
        XCTAssertEqual(o.command, "run")
        XCTAssertEqual(o.mode, .virtual)
        XCTAssertTrue(o.noBoot, "no-boot is the default engine")
        XCTAssertEqual(o.languages, ["en-US"])
    }

    func testListsAndCommand() throws {
        let o = try Options.parse(["--config", emptyConfig(), "list", "--devices", "iPhone 18 Pro, iPhone Duo", "--languages", "en-US,de-DE", "--ios", "27.0,27.1"])
        XCTAssertEqual(o.command, "list")
        XCTAssertEqual(o.devices, ["iPhone 18 Pro", "iPhone Duo"])
        XCTAssertEqual(o.languages, ["en-US", "de-DE"])
        XCTAssertEqual(o.iosVersions, ["27.0", "27.1"])
    }

    func testUnknownCommandAndOption() {
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "deploy"]))
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "--no-such-flag"]))
    }

    func testConfigFileThenCLIOverrides() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-\(UUID()).json")
        try #"{"devices": ["iPhone 17"], "languages": ["fr-FR"], "output_directory": "out"}"#.write(to: url, atomically: true, encoding: .utf8)
        let o = try Options.parse(["--config", url.path, "--languages", "ja-JP"])
        XCTAssertEqual(o.devices, ["iPhone 17"])
        XCTAssertEqual(o.languages, ["ja-JP"], "CLI wins over the config file")
        XCTAssertEqual(o.output, "out")
    }

    func testScreenRule() throws {
        let r = try parseScreenRule("Settings: appearances=light,dark devices=iPhone_17 full_length=true delay=0.5")
        XCTAssertEqual(r.preview, "Settings")
        XCTAssertEqual(r.appearances, ["light", "dark"])
        XCTAssertEqual(r.fullLength, true)
        XCTAssertEqual(r.delay, 0.5)
        XCTAssertThrowsError(try parseScreenRule("no colon here"))
        XCTAssertThrowsError(try parseScreenRule("X: colour=red"))
    }

    func testFrameOptions() throws {
        XCTAssertNil(try Options.parse(["--config", emptyConfig()]).frame, "no frames by default")
        XCTAssertEqual(try Options.parse(["--config", emptyConfig(), "--frame"]).frame, .plain)
        XCTAssertEqual(try Options.parse(["--config", emptyConfig(), "--frame", "--verbose"]).frame, .plain, "the mode is optional")
        let o = try Options.parse(["--config", emptyConfig(), "--frame", "appstore", "--frame-color", "Deep Blue, iPad Pro 13-inch (M5)=Silver",
                                   "--framefile", "F.json", "--frame-background", "#000000", "--accept-bezel-license"])
        XCTAssertEqual(o.frame, .appstore)
        XCTAssertEqual(o.frameColors, ["Deep Blue", "iPad Pro 13-inch (M5)=Silver"])
        XCTAssertEqual(o.framefile, "F.json"); XCTAssertEqual(o.frameBackground, "#000000"); XCTAssertTrue(o.acceptBezelLicense)
        XCTAssertNil(try Options.parse(["--config", emptyConfig(), "--frame", "none"]).frame)
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "--screen", "X: frame=fancy"]))
        XCTAssertEqual(try parseScreenRule("Debug*: frame=none").frame, "none")
    }

    func testFrameConfigKeys() throws {
        func parse(_ json: String) throws -> Options {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-\(UUID()).json")
            try json.write(to: url, atomically: true, encoding: .utf8)
            return try Options.parse(["--config", url.path])
        }
        XCTAssertEqual(try parse(#"{"frame": true}"#).frame, .plain)
        XCTAssertNil(try parse(#"{"frame": false}"#).frame)
        XCTAssertEqual(try parse(#"{"frame": "appstore", "frame_color": "Silver"}"#).frameColors, ["Silver"])
        XCTAssertEqual(try parse(#"{"frame_color": {"iPhone 17": "Black", "iPhone Air": "Sky Blue"}}"#).frameColors, ["iPhone 17=Black", "iPhone Air=Sky Blue"])
        XCTAssertEqual(try parse(#"{"frame_color": ["Silver"], "frame_output": "out", "accept_bezel_license": true}"#).frameOutput, "out")
        XCTAssertThrowsError(try parse(#"{"frame": "shiny"}"#))
        XCTAssertEqual(try parse(#"{"screens": [{"preview": "Debug", "frame": "none"}]}"#).screens.first?.frame, "none")
    }

    func testFrameCommand() throws {
        let o = try Options.parse(["--config", emptyConfig(), "frame", "fastlane/screenshots"])
        XCTAssertEqual(o.command, "frame")
        XCTAssertEqual(o.inputFiles, ["fastlane/screenshots"])
        XCTAssertEqual(o.frame, .plain, "like frameit: plain unless asked")
        XCTAssertEqual(try Options.parse(["--config", emptyConfig(), "frame", "--frame", "appstore"]).frame, .appstore)
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "frame", "a", "b"]))
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "frame", "--frame", "none"]))
    }

    func testTextSizes() throws {
        XCTAssertNoThrow(try validateTextSizes(["default", "XXXL", "AX5"]))
        XCTAssertThrowsError(try validateTextSizes(["enormous"]))
        XCTAssertEqual(contentSizeCategory("XXXL"), "UICTContentSizeCategoryXXXL")
        XCTAssertEqual(contentSizeCategory("AX5"), "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertNil(contentSizeCategory("default"))
    }

    func testLocaleIdentifier() {
        XCTAssertEqual(localeIdentifier(for: "de-DE"), "de_DE")
        XCTAssertEqual(localeIdentifier(for: "en"), "en")
    }

    // MARK: verify, record, accept

    private func config(_ json: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-\(UUID()).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testBaselineCommandsAndKeys() throws {
        let path = config(#"{"output_directory": "shots", "baseline_directory": "base", "report_directory": "rep", "tolerance": {"pixels": 5, "max_channel_delta": 1}, "screens": [{"preview": "Clock*", "tolerance": {"max_channel_delta": 2}}, {"preview": "Feed", "ignore_regions": [[0, 0, 16, 4]]}, {"preview": "Other", "appearances": ["dark"]}]}"#)
        let o = try Options.parse(["--config", path, "verify"])
        XCTAssertEqual(o.command, "verify")
        XCTAssertEqual(o.baselineDirectory, "base")
        XCTAssertEqual(o.reportDirectory, "rep")
        XCTAssertEqual(o.tolerance, Tolerance(pixels: 5, maxChannelDelta: 1))
        let c = CompareConfig.from(o)
        XCTAssertEqual(c.rules.map(\.preview), ["Clock*", "Feed", "Other"])
        XCTAssertEqual(c.rules[0].tolerance, Tolerance(pixels: 0, maxChannelDelta: 2))
        XCTAssertEqual(c.rules[1].ignoreRegions, [[0, 0, 16, 4]])
        XCTAssertNil(c.rules[2].tolerance)
        XCTAssertEqual(try Options.parse(["--config", path, "record", "--baseline-directory", "b2", "--report-directory", "r2"]).baselineDirectory, "b2")
        // Defaults.
        let d = try Options.parse(["--config", config("{}"), "verify", "--output", "out"])
        XCTAssertEqual(d.baselineDirectory, "screenshots-baseline")
        XCTAssertTrue(d.reportPath.hasSuffix("/out-report"), d.reportPath)
        XCTAssertNil(d.tolerance)
    }

    func testBaselineCommandsComparePlainPngsOnly() throws {
        for command in ["verify", "record"] {
            XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), command, "--format", "jpeg"])) { XCTAssertTrue($0 is UsageError, "\($0)") }
            XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), command, "--frame"])) { XCTAssertTrue($0 is UsageError, "\($0)") }
            XCTAssertThrowsError(try Options.parse(["--config", config(#"{"format": "jpeg"}"#), command])) { XCTAssertTrue($0 is UsageError, "\($0)") }
            // A config's frames are for run: verify and record skip them.
            let o = try Options.parse(["--config", config(#"{"frame": "appstore", "screens": [{"preview": "A", "frame": "plain"}]}"#), command])
            XCTAssertNil(o.frame)
            XCTAssertNil(o.screens[0].frame)
            XCTAssertTrue(FrameRun.modes(o).isEmpty)
        }
        XCTAssertNoThrow(try Options.parse(["--config", emptyConfig(), "run", "--format", "jpeg"]))
    }

    func testInvalidToleranceIsAUsageError() {
        for bad in [#"{"tolerance": {"pixels": -1}}"#, #"{"tolerance": {"pixels": 1.5}}"#, #"{"tolerance": {"colour": 1}}"#, #"{"tolerance": 3}"#,
                    #"{"screens": [{"preview": "A", "ignore_regions": [[0, 0, 1]]}]}"#, #"{"screens": [{"preview": "A", "ignore_regions": [[0, 0, -1, 1]]}]}"#] {
            XCTAssertThrowsError(try Options.parse(["--config", config(bad), "verify"]), bad) { XCTAssertTrue($0 is UsageError, "\(bad): \($0)") }
        }
    }

    func testAcceptFlagsAreForAcceptOnly() {
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "verify", "--from", "x"]))
        XCTAssertThrowsError(try Options.parse(["--config", emptyConfig(), "run", "--only", "x"]))
    }

    func testUsageErrorsExit64() async {
        let empty = emptyConfig()
        do { let code = await Command.run(["--config", empty, "verify", "--format", "jpeg"]); XCTAssertEqual(code, 64) }
        do { let code = await Command.run(["--config", empty, "record", "--frame"]); XCTAssertEqual(code, 64) }
        do { let code = await Command.run(["--config", empty, "accept"]); XCTAssertEqual(code, 64) }
        do { let code = await Command.run(["--config", empty, "verify", "--no-such-flag"]); XCTAssertEqual(code, 64) }
    }

    func testCommandAfterLeadingFlags() async throws {
        let empty = emptyConfig()
        XCTAssertEqual(Options.command(["-v", "verify"]), "verify")
        XCTAssertEqual(Options.command(["--output", "out", "--no-boot", "record"]), "record")
        XCTAssertEqual(Options.command(["--frame", "plain", "--output", "out"]), "run")
        let o = try Options.parse(["--config", empty, "-v", "verify", "--output", "out"])
        XCTAssertEqual(o.command, "verify")
        XCTAssertTrue(o.verbose)
        XCTAssertEqual(try Options.parse(["--config", empty, "--output", "out", "list"]).command, "list")
        // A usage error of verify after a leading flag is still verify's: 64.
        do { let code = await Command.run(["--config", empty, "-v", "verify", "--no-such-flag"]); XCTAssertEqual(code, 64) }
        do { let code = await Command.run(["-v", "--config", empty, "accept"]); XCTAssertEqual(code, 64) }
    }

    private func emptyConfig() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-empty.json")
        try? "{}".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
