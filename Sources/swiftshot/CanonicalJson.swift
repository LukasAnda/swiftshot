import CryptoKit
import Foundation

/// A JSON value as the baseline format reads and writes it (docs/wiki/Baseline-format.md, Serialization).
/// Numbers keep whether they were written as integers, like the JVM implementation's Long/Double.
enum JSON: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    subscript(key: String) -> JSON? { if case .object(let o) = self { return o[key] }; return nil }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }
    var number: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; default: return nil }
    }
    var isNull: Bool { self == .null }

    /// What the JVM implementation's `toString()` gives for the value (messages, JUnit class names).
    var text: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return d == d.rounded(.towardZero) && abs(d) < 1e7 ? String(format: "%.1f", d) : "\(d)"
        case .string(let s): return s
        case .array(let a): return "[" + a.map(\.text).joined(separator: ", ") + "]"
        case .object(let o): return "{" + o.keys.sorted(by: utf8Less).map { "\($0)=\(o[$0]!.text)" }.joined(separator: ", ") + "}"
        }
    }

    // MARK: writing

    /// Pretty form: 2-space indent, sorted keys, empty containers as `[]`/`{}`, a final newline.
    func pretty() -> String { var out = ""; write(&out, indent: "  ", pad: ""); return out + "\n" }

    /// Compact form (hashes): no whitespace at all.
    func compact() -> String { var out = ""; write(&out, indent: nil, pad: ""); return out }

    private func write(_ out: inout String, indent: String?, pad: String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += JSON.number(d)
        case .string(let s): JSON.quote(&out, s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            let inner = indent.map { pad + $0 }
            out += "["
            for (n, item) in items.enumerated() {
                if n > 0 { out += "," }
                if let inner { out += "\n" + inner }
                item.write(&out, indent: indent, pad: inner ?? "")
            }
            if indent != nil { out += "\n" + pad }
            out += "]"
        case .object(let o):
            if o.isEmpty { out += "{}"; return }
            let inner = indent.map { pad + $0 }
            out += "{"
            for (n, key) in o.keys.sorted(by: utf8Less).enumerated() {
                if n > 0 { out += "," }
                if let inner { out += "\n" + inner }
                JSON.quote(&out, key)
                out += indent != nil ? ": " : ":"
                o[key]!.write(&out, indent: indent, pad: inner ?? "")
            }
            if indent != nil { out += "\n" + pad }
            out += "}"
        }
    }

    static func quote(_ out: inout String, _ s: String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    /// An integral value as an integer, others in the shortest round-tripping decimal, never with an exponent.
    static func number(_ d: Double) -> String {
        precondition(d.isFinite && abs(d) < 1e15, "number out of range: \(d)")
        if d == d.rounded(.towardZero) { return String(Int64(d)) }
        let s = "\(d)"   // shortest round-trip form, possibly with an exponent
        guard let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return s }
        let exp = Int(s[s.index(after: e)...])!
        var mantissa = String(s[..<e])
        let negative = mantissa.hasPrefix("-")
        if negative { mantissa.removeFirst() }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0]), frac = parts.count > 1 ? String(parts[1]) : ""
        var digits = whole + frac
        var point = whole.count + exp   // position of the decimal point in `digits`
        if point <= 0 { digits = String(repeating: "0", count: 1 - point) + digits; point = 1 }
        if point >= digits.count { digits += String(repeating: "0", count: point - digits.count) }
        var intPart = String(digits.prefix(point)), fracPart = String(digits.dropFirst(point))
        while fracPart.hasSuffix("0") { fracPart.removeLast() }
        while intPart.count > 1 && intPart.hasPrefix("0") { intPart.removeFirst() }
        return (negative ? "-" : "") + intPart + (fracPart.isEmpty ? "" : "." + fracPart)
    }

    // MARK: reading

    struct ParseError: Error, CustomStringConvertible { let description: String }

    static func parse(_ text: String) throws -> JSON {
        var p = Parser(Array(text.utf8))
        let v = try p.value()
        p.ws()
        guard p.i == p.s.count else { throw ParseError(description: "trailing data at \(p.i)") }
        return v
    }

    static func parse(_ data: Data) throws -> JSON { try parse(String(decoding: data, as: UTF8.self)) }

    private struct Parser {
        let s: [UInt8]
        var i = 0
        init(_ s: [UInt8]) { self.s = s }

        func fail(_ what: String) -> ParseError { ParseError(description: "\(what) at \(i)") }
        mutating func ws() { while i < s.count, [0x20, 0x0a, 0x0d, 0x09].contains(s[i]) { i += 1 } }
        func peek() throws -> UInt8 { guard i < s.count else { throw fail("unexpected end") }; return s[i] }

        mutating func value() throws -> JSON {
            ws()
            switch try peek() {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default: throw fail("unexpected character")
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= s.count, Array(s[i..<(i + w.count)]) == w else { throw fail("bad literal") }
            i += w.count
        }

        mutating func object() throws -> JSON {
            var m: [String: JSON] = [:]
            i += 1; ws()
            if try peek() == UInt8(ascii: "}") { i += 1; return .object(m) }
            while true {
                ws()
                guard try peek() == UInt8(ascii: "\"") else { throw fail("expected string") }
                let k = try string()
                ws()
                guard try peek() == UInt8(ascii: ":") else { throw fail("expected :") }
                i += 1
                m[k] = try value()
                ws()
                let c = try peek(); i += 1
                if c == UInt8(ascii: ",") { continue }
                if c == UInt8(ascii: "}") { return .object(m) }
                throw fail("expected , or }")
            }
        }

        mutating func array() throws -> JSON {
            var l: [JSON] = []
            i += 1; ws()
            if try peek() == UInt8(ascii: "]") { i += 1; return .array(l) }
            while true {
                l.append(try value())
                ws()
                let c = try peek(); i += 1
                if c == UInt8(ascii: ",") { continue }
                if c == UInt8(ascii: "]") { return .array(l) }
                throw fail("expected , or ]")
            }
        }

        mutating func hex4() throws -> UInt16 {
            guard i + 4 <= s.count, let v = UInt16(String(decoding: s[i..<(i + 4)], as: UTF8.self), radix: 16) else { throw fail("bad \\u escape") }
            i += 4
            return v
        }

        mutating func string() throws -> String {
            i += 1
            var bytes: [UInt8] = []
            while true {
                let c = try peek(); i += 1
                switch c {
                case UInt8(ascii: "\""): return String(decoding: bytes, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    let e = try peek(); i += 1
                    switch e {
                    case UInt8(ascii: "n"): bytes.append(0x0a)
                    case UInt8(ascii: "t"): bytes.append(0x09)
                    case UInt8(ascii: "r"): bytes.append(0x0d)
                    case UInt8(ascii: "b"): bytes.append(0x08)
                    case UInt8(ascii: "f"): bytes.append(0x0c)
                    case UInt8(ascii: "u"):
                        var units = [try hex4()]
                        // A surrogate pair is two escapes.
                        if (0xD800..<0xDC00).contains(units[0]), i + 6 <= s.count, s[i] == UInt8(ascii: "\\"), s[i + 1] == UInt8(ascii: "u") {
                            i += 2; units.append(try hex4())
                        }
                        bytes += Array(String(decoding: units, as: UTF16.self).utf8)
                    default: bytes.append(e)
                    }
                default: bytes.append(c)
                }
            }
        }

        mutating func number() throws -> JSON {
            let start = i
            if s[i] == UInt8(ascii: "-") { i += 1 }
            while i < s.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(s[i]) || [UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"), UInt8(ascii: "+"), UInt8(ascii: "-")].contains(s[i]) { i += 1 }
            let t = String(decoding: s[start..<i], as: UTF8.self)
            if t.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) {
                guard let d = Double(t) else { throw fail("bad number") }
                return .double(d)
            }
            guard let n = Int64(t) else { throw fail("bad number") }
            return .int(n)
        }
    }
}

/// UTF-8 byte order (= code point order), the order of every sorted key and list in the baseline format.
func utf8Less(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

enum CanonicalJson {
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The hash of a value: SHA-256 of its compact form.
    static func hash(_ v: JSON) -> String { sha256(v.compact()) }
}
