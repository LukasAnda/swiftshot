import Foundation

/// `summary.md` (docs/wiki/Baseline-format.md): the report in a few lines of Markdown, for a CI's summary page and the pull request comment.
enum Summary {
    /// First line; finds the comment again on the next run.
    static let marker = "<!-- swiftshot -->"
    private static let maxRows = 200
    private static let maxBytes = 60_000
    private static let order = ["error", "changed", "added", "removed"]

    static func acceptHint(_ provider: String?) -> String {
        switch provider {
        case "github": return "Comment `/swiftshot accept` on this pull request to accept every change, or `/swiftshot accept <id> …` for some."
        case "gitlab": return "Run the manual `swiftshot-accept` job in this pipeline to accept the changes."
        case "bitbucket": return "Run the `swiftshot-accept` custom pipeline on this branch to accept the changes."
        case "bitrise": return "Run the `swiftshot-accept` workflow on this branch to accept the changes."
        case "codemagic": return "Start the `swiftshot-accept` workflow on this branch to accept the changes."
        case "circleci": return "Approve the `accept-screenshots` job in this workflow to accept the changes."
        case "azure": return "Approve the `Accept screenshots` stage in this run to accept the changes."
        case "jenkins": return "Approve the `Accept screenshots` stage in this build to accept the changes."
        default: return "Accept the changes with `swiftshot accept --from <this report>`."
        }
    }

    private static func heading(_ status: String) -> String {
        switch status {
        case "passed": return "Screenshots match the baseline"
        case "failed": return "Screenshots differ from the baseline"
        default: return "Screenshot run had errors"
        }
    }

    static func counts(_ v: Verification) -> String {
        let c = v.counts
        return "\(c["changed"]!) changed · \(c["added"]!) added · \(c["removed"]!) removed · \(c["errors"]!) errors · \(c["unchanged"]!) unchanged"
    }

    /// The rows a run has to show, as (status, id): errors, changed, added, removed; each by id in UTF-8 byte order.
    static func rows(_ v: Verification) -> [(status: String, id: String)] {
        v.entries.compactMap { e -> (status: String, id: String)? in
            guard let s = e["status"]?.string, order.contains(s), let id = e["id"]?.string else { return nil }
            return (s, id)
        }.sorted { a, b in
            let (x, y) = (order.firstIndex(of: a.status)!, order.firstIndex(of: b.status)!)
            return x != y ? x < y : utf8Less(a.id, b.id)
        }
    }

    static func markdown(_ v: Verification, ci: Ci?) -> String {
        var notes = v.mismatches.map { "> **Note:** Baseline rendered differently: \($0)" }
        if v.localBaseline { notes.append("> **Note:** Some baseline images were recorded outside CI (local); record or accept them on CI") }
        let rows = rows(v)
        var tail: [String] = []
        if let url = ci?.buildUrl { tail.append("[Full report](\(url))") }
        if v.status == "failed" { tail.append(acceptHint(ci?.provider)) }

        func build(_ shown: Int) -> String {
            var blocks = ["\(marker)\n### \(heading(v.status))", counts(v)]
            if !notes.isEmpty { blocks.append(notes.joined(separator: "\n")) }
            if !rows.isEmpty {
                var lines = ["| Status | Screenshot |", "|---|---|"]
                for r in rows.prefix(shown) { lines.append("| \(r.status) | `\(r.id.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "`", with: "'"))` |") }
                if shown < rows.count { lines.append("| | …and \(rows.count - shown) more |") }
                blocks.append(lines.joined(separator: "\n"))
            }
            blocks += tail
            return blocks.joined(separator: "\n\n") + "\n"
        }
        var shown = min(maxRows, rows.count)
        while shown > 0 && build(shown).utf8.count > maxBytes { shown -= 1 }
        return build(shown)
    }
}
