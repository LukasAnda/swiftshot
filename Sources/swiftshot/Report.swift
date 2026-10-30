import Foundation

/// A render error; `id` is the screenshot it would have written (nil when the run can't tell, e.g. a failed launch).
struct RunError: Equatable {
    var id: String?
    var message: String
    var json: JSON { id.map { .object(["id": .string($0), "message": .string(message)]) } ?? .object(["message": .string(message)]) }
    var line: String { id.map { "\($0): \(message)" } ?? message }
}

/// A run's `scope` (docs/wiki/Baseline-format.md): the requested matrix ∪ the values actually rendered.
struct RunScope {
    var devices = Set<String>()
    var languages = Set<String>()
    var appearances = Set<String>()
    var textSizes = Set<String>()
    var runtimes = Set<String>()
    var previews = Set<String>()
    var previewFilter: [String]

    init(previewFilter: [String]) { self.previewFilter = previewFilter }

    /// The values of one rendered screenshot.
    mutating func add(_ s: ShotRecord) {
        devices.insert(s.device); languages.insert(s.language); appearances.insert(s.appearance)
        textSizes.insert(s.textSize ?? "default"); runtimes.insert(s.runtime); previews.insert(s.preview)
    }

    func json() -> JSON {
        func list(_ s: Set<String>) -> JSON { .array(s.sorted(by: utf8Less).map { .string($0) }) }
        return .object([
            "platforms": .array([.string("ios")]), "modules": .array([]), "devices": list(devices), "languages": list(languages),
            "appearances": list(appearances), "textSizes": list(textSizes.isEmpty ? ["default"] : textSizes), "runtimes": list(runtimes),
            "previews": list(previews), "previewFilter": .array(previewFilter.sorted(by: utf8Less).map { .string($0) }),
        ])
    }
}

extension JSON {
    /// A number: an integer when integral (as the report readers expect `3`, not `3.0`).
    static func num(_ d: Double) -> JSON { d.isFinite && d == d.rounded(.towardZero) && abs(d) < 1e15 ? .int(Int64(d)) : .double(d) }
}

enum Report {
    /// A screenshot's id: its path relative to the output directory, without `.png`.
    static func id(_ file: String) -> String { file.hasSuffix(".png") ? String(file.dropLast(4)) : (file as NSString).deletingPathExtension }

    /// One report screenshot: the agent's record plus `id`, `platform` and `scale`.
    static func shotJSON(_ s: ShotRecord) -> JSON {
        var o: [String: JSON] = [
            "preview": .string(s.preview), "device": .string(s.device), "appearance": .string(s.appearance), "language": .string(s.language),
            "runtime": .string(s.runtime), "file": .string(s.file), "width": .int(Int64(s.width)), "height": .int(Int64(s.height)),
            "renderMs": .num(s.renderMs), "id": .string(id(s.file)), "platform": .string("ios"),
        ]
        if let t = s.textSize { o["textSize"] = .string(t) }
        if let f = s.framed { o["framed"] = .string(f) }
        if let scale = s.scale { o["scale"] = .num(scale) }
        return .object(o)
    }

    static func json(shots: [ShotRecord], errors: [RunError], scope: RunScope, fingerprint: [String: JSON], timings: [(String, Double)], total: Double) -> JSON {
        .object([
            "totalSeconds": .num(total),
            "screenshots": .array(shots.map(shotJSON).sorted { utf8Less($0["id"]!.string!, $1["id"]!.string!) }),
            "errors": .array(errors.map(\.json)), "scope": scope.json(), "fingerprint": .object(fingerprint),
            "timings": .object(Dictionary(timings, uniquingKeysWith: { $1 }).mapValues { .num($0) }), "platform": .string("ios"),
        ])
    }

    /// A run that failed as a whole (no screenshots): one error without id, no scope, no fingerprint.
    static func writeFailure(to dir: String, message: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let json: JSON = .object(["totalSeconds": .int(0), "screenshots": .array([]), "errors": .array([RunError(id: nil, message: message).json]),
                                  "scope": .object([:]), "fingerprint": .object([:]), "platform": .string("ios")])
        try Data(json.pretty().utf8).write(to: URL(fileURLWithPath: dir).appendingPathComponent("swiftshot-report.json"))
    }

    static func write(shots: [ShotRecord], errors: [RunError], scope: RunScope, fingerprint: [String: JSON], to dir: String, html: Bool,
                      timings: [(String, Double)], total: Double) throws {
        let sorted = shots.sorted { ($0.language, $0.runtime, $0.device, $0.preview, $0.appearance) < ($1.language, $1.runtime, $1.device, $1.preview, $1.appearance) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let report = json(shots: shots, errors: errors, scope: scope, fingerprint: fingerprint, timings: timings, total: total)
        try Data(report.pretty().utf8).write(to: URL(fileURLWithPath: dir).appendingPathComponent("swiftshot-report.json"))
        guard html else { return }

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var body = ""
        for (language, group) in Dictionary(grouping: sorted, by: \.language).sorted(by: { $0.key < $1.key }) {
            body += "<h2>\(esc(language))</h2>\n"
            for (key, row) in Dictionary(grouping: group, by: { "\($0.device) · \($0.runtime.hasPrefix("watchOS") ? "" : "iOS ")\($0.runtime)" }).sorted(by: { $0.key < $1.key }) {
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
