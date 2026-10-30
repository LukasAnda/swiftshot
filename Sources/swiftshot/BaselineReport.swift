import Foundation

/// The report directory's files (docs/wiki/Baseline-format.md): result.json, manifest.json, junit.xml, and the console summary.
enum BaselineReport {
    static let files = ["result.json", "manifest.json", "junit.xml"]

    /// Removes what an earlier verify wrote there (only its own files: the directory may be the user's).
    static func clear(_ report: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: report.appendingPathComponent("images"))
        for f in files { try? fm.removeItem(at: report.appendingPathComponent(f)) }
        try fm.createDirectory(at: report, withIntermediateDirectories: true)
    }

    static func write(_ v: Verification, report: URL) throws {
        try FileManager.default.createDirectory(at: report, withIntermediateDirectories: true)
        try Data(result(v).pretty().utf8).write(to: report.appendingPathComponent("result.json"))
        try Data(manifest(v).pretty().utf8).write(to: report.appendingPathComponent("manifest.json"))
        try Data(junit(v).utf8).write(to: report.appendingPathComponent("junit.xml"))
    }

    static func optional(_ s: String?) -> JSON { s.map { .string($0) } ?? .null }

    static func result(_ v: Verification) -> JSON {
        .object([
            "schema": .int(1), "status": .string(v.status), "counts": .object(v.counts.mapValues { .int(Int64($0)) }),
            "commit": optional(v.env.git.commit), "branch": optional(v.env.git.branch), "version": .string(v.env.version), "ci": .bool(v.env.ci),
            "host": optional(v.host), "fingerprint": .object(v.fingerprint), "fingerprintMismatch": .array(v.mismatches.map { .string($0) }),
            "localBaseline": .bool(v.localBaseline), "screenshots": .array(v.entries.map { .object($0) }), "errors": .array(v.errors),
            "strayBaselineFiles": .int(Int64(v.strays)),
        ])
    }

    static func manifest(_ v: Verification) -> JSON {
        func ids(_ s: String) -> JSON { .array(v.ids(s).map { .string($0) }) }
        return .object([
            "schema": .int(1), "commit": optional(v.env.git.commit), "branch": optional(v.env.git.branch), "ci": .bool(v.env.ci),
            "configHash": .string(v.configHash), "fingerprint": .object(v.fingerprint),
            "ids": .object(["changed": ids("changed"), "added": ids("added"), "removed": ids("removed")]),
        ])
    }

    static func junit(_ v: Verification) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<testsuite name="swiftshot" tests="\#(v.entries.count + v.unattributed.count)" failures="\#(v.failures)" errors="\#(v.errors.count)">"#,
        ]
        func field(_ e: [String: JSON], _ k: String) -> String { e[k]?.text ?? "null" }
        for e in v.entries {
            let classname = e["platform"] != nil ? "\(field(e, "platform")).\(field(e, "device")).\(field(e, "language"))" : "swiftshot"
            let attrs = #"classname="\#(attr(classname))" name="\#(attr(field(e, "id")))""#
            let failure: String
            switch e["status"]?.string {
            case "error":
                lines += ["  <testcase \(attrs)>", #"    <error message="\#(attr(field(e, "message")))"/>"#, "  </testcase>"]
                continue
            case "changed":
                if e["reason"] == .string("size"), let b = e["baselineSize"]?.array, let n = e["newSize"]?.array, b.count == 2, n.count == 2 {
                    failure = "changed: size \(b[0].text)x\(b[1].text) to \(n[0].text)x\(n[1].text)"
                } else {
                    failure = "changed: \(field(e, "pixels")) pixels"
                }
            case "added", "removed": failure = e["status"]!.string!
            default:
                lines.append("  <testcase \(attrs)/>")
                continue
            }
            lines += ["  <testcase \(attrs)>", #"    <failure message="\#(attr(failure))"/>"#, "  </testcase>"]
        }
        for (i, err) in v.unattributed.enumerated() {
            lines += [#"  <testcase classname="swiftshot" name="error \#(i + 1)">"#, #"    <error message="\#(attr(err["message"]?.text ?? "null"))"/>"#, "  </testcase>"]
        }
        lines.append("</testsuite>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func attr(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out += "&#\(u.value);"
            default: if u.value >= 0x20 { out.unicodeScalars.append(u) }
            }
        }
        return out
    }

    /// What verify prints, in order: fingerprint mismatches first, the local-baseline warning, each difference, the totals.
    static func summary(_ v: Verification, report: URL) -> [(String, String)] {
        var out: [(String, String)] = []
        for m in v.mismatches { out.append(("warn", "Baseline rendered differently: \(m)")) }
        if v.localBaseline { out.append(("warn", "Some baseline images were recorded outside CI (local); record or accept them on CI")) }
        for e in v.entries {
            let id = e["id"]?.text ?? "null"
            switch e["status"]?.string {
            case "changed": out.append(("plain", "changed  \(id)  (\(e["reason"] == .string("size") ? "size" : "\(e["pixels"]?.text ?? "0") pixels"))"))
            case "added", "removed": out.append(("plain", "\(e["status"]!.string!)  \(id)"))
            case "error": out.append(("error", "\(id): \(e["message"]?.text ?? "null")"))
            default: break
            }
        }
        for err in v.unattributed { out.append(("error", err["message"]?.text ?? "null")) }
        let c = v.counts
        let totals = "\(c["unchanged"]!) unchanged, \(c["changed"]!) changed, \(c["added"]!) added, \(c["removed"]!) removed, \(c["errors"]!) errors → \(report.path)"
        out.append((v.status == "passed" ? "ok" : v.status == "failed" ? "warn" : "error", "Verify \(v.status): \(totals)"))
        return out
    }
}
