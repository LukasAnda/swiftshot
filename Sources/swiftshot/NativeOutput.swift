import Foundation
import zlib

/// What each CI reads from a verify run besides the report files (docs/wiki/Baseline-format.md, "Native CI output").
/// `env` is the process environment, read once by the caller; `out` prints a line to stdout (workflow commands).
/// A failure is one warning: it never changes verify's exit code.
enum NativeOutput {
    private static let maxAnnotations = 10

    static func write(_ v: Verification, ci: Ci?, reportDir: URL, env: [String: String], out: (String) -> Void, log: Console) {
        guard let provider = ci?.provider else { return }
        func set(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        let report = reportDir.standardizedFileURL
        let fm = FileManager.default
        func copy(_ from: URL, to: URL) throws {
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)
        }
        do {
            switch provider {
            case "github":
                for r in Summary.rows(v).prefix(maxAnnotations) {
                    if r.status == "error" {
                        let message = v.entries.first { $0["id"]?.string == r.id && $0["status"]?.string == "error" }?["message"]?.text ?? "null"
                        out("::error title=Render error::\(data("\(r.id): \(message)"))")
                    } else {
                        out("::error title=\(data("\(r.status) screenshot", title: true))::\(data(r.id))")
                    }
                }
                if let path = set("GITHUB_STEP_SUMMARY") {
                    let text = try Data(contentsOf: report.appendingPathComponent("summary.md"))
                    let url = URL(fileURLWithPath: path)
                    if !fm.fileExists(atPath: path) { try Data().write(to: url) }
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: text)
                }
            case "azure":
                out("##vso[results.publish type=JUnit;mergeResults=false;runTitle=swiftshot;resultFiles=\(report.appendingPathComponent("junit.xml").path)]")
                out("##vso[task.uploadsummary]\(report.appendingPathComponent("summary.md").path)")
                if v.status != "passed" { out("##vso[task.logissue type=error]Screenshots: \(Summary.counts(v))") }
            case "bitbucket":
                if let dir = set("BITBUCKET_CLONE_DIR") {
                    try copy(report.appendingPathComponent("junit.xml"), to: URL(fileURLWithPath: dir).appendingPathComponent("test-results/swiftshot/junit.xml"))
                }
            case "bitrise":
                if let dir = set("BITRISE_TEST_RESULT_DIR") {
                    let target = URL(fileURLWithPath: dir).appendingPathComponent("swiftshot")
                    try copy(report.appendingPathComponent("junit.xml"), to: target.appendingPathComponent("junit.xml"))
                    try Data(#"{"test-name":"swiftshot"}"#.utf8).write(to: target.appendingPathComponent("test-info.json"))
                }
                if let dir = set("BITRISE_DEPLOY_DIR") {
                    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    try zip(report, to: URL(fileURLWithPath: dir).appendingPathComponent("swiftshot-report.zip"))
                }
            default: break
            }
        } catch {
            log.warn("Could not write the \(provider) CI output: \(error.localizedDescription)")
        }
    }

    /// A workflow command's data (and, for a property such as the title, also `:` and `,`).
    private static func data(_ s: String, title: Bool = false) -> String {
        var b = ""
        for c in s.unicodeScalars {
            switch c {
            case "%": b += "%25"
            case "\r": b += "%0D"
            case "\n": b += "%0A"
            case ":" where title: b += "%3A"
            case "," where title: b += "%2C"
            default: b.unicodeScalars.append(c)
            }
        }
        return b
    }

    /// The report directory's files at the zip's root (as `accept --from` reads them): sorted, one fixed timestamp.
    static func zip(_ dir: URL, to: URL) throws {
        let fm = FileManager.default
        let root = dir.resolvingSymlinksInPath().standardizedFileURL.path
        let target = to.resolvingSymlinksInPath().standardizedFileURL.path
        var names: [String] = []
        if let walk = fm.enumerator(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in walk {
                let path = u.standardizedFileURL.path
                if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, path != target {
                    names.append(String(path.dropFirst(root.count + 1)))
                }
            }
        }
        var archive = ZipArchive()
        for name in names.sorted(by: utf8Less) { try archive.add(name, try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(name))) }
        try Data(try archive.finish()).write(to: to)
    }
}

/// A zip file written in memory: deflated entries, DOS time 1980-01-01 00:00, names in the order added. No zip64:
/// more than 65,535 entries or a size past 32 bits is an error.
struct ZipArchive {
    struct Failure: LocalizedError { let errorDescription: String? }

    private var body: [UInt8] = []
    private var central: [UInt8] = []
    private var count = 0

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
    private static let dosDate = 1 << 5 | 1   // 1980-01-01
    static let maxEntries = 65_535

    /// A size or offset that fits the 32-bit fields (0xFFFFFFFF would mean zip64).
    private func u32(_ v: Int, _ what: String) throws -> UInt32 {
        guard v >= 0, v < Int(UInt32.max) else { throw Failure(errorDescription: "the report zip is too large (\(what))") }
        return UInt32(v)
    }

    private func deflateRaw(_ data: [UInt8]) throws -> [UInt8] {
        var s = z_stream()
        guard deflateInit2_(&s, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure(errorDescription: "zlib could not start compressing")
        }
        defer { deflateEnd(&s) }
        var out = [UInt8](repeating: 0, count: Int(deflateBound(&s, uLong(data.count))) + 16)
        var input = data
        let (code, n): (Int32, Int) = input.withUnsafeMutableBufferPointer { inp in
            out.withUnsafeMutableBufferPointer { o in
                s.next_in = inp.baseAddress; s.avail_in = uInt(inp.count)
                s.next_out = o.baseAddress; s.avail_out = uInt(o.count)
                let code = deflate(&s, Z_FINISH)
                return (code, Int(s.total_out))
            }
        }
        guard code == Z_STREAM_END else { throw Failure(errorDescription: "zlib could not compress a file (\(code))") }
        return Array(out[0..<n])
    }

    mutating func add(_ name: String, _ content: Data) throws {
        guard count < Self.maxEntries else { throw Failure(errorDescription: "the report has more than \(Self.maxEntries) files for one zip") }
        let data = [UInt8](content)
        let nameBytes = Array(name.utf8)
        guard nameBytes.count <= 0xFFFF else { throw Failure(errorDescription: "a file name is too long for the zip") }
        let size = try u32(data.count, "a file")
        let crc = UInt32(crc32(0, data, uInt(size)))
        let packed = try deflateRaw(data)
        let (offset, packedSize) = (try u32(body.count, "offset"), try u32(packed.count, "a file"))
        body += le32(0x0403_4b50) + le16(20) + le16(0x800) + le16(8) + le16(0) + le16(Self.dosDate) + le32(crc) + le32(packedSize) + le32(size)
            + le16(nameBytes.count) + le16(0) + nameBytes + packed
        central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0x800) + le16(8) + le16(0) + le16(Self.dosDate) + le32(crc) + le32(packedSize) + le32(size)
            + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameBytes
        count += 1
    }

    func finish() throws -> [UInt8] {
        let (centralSize, centralOffset) = (try u32(central.count, "directory"), try u32(body.count, "directory offset"))
        return body + central + le32(0x0605_4b50) + le16(0) + le16(0) + le16(count) + le16(count) + le32(centralSize) + le32(centralOffset) + le16(0)
    }
}
