import Foundation
import zlib

/// Extracts the zip of a verify report (accept --from), in-process and strict: no entry may leave the target
/// directory or be a symbolic link, at most `maxEntries` entries and `maxBytes` extracted, sizes and CRCs checked.
/// Every problem is a UsageError naming the zip.
enum Zip {
    static let maxBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maxEntries = 200_000

    private struct Entry {
        let name: String
        let method: Int
        let flags: Int
        let crc: UInt32
        let compressed: UInt64
        let size: UInt64
        let offset: UInt64
        let symlink: Bool
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt64 { UInt64(u16(b, i)) | UInt64(u16(b, i + 2)) << 16 }
    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 { u32(b, i) | u32(b, i + 4) << 32 }

    static func extract(_ zip: URL, to dest: URL, label: String, maxBytes: Int64 = maxBytes, maxEntries: Int = maxEntries) throws {
        guard let file = FileHandle(forReadingAtPath: zip.path) else { throw UsageError("\(label): can't be read") }
        defer { try? file.close() }
        func read(at offset: UInt64, _ count: Int) throws -> [UInt8] {
            try file.seek(toOffset: offset)
            let data = try file.read(upToCount: count) ?? Data()
            guard data.count == count else { throw UsageError("\(label): damaged zip file (unexpected end)") }
            return [UInt8](data)
        }
        let length = try file.seekToEnd()
        let entries = try centralDirectory(read: read, length: length, label: label, maxEntries: maxEntries)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let root = dest.resolvingSymlinksInPath().standardizedFileURL.path
        var budget = maxBytes
        for e in entries {
            if e.symlink { throw UsageError("\(label): zip entry \"\(e.name)\" is a symbolic link") }
            let parts = e.name.split(separator: "/", omittingEmptySubsequences: false)
            let escapes = e.name.hasPrefix("/") || e.name.contains("\\") || e.name.contains("\0") || e.name.range(of: "^[A-Za-z]:", options: .regularExpression) != nil
                || parts.contains("..")
            let target = URL(fileURLWithPath: root).appendingPathComponent(e.name).standardizedFileURL
            if escapes || !(target.path == root || target.path.hasPrefix(root + "/")) { throw UsageError("\(label): zip entry \"\(e.name)\" points outside the report") }
            if e.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            if e.flags & 1 != 0 { throw UsageError("\(label): zip entry \"\(e.name)\" is encrypted") }
            guard e.method == 0 || e.method == 8 else { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" uses compression method \(e.method))") }
            let local = try read(at: e.offset, 30)
            guard u32(local, 0) == 0x0403_4b50 else { throw UsageError("\(label): damaged zip file (no local header for \"\(e.name)\")") }
            let start = e.offset + 30 + UInt64(u16(local, 26)) + UInt64(u16(local, 28))
            guard start + e.compressed <= length else { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" is cut off)") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            guard FileManager.default.createFile(atPath: target.path, contents: nil), let out = FileHandle(forWritingAtPath: target.path) else {
                throw UsageError("\(label): can't write \(e.name)")
            }
            defer { try? out.close() }
            var crc = crc32(0, nil, 0)
            var written: UInt64 = 0
            func emit(_ chunk: UnsafeBufferPointer<UInt8>) throws {
                guard chunk.count > 0 else { return }
                budget -= Int64(chunk.count)
                if budget < 0 { throw UsageError("\(label): larger than \(maxBytes >> 30 > 0 ? "\(maxBytes >> 30) GB" : "\(maxBytes) bytes") extracted") }
                crc = crc32(crc, chunk.baseAddress, uInt(chunk.count))
                written += UInt64(chunk.count)
                try out.write(contentsOf: Data(buffer: chunk))
            }
            try file.seek(toOffset: start)
            var remaining = e.compressed
            if e.method == 0 {
                while remaining > 0 {
                    let data = [UInt8](try file.read(upToCount: Int(min(remaining, 1 << 16))) ?? Data())
                    if data.isEmpty { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" is cut off)") }
                    remaining -= UInt64(data.count)
                    try data.withUnsafeBufferPointer { try emit($0) }
                }
            } else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw UsageError("\(label): zlib failed") }
                defer { inflateEnd(&stream) }
                var outBuf = [UInt8](repeating: 0, count: 1 << 16)
                var ended = false
                while !ended {
                    var input = [UInt8](try file.read(upToCount: Int(min(remaining, 1 << 16))) ?? Data())
                    remaining -= UInt64(input.count)
                    let last = remaining == 0
                    if input.isEmpty && !last { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" is cut off)") }
                    try input.withUnsafeMutableBufferPointer { inp in
                        stream.next_in = inp.baseAddress
                        stream.avail_in = uInt(inp.count)
                        repeat {
                            let (ret, produced): (Int32, Int) = outBuf.withUnsafeMutableBufferPointer { o in
                                stream.next_out = o.baseAddress
                                stream.avail_out = uInt(o.count)
                                let r = inflate(&stream, Z_NO_FLUSH)
                                return (r, o.count - Int(stream.avail_out))
                            }
                            try outBuf.withUnsafeBufferPointer { try emit(UnsafeBufferPointer(rebasing: $0[0..<produced])) }
                            if ret == Z_STREAM_END { ended = true; return }
                            if ret == Z_BUF_ERROR && stream.avail_in == 0 { break }
                            guard ret == Z_OK else { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\": \(stream.msg.map { String(cString: $0) } ?? String(cString: zError(ret))))") }
                        } while stream.avail_in > 0 || stream.avail_out == 0
                    }
                    if !ended && last { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" is cut off)") }
                }
            }
            guard written == e.size, UInt32(crc) == e.crc else { throw UsageError("\(label): damaged zip file (entry \"\(e.name)\" fails its size or CRC check)") }
        }
    }

    /// The central directory's entries (zip64 sizes and offsets included).
    private static func centralDirectory(read: (UInt64, Int) throws -> [UInt8], length: UInt64, label: String, maxEntries: Int) throws -> [Entry] {
        let tail = min(length, 22 + 65535)
        guard tail >= 22 else { throw UsageError("\(label): not a zip file") }
        let buf = try read(length - tail, Int(tail))
        guard let eocd = stride(from: buf.count - 22, through: 0, by: -1).first(where: { u32(buf, $0) == 0x0605_4b50 }) else { throw UsageError("\(label): not a zip file") }
        var count = UInt64(u16(buf, eocd + 10))
        var size = u32(buf, eocd + 12)
        var offset = u32(buf, eocd + 16)
        if offset == 0xffff_ffff || count == 0xffff || size == 0xffff_ffff {
            let loc = eocd - 20
            guard loc >= 0, u32(buf, loc) == 0x0706_4b50 else { throw UsageError("\(label): damaged zip64 file") }
            let z64 = try read(u64(buf, loc + 8), 56)
            guard u32(z64, 0) == 0x0606_4b50 else { throw UsageError("\(label): damaged zip64 file") }
            count = u64(z64, 32); size = u64(z64, 40); offset = u64(z64, 48)
        }
        if count > UInt64(maxEntries) { throw UsageError("\(label): more than \(maxEntries) entries") }
        guard offset < length || (count == 0 && offset == length), offset + size <= length, size <= UInt64(Int32.max) else { throw UsageError("\(label): damaged zip file") }
        let cd = try read(offset, Int(size))
        var entries: [Entry] = []
        var i = 0
        while entries.count < Int(count) {
            guard i + 46 <= cd.count, u32(cd, i) == 0x0201_4b50 else { throw UsageError("\(label): damaged zip file (central directory)") }
            let nameLen = u16(cd, i + 28), extraLen = u16(cd, i + 30), commentLen = u16(cd, i + 32)
            guard i + 46 + nameLen + extraLen + commentLen <= cd.count else { throw UsageError("\(label): damaged zip file (central directory)") }
            guard let name = String(bytes: cd[(i + 46)..<(i + 46 + nameLen)], encoding: .utf8) else {
                throw UsageError("\(label): damaged zip file or an entry name that isn't UTF-8")
            }
            var compressed = u32(cd, i + 20), uncompressed = u32(cd, i + 24), local = u32(cd, i + 42)
            // Zip64: the 0xffffffff fields follow in order in the 0x0001 extra field.
            var x = i + 46 + nameLen
            let extraEnd = x + extraLen
            while x + 4 <= extraEnd {
                let id = u16(cd, x), n = u16(cd, x + 2)
                if id == 1 {
                    var p = x + 4
                    if uncompressed == 0xffff_ffff, p + 8 <= x + 4 + n { uncompressed = u64(cd, p); p += 8 }
                    if compressed == 0xffff_ffff, p + 8 <= x + 4 + n { compressed = u64(cd, p); p += 8 }
                    if local == 0xffff_ffff, p + 8 <= x + 4 + n { local = u64(cd, p); p += 8 }
                }
                x += 4 + n
            }
            let madeBy = u16(cd, i + 4) >> 8
            let mode = Int(u32(cd, i + 38) >> 16)
            entries.append(Entry(name: name, method: u16(cd, i + 10), flags: u16(cd, i + 8), crc: UInt32(u32(cd, i + 16)), compressed: compressed,
                                 size: uncompressed, offset: local, symlink: madeBy == 3 && mode & 0xF000 == 0xA000))
            i += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }
}
