import Foundation

/// `tolerance` of the comparison config: up to `pixels` differing pixels pass; a channel differs by more than `maxChannelDelta`.
struct Tolerance: Equatable {
    var pixels = 0
    var maxChannelDelta = 0
}

/// A rectangle in pixels.
struct Region: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

/// One comparison. `status` unchanged or changed; `reason` tolerance (unchanged, `pixels` > 0), pixels or size
/// (changed), else nil. `boxes`, `diffImage` and the sizes (`[w, h]`, size changes only) are set for changed only.
struct Diff: Equatable {
    var status: String
    var reason: String?
    var pixels: Int
    var boxes: [Region]
    var diffImage: PngImage?
    var baselineSize: [Int]? = nil
    var newSize: [Int]? = nil
}

/// The pixel comparison of docs/wiki/Baseline-format.md (Comparison, Boxes, Diff image).
enum Compare {
    /// Boxes closer than this (in pixels, along the larger axis gap) are merged.
    static let mergeDistance = 16
    static let diffColor: UInt32 = 0xFFFF_2D55

    /// Compares two PNG files. Equal bytes are unchanged without decoding; otherwise both are decoded (throws
    /// UnsupportedPNG). `ignore` pixels never differ (see ignoreRegion); they are clipped to the canvas.
    static func images(baseline: URL, new: URL, tolerance: Tolerance, ignore: [Region]) throws -> Diff {
        let a = [UInt8](try Data(contentsOf: baseline)), b = [UInt8](try Data(contentsOf: new))
        if a == b { return Diff(status: "unchanged", reason: nil, pixels: 0, boxes: [], diffImage: nil) }
        return images(try Png.decode(a), try Png.decode(b), tolerance: tolerance, ignore: ignore)
    }

    static func images(_ base: PngImage, _ new: PngImage, tolerance: Tolerance, ignore: [Region]) -> Diff {
        let cw = max(base.width, new.width), ch = max(base.height, new.height)
        var mask = [Bool](repeating: false, count: cw * ch)
        let d = UInt32(tolerance.maxChannelDelta)
        func channel(_ p: UInt32, _ q: UInt32, _ shift: UInt32) -> UInt32 {
            let a = p >> shift & 255, b = q >> shift & 255
            return a > b ? a - b : b - a
        }
        mask.withUnsafeMutableBufferPointer { m in
            base.argb.withUnsafeBufferPointer { bp in
                new.argb.withUnsafeBufferPointer { np in
                    for y in 0..<ch {
                        for x in 0..<cw {
                            if x >= base.width || y >= base.height || x >= new.width || y >= new.height { m[y * cw + x] = true; continue }
                            let p = bp[y * base.width + x], q = np[y * new.width + x]
                            if p != q && (channel(p, q, 24) > d || channel(p, q, 16) > d || channel(p, q, 8) > d || channel(p, q, 0) > d) { m[y * cw + x] = true }
                        }
                    }
                }
            }
            for r in ignore {
                let x0 = min(max(r.x, 0), cw), y0 = min(max(r.y, 0), ch)
                let x1 = min(max(r.x + r.width, 0), cw), y1 = min(max(r.y + r.height, 0), ch)
                if x1 <= x0 { continue }
                for y in y0..<max(y0, y1) { for x in x0..<x1 { m[y * cw + x] = false } }
            }
        }
        let count = mask.reduce(0) { $1 ? $0 + 1 : $0 }
        let sized = base.width != new.width || base.height != new.height
        if !sized && count <= tolerance.pixels {
            return Diff(status: "unchanged", reason: count > 0 ? "tolerance" : nil, pixels: count, boxes: [], diffImage: nil)
        }
        return Diff(status: "changed", reason: sized ? "size" : "pixels", pixels: count, boxes: boxes(mask, cw, ch),
                    diffImage: diffImage(base, mask, cw, ch),
                    baselineSize: sized ? [base.width, base.height] : nil, newSize: sized ? [new.width, new.height] : nil)
    }

    /// An `ignore_regions` entry `[x, y, w, h]` in points/dp at `scale` pixels per point, in pixels:
    /// `floor(x·s)`, `floor(y·s)` to `ceil((x+w)·s)`, `ceil((y+h)·s)`, not yet clipped to the canvas.
    static func ignoreRegion(_ rect: [Double], scale: Double) -> Region {
        precondition(rect.count == 4, "ignore region must be [x, y, w, h]")
        let x = rect[0], y = rect[1], w = rect[2], h = rect[3]
        func int(_ v: Double) -> Int { v.isFinite ? Int(max(min(v, Double(Int32.max)), Double(Int32.min))) : 0 }
        let x0 = int((x * scale).rounded(.down)), y0 = int((y * scale).rounded(.down))
        let x1 = int(((x + w) * scale).rounded(.up)), y1 = int(((y + h) * scale).rounded(.up))
        return Region(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Pair checks and grid entries of the last `boxes` call (tests keep it bounded).
    nonisolated(unsafe) static var lastBoxWork = 0

    /// Bounding boxes of the 8-connected components, merged while any two are closer than mergeDistance; sorted by
    /// y, x, w, h. The merged result doesn't depend on the order of merges, and every merge of a close pair is forced,
    /// so this starts from coarser groups that would merge anyway: all differing pixels of one 16×16 cell are at most
    /// 15 px apart, so their components are close. It then unions close boxes (found through a 16 px grid) until none is.
    static func boxes(_ mask: [Bool], _ w: Int, _ h: Int) -> [Region] {
        let c = mergeDistance
        let gw = (w + c - 1) / c, gh = (h + c - 1) / c
        var work = 0
        // One box per non-empty cell: x0, y0, x1, y1.
        var cells = [Int](repeating: 0, count: gw * gh * 4)
        var used = [Bool](repeating: false, count: gw * gh)
        mask.withUnsafeBufferPointer { m in
            cells.withUnsafeMutableBufferPointer { cell in
                used.withUnsafeMutableBufferPointer { u in
                    for y in 0..<h {
                        let row = y * w, cy = y / c
                        for x in 0..<w where m[row + x] {
                            let k = cy * gw + x / c, o = k * 4
                            if !u[k] { u[k] = true; cell[o] = x; cell[o + 1] = y; cell[o + 2] = x + 1; cell[o + 3] = y + 1 } else {
                                if x < cell[o] { cell[o] = x }
                                if x + 1 > cell[o + 2] { cell[o + 2] = x + 1 }
                                cell[o + 3] = y + 1
                            }
                        }
                    }
                }
            }
        }
        var boxes: [[Int]] = []
        for k in used.indices where used[k] { boxes.append(Array(cells[(k * 4)..<(k * 4 + 4)])) }
        func gap(_ a: [Int], _ b: [Int]) -> Int { max(0, b[0] - a[2], a[0] - b[2], b[1] - a[3], a[1] - b[3]) }
        // Union every close pair (union-find), replace each group by its union, repeat until a pass merges nothing.
        while true {
            let n = boxes.count
            // Grid buckets (CSR): box i is listed in every cell it covers.
            var count = [Int](repeating: 0, count: gw * gh + 1)
            for b in boxes { for cy in (b[1] / c)...((b[3] - 1) / c) { for cx in (b[0] / c)...((b[2] - 1) / c) { count[cy * gw + cx + 1] += 1 } } }
            for k in 1..<count.count { count[k] += count[k - 1] }
            var fillAt = count
            var members = [Int](repeating: 0, count: count[count.count - 1])
            for (i, b) in boxes.enumerated() {
                for cy in (b[1] / c)...((b[3] - 1) / c) { for cx in (b[0] / c)...((b[2] - 1) / c) { members[fillAt[cy * gw + cx]] = i; fillAt[cy * gw + cx] += 1 } }
            }
            work += members.count
            var parent = Array(0..<n)
            func find(_ i: Int) -> Int {
                var r = i
                while parent[r] != r { r = parent[r] }
                var j = i
                while parent[j] != r { let next = parent[j]; parent[j] = r; j = next }
                return r
            }
            var stamp = [Int](repeating: -1, count: n)
            var merged = false
            for i in 0..<n {
                let a = boxes[i]
                // gap < c: a close box starts at most c px past this one's last pixel, and ends at most c before its first.
                let cx0 = max(0, a[0] - c) / c, cx1 = min(w - 1, a[2] - 1 + c) / c
                let cy0 = max(0, a[1] - c) / c, cy1 = min(h - 1, a[3] - 1 + c) / c
                for cy in cy0...cy1 {
                    for cx in cx0...cx1 {
                        let k = cy * gw + cx
                        for m in count[k]..<count[k + 1] {
                            let j = members[m]
                            if j <= i || stamp[j] == i { continue }
                            stamp[j] = i
                            work += 1
                            if gap(a, boxes[j]) < c {
                                let ri = find(i), rj = find(j)
                                if ri != rj { parent[rj] = ri; merged = true }
                            }
                        }
                    }
                }
            }
            if !merged { break }
            var order: [Int] = []
            var groups: [Int: [Int]] = [:]
            for i in 0..<n {
                let b = boxes[i], r = find(i)
                if var g = groups[r] {
                    g[0] = min(g[0], b[0]); g[1] = min(g[1], b[1]); g[2] = max(g[2], b[2]); g[3] = max(g[3], b[3])
                    groups[r] = g
                } else { groups[r] = b; order.append(r) }
            }
            boxes = order.map { groups[$0]! }
        }
        lastBoxWork = work
        return boxes.map { Region(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }
            .sorted { ($0.y, $0.x, $0.width, $0.height) < ($1.y, $1.x, $1.width, $1.height) }
    }

    /// Canvas-sized, opaque: differing pixels #FF2D55, other baseline pixels at 30 % over white, the rest white.
    private static func diffImage(_ base: PngImage, _ mask: [Bool], _ cw: Int, _ ch: Int) -> PngImage {
        var out = [UInt32](repeating: 0xFFFF_FFFF, count: cw * ch)
        out.withUnsafeMutableBufferPointer { o in
            base.argb.withUnsafeBufferPointer { bp in
                for y in 0..<ch {
                    for x in 0..<cw {
                        let i = y * cw + x
                        if mask[i] { o[i] = diffColor; continue }
                        guard x < base.width && y < base.height else { continue }
                        let p = bp[y * base.width + x], a = p >> 24
                        func mix(_ c: UInt32) -> UInt32 { let c1 = (c * a + 255 * (255 - a) + 127) / 255; return (3 * c1 + 7 * 255 + 5) / 10 }
                        o[i] = 0xFF00_0000 | mix(p >> 16 & 255) << 16 | mix(p >> 8 & 255) << 8 | mix(p & 255)
                    }
                }
            }
        }
        return PngImage(width: cw, height: ch, argb: out)
    }
}
