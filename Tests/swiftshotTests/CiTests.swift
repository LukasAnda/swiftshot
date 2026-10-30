import XCTest
@testable import swiftshot

/// CI detection against the shared fixtures in Shared/testdata/ci (docs/wiki/Baseline-format.md, "CI detection").
final class CiTests: XCTestCase {
    let root = repoRoot.appendingPathComponent("Shared/testdata/ci")

    func detect(_ env: [String: String], _ files: [String: String] = [:]) -> Ci { Ci.detect(env, readFile: { files[$0] }) }

    func testEveryFixtureCaseMatches() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertEqual(names.count, 20, "fixture cases")
        var problems: [String] = []
        for name in names {
            let c = try readJSON(root.appendingPathComponent(name))
            var env: [String: String] = [:]
            for (k, v) in c["env"]!.object! { env[k] = v.string! }
            var files: [String: String] = [:]
            for (k, v) in c["files"]?.object ?? [:] { files[k] = v.string ?? v.compact() }
            let ci = detect(env, files)
            func opt(_ s: String?) -> JSON { s.map { .string($0) } ?? .null }
            let got: JSON = .object([
                "provider": opt(ci.provider), "commit": opt(ci.commit), "branch": opt(ci.branch), "pullRequest": opt(ci.pullRequest),
                "fork": ci.fork.map { .bool($0) } ?? .null, "buildUrl": opt(ci.buildUrl), "repository": opt(ci.repository),
                "isCi": .bool(ci.isCi), "warnings": .array(ci.warnings.map { .string($0) }),
            ])
            if got.compact() != c["expected"]!.compact() { problems.append("\(name):\n  want \(c["expected"]!.compact())\n  got  \(got.compact())") }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testEmptyValuesCountAsUnset() {
        let ci = detect(["GITLAB_CI": "true", "CI_COMMIT_SHA": "abc1234", "CI_MERGE_REQUEST_SOURCE_BRANCH_SHA": "", "CI_COMMIT_BRANCH": "", "CI_JOB_URL": ""])
        XCTAssertEqual(ci.commit, "abc1234")
        XCTAssertNil(ci.branch)
        XCTAssertNil(ci.buildUrl)
        XCTAssertFalse(detect(["GITHUB_ACTIONS": ""]).isCi)
    }

    func testSwiftshotCiOverridesDetection() {
        let gh = ["GITHUB_ACTIONS": "true", "GITHUB_SHA": "abc1234"]
        XCTAssertFalse(detect(gh.merging(["SWIFTSHOT_CI": "0"]) { $1 }).isCi)
        XCTAssertEqual(detect(gh.merging(["SWIFTSHOT_CI": "1"]) { $1 }).provider, "github")
        XCTAssertEqual(detect(gh.merging(["SWIFTSHOT_CI": ""]) { $1 }).provider, "github")
        // A CI of unknown provider: SWIFTSHOT_CI or the generic CI variable.
        for env in [["SWIFTSHOT_CI": "TRUE"], ["CI": "true"], ["CI": "1"]] {
            let ci = detect(env)
            XCTAssertTrue(ci.isCi, "\(env)")
            XCTAssertNil(ci.provider)
        }
        XCTAssertFalse(detect(["CI": "false"]).isCi)
    }

    func testFirstProviderInTableOrderWins() {
        XCTAssertEqual(detect(["GITHUB_ACTIONS": "true", "JENKINS_URL": "https://j/", "CIRCLECI": "true"]).provider, "github")
        XCTAssertEqual(detect(["JENKINS_URL": "https://j/", "CIRCLECI": "true"]).provider, "circleci")
    }

    func testMalformedGithubEventFallsBackToTheMergeCommit() {
        let env = ["GITHUB_ACTIONS": "true", "GITHUB_SHA": "5e6f708", "GITHUB_EVENT_PATH": "event.json"]
        for text in ["{", "[]", "\"x\"", ""] {
            let ci = detect(env, ["event.json": text])
            XCTAssertEqual(ci.commit, "5e6f708", text)
            XCTAssertEqual(ci.warnings, ["GITHUB_EVENT_PATH unreadable; recording GITHUB_SHA, which is a merge commit on pull requests"], text)
        }
        // An unset path is not an error.
        var unset = env
        unset["GITHUB_EVENT_PATH"] = nil
        XCTAssertEqual(detect(unset).warnings, [])
    }

    func testGithubPushEventHasNoPullRequest() {
        let ci = detect(["GITHUB_ACTIONS": "true", "GITHUB_SHA": "abc1234", "GITHUB_EVENT_PATH": "e.json"], ["e.json": #"{"ref": "refs/heads/main"}"#])
        XCTAssertEqual(ci.commit, "abc1234")
        XCTAssertNil(ci.pullRequest)
        XCTAssertEqual(ci.warnings, [])
    }

    func testDefaultReaderReadsAFileOrNothing() throws {
        let dir = temporaryDirectory("swiftshot-ci")
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("event.json")
        try "{}".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(defaultRead(f.path), "{}")
        XCTAssertNil(defaultRead(dir.appendingPathComponent("missing.json").path))
        XCTAssertNil(defaultRead(dir.path))
    }

    func testJenkinsBranchWithoutOriginPrefixAndAzureRefs() {
        XCTAssertEqual(detect(["JENKINS_URL": "https://j/", "GIT_BRANCH": "origin/release/1"]).branch, "release/1")
        XCTAssertEqual(detect(["TF_BUILD": "True", "BUILD_SOURCEBRANCH": "refs/heads/feature/tools", "BUILD_SOURCEBRANCHNAME": "tools"]).branch, "feature/tools")
        XCTAssertEqual(detect(["TF_BUILD": "True", "BUILD_SOURCEBRANCHNAME": "tools"]).branch, "tools")
    }
}
