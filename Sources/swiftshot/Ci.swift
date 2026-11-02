import Foundation

/// A file's text, a relative path from the working directory; nil when it can't be read.
func defaultRead(_ path: String) -> String? {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
    return try? String(contentsOfFile: path, encoding: .utf8)
}

/// Where a run happens, from the CI's environment (docs/wiki/Baseline-format.md, "CI detection"). `isCi` is false
/// when no CI was found or `SWIFTSHOT_CI` says there is none; `provider` is nil for a CI of unknown provider.
/// `warnings` are printed by verify. `repository` is the clone URL or slug the CI gives (not written to reports).
struct Ci: Equatable {
    var provider: String?
    var commit: String?
    var branch: String?
    var pullRequest: String?
    var fork: Bool?
    var buildUrl: String?
    var repository: String?
    var isCi: Bool
    var warnings: [String] = []

    static let eventWarning = "GITHUB_EVENT_PATH unreadable; recording GITHUB_SHA, which is a merge commit on pull requests"
    private static let none = Ci(provider: nil, commit: nil, branch: nil, pullRequest: nil, fork: nil, buildUrl: nil, repository: nil, isCi: false)

    /// `env` is the whole environment; `readFile` reads the GitHub event file. Empty values count as unset.
    static func detect(_ env: [String: String], readFile: (String) -> String? = defaultRead) -> Ci {
        func v(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        func flag(_ k: String) -> Bool { v(k)?.lowercased() == "true" }
        func first(_ s: String?...) -> String? { s.first { $0 != nil && !$0!.isEmpty } ?? nil }
        func after(_ prefix: String, _ s: String?) -> String? { s.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 } }
        func ci(_ provider: String?, _ commit: String?, _ branch: String?, _ pr: String?, _ fork: Bool?, _ url: String?, _ repo: String?) -> Ci {
            Ci(provider: provider, commit: commit, branch: branch, pullRequest: pr, fork: fork, buildUrl: url, repository: repo, isCi: true)
        }

        let override = v("SWIFTSHOT_CI")
        if let o = override, o.lowercased() != "true", o != "1" { return none }

        if flag("GITHUB_ACTIONS") { return github(env, readFile) }
        if flag("GITLAB_CI") {
            let source = v("CI_MERGE_REQUEST_SOURCE_PROJECT_ID"), target = v("CI_MERGE_REQUEST_PROJECT_ID")
            return ci("gitlab", first(v("CI_MERGE_REQUEST_SOURCE_BRANCH_SHA"), v("CI_COMMIT_SHA")),
                      first(v("CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"), v("CI_COMMIT_BRANCH")), v("CI_MERGE_REQUEST_IID"),
                      source != nil && target != nil ? source != target : nil, v("CI_JOB_URL"), v("CI_PROJECT_URL"))
        }
        if v("BITBUCKET_BUILD_NUMBER") != nil {
            let pr = v("BITBUCKET_PR_ID")
            var url: String? = nil
            if let origin = v("BITBUCKET_GIT_HTTP_ORIGIN"), let n = v("BITBUCKET_BUILD_NUMBER") { url = "\(origin)/pipelines/results/\(n)" }
            return ci("bitbucket", v("BITBUCKET_COMMIT"), v("BITBUCKET_BRANCH"), pr, pr != nil ? false : nil, url, v("BITBUCKET_GIT_HTTP_ORIGIN"))
        }
        if flag("BITRISE_IO") {
            let from = v("BITRISEIO_PULL_REQUEST_REPOSITORY_URL"), repo = v("GIT_REPOSITORY_URL")
            return ci("bitrise", first(v("BITRISE_GIT_COMMIT"), v("GIT_CLONE_COMMIT_HASH")), v("BITRISE_GIT_BRANCH"), v("BITRISE_PULL_REQUEST"),
                      from != nil && repo != nil ? from != repo : nil, v("BITRISE_BUILD_URL"), repo)
        }
        if v("CM_BUILD_ID") != nil {
            return ci("codemagic", v("CM_COMMIT"), v("CM_BRANCH"),
                      v("CM_PULL_REQUEST_NUMBER"), nil, nil, nil)
        }
        if flag("CIRCLECI") {
            let url = v("CIRCLE_PULL_REQUEST")
            let number = url.flatMap { u -> String? in
                var s = Substring(u)
                while s.hasSuffix("/") { s = s.dropLast() }
                return String(s.split(separator: "/", omittingEmptySubsequences: false).last ?? s)
            }
            return ci("circleci", v("CIRCLE_SHA1"), v("CIRCLE_BRANCH"), number,
                      v("CIRCLE_PR_NUMBER") != nil ? true : url != nil ? false : nil, v("CIRCLE_BUILD_URL"), v("CIRCLE_REPOSITORY_URL"))
        }
        if flag("TF_BUILD") {
            var url: String? = nil
            if var collection = v("SYSTEM_COLLECTIONURI"), let project = v("SYSTEM_TEAMPROJECT"), let build = v("BUILD_BUILDID") {
                while collection.hasSuffix("/") { collection.removeLast() }
                url = "\(collection)/\(project)/_build/results?buildId=\(build)"
            }
            let fork: Bool?
            switch v("SYSTEM_PULLREQUEST_ISFORK")?.lowercased() { case "true": fork = true; case "false": fork = false; default: fork = nil }
            return ci("azure", first(v("SYSTEM_PULLREQUEST_SOURCECOMMITID"), v("BUILD_SOURCEVERSION")),
                      first(after("refs/heads/", v("SYSTEM_PULLREQUEST_SOURCEBRANCH")), after("refs/heads/", v("BUILD_SOURCEBRANCH")), v("BUILD_SOURCEBRANCHNAME")),
                      first(v("SYSTEM_PULLREQUEST_PULLREQUESTNUMBER"), v("SYSTEM_PULLREQUEST_PULLREQUESTID")), fork, url, v("BUILD_REPOSITORY_URI"))
        }
        if v("JENKINS_URL") != nil {
            let id = v("CHANGE_ID")
            return ci("jenkins", v("GIT_COMMIT"), first(v("CHANGE_BRANCH"), v("BRANCH_NAME"), after("origin/", v("GIT_BRANCH"))), id,
                      v("CHANGE_FORK") != nil ? true : id != nil ? false : nil, v("BUILD_URL"), v("GIT_URL"))
        }
        if override != nil || ["true", "1"].contains(v("CI")?.lowercased() ?? "") { return ci(nil, nil, nil, nil, nil, nil, nil) }
        return none
    }

    /// GitHub Actions: the pull request's head commit, number and fork flag are only in the event file.
    private static func github(_ env: [String: String], _ readFile: (String) -> String?) -> Ci {
        func v(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        var warnings: [String] = []
        var event: JSON? = nil
        if let path = v("GITHUB_EVENT_PATH") {
            event = readFile(path).flatMap { try? JSON.parse($0) }.flatMap { $0.object == nil ? nil : $0 }
            if event == nil { warnings.append(eventWarning) }
        }
        func text(_ j: JSON?) -> String? { j?.string.flatMap { $0.isEmpty ? nil : $0 } }
        let pull = event?["pull_request"]
        let head = text(pull?["head"]?["repo"]?["full_name"]), base = text(pull?["base"]?["repo"]?["full_name"])
        var number: String? = nil
        if case .int(let n)? = pull?["number"] { number = String(n) }
        var url: String? = nil, repository: String? = nil
        if let server = v("GITHUB_SERVER_URL"), let repo = v("GITHUB_REPOSITORY") {
            repository = "\(server)/\(repo)"
            if let run = v("GITHUB_RUN_ID") { url = "\(server)/\(repo)/actions/runs/\(run)" }
        }
        // GITHUB_REF_NAME is a branch to push to only on a push of a branch (an issue comment's is the default branch).
        let pushed = v("GITHUB_EVENT_NAME") == "push" && v("GITHUB_REF_TYPE") != "tag"
        return Ci(provider: "github", commit: text(pull?["head"]?["sha"]) ?? v("GITHUB_SHA"), branch: v("GITHUB_HEAD_REF") ?? (pushed ? v("GITHUB_REF_NAME") : nil),
                  pullRequest: number, fork: head != nil && base != nil ? head != base : nil, buildUrl: url, repository: repository,
                  isCi: true, warnings: warnings)
    }
}
