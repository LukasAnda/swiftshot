import Foundation

/// `accept` (docs/wiki/Baseline-format.md): applies verify reports to the baseline without rendering. Changed and
/// added ids get the report's new image, removed ids lose theirs; nothing else in the baseline is touched.
/// Exit 0 applied (or nothing to do), 64 usage or invalid report, 1 refused (stale report, push failed).
enum Accept {
    static let defaultAuthor = "swiftshot <swiftshot@users.noreply.github.com>"
    /// The trailer that marks a commit made by `accept`; its value is the verified commit.
    static let trailer = "Swiftshot-Accept"

    /// A refusal (exit 1): the report doesn't fit the branch, or git couldn't finish.
    struct Refused: Error, CustomStringConvertible { let description: String }

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

    struct Report { let label: String; let commit: String; let changes: [Change] }

    static func message(changed: Int, added: Int, removed: Int) -> String {
        let parts = [(changed, "changed"), (added, "added"), (removed, "removed")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return "Update screenshot baseline (\(parts.joined(separator: ", ")))"
    }

    static func run(from: [String], only: Set<String>?, push: Bool, author: String?, baseline: URL, log: Console,
                    token: String? = ProcessInfo.processInfo.environment["SWIFTSHOT_ARTIFACT_TOKEN"].flatMap { $0.isEmpty ? nil : $0 },
                    gitEnv: [String: String] = [:]) -> Int32 {
        var temps: [URL] = []
        defer { for t in temps { try? FileManager.default.removeItem(at: t) } }
        do {
            return try apply(from: from, only: only, push: push, author: author, baseline: baseline.standardizedFileURL, log: log, token: token, gitEnv: gitEnv, temps: &temps)
        } catch let e as UsageError {
            log.error(e.description); return 64
        } catch let e as Refused {
            log.error(e.description); return 1
        } catch {
            log.error((error as NSError).localizedDescription); return 1
        }
    }

    private static func apply(from: [String], only: Set<String>?, push: Bool, author: String?, baseline: URL, log: Console, token: String?,
                              gitEnv: [String: String], temps: inout [URL]) throws -> Int32 {
        if from.isEmpty { throw UsageError("accept needs --from <report directory, .zip or URL>") }
        let identity = try parseAuthor(author ?? defaultAuthor)
        var start = baseline
        while !isDirectory(start) && start.path != "/" { start = start.deletingLastPathComponent() }
        guard let top = Git(dir: start, env: gitEnv).out("rev-parse", "--show-toplevel") else {
            throw UsageError("\(baseline.path) is not in a git repository: accept checks the report against the branch")
        }
        let git = Git(dir: URL(fileURLWithPath: top), env: gitEnv)
        guard let head = git.out("rev-parse", "HEAD") else { throw UsageError("The repository at \(top) has no commits") }

        let reports = try from.map { try load($0, token: token, temps: &temps) }
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

        if selected.isEmpty {
            log.ok("Nothing to accept: the report has no changed, added or removed screenshots\(only != nil ? " among --only" : "")")
            return 0
        }
        let written = try write(baseline, selected)
        let counts = ["changed", "added", "removed"].map { k in selected.filter { $0.kind == k }.count }
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
        let branch = git.out("symbolic-ref", "--short", "-q", "HEAD")
        let remote = branch.flatMap { git.out("config", "branch.\($0).remote") }
        let merge = branch.flatMap { git.out("config", "branch.\($0).merge") }
        let target = remote != nil && merge != nil ? [remote!, "HEAD:\(merge!)"] : ["origin", "HEAD"]
        let pushed = git.run(["push"] + target)
        if pushed.code != 0 { throw Refused(description: "Committed \(commit), but git push \(target.joined(separator: " ")) failed:\n\(pushed.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        log.ok("Committed \(commit) and pushed to \(target.joined(separator: " "))")
        return 0
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
    private static func write(_ baseline: URL, _ selected: [Change]) throws -> [String] {
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

    private static func load(_ from: String, token: String?, temps: inout [URL]) throws -> Report {
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
            try Download.fetch(from, to: zip, token: token, maxBytes: Zip.maxBytes)
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
        guard let ci = manifest["ci"]?.bool else { throw UsageError("\(label): manifest.json has no ci") }
        guard let fingerprint = manifest["fingerprint"]?.object else { throw UsageError("\(label): manifest.json has no fingerprint") }
        guard let ids = manifest["ids"]?.object else { throw UsageError("\(label): manifest.json has no ids") }
        var shots: [String: [String: JSON]] = [:]
        for s in try json("result.json")["screenshots"]?.array ?? [] { if let o = s.object, let id = o["id"]?.string { shots[id] = o } }
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
                entry["local"] = .bool(!ci)
                entry["fingerprint"] = .string(Fingerprints.id(fp))
                changes.append(Change(id: id, kind: kind, report: label, png: png, entry: entry, fingerprint: fp))
            }
        }
        return Report(label: label, commit: commit, changes: changes)
    }

    /// A screenshot id is a relative `/`-separated path; nothing that could leave the baseline directory.
    private static func checkId(_ id: String, label: String) throws {
        let bad = id.isEmpty || id.hasPrefix("/") || id.contains("\\") || id.contains("\0") || id.range(of: "^[A-Za-z]:", options: .regularExpression) != nil
            || id.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
        if bad { throw UsageError("\(label): \"\(id)\" is not a valid screenshot id") }
    }

    // MARK: git

    struct Git {
        let dir: URL
        let env: [String: String]

        func run(_ args: String..., input: String? = nil) -> Proc.Result { run(args, input: input) }

        func run(_ args: [String], input: String? = nil) -> Proc.Result {
            var e = env
            e["GIT_TERMINAL_PROMPT"] = "0"
            return Proc.run(["git"] + args, cwd: dir, env: e, input: input.map { Data($0.utf8) })
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

    static func fetch(_ url: String, to dest: URL, token: String?, maxBytes: Int64) throws {
        guard let origin = URL(string: url), origin.host != nil else { throw UsageError("--from \(url): not a valid URL") }
        var current = origin
        for _ in 0..<10 {
            var request = URLRequest(url: current, timeoutInterval: 600)
            request.setValue("swiftshot", forHTTPHeaderField: "User-Agent")
            if let token, current.scheme?.lowercased() == origin.scheme?.lowercased(), current.host?.lowercased() == origin.host?.lowercased(), current.port == origin.port {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
