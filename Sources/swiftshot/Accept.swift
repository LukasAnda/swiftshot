import Foundation

/// `accept` (docs/wiki/Baseline-format.md): applies verify reports to the baseline without rendering. Changed and
/// added ids get the report's new image, removed ids lose theirs; nothing else in the baseline is touched.
/// Exit 0 applied (or nothing to do), 64 usage or invalid report, 1 refused (stale report, push failed), 2 interrupted
/// (SIGINT or SIGTERM: the baseline may be partly updated, as on Android).
enum Accept {
    static let defaultAuthor = "swiftshot <swiftshot@users.noreply.github.com>"
    /// The trailer that marks a commit made by `accept`; its value is the verified commit.
    static let trailer = "Swiftshot-Accept"

    /// A refusal (exit 1): the report doesn't fit the branch, or git couldn't finish.
    struct Refused: Error, CustomStringConvertible { let description: String }

    /// Set by SIGINT or SIGTERM; accept looks at it between steps. A second signal ends the process at once.
    final class Interruption: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        func set() { lock.lock(); flag = true; lock.unlock() }
    }

    /// accept was interrupted (exit 2).
    struct Interrupted: Error {}

    /// The exit status for an error: an interrupted accept is 2 whatever the step it stopped in failed with.
    static func exitCode(for error: Error, interrupted: Bool) -> Int32 {
        if interrupted || error is Interrupted { return 2 }
        return error is UsageError ? 64 : 1
    }

    /// What one report does to one id: a new image (changed, added) or none (removed).
    struct Change {
        let id: String
        let kind: String
        let report: String
        let png: URL?
        let entry: [String: JSON]?
        let fingerprint: JSON?

        func sameAs(_ o: Change) -> Bool {
            guard (png == nil) == (o.png == nil), entry == o.entry else { return false }
            guard let a = png, let b = o.png else { return true }
            return (try? Data(contentsOf: a)) == (try? Data(contentsOf: b))
        }
    }

    /// `errors`: the verify had errors (its result.json status is `error`).
    struct Report { let label: String; let commit: String; let changes: [Change]; let errors: Bool }

    static func message(changed: Int, added: Int, removed: Int) -> String {
        let parts = [(changed, "changed"), (added, "added"), (removed, "removed")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return "Update screenshot baseline (\(parts.joined(separator: ", ")))"
    }

    static func run(from: [String], only: Set<String>?, push: Bool, author: String?, baseline: URL, log: Console,
                    branch: String? = nil, env: [String: String] = [:], gitEnv: [String: String] = [:],
                    interruption: Interruption = Interruption(), handleSignals: Bool = false) -> Int32 {
        var temps: [URL] = []
        let sources = handleSignals ? watchSignals(interruption) : []
        defer {
            for s in sources { s.cancel() }
            for sig in handleSignals ? [SIGINT, SIGTERM] : [] { signal(sig, SIG_DFL) }
            for t in temps { try? FileManager.default.removeItem(at: t) }
        }
        do {
            return try apply(from: from, only: only, push: push, author: author, baseline: baseline.standardizedFileURL, log: log, branch: branch, env: env, gitEnv: gitEnv, temps: &temps, interruption: interruption)
        } catch {
            let code = exitCode(for: error, interrupted: interruption.isSet)
            if code == 2 {
                log.error("accept was interrupted; the baseline may be partly updated (git status shows what changed)")
            } else if let e = error as? UsageError {
                log.error(e.description)
            } else if let e = error as? Refused {
                log.error(e.description)
            } else {
                log.error((error as NSError).localizedDescription)
            }
            return code
        }
    }

    /// The first SIGINT or SIGTERM sets the flag; the next one restores the default and ends the process.
    private static func watchSignals(_ interruption: Interruption) -> [DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler {
                if interruption.isSet { signal(sig, SIG_DFL); raise(sig) } else { interruption.set() }
            }
            source.resume()
            return source
        }
    }

    private static func check(_ interruption: Interruption) throws {
        if interruption.isSet { throw Interrupted() }
    }

    private static func apply(from: [String], only: Set<String>?, push: Bool, author: String?, baseline: URL, log: Console, branch: String?,
                              env: [String: String], gitEnv: [String: String], temps: inout [URL], interruption: Interruption) throws -> Int32 {
        func v(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        let token = v("SWIFTSHOT_ARTIFACT_TOKEN")
        if from.isEmpty { throw UsageError("accept needs --from <report directory, .zip or URL>") }
        let identity = try parseAuthor(author ?? defaultAuthor)
        var start = baseline
        while !isDirectory(start) && start.path != "/" { start = start.deletingLastPathComponent() }
        guard let top = Git(dir: start, env: gitEnv).out("rev-parse", "--show-toplevel") else {
            throw UsageError("\(baseline.path) is not in a git repository: accept checks the report against the branch")
        }
        let git = Git(dir: URL(fileURLWithPath: top), env: gitEnv)
        guard let head = git.out("rev-parse", "HEAD") else { throw UsageError("The repository at \(top) has no commits") }

        // Refuse before downloading or writing anything: a fork's branch can't be pushed to, and a detached HEAD needs a name.
        let ci = Ci.detect(env)
        var target: [String] = []
        if push {
            if ci.fork == true { throw Refused(description: "This pull request comes from a fork; download the report and run swiftshot accept --from <report> in the fork") }
            target = try pushTarget(git, branch: branch, ciBranch: v("SWIFTSHOT_BRANCH") ?? ci.branch)
        }

        let reports = try from.map { try load($0, token: token, env: env, temps: &temps) }
        try check(interruption)
        var changes: [String: [Change]] = [:]
        for c in reports.flatMap(\.changes) { changes[c.id, default: []].append(c) }
        if let only {
            let unknown = only.subtracting(changes.keys).sorted(by: utf8Less)
            if !unknown.isEmpty { throw UsageError("--only: not changed, added or removed in the report: \(unknown.joined(separator: ", "))") }
        }
        // Several reports may name the same id (overlapping runs), but only with the same content.
        let selected: [Change] = try changes.keys.filter { only == nil || only!.contains($0) }.sorted(by: utf8Less).map { id in
            let list = changes[id]!
            if let other = list.first(where: { !$0.sameAs(list[0]) }) { throw UsageError("\(id) differs between \(list[0].report) and \(other.report); accept them separately") }
            return list[0]
        }
        var seenCommits: [String] = []
        for r in reports where !seenCommits.contains(r.commit) { seenCommits.append(r.commit) }
        for commit in seenCommits { try checkFresh(git, commit: commit, head: head) }
        for r in reports where r.errors { log.warn("\(r.label): verify had errors; only its changed, added and removed screenshots are accepted (those with errors keep their baseline)") }

        if selected.isEmpty {
            log.ok("Nothing to accept: the report has no changed, added or removed screenshots\(only != nil ? " among --only" : "")")
            return 0
        }
        let written = try write(baseline, selected, interruption)
        let counts = ["changed", "added", "removed"].map { k in selected.filter { $0.kind == k }.count }
        if counts[2] == selected.count { log.warn("Every change in the report is a removal (\(count(counts[2], "screenshot"))); check the run rendered what you expected") }
        let summary = message(changed: counts[0], added: counts[1], removed: counts[2])
        log.ok("\(summary.dropFirst("Update screenshot baseline (".count).dropLast()) → \(baseline.path)")
        if !push { return 0 }

        // Only the files accept wrote or deleted: other edits in the baseline directory stay out of the commit.
        let topPath = URL(fileURLWithPath: top).resolvingSymlinksInPath().path
        let basePath = canonical(baseline).path
        let relative = basePath == topPath ? "" : basePath.hasPrefix(topPath + "/") ? String(basePath.dropFirst(topPath.count + 1)) : basePath
        let prefix = relative.isEmpty ? "" : relative + "/"
        let ours = written.map { prefix + $0 }
        // A deleted file git never knew can't be staged; leave it out.
        let tracked = Set(git.run("ls-files", "-z", "--", ":(literal)" + (prefix.isEmpty ? "." : prefix)).out.split(separator: "\0").map(String.init))
        let specs = ours.filter { FileManager.default.fileExists(atPath: topPath + "/" + $0) || tracked.contains($0) }.map { ":(literal)" + $0 }
        try check(interruption)
        _ = try git.must("add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", input: specs.joined(separator: "\0"))
        let staged = try git.must("-c", "core.quotePath=false", "diff", "--cached", "--name-only", "--no-renames", "-z")
            .split(separator: "\0").map(String.init).filter { ours.contains($0) }
        if staged.isEmpty {
            log.ok("The baseline already matches the report; nothing to commit")
            return 0
        }
        let trailers = seenCommits.map { "\(trailer): \($0)" }.joined(separator: "\n")
        _ = try git.must("-c", "user.name=\(identity.name)", "-c", "user.email=\(identity.email)", "commit", "-q",
                         "--author", "\(identity.name) <\(identity.email)>", "-m", summary, "-m", trailers,
                         "--pathspec-from-file=-", "--pathspec-file-nul", input: staged.map { ":(literal)" + $0 }.joined(separator: "\0"))
        let commit = git.out("rev-parse", "HEAD") ?? "?"
        let header = pushHeader(git, remote: target[0], env: env, log: log)
        let command = pushCommand(target, header: header, processEnv: ProcessInfo.processInfo.environment.merging(gitEnv) { $1 })
        let pushGit = header == nil ? git : Git(dir: URL(fileURLWithPath: top), env: gitEnv.merging(command.env) { $1 }, secrets: secrets(header!, v("SWIFTSHOT_HOST_TOKEN")))
        let pushed = pushGit.run(command.args)
        if pushed.code != 0 { throw Refused(description: "Committed \(commit), but git push \(target.joined(separator: " ")) failed:\n\(pushed.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        log.ok("Committed \(commit) and pushed to \(target.joined(separator: " "))")
        return 0
    }

    /// What `git push` gets: `--branch`, else the upstream, else (detached) the CI's branch, else `origin HEAD`.
    private static func pushTarget(_ git: Git, branch: String?, ciBranch: String?) throws -> [String] {
        let current = git.out("symbolic-ref", "--short", "-q", "HEAD")
        let remote = current.flatMap { git.out("config", "branch.\($0).remote") }
        let merge = current.flatMap { git.out("config", "branch.\($0).merge") }
        func named(_ name: String) throws -> [String] {
            if git.run("check-ref-format", "refs/heads/\(name)").code != 0 { throw UsageError("\"\(name)\" is not a valid branch name") }
            return [remote ?? "origin", "HEAD:refs/heads/\(name)"]
        }
        if let branch { return try named(branch) }
        if let remote, let merge { return [remote, "HEAD:\(merge)"] }
        if current != nil { return ["origin", "HEAD"] }
        if let ciBranch { return try named(ciBranch) }
        throw Refused(description: "HEAD is detached and no branch is known; pass --branch <the pull request branch>")
    }

    /// `git push` `target` and the environment that carries `header` to that one command: `GIT_CONFIG_*` entries after
    /// any `processEnv` already has, so the token is never on git's command line or in the git config.
    static func pushCommand(_ target: [String], header: String?, processEnv: [String: String]) -> (args: [String], env: [String: String]) {
        let args = ["push"] + target
        guard let header else { return (args, [:]) }
        let n = processEnv["GIT_CONFIG_COUNT"].flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil } ?? 0
        return (args, ["GIT_CONFIG_COUNT": "\(n + 1)", "GIT_CONFIG_KEY_\(n)": "http.extraHeader", "GIT_CONFIG_VALUE_\(n)": header])
    }

    /// The `http.extraHeader` for pushing to `remote` with `SWIFTSHOT_HOST_TOKEN`; nil when there is no token, or (with
    /// a warning) when the remote isn't https (or this machine) or its host is unknown.
    private static func pushHeader(_ git: Git, remote: String, env: [String: String], log: Console) -> String? {
        guard let token = env["SWIFTSHOT_HOST_TOKEN"], !token.isEmpty else { return nil }
        guard let url = git.out("remote", "get-url", "--push", remote), let u = URL(string: url), let scheme = u.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && Download.loopback.contains((u.host ?? "").lowercased())) else {
            log.warn("SWIFTSHOT_HOST_TOKEN is not used: \(remote) is not an https remote (a token push needs one)")
            return nil
        }
        guard let host = Host.detect(url, env: env) else {
            log.warn("SWIFTSHOT_HOST_TOKEN is not used: the git host of \(remote) is unknown (set SWIFTSHOT_GIT_HOST to github, gitlab or bitbucket)")
            return nil
        }
        return host.pushHeader(token, jobToken: env["CI_JOB_TOKEN"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// What git output must never show: the header, its base64 credential and the token.
    private static func secrets(_ header: String, _ token: String?) -> [String] {
        var all = [header]
        if let r = header.range(of: "Basic ") { all.append(String(header[r.upperBound...])) }
        if let token { all.append(token) }
        return all.filter { !$0.isEmpty }
    }

    private static func isDirectory(_ url: URL) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue }

    /// The path with symbolic links resolved in its existing part.
    static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL, rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) && existing.path != "/" { rest.insert(existing.lastPathComponent, at: 0); existing = existing.deletingLastPathComponent() }
        var out = existing.resolvingSymlinksInPath()
        for r in rest { out.appendPathComponent(r) }
        return out.standardizedFileURL
    }

    /// Writes the images, then baseline.json (temp file + rename); the paths it wrote or deleted, relative to the baseline.
    private static func write(_ baseline: URL, _ selected: [Change], _ interruption: Interruption) throws -> [String] {
        let fm = FileManager.default
        let jsonFile = baseline.appendingPathComponent("baseline.json")
        var json: [String: JSON]?
        if fm.fileExists(atPath: jsonFile.path) {
            guard let j = (try? JSON.parse(try Data(contentsOf: jsonFile)))?.object else { throw UsageError("\(jsonFile.path) is not valid JSON") }
            json = j
        }
        func map(_ key: String) throws -> [String: JSON] {
            guard let v = json?[key] else { return [:] }
            guard let o = v.object, o.values.allSatisfy({ $0.object != nil }) else { throw UsageError("\(jsonFile.path): \"\(key)\" must be an object of objects") }
            return o
        }
        var fingerprints = try map("fingerprints")
        var images = try map("images")
        try fm.createDirectory(at: baseline, withIntermediateDirectories: true)
        let root = canonical(baseline)
        for c in selected where !canonical(root.appendingPathComponent(c.id + ".png")).path.hasPrefix(root.path + "/") {
            throw UsageError("\(c.id): outside the baseline directory")
        }
        for c in selected {
            try check(interruption)
            let target = root.appendingPathComponent(c.id + ".png")
            if let png = c.png {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fm.attributesOfItem(atPath: target.path)) != nil { try fm.removeItem(at: target) }
                try fm.copyItem(at: png, to: target)
                let fid = Fingerprints.id(c.fingerprint!)
                fingerprints[fid] = c.fingerprint!
                var entry = c.entry!
                entry["fingerprint"] = .string(fid)
                images[c.id] = .object(entry)
            } else {
                try? fm.removeItem(at: target)
                images[c.id] = nil
                var dir = target.deletingLastPathComponent()
                while dir.path != root.path && dir.path.hasPrefix(root.path + "/"), (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                    try? fm.removeItem(at: dir)
                    dir = dir.deletingLastPathComponent()
                }
            }
        }
        let referenced = Set(images.values.compactMap { $0["fingerprint"]?.string })
        let tmp = root.appendingPathComponent(".baseline.json.tmp")
        let out: JSON = .object(["schema": .int(1), "fingerprints": .object(fingerprints.filter { referenced.contains($0.key) }), "images": .object(images)])
        try Data(out.pretty().utf8).write(to: tmp)
        guard rename(tmp.path, root.appendingPathComponent("baseline.json").path) == 0 else {
            throw CLIError("Couldn't replace \(root.path)/baseline.json: \(String(cString: strerror(errno)))")
        }
        return selected.map { $0.id + ".png" } + ["baseline.json"]
    }

    /// The report must be from HEAD, or from a commit that only accept commits follow.
    private static func checkFresh(_ git: Git, commit: String, head: String) throws {
        if commit == head { return }
        if git.run("cat-file", "-e", "\(commit)^{commit}").code != 0 {
            throw Refused(description: "The report is from commit \(commit), which this repository doesn't have (HEAD is \(head)). Run verify on \(head) and accept that report.")
        }
        if git.run("merge-base", "--is-ancestor", commit, head).code != 0 {
            throw Refused(description: "The report is from commit \(commit), which is not an ancestor of HEAD \(head). Run verify on \(head) and accept that report.")
        }
        let log = git.out("log", "--format=%H%x1f%(trailers:key=\(trailer),valueonly)%x1e", "\(commit)..\(head)") ?? ""
        let others: [String] = log.split(separator: "\u{1e}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.compactMap { rec in
            let parts = rec.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
            let trailer = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return trailer.isEmpty ? String(parts[0]) : nil
        }
        if !others.isEmpty {
            let one = others.count == 1
            let shown = others.prefix(3).map { String($0.prefix(12)) }.joined(separator: ", ") + (others.count > 3 ? ", …" : "")
            throw Refused(description: "The report is from commit \(commit), but HEAD is \(head) and \(others.count) commit\(one ? "" : "s") since then "
                + "\(one ? "is not a baseline commit" : "are not baseline commits") made by accept (\(shown)). Run verify on \(head) and accept that report.")
        }
    }

    private static func parseAuthor(_ s: String) throws -> (name: String, email: String) {
        let regex = try NSRegularExpression(pattern: #"^\s*([^<>]*?)\s*<([^<>\s]+@[^<>\s]+)>\s*$"#)
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { throw UsageError("--author: \"Name <email>\", not \"\(s)\"") }
        let name = ns.substring(with: m.range(at: 1)), email = ns.substring(with: m.range(at: 2))
        if name.trimmingCharacters(in: .whitespaces).isEmpty { throw UsageError("--author: \"Name <email>\", not \"\(s)\"") }
        return (name, email)
    }

    // MARK: reports

    private static func load(_ from: String, token: String?, env: [String: String], temps: inout [URL]) throws -> Report {
        let fm = FileManager.default
        func tempDir() throws -> URL {
            let t = fm.temporaryDirectory.appendingPathComponent("swiftshot-accept-\(UUID().uuidString)")
            try fm.createDirectory(at: t, withIntermediateDirectories: true)
            temps.append(t)
            return t
        }
        let lower = from.lowercased()
        let dir: URL
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            let tmp = try tempDir()
            let zip = tmp.appendingPathComponent("report.zip")
            try Download.fetch(from, to: zip, token: token, env: env, maxBytes: Zip.maxBytes)
            dir = try extracted(zip, into: tmp.appendingPathComponent("report"), label: from)
        } else if isDirectory(URL(fileURLWithPath: from)) {
            dir = URL(fileURLWithPath: from)
        } else if fm.fileExists(atPath: from) {
            dir = try extracted(URL(fileURLWithPath: from), into: try tempDir(), label: from)
        } else {
            throw UsageError("--from \(from): no such report directory or zip")
        }
        return try read(dir, label: from)
    }

    /// Unzips `zip` into `dest`; the report is its root or its only top-level directory.
    private static func extracted(_ zip: URL, into dest: URL, label: String) throws -> URL {
        do { try Zip.extract(zip, to: dest, label: label) } catch let e as UsageError { throw e } catch {
            throw UsageError("\(label): damaged zip file (\((error as NSError).localizedDescription))")
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.appendingPathComponent("manifest.json").path) { return dest }
        let dirs = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []).map { dest.appendingPathComponent($0) }.filter(isDirectory)
        if dirs.count == 1, fm.fileExists(atPath: dirs[0].appendingPathComponent("manifest.json").path) { return dirs[0] }
        throw UsageError("\(label): no manifest.json in the zip (expected a verify report directory)")
    }

    private static func read(_ dir: URL, label: String) throws -> Report {
        func json(_ name: String) throws -> [String: JSON] {
            let f = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: f.path) else { throw UsageError("\(label): no \(name) (expected a verify report directory)") }
            guard let o = (try? JSON.parse(try Data(contentsOf: f)))?.object else { throw UsageError("\(label): \(name) is not valid JSON") }
            return o
        }
        let manifest = try json("manifest.json")
        guard manifest["schema"]?.number == 1 else { throw UsageError("\(label): manifest.json schema \(manifest["schema"]?.text ?? "null") is not supported") }
        guard let commit = manifest["commit"]?.string else { throw UsageError("\(label): manifest.json has no commit (verify ran outside a git checkout)") }
        guard commit.range(of: "^[0-9a-f]{7,64}$", options: .regularExpression) != nil else { throw UsageError("\(label): manifest.json commit \"\(commit)\" is not a commit hash") }
        // null (not a CI) or an object (which CI); a manifest of the earlier boolean form, or none, is refused.
        guard let ci = manifest["ci"], ci == .null || ci.object != nil else { throw UsageError("\(label): manifest.json has no ci") }
        let local = ci == .null
        guard let fingerprint = manifest["fingerprint"]?.object else { throw UsageError("\(label): manifest.json has no fingerprint") }
        guard let ids = manifest["ids"]?.object else { throw UsageError("\(label): manifest.json has no ids") }
        let result = try json("result.json")
        var shots: [String: [String: JSON]] = [:]
        for s in result["screenshots"]?.array ?? [] { if let o = s.object, let id = o["id"]?.string { shots[id] = o } }
        var changes: [Change] = []
        var seen = Set<String>()
        for kind in ["changed", "added", "removed"] {
            guard let list = ids[kind]?.array else { throw UsageError("\(label): manifest.json ids.\(kind) is missing") }
            for raw in list {
                guard let id = raw.string else { throw UsageError("\(label): manifest.json ids.\(kind) has a non-string id") }
                try checkId(id, label: label)
                guard seen.insert(id).inserted else { throw UsageError("\(label): \(id) is listed twice in manifest.json") }
                if kind == "removed" { changes.append(Change(id: id, kind: kind, report: label, png: nil, entry: nil, fingerprint: nil)); continue }
                guard let shot = shots[id], shot["status"] == .string(kind) else { throw UsageError("\(label): \(id) is \(kind) in manifest.json but not in result.json") }
                let png = dir.appendingPathComponent("images/new/\(id).png")
                var d: ObjCBool = false
                guard FileManager.default.fileExists(atPath: png.path, isDirectory: &d), !d.boolValue else { throw UsageError("\(label): images/new/\(id).png is missing") }
                guard let platform = shot["platform"]?.string else { throw UsageError("\(label): \(id) has no platform in result.json") }
                guard let runFp = fingerprint[platform], runFp.object != nil else { throw UsageError("\(label): manifest.json has no \(platform) fingerprint for \(id)") }
                let fp = Fingerprints.forImage(runFp, shot)
                var entry = Baseline.describe(shot)
                entry["local"] = .bool(local)
                entry["fingerprint"] = .string(Fingerprints.id(fp))
                changes.append(Change(id: id, kind: kind, report: label, png: png, entry: entry, fingerprint: fp))
            }
        }
        return Report(label: label, commit: commit, changes: changes, errors: result["status"] == .string("error"))
    }

    /// A screenshot id is a relative `/`-separated path; nothing that could leave the baseline directory.
    private static func checkId(_ id: String, label: String) throws {
        if !Baseline.validId(id) { throw UsageError("\(label): \"\(id)\" is not a valid screenshot id") }
    }

    // MARK: git

    struct Git {
        let dir: URL
        let env: [String: String]
        /// Never in the output of a run: each is replaced with `***`.
        var secrets: [String] = []

        private func hide(_ s: String) -> String { secrets.sorted { $0.count > $1.count }.reduce(s) { $0.replacingOccurrences(of: $1, with: "***") } }

        func run(_ args: String..., input: String? = nil) -> Proc.Result { run(args, input: input) }

        func run(_ args: [String], input: String? = nil) -> Proc.Result {
            var e = env
            e["GIT_TERMINAL_PROMPT"] = "0"
            let r = Proc.run(["git"] + args, cwd: dir, env: e, input: input.map { Data($0.utf8) })
            return secrets.isEmpty ? r : Proc.Result(code: r.code, out: hide(r.out), err: hide(r.err))
        }

        /// Trimmed output, nil on failure or no output.
        func out(_ args: String...) -> String? {
            let r = run(args)
            let s = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.code == 0 && !s.isEmpty ? s : nil
        }

        func must(_ args: String..., input: String? = nil) throws -> String {
            let r = run(args, input: input)
            if r.code != 0 {
                let name = args.first { !$0.hasPrefix("-") && !$0.contains("=") } ?? "git"
                throw Refused(description: "git \(name) failed:\n\((r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return r.out
        }
    }
}

/// `accept --from <url>`: a report zip over HTTP(S). The artifact token goes only to the host it was given for, never
/// along a redirect to storage elsewhere; redirects are followed here (at most 10), not by URLSession.
enum Download {
    /// Hosts that are this machine: a token may go there over plain http.
    static let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"]

    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let out: FileHandle
        let maxBytes: Int64
        var received: Int64 = 0
        var response: HTTPURLResponse?
        var error: Error?
        var tooLarge = false
        let done = DispatchSemaphore(value: 0)
        init(out: FileHandle, maxBytes: Int64) { self.out = out; self.maxBytes = maxBytes }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)   // handled by the caller
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response as? HTTPURLResponse
            completionHandler(self.response?.statusCode == 200 ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            received += Int64(data.count)
            if received > maxBytes { tooLarge = true; dataTask.cancel(); return }
            do { try out.write(contentsOf: data) } catch { self.error = error; dataTask.cancel() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if self.error == nil, let error, (error as NSError).code != NSURLErrorCancelled { self.error = error }
            done.signal()
        }
    }

    /// The header that carries the artifact `token` to `url`: `SWIFTSHOT_ARTIFACT_HEADER` ("Name: value", `{token}` in the value)
    /// wins, else the host's own (docs/wiki/Baseline-format.md, "accept"), else Bearer.
    static func artifactHeader(_ url: URL, token: String, env: [String: String]) throws -> (name: String, value: String) {
        if let template = env["SWIFTSHOT_ARTIFACT_HEADER"], !template.isEmpty {
            guard let colon = template.firstIndex(of: ":"), !template[..<colon].trimmingCharacters(in: .whitespaces).isEmpty else {
                throw UsageError("SWIFTSHOT_ARTIFACT_HEADER: \"Name: value\" with {token} in the value")
            }
            return (template[..<colon].trimmingCharacters(in: .whitespaces),
                    template[template.index(after: colon)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "{token}", with: token))
        }
        func hostOf(_ key: String) -> String? { env[key].flatMap { URL(string: $0)?.host?.lowercased() } }
        func basic(_ s: String) -> String { "Basic " + Data(s.utf8).base64EncodedString() }
        let host = url.host?.lowercased() ?? ""
        if host == "api.github.com" || host == hostOf("GITHUB_API_URL") { return ("Authorization", "Bearer \(token)") }
        if host == "gitlab.com" || host == hostOf("CI_API_V4_URL") { return (token == env["CI_JOB_TOKEN"] ? "JOB-TOKEN" : "PRIVATE-TOKEN", token) }
        if host == "circleci.com" || host.hasSuffix(".circleci.com") { return ("Circle-Token", token) }
        if host == "dev.azure.com" || host.hasSuffix(".visualstudio.com") { return ("Authorization", basic(":\(token)")) }
        if token.contains(":") { return ("Authorization", basic(token)) }
        return ("Authorization", "Bearer \(token)")
    }

    static func fetch(_ url: String, to dest: URL, token: String?, env: [String: String], maxBytes: Int64) throws {
        guard let origin = URL(string: url), let host = origin.host else { throw UsageError("--from \(url): not a valid URL") }
        // A bearer token in plain text is anyone's on the way; this machine's own server (tests, a local proxy) is no way.
        if token != nil, origin.scheme?.lowercased() != "https", !loopback.contains(host.lowercased()) {
            throw UsageError("--from \(url): SWIFTSHOT_ARTIFACT_TOKEN is sent only over https; use an https URL or unset the token")
        }
        let auth = try token.map { try artifactHeader(origin, token: $0, env: env) }
        var current = origin
        for _ in 0..<10 {
            var request = URLRequest(url: current, timeoutInterval: 600)
            request.setValue("swiftshot", forHTTPHeaderField: "User-Agent")
            if let auth, current.scheme?.lowercased() == origin.scheme?.lowercased(), current.host?.lowercased() == origin.host?.lowercased(), current.port == origin.port {
                request.setValue(auth.value, forHTTPHeaderField: auth.name)
            }
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            guard let out = FileHandle(forWritingAtPath: dest.path) else { throw UsageError("--from \(url): can't write \(dest.path)") }
            let receiver = Receiver(out: out, maxBytes: maxBytes)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 600
            config.httpShouldSetCookies = false
            let session = URLSession(configuration: config, delegate: receiver, delegateQueue: nil)
            session.dataTask(with: request).resume()
            receiver.done.wait()
            session.finishTasksAndInvalidate()
            try? out.close()
            if receiver.tooLarge { throw UsageError("--from \(url): larger than \(maxBytes >> 30) GB") }
            if let error = receiver.error { throw UsageError("--from \(url): download failed: \(error.localizedDescription)") }
            guard let response = receiver.response else { throw UsageError("--from \(url): download failed: no response") }
            let code = response.statusCode
            if (300...399).contains(code), let location = response.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: current)?.absoluteURL {
                current = next
                continue
            }
            if code == 200 { return }
            throw UsageError("--from \(url): HTTP \(code)\([401, 403, 404].contains(code) ? " (is SWIFTSHOT_ARTIFACT_TOKEN set and allowed to read it?)" : "")")
        }
        throw UsageError("--from \(url): too many redirects")
    }
}
