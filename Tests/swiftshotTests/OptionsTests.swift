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

    private func emptyConfig() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-empty.json")
        try? "{}".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
