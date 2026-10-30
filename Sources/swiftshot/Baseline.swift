import Foundation

/// A `screens` rule's comparison settings (rules without them still decide which rule applies first).
struct CompareRule: Equatable {
    var preview: String
    var tolerance: Tolerance? = nil
    var ignoreRegions: [[Double]]? = nil
}

/// The comparison config of docs/wiki/Baseline-format.md: the global `tolerance` and the `screens` rules in order.
struct CompareConfig {
    var tolerance: Tolerance?
    var rules: [CompareRule]

    /// The tolerance and the ignored pixels for a screenshot of `preview`, rendered in `mode` at `scale` px per pt.
    func forShot(preview: String, mode: String?, scale: Double) -> (Tolerance, [Region]) {
        let rule = rules.first { Baseline.glob($0.preview, preview) }
        let t = rule?.tolerance ?? tolerance ?? (mode == "device" ? Tolerance(pixels: 0, maxChannelDelta: 1) : Tolerance())
        return (t, (rule?.ignoreRegions ?? []).map { Compare.ignoreRegion($0, scale: scale) })
    }

    /// configHash: the hash of the normalized config.
    func hash() -> String {
        func tol(_ t: Tolerance?) -> JSON { .object(["max_channel_delta": .int(Int64(t?.maxChannelDelta ?? 0)), "pixels": .int(Int64(t?.pixels ?? 0))]) }
        let screens: [JSON] = rules.map { r in
            var m: [String: JSON] = ["preview": .string(r.preview)]
            if let t = r.tolerance { m["tolerance"] = tol(t) }
            if let regions = r.ignoreRegions { m["ignore_regions"] = .array(regions.map { .array($0.map { .double($0) }) }) }
            return .object(m)
        }
        return CanonicalJson.hash(.object(["screens": .array(screens), "tolerance": tol(tolerance)]))
    }

    static func from(_ o: Options) -> CompareConfig {
        CompareConfig(tolerance: o.tolerance, rules: o.screens.enumerated().map { i, r in
            let c = i < o.screenComparisons.count ? o.screenComparisons[i] : nil
            return CompareRule(preview: r.preview, tolerance: c?.tolerance, ignoreRegions: c?.ignoreRegions)
        })
    }
}

/// Commit and branch: `SWIFTSHOT_COMMIT`/`SWIFTSHOT_BRANCH`, else git; nil when unknown.
struct GitInfo {
    var commit: String?
    var branch: String?

    static func detect(_ dir: URL) -> GitInfo {
        func git(_ args: String...) -> String? {
            let r = Proc.run(["git"] + args, cwd: dir)
            let out = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.code == 0 && !out.isEmpty ? out : nil
        }
        let env = ProcessInfo.processInfo.environment
        let commit = env["SWIFTSHOT_COMMIT"] ?? git("rev-parse", "HEAD")
        let branch = env["SWIFTSHOT_BRANCH"] ?? git("rev-parse", "--abbrev-ref", "HEAD").flatMap { $0 == "HEAD" ? nil : $0 }
        return GitInfo(commit: commit, branch: branch)
    }
}

/// What a verify run records about where it ran.
struct BaselineEnv {
    var git: GitInfo
    var version: String
    var ci: Bool

    static func detect(_ dir: URL) -> BaselineEnv { BaselineEnv(git: GitInfo.detect(dir), version: Fingerprints.version(), ci: ci()) }

    /// `SWIFTSHOT_CI` (true/false), else `CI` set to true.
    static func ci() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let v = env["SWIFTSHOT_CI"] { return v.lowercased() == "true" || v == "1" }
        return env["CI"].map { $0.lowercased() == "true" || $0 == "1" } ?? false
    }
}

/// The outcome of comparing one run with the baseline (written as result.json, manifest.json, junit.xml).
struct Verification {
    let entries: [[String: JSON]]
    /// Every {"id", "message"} of an error entry, then the run's errors without id.
    let errors: [JSON]
    let unattributed: [JSON]
    let fingerprint: [String: JSON]
    let mismatches: [String]
    let localBaseline: Bool
    let strays: Int
    let env: BaselineEnv
    let configHash: String

    var counts: [String: Int] {
        var c: [String: Int] = [:]
        for k in ["unchanged", "changed", "added", "removed"] { c[k] = entries.filter { $0["status"] == .string(k) }.count }
        c["errors"] = errors.count
        return c
    }
    var failures: Int { let c = counts; return c["changed"]! + c["added"]! + c["removed"]! }
    var status: String { !errors.isEmpty ? "error" : failures > 0 ? "failed" : "passed" }
    var exitCode: Int32 { status == "error" ? 2 : status == "failed" ? 1 : 0 }
    /// This run's host: the one in its fingerprints (one run, one host).
    var host: String? { fingerprint.values.compactMap { $0["host"]?.string }.min(by: utf8Less) }
    func ids(_ status: String) -> [String] { entries.filter { $0["status"] == .string(status) }.compactMap { $0["id"]?.string } }
}

/// `verify` and `record` (docs/wiki/Baseline-format.md): a finished run's output directory (its PNGs and
/// swiftshot-report.json) against the baseline directory (its PNGs and baseline.json).
enum Baseline {
    /// Run inputs, as the report lists them.
    struct Run {
        let shots: [String: [String: JSON]]
        let shotOrder: [String]
        /// The first message per id.
        let failed: [String: String]
        let failedOrder: [String]
        let unattributed: [JSON]
        let scope: [String: JSON]
        let fingerprint: [String: JSON]

        init(_ output: URL) throws {
            let file = output.appendingPathComponent("swiftshot-report.json")
            guard FileManager.default.fileExists(atPath: file.path) else { throw CLIError("No swiftshot-report.json in \(output.path)") }
            guard let report = (try? JSON.parse(try Data(contentsOf: file)))?.object else { throw CLIError("\(file.path) is not a report (malformed JSON)") }
            var shots: [String: [String: JSON]] = [:], order: [String] = []
            for s in report["screenshots"]?.array ?? [] {
                guard let o = s.object, let id = o["id"]?.string else { continue }
                guard Baseline.validId(id) else { throw CLIError("swiftshot-report.json in \(output.path): \"\(id)\" is not a valid screenshot id") }
                if shots[id] == nil { order.append(id) }
                shots[id] = o
            }
            self.shots = shots; shotOrder = order
            let errors: [[String: JSON]] = (report["errors"]?.array ?? []).map { $0.object ?? ["message": .string($0.text)] }
            var failed: [String: String] = [:], failedOrder: [String] = []
            for e in errors { if let id = e["id"]?.string, failed[id] == nil { failed[id] = e["message"]?.text ?? "null"; failedOrder.append(id) } }
            self.failed = failed; self.failedOrder = failedOrder
            unattributed = errors.filter { $0["id"]?.string == nil }.map { e in
                .object(["message": e["message"].map { $0.isNull ? .null : .string($0.text) } ?? .null])
            }
            scope = report["scope"]?.object ?? [:]
            fingerprint = report["fingerprint"]?.object ?? [:]
        }

        func mode(_ platform: JSON?) -> String? { platform?.string.flatMap { fingerprint[$0]?["mode"]?.string } }
    }

    /// The baseline: baseline.json and every PNG under the directory (by id). A baseline.json that isn't one is a usage error.
    struct Stored {
        let fingerprints: [String: JSON]
        let images: [String: [String: JSON]]
        let files: Set<String>

        init(_ dir: URL) throws {
            let file = dir.appendingPathComponent("baseline.json")
            var json: [String: JSON]?
            if FileManager.default.fileExists(atPath: file.path) {
                guard let j = (try? JSON.parse(try Data(contentsOf: file)))?.object else { throw UsageError("\(file.path) is not valid JSON") }
                json = j
            }
            func section(_ key: String) throws -> [String: [String: JSON]] {
                guard let v = json?[key] else { return [:] }
                guard let o = v.object, o.values.allSatisfy({ $0.object != nil }) else { throw UsageError("\(file.path): \"\(key)\" must be an object of objects") }
                return o.mapValues { $0.object! }
            }
            fingerprints = try section("fingerprints").mapValues { .object($0) }
            images = try section("images")
            for id in images.keys where !Baseline.validId(id) { throw UsageError("\(file.path): \"\(id)\" is not a valid screenshot id") }
            files = Baseline.pngIds(dir)
        }
    }

    /// A screenshot id is a relative `/`-separated path; nothing that could leave the baseline directory.
    static func validId(_ id: String) -> Bool {
        !(id.isEmpty || id.hasPrefix("/") || id.contains("\\") || id.contains("\0") || id.range(of: "^[A-Za-z]:", options: .regularExpression) != nil
            || id.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    /// Every PNG under `dir`, as an id (relative path, `/`-separated, without `.png`).
    static func pngIds(_ dir: URL) -> Set<String> {
        var out = Set<String>()
        let root = dir.standardizedFileURL.resolvingSymlinksInPath().path
        guard let e = FileManager.default.enumerator(atPath: root) else { return out }
        while let rel = e.nextObject() as? String {
            guard rel.hasSuffix(".png") else { continue }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: root + "/" + rel, isDirectory: &isDir), !isDir.boolValue { out.insert(String(rel.dropLast(4))) }
        }
        return out
    }

    static let descriptive = ["platform", "module", "device", "language", "appearance", "preview", "fontScale", "textSize", "runtime"]

    static func describe(_ meta: [String: JSON]) -> [String: JSON] {
        var d: [String: JSON] = [:]
        for k in descriptive { if let v = meta[k] { d[k] = v } }
        if d["platform"] == .string("ios") && d["textSize"] == nil { d["textSize"] = .string("default") }
        return d
    }

    /// `*` = any run of characters, whole name, ASCII case-insensitive.
    static func glob(_ pattern: String, _ name: String) -> Bool {
        func lower(_ s: String) -> [UInt16] { s.utf16.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 } }
        let p = lower(pattern), s = lower(name)
        let parts = p.split(separator: 42, omittingEmptySubsequences: false).map(Array.init)
        if parts.count == 1 { return s == parts[0] }
        let first = parts[0], last = parts[parts.count - 1]
        guard s.count >= first.count + last.count, s.starts(with: first), s.suffix(last.count).elementsEqual(last) else { return false }
        var i = first.count
        let end = s.count - last.count
        for part in parts[1..<(parts.count - 1)] {
            guard let k = indexOf(part, in: s, from: i), k + part.count <= end else { return false }
            i = k + part.count
        }
        return true
    }

    private static func indexOf(_ needle: [UInt16], in hay: [UInt16], from: Int) -> Int? {
        if needle.isEmpty { return from <= hay.count ? from : nil }
        guard hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        for k in from...(hay.count - needle.count) where hay[k] == needle[0] && Array(hay[k..<(k + needle.count)]) == needle { return k }
        return nil
    }

    /// Whether a baseline image lies inside the run's scope (a list missing from the scope matches nothing).
    static func inScope(_ image: [String: JSON], _ scope: [String: JSON]) -> Bool {
        let fields = [("platform", "platforms"), ("device", "devices"), ("language", "languages"), ("appearance", "appearances"),
                      ("fontScale", "fontScales"), ("textSize", "textSizes"), ("module", "modules"), ("runtime", "runtimes")]
        for (field, key) in fields {
            guard let v = image[field] else { continue }
            guard let values = scope[key]?.array else { return false }
            let hit: Bool
            if field == "fontScale" {
                let d = v.number
                hit = d != nil && values.contains { $0.number == d }
            } else {
                hit = values.contains(v)
            }
            if !hit { return false }
        }
        let globs = (scope["previewFilter"]?.array ?? []).map(\.text)
        let preview = image["preview"].flatMap { $0.isNull ? nil : $0.text } ?? ""
        return globs.isEmpty || globs.contains { glob($0, preview) }
    }

    /// Compares the run in `output` with `baseline`, writes the report directory and says what it found; the exit code.
    static func verify(output: URL, baseline: URL, report: URL, config: CompareConfig, env: BaselineEnv, log: Console) throws -> Int32 {
        let start = Date()
        let v = try evaluate(output: output, baseline: baseline, report: report, config: config, env: env)
        try BaselineReport.writeTimings(compareSeconds: Date().timeIntervalSince(start), report: report)
        for (kind, line) in BaselineReport.summary(v, report: report) {
            switch kind {
            case "warn": log.warn(line)
            case "error": log.error(line)
            case "ok": log.ok(line)
            default: log.plain(line)
            }
        }
        return v.exitCode
    }

    /// The comparison: statuses in id order, report files written into `report`.
    static func evaluate(output: URL, baseline: URL, report: URL, config: CompareConfig, env: BaselineEnv) throws -> Verification {
        let run = try Run(output)
        let stored = try Stored(baseline)
        let stray = stored.files.subtracting(stored.images.keys)
        let ids = Set(run.shots.keys).union(stored.images.keys).union(run.failed.keys).union(stray.intersection(run.shots.keys)).sorted(by: utf8Less)
        try BaselineReport.clear(report)
        let fm = FileManager.default
        func png(_ dir: URL, _ id: String) -> URL { dir.appendingPathComponent(id + ".png") }
        func isFile(_ url: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: url.path, isDirectory: &d) && !d.boolValue }

        var slots: [[String: JSON]?] = []
        var jobs: [(Int, () throws -> [String: JSON])] = []
        var compared: [[String: JSON]] = []
        var local = false
        for id in ids {
            let b = stored.images[id], o = run.shots[id]
            if o == nil && run.failed[id] == nil && (!inScope(b!, run.scope) || !run.unattributed.isEmpty) { continue }
            if let b {
                compared.append(b)
                if b["local"] == .bool(true) { local = true }
            }
            var e = (o ?? b).map(describe) ?? [:]
            e["id"] = .string(id)
            let error: String? = run.failed[id]
                ?? (o != nil && !isFile(png(output, id)) ? "output image missing"
                    : b != nil && !stored.files.contains(id) ? "baseline image missing"
                    : b == nil && stored.files.contains(id) ? "baseline image not in baseline.json" : nil)
            if let error {
                e["status"] = .string("error"); e["message"] = .string(error)
            } else if o == nil {
                e["status"] = .string("removed"); e["baseline"] = .string("images/baseline/\(id).png")
                try copy(png(baseline, id), to: report.appendingPathComponent("images/baseline/\(id).png"))
            } else if b == nil {
                e["status"] = .string("added"); e["new"] = .string("images/new/\(id).png")
                try copy(png(output, id), to: report.appendingPathComponent("images/new/\(id).png"))
            } else {
                let entry = e, shot = o!
                jobs.append((slots.count, { try compare(entry, id: id, shot: shot, output: output, baseline: baseline, report: report, config: config, run: run) }))
                slots.append(nil)
                continue
            }
            slots.append(e)
        }
        // Comparisons in parallel (a few at a time: each holds two decoded images); each writes its images and drops them.
        let lock = NSLock()
        var failure: Error?
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4))
        for (slot, job) in jobs {
            queue.addOperation {
                do {
                    let e = try autoreleasepool { try job() }
                    lock.lock(); slots[slot] = e; lock.unlock()
                } catch {
                    lock.lock(); if failure == nil { failure = error }; lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        if let failure { throw failure }
        let entries = slots.map { $0! }
        var mismatches: [String] = []
        // Each image against the fingerprint this run gives it (its own runtime's build).
        var seen = Set<String>()
        for b in compared {
            guard let f = b["fingerprint"]?.string, let fp = stored.fingerprints[f], fp.object != nil, let platform = fp["platform"]?.string,
                  let mine = run.fingerprint[platform], mine.object != nil else { continue }
            for m in Fingerprints.mismatches(baseline: fp, run: Fingerprints.forImage(mine, b)) where seen.insert(m).inserted { mismatches.append(m) }
        }
        mismatches.sort(by: utf8Less)
        let errors: [JSON] = entries.filter { $0["status"] == .string("error") }.map { .object(["id": $0["id"]!, "message": $0["message"]!]) } + run.unattributed
        let listed = Set(entries.compactMap { $0["id"]?.string })
        let v = Verification(entries: entries, errors: errors, unattributed: run.unattributed, fingerprint: run.fingerprint, mismatches: mismatches,
                             localBaseline: local, strays: stray.subtracting(listed).count, env: env, configHash: config.hash())
        try BaselineReport.write(v, report: report)
        return v
    }

    /// Both PNGs present: equal bytes, else decode and compare; a changed shot's images are written right away.
    private static func compare(_ entry: [String: JSON], id: String, shot o: [String: JSON], output: URL, baseline: URL, report: URL, config: CompareConfig, run: Run) throws -> [String: JSON] {
        var e = entry
        let a = [UInt8](try Data(contentsOf: baseline.appendingPathComponent(id + ".png")))
        let b = [UInt8](try Data(contentsOf: output.appendingPathComponent(id + ".png")))
        if a == b { e["status"] = .string("unchanged"); return e }
        let base: PngImage, new: PngImage
        do { base = try Png.decode(a); new = try Png.decode(b) } catch {
            e["status"] = .string("error"); e["message"] = .string("unsupported PNG"); return e
        }
        let (tolerance, ignore) = config.forShot(preview: o["preview"].flatMap { $0.isNull ? nil : $0.text } ?? "", mode: run.mode(o["platform"]), scale: o["scale"]?.number ?? 1)
        let diff = Compare.images(base, new, tolerance: tolerance, ignore: ignore)
        if diff.status == "unchanged" {
            e["status"] = .string("unchanged")
            if diff.pixels > 0 { e["reason"] = .string("tolerance"); e["pixels"] = .int(Int64(diff.pixels)) }
            return e
        }
        e["status"] = .string("changed")
        e["reason"] = diff.reason.map { .string($0) } ?? .null
        e["pixels"] = .int(Int64(diff.pixels))
        e["boxes"] = .array(diff.boxes.map { .array([$0.x, $0.y, $0.width, $0.height].map { .int(Int64($0)) }) })
        e["baseline"] = .string("images/baseline/\(id).png")
        e["new"] = .string("images/new/\(id).png")
        e["diff"] = .string("images/diff/\(id).png")
        if let s = diff.baselineSize { e["baselineSize"] = .array(s.map { .int(Int64($0)) }) }
        if let s = diff.newSize { e["newSize"] = .array(s.map { .int(Int64($0)) }) }
        try write(report.appendingPathComponent("images/baseline/\(id).png"), Data(a))
        try write(report.appendingPathComponent("images/new/\(id).png"), Data(b))
        try write(report.appendingPathComponent("images/diff/\(id).png"), Data(Png.encode(diff.diffImage!)))
        return e
    }

    static func write(_ url: URL, _ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func copy(_ from: URL, to: URL) throws {
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.copyItem(at: from, to: to)
    }

    /// `record`: the run's screenshots become the baseline. Rendered ids are copied in (local = !ci); baseline images
    /// in the run's scope that it didn't render (and that have no render error) are deleted, as a verify would report
    /// them removed; images outside the scope stay. Exit 2 when the run had errors, else 0.
    static func record(output: URL, baseline: URL, ci: Bool, log: Console) throws -> Int32 {
        let run = try Run(output)
        if run.shots.isEmpty && (!run.failed.isEmpty || !run.unattributed.isEmpty) {
            for id in run.failedOrder { log.error("\(id): \(run.failed[id]!)") }
            for e in run.unattributed { log.error(e["message"]?.text ?? "null") }
            log.error("Nothing rendered; the baseline is unchanged")
            return 2
        }
        let stored = try Stored(baseline)
        var images: [String: JSON] = [:]
        var fingerprints: [String: JSON] = [:]
        for (id, b) in stored.images {
            images[id] = .object(b)
            if let f = b["fingerprint"]?.string, let fp = stored.fingerprints[f], fp.object != nil { fingerprints[f] = fp }
        }
        let gone = !run.unattributed.isEmpty ? [] : stored.images.filter { id, b in run.shots[id] == nil && run.failed[id] == nil && inScope(b, run.scope) }.keys.sorted(by: utf8Less)
        // A run that rendered nothing can't tell a deleted preview from a broken one: it wipes nothing.
        if run.shots.isEmpty && !gone.isEmpty {
            log.error("Nothing rendered; the baseline is unchanged (record would have removed \(gone.count) screenshots)")
            return 2
        }
        for id in gone {
            images[id] = nil
            try? FileManager.default.removeItem(at: baseline.appendingPathComponent(id + ".png"))
        }
        let removed = gone.count
        var written = 0
        var missing: [String] = []
        for id in run.shotOrder {
            let o = run.shots[id]!
            let png = output.appendingPathComponent(id + ".png")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: png.path, isDirectory: &isDir), !isDir.boolValue else { missing.append(id); continue }
            let platform = o["platform"] ?? .null
            let fp = platform.string.flatMap { run.fingerprint[$0] }.flatMap { $0.object != nil ? Fingerprints.forImage($0, o) : nil } ?? .object(["platform": platform])
            let fid = Fingerprints.id(fp)
            fingerprints[fid] = fp
            var entry = describe(o)
            entry["fingerprint"] = .string(fid)
            entry["local"] = .bool(!ci)
            images[id] = .object(entry)
            try copy(png, to: baseline.appendingPathComponent(id + ".png"))
            written += 1
        }
        let referenced = Set(images.values.compactMap { $0["fingerprint"]?.string })
        let json: JSON = .object(["schema": .int(1), "fingerprints": .object(fingerprints.filter { referenced.contains($0.key) }), "images": .object(images)])
        try FileManager.default.createDirectory(at: baseline, withIntermediateDirectories: true)
        try Data(json.pretty().utf8).write(to: baseline.appendingPathComponent("baseline.json"), options: .atomic)
        for id in missing { log.error("\(id): output image missing") }
        for id in run.failedOrder { log.error("\(id): \(run.failed[id]!)") }
        for e in run.unattributed { log.error(e["message"]?.text ?? "null") }
        log.ok("Recorded \(written) screenshots\(removed > 0 ? ", removed \(removed)" : "")\(ci ? "" : " (locally: verify will say so until CI records them)") → \(baseline.path)")
        return !run.failed.isEmpty || !run.unattributed.isEmpty || !missing.isEmpty ? 2 : 0
    }
}
