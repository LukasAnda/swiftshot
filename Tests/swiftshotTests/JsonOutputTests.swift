import XCTest
@testable import swiftshot

final class JsonOutputTests: XCTestCase {
    func testListKeepsTheOrder() {
        XCTAssertEqual(JsonOutput.list(previews: ["Welcome", "Settings"]).compact(), #"{"previews":[{"name":"Welcome"},{"name":"Settings"}]}"#)
        XCTAssertEqual(JsonOutput.list(previews: []).compact(), #"{"previews":[]}"#)
    }

    func testListEscapesNames() {
        XCTAssertEqual(JsonOutput.list(previews: ["A \"b\""]).compact(), #"{"previews":[{"name":"A \"b\""}]}"#)
    }

    func testDevicesAreNumbersWithSortedKeys() {
        let json = JsonOutput.devices([.init(name: "iPhone 17 Pro", platform: "ios", width: 402, height: 874, scale: 3),
                                       .init(name: "iPhone 12 mini", platform: "ios", width: 375, height: 812, scale: 2.88)], runtimes: ["26.5", "27.0"])
        XCTAssertEqual(json.compact(), #"{"devices":[{"height":874,"name":"iPhone 17 Pro","platform":"ios","scale":3,"width":402},"#
            + #"{"height":812,"name":"iPhone 12 mini","platform":"ios","scale":2.88,"width":375}],"runtimes":["26.5","27.0"]}"#)
        XCTAssertTrue(json.pretty().hasSuffix("}\n"))
    }

    func testUsageAndVersionGoToStderrWithJson() {
        var out: [String] = [], err: [String] = []
        Options.info("usage", json: true, stdout: { out.append($0) }, stderr: { err.append($0) })
        XCTAssertEqual(out, [])
        XCTAssertEqual(err, ["usage"])
        Options.info("usage", json: false, stdout: { out.append($0) }, stderr: { err.append($0) })
        XCTAssertEqual(out, ["usage"])
    }

    func testNoRuntimesIsAnEmptyList() {
        XCTAssertEqual(JsonOutput.devices([], runtimes: []).compact(), #"{"devices":[],"runtimes":[]}"#)
    }
}

extension JsonOutputTests {
    /// Shared/testdata/json/list.json: the bytes both CLIs print for these previews.
    func testListMatchesTheSharedFixture() throws {
        let expected = try String(contentsOf: repoRoot.appendingPathComponent("Shared/testdata/json/list.json"), encoding: .utf8)
        XCTAssertEqual(JsonOutput.list(previews: ["Welcome", "Settings \"dark\"", "Zürich"]).pretty(), expected)
    }
}
