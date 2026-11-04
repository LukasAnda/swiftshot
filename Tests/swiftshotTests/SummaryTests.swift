import XCTest
@testable import swiftshot

/// `summary.md` (docs/wiki/Baseline-format.md); the fixture cases compare it byte for byte in BaselineTests.
final class SummaryTests: XCTestCase {
    func ci(_ provider: String?, buildUrl: String? = nil) -> Ci {
        Ci(provider: provider, commit: nil, branch: nil, pullRequest: nil, fork: nil, buildUrl: buildUrl, repository: nil, isCi: true)
    }

    func entry(_ status: String, _ id: String, _ message: String? = nil) -> [String: JSON] {
        var e: [String: JSON] = ["id": .string(id), "status": .string(status)]
        if let message { e["message"] = .string(message) }
        return e
    }

    func verification(_ entries: [[String: JSON]], ci: Ci? = nil, mismatches: [String] = [], local: Bool = false) -> Verification {
        let errors = entries.filter { $0["status"] == .string("error") }.map { JSON.object(["id": $0["id"]!, "message": $0["message"]!]) }
        return Verification(entries: entries, errors: errors, unattributed: [], fingerprint: [:], mismatches: mismatches, localBaseline: local, strays: 0,
                            env: BaselineEnv(git: GitInfo(commit: nil, branch: nil), version: "1.0.0-test", ci: ci), configHash: "hash")
    }

    func testAcceptHintPerProvider() {
        XCTAssertEqual(Summary.acceptHint("github"), "Comment `/swiftshot accept` on this pull request to accept every change, or put screenshot ids one per line below it to accept some.")
        XCTAssertEqual(Summary.acceptHint("gitlab"), "Run the manual `swiftshot-accept` job in this pipeline to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("bitbucket"), "Run the `swiftshot-accept` custom pipeline on this branch to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("bitrise"), "Run the `swiftshot-accept` workflow on this branch to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("codemagic"), "Start the `swiftshot-accept` workflow on this branch to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("circleci"), "Approve the `accept-screenshots` job in this workflow to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("azure"), "Approve the `Accept screenshots` stage in this run to accept the changes.")
        XCTAssertEqual(Summary.acceptHint("jenkins"), "Approve the `Accept screenshots` stage in this build to accept the changes.")
        XCTAssertEqual(Summary.acceptHint(nil), "Accept the changes with `swiftshot accept --from <this report>`.")
        XCTAssertEqual(Summary.acceptHint("somewhere"), "Accept the changes with `swiftshot accept --from <this report>`.")
    }

    func testPassedHasNoTableAndNoHint() {
        XCTAssertEqual(Summary.markdown(verification([entry("unchanged", "en-US/A")]), ci: nil),
                       "<!-- swiftshot -->\n### Screenshots match the baseline\n\n0 changed · 0 added · 0 removed · 0 errors · 1 unchanged\n")
    }

    func testRowsAreOrderedByStatusThenUtf8IdAndEscaped() {
        let v = verification([entry("added", "b"), entry("removed", "a"), entry("changed", "z|y`x"), entry("error", "m", "boom"), entry("added", "\u{1F600}"), entry("added", "\u{FF5E}"), entry("unchanged", "u")], ci: ci("gitlab"))
        XCTAssertEqual(Summary.markdown(v, ci: ci("gitlab")),
            "<!-- swiftshot -->\n### Screenshot run had errors\n\n1 changed · 3 added · 1 removed · 1 errors · 1 unchanged\n\n" +
            "| Status | Screenshot | Pixels |\n|---|---|---|\n| error | `m` | |\n| changed | `z\\|y'x` | |\n| added | `b` | |\n| added | `\u{FF5E}` | |\n| added | `\u{1F600}` | |\n| removed | `a` | |\n")
    }

    func testPixelsColumnIsAPercentageForChangedRowsOnly() {
        var changed = entry("changed", "a")
        changed["pixels"] = .int(62)
        changed["canvasSize"] = .array([.int(40), .int(80)])
        let text = Summary.markdown(verification([changed, entry("added", "b")]), ci: nil)
        XCTAssertTrue(text.contains("| changed | `a` | 1.9% |\n| added | `b` | |\n"), text)
    }

    func testAlmostEverythingChangedNeverReadsAsAll() {
        var changed = entry("changed", "a")
        changed["pixels"] = .int(1999)
        changed["canvasSize"] = .array([.int(40), .int(50)])
        let text = Summary.markdown(verification([changed]), ci: nil)
        XCTAssertTrue(text.contains("| changed | `a` | \\>99.9% |\n"), text)
    }

    func testPercentIsIntegerMathRoundedHalfUp() {
        let table: [(Int64, Int64, String)] = [(0, 1000, "0.0%"), (1, 1001, "<0.1%"), (1, 2000, "<0.1%"), (1, 1000, "0.1%"), (3, 2000, "0.2%"), (149, 1000, "14.9%"), (999, 1000, "99.9%"), (1999, 2000, ">99.9%"), (9990, 10000, "99.9%"), (9991, 10000, ">99.9%"), (1, 1, "100.0%")]
        for (pixels, total, want) in table {
            XCTAssertEqual(Summary.percent(pixels: pixels, total: total), want, "\(pixels)/\(total)")
        }
        // Far beyond what floats keep exact.
        XCTAssertEqual(Summary.percent(pixels: 1 << 40, total: 3 << 40), "33.3%")
    }

    func testEntriesWithoutAStringIdAreSkipped() {
        let v = verification([entry("added", "b"), ["status": .string("added")], ["id": .int(3), "status": .string("changed")]])
        XCTAssertEqual(Summary.rows(v).map { "\($0.0) \($0.1)" }, ["added b"])
    }

    func testFailedHintFollowsTheFullReportLink() {
        let c = ci("github", buildUrl: "https://example.com/run/1")
        let text = Summary.markdown(verification([entry("added", "a")], ci: c), ci: c)
        XCTAssertTrue(text.hasSuffix("| added | `a` | |\n\n[Full report](https://example.com/run/1)\n\n\(Summary.acceptHint("github"))\n"), text)
        let passed = Summary.markdown(verification([entry("unchanged", "a")], ci: c), ci: c)
        XCTAssertTrue(passed.hasSuffix("1 unchanged\n\n[Full report](https://example.com/run/1)\n"), passed)
    }

    func testNotesComeFromMismatchesThenLocalBaseline() {
        let text = Summary.markdown(verification([entry("unchanged", "a")], mismatches: ["x: baseline 1, this run 2"], local: true), ci: nil)
        XCTAssertTrue(text.contains("\n\n> **Note:** Baseline rendered differently: x: baseline 1, this run 2\n> **Note:** Some baseline images were recorded outside CI (local); record or accept them on CI\n"), text)
    }

    func testManyRowsAreCappedAtTwoHundredAndSixtyThousandBytes() {
        let few = Summary.markdown(verification((1...250).map { entry("added", String(format: "id%03d", $0)) }), ci: nil)
        XCTAssertTrue(few.contains("| added | `id200` | |") && !few.contains("id201") && few.contains("| | …and 50 more | |"), few)
        let long = String(repeating: "x", count: 400)
        let text = Summary.markdown(verification((1...300).map { entry("added", long + String(format: "%03d", $0)) }), ci: nil)
        XCTAssertLessThanOrEqual(text.utf8.count, 60_000)
        let shown = text.components(separatedBy: "| added |").count - 1
        XCTAssertTrue((100...199).contains(shown), "\(shown)")
        XCTAssertTrue(text.contains("| | …and \(300 - shown) more | |"))
    }
}
