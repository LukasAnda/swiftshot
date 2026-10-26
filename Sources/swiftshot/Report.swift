import Foundation

enum Report {
    static func write(shots: [ShotRecord], errors: [String], to dir: String, html: Bool,
                      timings: [(String, Double)], total: Double) throws {
        let sorted = shots.sorted { ($0.language, $0.runtime, $0.device, $0.preview, $0.appearance) < ($1.language, $1.runtime, $1.device, $1.preview, $1.appearance) }
        struct Summary: Encodable { let totalSeconds: Double; let screenshots: [ShotRecord]; let errors: [String]; let timings: [String: Double] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try encoder.encode(Summary(totalSeconds: total, screenshots: sorted, errors: errors,
                                   timings: Dictionary(timings, uniquingKeysWith: { $1 })))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("swiftshot-report.json"))
        guard html else { return }

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var body = ""
        for (language, group) in Dictionary(grouping: sorted, by: \.language).sorted(by: { $0.key < $1.key }) {
            body += "<h2>\(esc(language))</h2>\n"
            for (key, row) in Dictionary(grouping: group, by: { "\($0.device) · iOS \($0.runtime)" }).sorted(by: { $0.key < $1.key }) {
                body += "<h3>\(esc(key))</h3><div class=row>\n"
                func url(_ path: String) -> String {
                    path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
                }
                for s in row {
                    // The framed version when there is one, linking to the plain screenshot.
                    let src = url(s.file), shown = s.framed.map(url) ?? src
                    let raw = s.framed == nil ? "" : " · <a href=\"\(src)\">unframed</a>"
                    body += "<figure><a href=\"\(shown)\"><img class=\"\(s.framed == nil ? "" : "framed")\" loading=lazy src=\"\(shown)\"></a><figcaption>\(esc(s.preview)) · \(s.appearance) · \(s.width)×\(s.height)\(raw)</figcaption></figure>\n"
                }
                body += "</div>\n"
            }
        }
        let page = """
        <!doctype html><meta charset=utf-8><title>Screenshots</title>
        <style>body{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}
        .row{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:220px}img{width:100%;border-radius:12px;box-shadow:0 2px 8px #0002;background:#fff}img.framed{border-radius:0;box-shadow:none;background:none}
        figcaption{font-size:12px;color:#555;margin-top:6px}h3{font-weight:500;color:#444}
        @media (prefers-color-scheme:dark){body{background:#111;color:#eee}figcaption,h3{color:#aaa}}</style>
        <h1>\(sorted.count) screenshots · \(String(format: "%.1f", total))s</h1>
        \(body)
        """
        try page.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screenshots.html"), atomically: true, encoding: .utf8)
    }
}
