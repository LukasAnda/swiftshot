// fastlane frameit's Framefile.json and title.strings / keyword.strings.
//
// A Framefile has a "default" object and a "data" array; every "data" entry whose "filter" is a
// substring of the screenshot's path (relative to the screenshots folder, e.g.
// "de-DE/iPhone 17 Pro Max-Welcome.png") is deep-merged over the default, in file order.
// Texts come from the language folder's title.strings / keyword.strings first (the longest key
// contained in the file name wins), then from the Framefile's title.text / keyword.text.

import Foundation

struct Framefile {
    let path: String
    let defaults: [String: Any]
    let data: [[String: Any]]

    /// The keys swiftshot reads; anything else (offset, use_platform, font_weight…) is ignored.
    static let supportedKeys: Set<String> = [
        "filter", "background", "title", "keyword", "padding", "title_below_image", "stack_title", "show_complete_frame",
        "title_min_height", "font_scale_factor", "interline_spacing", "frame",
    ]
    static let supportedTextKeys: Set<String> = ["text", "color", "font", "font_size", "fonts"]

    static func load(_ path: String) throws -> Framefile {
        guard let data = FileManager.default.contents(atPath: path) else { throw CLIError("Cannot read Framefile \(path)") }
        return try parse(data, path: path)
    }

    static func parse(_ json: Data, path: String) throws -> Framefile {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CLIError("\(path) is not a valid Framefile.json (a JSON object with \"default\" and \"data\")")
        }
        let entries = object["data"] as? [[String: Any]] ?? []
        for entry in entries where !(entry["filter"] is String) { throw CLIError("\(path): every \"data\" entry needs a \"filter\" string") }
        return Framefile(path: path, defaults: object["default"] as? [String: Any] ?? [:], data: entries)
    }

    /// frameit's lookup: the language folder, the screenshots folder, then two levels above it.
    static func find(languageDir: String, root: String) -> String? {
        let candidates = [languageDir, root, ((root as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent]
        return candidates.map { ($0 as NSString).appendingPathComponent("Framefile.json") }.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in over {
            if let a = result[key] as? [String: Any], let b = value as? [String: Any] { result[key] = deepMerge(a, b) } else { result[key] = value }
        }
        return result
    }

    /// The merged settings for one screenshot.
    func values(for relativePath: String) -> [String: Any] {
        data.filter { relativePath.contains($0["filter"] as? String ?? "\u{0}") }.reduce(defaults) { Framefile.deepMerge($0, $1) }
    }

    /// Keys in this file that swiftshot does not use.
    var unsupportedKeys: [String] {
        var found = Set<String>()
        for entry in [defaults] + data {
            for (key, value) in entry {
                if !Framefile.supportedKeys.contains(key) { found.insert(key) }
                if ["title", "keyword"].contains(key), let text = value as? [String: Any] {
                    for k in text.keys where !Framefile.supportedTextKeys.contains(k) { found.insert("\(key).\(k)") }
                }
            }
        }
        return found.sorted()
    }

    func style(for relativePath: String) throws -> FrameStyle {
        try FrameStyle(values(for: relativePath), baseDir: (path as NSString).deletingLastPathComponent, source: path)
    }
}

/// A length in pixels or as a percentage of the canvas's shorter side.
enum Length: Equatable {
    case pixels(Double), percent(Double)

    init?(_ value: Any) {
        if let n = value as? NSNumber, !(value is Bool) { self = .pixels(n.doubleValue); return }
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasSuffix("%"), let p = Double(s.dropLast()), p >= 0 { self = .percent(p) } else if let n = Double(s) { self = .pixels(n) } else { return nil }
    }

    func resolve(_ shortSide: Double) -> Double {
        switch self { case .pixels(let p): return p; case .percent(let p): return shortSide * p / 100 }
    }
}

/// One screenshot's settings from a Framefile (or defaults), before fonts and images are loaded.
struct FrameStyle: Equatable {
    struct Text: Equatable {
        var text: String?
        var color: String?
        var font: String?
        var fontSize: Double?
        /// Per-language fonts: the first whose `supported` lists the language (or has no list).
        var fonts: [Font] = []
        struct Font: Equatable { var font: String; var supported: [String]? }

        func font(for language: String) -> String? {
            font ?? fonts.first { $0.supported == nil || $0.supported!.contains { $0.caseInsensitiveCompare(language) == .orderedSame } }?.font
        }
    }
    /// "#RRGGBB" or an image path (absolute).
    var background: String?
    var title = Text()
    var keyword = Text()
    var padding: (h: Length, v: Length)?
    var titleBelowImage = false
    var stackTitle = false
    var showCompleteFrame = true
    var titleMinHeight: Length?
    var fontScaleFactor: Double?
    var interlineSpacing: Double?
    /// frameit's frame colour ("BLACK", "ROSE_GOLD"…), matched against the bezel's colours.
    var frame: String?

    static func == (a: FrameStyle, b: FrameStyle) -> Bool {
        a.background == b.background && a.title == b.title && a.keyword == b.keyword && a.padding?.h == b.padding?.h && a.padding?.v == b.padding?.v
            && a.titleBelowImage == b.titleBelowImage && a.stackTitle == b.stackTitle && a.showCompleteFrame == b.showCompleteFrame
            && a.titleMinHeight == b.titleMinHeight && a.fontScaleFactor == b.fontScaleFactor && a.interlineSpacing == b.interlineSpacing && a.frame == b.frame
    }

    init() {}

    init(_ values: [String: Any], baseDir: String, source: String) throws {
        func absolute(_ p: String) -> String { p.hasPrefix("/") ? p : ((baseDir as NSString).appendingPathComponent(p) as NSString).standardizingPath }
        func bool(_ key: String) throws -> Bool? {
            guard let v = values[key] else { return nil }
            guard let b = v as? Bool else { throw CLIError("\(source): \"\(key)\" must be true or false") }
            return b
        }
        func text(_ key: String) throws -> Text {
            guard let v = values[key] else { return Text() }
            guard let d = v as? [String: Any] else { throw CLIError("\(source): \"\(key)\" must be an object") }
            var t = Text()
            t.text = d["text"] as? String
            t.color = d["color"] as? String
            if let c = t.color, Framer.color(c) == nil { throw CLIError("\(source): \(key).color '\(c)' is not a #RRGGBB colour") }
            t.font = (d["font"] as? String).map { $0.contains("/") || $0.contains(".") ? absolute($0) : $0 }
            t.fontSize = (d["font_size"] as? NSNumber)?.doubleValue
            for f in d["fonts"] as? [[String: Any]] ?? [] {
                guard let path = f["font"] as? String else { throw CLIError("\(source): \(key).fonts entries need a \"font\"") }
                t.fonts.append(.init(font: absolute(path), supported: f["supported"] as? [String]))
            }
            return t
        }
        if let bg = values["background"] as? String { background = bg.hasPrefix("#") ? bg : absolute(bg) }
        if let bg = background, bg.hasPrefix("#"), Framer.color(bg) == nil { throw CLIError("\(source): background '\(bg)' is not a #RRGGBB colour or an image") }
        title = try text("title")
        keyword = try text("keyword")
        if let p = values["padding"] {
            if let s = p as? String, s.contains("x") {
                let parts = s.split(separator: "x").map(String.init)
                guard parts.count == 2, let h = Length(parts[0]), let v = Length(parts[1]) else { throw CLIError("\(source): padding '\(s)' must be N, \"AxB\" or \"N%\"") }
                padding = (h, v)
            } else if let l = Length(p) {
                padding = (l, l)
            } else {
                throw CLIError("\(source): padding must be N, \"AxB\" or \"N%\"")
            }
        }
        titleBelowImage = try bool("title_below_image") ?? false
        stackTitle = try bool("stack_title") ?? false
        showCompleteFrame = try bool("show_complete_frame") ?? true
        if let m = values["title_min_height"] {
            guard let l = Length(m) else { throw CLIError("\(source): title_min_height must be N or \"N%\"") }
            titleMinHeight = l
        }
        fontScaleFactor = (values["font_scale_factor"] as? NSNumber)?.doubleValue
        if let f = fontScaleFactor, f <= 0 { throw CLIError("\(source): font_scale_factor must be above 0") }
        interlineSpacing = (values["interline_spacing"] as? NSNumber)?.doubleValue
        frame = values["frame"] as? String
    }
}

/// Apple .strings files (UTF-8 or UTF-16, with or without a byte order mark).
enum StringsFile {
    static func decode(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(4))
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if b.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if b.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        // No BOM: UTF-16 has a NUL in every other byte of ASCII text.
        if b.count >= 2, b[0] == 0 || b[1] == 0 { return String(data: data, encoding: b[0] == 0 ? .utf16BigEndian : .utf16LittleEndian) }
        return String(data: data, encoding: .utf8)
    }

    static func parse(_ data: Data, path: String) throws -> [String: String] {
        guard let text = decode(data) else { throw CLIError("\(path): not UTF-8 or UTF-16 text") }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        // Old-style property list parser: comments, escapes (\" \n \U…), unquoted keys.
        guard let table = try? PropertyListSerialization.propertyList(from: text.data(using: .utf16)!, format: nil) as? [String: String] else {
            throw CLIError("\(path): not a valid .strings file (expected lines like \"Welcome\" = \"Track every habit\";)")
        }
        return table
    }

    static func load(_ path: String) throws -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path) else { throw CLIError("Cannot read \(path)") }
        return try parse(data, path: path)
    }

    /// The text for a screenshot: the longest key that its file name contains (case-insensitive);
    /// "Stats landscape" beats "Stats". Empty values don't count.
    static func lookup(_ table: [String: String], fileName: String) -> String? {
        table.filter { !$0.key.isEmpty && !$0.value.isEmpty && fileName.range(of: $0.key, options: .caseInsensitive) != nil }
            .max { ($0.key.count, $1.key) < ($1.key.count, $0.key) }?.value
    }

    /// frameit's lookup: the language folder, the screenshots folder, the folder above it.
    static func find(_ name: String, languageDir: String, root: String) -> String? {
        [languageDir, root, (root as NSString).deletingLastPathComponent].map { ($0 as NSString).appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
