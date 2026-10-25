import XCTest
@testable import swiftshot

final class ShellTests: XCTestCase {
    /// Every byte of a large output arrives, with many commands running at once (a `simctl list -j`
    /// used to come back cut short).
    func testLargeOutputIsComplete() async throws {
        let size = 3_000_000
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<40 {
                group.addTask { try await sh(["/bin/sh", "-c", "head -c \(size) /dev/zero | tr '\\\\0' a"], stdoutOnly: true).utf8.count }
            }
            for try await count in group { XCTAssertEqual(count, size) }
        }
    }

    func testFailureCarriesOutput() async {
        do { _ = try await sh(["/bin/sh", "-c", "echo out; echo err >&2; exit 3"]); XCTFail("no error") } catch let error as ShellError {
            XCTAssertEqual(error.status, 3)
            XCTAssertTrue(error.output.contains("out") && error.output.contains("err"))
        } catch { XCTFail("\(error)") }
    }
}
