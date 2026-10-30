import Foundation
import zlib

/// Not a PNG the comparison reads (docs/wiki/Baseline-format.md, Decoding).
struct UnsupportedPNG: Error, CustomStringConvertible { var description: String { "unsupported PNG" } }

/// Decoded pixels as packed ARGB, samples as stored.
struct PngImage: Equatable {
    let width: Int
    let height: Int
    let argb: [UInt32]
}

/// The PNG subset of the baseline format: a strict decoder for 8-bit RGB/RGBA and the canonical encoder (RGBA,
/// filter 0, one IDAT written by zlib level 6, IHDR/IDAT/IEND only). ImageIO is laxer and its encoder's bytes
/// aren't specified, so neither is used here; zlib is the system's (madler's zlib, as the format requires).
enum Png {
    static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    static func decode(_ data: [UInt8]) throws -> PngImage {
        func u32(_ at: Int) -> Int { Int(data[at]) << 24 | Int(data[at + 1]) << 16 | Int(data[at + 2]) << 8 | Int(data[at + 3]) }
        guard data.count >= 8, Array(data[0..<8]) == signature else { throw UnsupportedPNG() }
        var i = 8
        var ihdr: [UInt8]?
        var idat: [UInt8] = []
        while i < data.count {
            guard i + 12 <= data.count else { throw UnsupportedPNG() }
            let len = u32(i)
            guard i + 12 + len <= data.count else { throw UnsupportedPNG() }
            let type = String(decoding: data[(i + 4)..<(i + 8)], as: UTF8.self)
            let crc = data.withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress! + i + 4, uInt(4 + len))) }
            guard Int(crc) == u32(i + 8 + len) else { throw UnsupportedPNG() }
            let body = i + 8
            i += 12 + len
            guard (ihdr == nil) == (type == "IHDR") else { throw UnsupportedPNG() }
            if type == "IHDR" {
                guard len == 13 else { throw UnsupportedPNG() }
                ihdr = Array(data[body..<(body + 13)])
            } else if type == "IDAT" {
                idat += data[body..<(body + len)]
            } else if type == "IEND" {
                break
            }
        }
        guard let h = ihdr else { throw UnsupportedPNG() }
        let width = Int(h[0]) << 24 | Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
        let height = Int(h[4]) << 24 | Int(h[5]) << 16 | Int(h[6]) << 8 | Int(h[7])
        let depth = h[8], colorType = h[9], interlace = h[12]
        guard depth == 8, colorType == 2 || colorType == 6, interlace == 0 else { throw UnsupportedPNG() }
        let bpp = colorType == 6 ? 4 : 3
        // Larger than an array can hold: no such image can be compared (its zlib data would be the wrong length or huge).
        let limit = Int(Int32.max) - 8
        guard width <= Int(Int32.max), height <= Int(Int32.max) else { throw UnsupportedPNG() }
        let stride = width * bpp                                   // < 2^34: no overflow
        let (expected, overflow) = height.multipliedReportingOverflow(by: 1 + stride)
        guard !overflow, expected <= limit, width * height <= limit else { throw UnsupportedPNG() }
        let raw = try inflate(idat, size: expected)
        var out = [UInt32](repeating: 0, count: width * height)
        var prev = [UInt8](repeating: 0, count: stride)
        var row = [UInt8](repeating: 0, count: stride)
        var o = 0
        for y in 0..<height {
            let f = raw[o]
            guard f <= 4 else { throw UnsupportedPNG() }
            row.withUnsafeMutableBufferPointer { r in
                raw.withUnsafeBufferPointer { src in
                    for x in 0..<stride { r[x] = src[o + 1 + x] }
                }
                prev.withUnsafeBufferPointer { p in
                    for x in 0..<stride {
                        let a = x >= bpp ? Int(r[x - bpp]) : 0
                        let b = Int(p[x])
                        let c = x >= bpp ? Int(p[x - bpp]) : 0
                        let pred: Int
                        switch f {
                        case 0: pred = 0
                        case 1: pred = a
                        case 2: pred = b
                        case 3: pred = (a + b) / 2
                        default:
                            let pa = abs(b - c), pb = abs(a - c), pc = abs(a + b - 2 * c)
                            pred = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
                        }
                        r[x] = r[x] &+ UInt8(truncatingIfNeeded: pred)
                    }
                }
                out.withUnsafeMutableBufferPointer { px in
                    for x in 0..<width {
                        let p = x * bpp
                        let alpha: UInt32 = bpp == 4 ? UInt32(r[p + 3]) : 255
                        px[y * width + x] = alpha << 24 | UInt32(r[p]) << 16 | UInt32(r[p + 1]) << 8 | UInt32(r[p + 2])
                    }
                }
            }
            o += 1 + stride
            swap(&prev, &row)
        }
        return PngImage(width: width, height: height, argb: out)
    }

    /// One complete zlib stream (data after its end is ignored) of exactly [size] bytes.
    private static func inflate(_ z: [UInt8], size: Int) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw UnsupportedPNG() }
        defer { inflateEnd(&stream) }
        // One byte more than expected: a stream that would write it is too long.
        var out = [UInt8](repeating: 0, count: size + 1)
        var input = z
        let ended: Bool = input.withUnsafeMutableBufferPointer { inp in
            out.withUnsafeMutableBufferPointer { o in
                stream.next_in = inp.baseAddress
                stream.avail_in = uInt(inp.count)
                stream.next_out = o.baseAddress
                stream.avail_out = uInt(o.count)
                while true {
                    let ret = zlib.inflate(&stream, Z_NO_FLUSH)
                    if ret == Z_STREAM_END { return true }
                    if ret != Z_OK { return false }   // data error, needs a dictionary, no progress possible (input ended)
                }
            }
        }
        guard ended, Int(stream.total_out) == size else { throw UnsupportedPNG() }
        out.removeLast()
        return out
    }

    /// The canonical encoding of an image as 8-bit RGBA.
    static func encode(_ image: PngImage) -> [UInt8] {
        let w = image.width, h = image.height
        var raw = [UInt8](repeating: 0, count: h * (1 + w * 4))
        raw.withUnsafeMutableBufferPointer { r in
            image.argb.withUnsafeBufferPointer { px in
                var o = 0
                for y in 0..<h {
                    r[o] = 0; o += 1
                    for x in 0..<w {
                        let p = px[y * w + x]
                        r[o] = UInt8(p >> 16 & 255); r[o + 1] = UInt8(p >> 8 & 255); r[o + 2] = UInt8(p & 255); r[o + 3] = UInt8(p >> 24)
                        o += 4
                    }
                }
            }
        }
        // compress2(…, 6): deflate level 6, window 15, memory level 8, default strategy.
        var n = compressBound(uLong(raw.count))
        var z = [UInt8](repeating: 0, count: Int(n))
        let ret = compress2(&z, &n, raw, uLong(raw.count), 6)
        precondition(ret == Z_OK, "zlib compress2 failed: \(ret)")
        var out = signature
        func int(_ v: Int, into a: inout [UInt8]) { a += [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        func chunk(_ type: String, _ body: ArraySlice<UInt8>) {
            let t = Array(type.utf8)
            int(body.count, into: &out)
            out += t
            out += body
            var crc = crc32(0, t, uInt(t.count))
            crc = body.withUnsafeBufferPointer { crc32(crc, $0.baseAddress, uInt($0.count)) }
            int(Int(crc), into: &out)
        }
        var ihdr: [UInt8] = []
        int(w, into: &ihdr); int(h, into: &ihdr); ihdr += [8, 6, 0, 0, 0]
        chunk("IHDR", ihdr[...])
        chunk("IDAT", z[0..<Int(n)])
        chunk("IEND", [][...])
        return out
    }
}
