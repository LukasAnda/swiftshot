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

    func testNoRuntimesIsAnEmptyList() {
        XCTAssertEqual(JsonOutput.devices([], runtimes: []).compact(), #"{"devices":[],"runtimes":[]}"#)
    }
}
