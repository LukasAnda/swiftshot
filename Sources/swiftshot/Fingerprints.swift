import Foundation

/// The renderer fingerprint of docs/wiki/Baseline-format.md (Fingerprint): what produced a run's pixels, per platform.
enum Fingerprints {
    /// This run's host, detected once (`SWIFTSHOT_HOST` overrides it).
    static let host: String = {
        if let h = ProcessInfo.processInfo.environment["SWIFTSHOT_HOST"], !h.isEmpty { return h }
        var u = utsname()
        uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return hostOf(os: "macos", arch: machine)
    }()

    static func hostOf(os: String, arch: String) -> String {
        let a: String
        switch arch.lowercased() {
        case "aarch64", "arm64": a = "arm64"
        case "amd64", "x86_64", "x64": a = "x64"
        default: a = arch.lowercased()
        }
        return "\(os)-\(a)"
    }

    /// The Swiftshot version (`SWIFTSHOT_VERSION_OVERRIDE` overrides it).
    static func version() -> String { ProcessInfo.processInfo.environment["SWIFTSHOT_VERSION_OVERRIDE"] ?? swiftshotVersion }

    /// Fingerprint id: the first 12 hex digits of its hash.
    static func id(_ fp: JSON) -> String { String(CanonicalJson.hash(fp).prefix(12)) }

    /// iOS: the mode (no-boot or device), Xcode's build and the simulator runtimes' builds (sorted, joined when several).
    static func ios(mode: String, xcode: String?, runtimes: [String], host: String = host, version: String = version()) -> JSON {
        var fp: [String: JSON] = ["platform": .string("ios"), "host": .string(host), "swiftshot": .string(version), "mode": .string(mode)]
        if let xcode { fp["xcode"] = .string(xcode) }
        let builds = Set(runtimes).sorted(by: utf8Less)
        if !builds.isEmpty { fp["runtime"] = .string(builds.joined(separator: ", ")) }
        return .object(fp)
    }

    /// `xcodebuild -version` output → its build ("Build version 17A400" → 17A400).
    static func xcodeBuild(_ output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("Build version ") {
            let v = line.dropFirst("Build version ".count).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { return v }
        }
        return nil
    }

    /// The pixel-relevant differences between a baseline fingerprint and this run's for the same platform, as
    /// `<platform> <field>: baseline <value>, this run <value>`. `swiftshot` compares its first two parts; `host`
    /// is ignored when this run renders with the exact iOS renderer.
    static func mismatches(baseline: JSON, run: JSON) -> [String] {
        let b = baseline.object ?? [:], r = run.object ?? [:]
        let platform = run["platform"]?.text ?? "null"
        let exactIos = run["platform"] == .string("ios") || run["renderer"] == .string("exact-ios")
        var out: [String] = []
        for k in Set(b.keys).union(r.keys).sorted(by: utf8Less) {
            let x = b[k].flatMap { $0.isNull ? nil : $0 }, y = r[k].flatMap { $0.isNull ? nil : $0 }
            if k == "host" && exactIos { continue }
            if k == "swiftshot", let xs = x?.string, let ys = y?.string,
               xs.split(separator: ".", omittingEmptySubsequences: false).prefix(2) == ys.split(separator: ".", omittingEmptySubsequences: false).prefix(2) { continue }
            if x != y { out.append("\(platform) \(k): baseline \(show(x)), this run \(show(y))") }
        }
        return out
    }

    private static func show(_ v: JSON?) -> String {
        guard let v, v != .null else { return "none" }
        if case .array(let a) = v { return a.map(\.text).joined(separator: ", ") }
        return v.text
    }
}
