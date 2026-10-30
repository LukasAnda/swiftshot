import XCTest
import zlib
@testable import swiftshot

/// The comparison against the shared fixtures in Shared/testdata/baseline (docs/wiki/Baseline-format.md):
/// statuses, boxes and sizes from each case's expected/result.json, diff images from expected/images/diff.
final class CompareTests: XCTestCase {
    var tmp: URL!
    override func setUp() { tmp = temporaryDirectory("swiftshot-compare") }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    struct Shot { var `case`: String; var id: String; var tolerance = Tolerance(); var ignore: [[Double]] = []; var scale = 2.625 }

    let shots: [Shot] = [
        Shot(case: "unchanged", id: "en-US/iPhone 17 Pro-Home-light", scale: 3),
        Shot(case: "changed-pixels", id: "en-US/Pixel 9-Home"),
        Shot(case: "changed-pixels", id: "en-US/Pixel 9-Settings"),
        Shot(case: "changed-size", id: "en-US/Pixel 9-Profile", scale: 3),
        Shot(case: "same-pixels-different-bytes", id: "en-US/iPhone 17 Pro-Home", scale: 3),
        Shot(case: "png-decoding", id: "en-US/iPhone 17 Pro-Rgb Filters", scale: 3),
        Shot(case: "png-decoding", id: "en-US/iPhone 17 Pro-Rgb Changed", scale: 3),
        Shot(case: "tolerance", id: "en-US/Pixel 9-Home", tolerance: Tolerance(pixels: 5, maxChannelDelta: 1)),
        Shot(case: "tolerance", id: "en-US/Pixel 9-Settings", tolerance: Tolerance(pixels: 5, maxChannelDelta: 1)),
        Shot(case: "tolerance", id: "en-US/Pixel 9-Clock", tolerance: Tolerance(maxChannelDelta: 2)),
        Shot(case: "tolerance", id: "en-US/Pixel 9-Clock Large", tolerance: Tolerance(maxChannelDelta: 2)),
        Shot(case: "ignore-region", id: "en-US/Pixel 9-Feed-light", ignore: [[0, 0, 16, 4], [3.2, 20, 2, 2]]),
        Shot(case: "ignore-region", id: "en-US/Pixel 9-Feed-dark", ignore: [[0, 0, 16, 4], [3.2, 20, 2, 2]]),
        Shot(case: "split-run-android", id: "en-US/Pixel 9-Settings"),
        Shot(case: "device-mode", id: "en-US/iPhone 17 Pro-Glass", tolerance: Tolerance(maxChannelDelta: 1), scale: 3),
        Shot(case: "device-mode", id: "en-US/iPhone 17 Pro-Blur", tolerance: Tolerance(maxChannelDelta: 1), scale: 3),
    ]

    func entry(_ c: String, _ id: String) throws -> JSON {
        let result = try readJSON(fixtures.appendingPathComponent("\(c)/expected/result.json"))
        return result["screenshots"]!.array!.first { $0["id"]?.string == id }!
    }

    func compare(_ s: Shot) throws -> Diff {
        try Compare.images(baseline: fixtures.appendingPathComponent("\(s.case)/baseline/\(s.id).png"),
                           new: fixtures.appendingPathComponent("\(s.case)/output/\(s.id).png"),
                           tolerance: s.tolerance, ignore: s.ignore.map { Compare.ignoreRegion($0, scale: s.scale) })
    }

    func regions(_ e: JSON) -> [Region] {
        (e["boxes"]?.array ?? []).map { b in let v = b.array!.map { Int($0.number!) }; return Region(x: v[0], y: v[1], width: v[2], height: v[3]) }
    }

    func testEveryFixtureShotMatchesResultJson() throws {
        for s in shots {
            let e = try entry(s.case, s.id)
            let d = try compare(s)
            let what = "\(s.case) \(s.id)"
            XCTAssertEqual(e["status"]?.string, d.status, what)
            XCTAssertEqual(e["reason"]?.string, d.reason, what)
            XCTAssertEqual(e["pixels"].map { Int($0.number!) } ?? 0, d.pixels, what)
            XCTAssertEqual(regions(e), d.boxes, what)
            XCTAssertEqual(e["baselineSize"]?.array?.map { Int($0.number!) }, d.baselineSize, what)
            XCTAssertEqual(e["newSize"]?.array?.map { Int($0.number!) }, d.newSize, what)
            XCTAssertEqual(d.status == "changed", d.diffImage != nil, what)
        }
    }

    func bytesEqual(_ c: String, _ id: String) -> Bool {
        let b = fixtures.appendingPathComponent("\(c)/baseline/\(id).png"), n = fixtures.appendingPathComponent("\(c)/output/\(id).png")
        let fm = FileManager.default
        return fm.fileExists(atPath: b.path) && fm.fileExists(atPath: n.path) && bytes(b) == bytes(n)
    }

    /// Every changed or compared id in every fixture is in `shots`, so no expected image goes unchecked.
    func testShotsCoverEveryComparedFixtureId() throws {
        var compared = Set<String>()
        for c in fixtureCases() {
            for e in try readJSON(c.appendingPathComponent("expected/result.json"))["screenshots"]!.array! {
                let id = e["id"]!.string!, status = e["status"]!.string!
                if status == "changed" || (status == "unchanged" && !bytesEqual(c.lastPathComponent, id)) { compared.insert(c.lastPathComponent + "|" + id) }
            }
        }
        XCTAssertEqual(compared, Set(shots.filter { !bytesEqual($0.case, $0.id) }.map { $0.case + "|" + $0.id }))
    }

    /// The diff image and the baseline/new copies of every listed id equal expected/images byte for byte.
    func testReportImagesMatchFixtures() throws {
        var expected = Set<String>()
        for c in fixtureCases() {
            for e in try readJSON(c.appendingPathComponent("expected/result.json"))["screenshots"]!.array! {
                let id = e["id"]!.string!
                var images: [String: [UInt8]] = [:]
                if let p = e["baseline"]?.string { images[p] = bytes(c.appendingPathComponent("baseline/\(id).png")) }
                if let p = e["new"]?.string { images[p] = bytes(c.appendingPathComponent("output/\(id).png")) }
                if let p = e["diff"]?.string {
                    let shot = shots.first { $0.case == c.lastPathComponent && $0.id == id }!
                    images[p] = Png.encode(try compare(shot).diffImage!)
                }
                for (path, data) in images {
                    let file = c.appendingPathComponent("expected/\(path)")
                    expected.insert(file.path)
                    XCTAssertEqual(bytes(file), data, "\(c.lastPathComponent) \(path)")
                }
            }
        }
        var present = Set<String>()
        for c in fixtureCases() { for (_, f) in files(c.appendingPathComponent("expected/images")) { present.insert(f.path) } }
        XCTAssertEqual(expected, present, "expected/images holds exactly the report's images")
    }

    func testChangedPixelsDiffImage() throws {
        let d = try compare(shots.first { $0.case == "changed-pixels" && $0.id == "en-US/Pixel 9-Home" }!)
        let img = d.diffImage!
        XCTAssertEqual(img.width, 40); XCTAssertEqual(img.height, 80)
        XCTAssertEqual(img.argb[5 * 40 + 5], 0xFFFF_2D55)
        XCTAssertEqual(img.argb[40 * 40 + 20], 0xFFFF_2D55)
        let base = try Png.decode(bytes(fixtures.appendingPathComponent("changed-pixels/baseline/en-US/Pixel 9-Home.png")))
        let c = base.argb[0]
        func mix(_ v: UInt32) -> UInt32 { (3 * v + 7 * 255 + 5) / 10 }
        XCTAssertEqual(0xFF00_0000 | (mix(c >> 16 & 255) << 16) | (mix(c >> 8 & 255) << 8) | mix(c & 255), img.argb[0])
    }

    func testChangedSizeUsesLargerCanvas() throws {
        let d = try compare(shots.first { $0.case == "changed-size" }!)
        XCTAssertEqual(d.reason, "size")
        XCTAssertEqual(d.baselineSize, [40, 80]); XCTAssertEqual(d.newSize, [40, 96])
        XCTAssertEqual(d.diffImage!.height, 96)
        XCTAssertEqual(d.diffImage!.argb[95 * 40], 0xFFFF_2D55)
    }

    func testSizeChangeIsChangedWhateverTheTolerance() throws {
        var s = shots.first { $0.case == "changed-size" }!
        s.tolerance = Tolerance(pixels: 100_000, maxChannelDelta: 255)
        XCTAssertEqual(try compare(s).reason, "size")
    }

    func testIdenticalBytesAreNeverDecoded() throws {
        let a = tmp.appendingPathComponent("a.png"), b = tmp.appendingPathComponent("b.png")
        try Data([1, 2, 3]).write(to: a); try Data([1, 2, 3]).write(to: b)
        XCTAssertEqual(try Compare.images(baseline: a, new: b, tolerance: Tolerance(), ignore: []), Diff(status: "unchanged", reason: nil, pixels: 0, boxes: [], diffImage: nil))
    }

    func testIgnoreRegionScalesFloorAndCeil() {
        XCTAssertEqual(Compare.ignoreRegion([0, 0, 16, 4], scale: 2.625), Region(x: 0, y: 0, width: 42, height: 11))
        XCTAssertEqual(Compare.ignoreRegion([3.2, 20, 2, 2], scale: 2.625), Region(x: 8, y: 52, width: 6, height: 6))
        XCTAssertEqual(Compare.ignoreRegion([0.5, 0.5, 1, 1], scale: 3), Region(x: 1, y: 1, width: 4, height: 4))
    }

    func testUnsupportedFixturePngs() throws {
        let dir = fixtures.appendingPathComponent("comparison-errors")
        for name in ["Sixteen Bit", "Corrupt"] {
            XCTAssertThrowsError(try Compare.images(baseline: dir.appendingPathComponent("baseline/en-US/Pixel 9-\(name).png"),
                                                    new: dir.appendingPathComponent("output/en-US/Pixel 9-\(name).png"), tolerance: Tolerance(), ignore: []), name) {
                XCTAssertTrue($0 is UnsupportedPNG, name)
            }
        }
        let palette = "en-US/Pixel 9-Palette Same.png"
        XCTAssertEqual(try Compare.images(baseline: dir.appendingPathComponent("baseline/\(palette)"), new: dir.appendingPathComponent("output/\(palette)"),
                                          tolerance: Tolerance(), ignore: []).status, "unchanged")
        XCTAssertThrowsError(try Png.decode(bytes(dir.appendingPathComponent("baseline/\(palette)"))))
    }

    // MARK: strict decoding, on hand-built PNGs (2x1 RGBA)

    let pixels: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80]
    func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
    func ihdr(w: UInt32 = 2, h: UInt32 = 1, depth: UInt8 = 8, type: UInt8 = 6, interlace: UInt8 = 0) -> [UInt8] { be(w) + be(h) + [depth, type, 0, 0, interlace] }
    func raw(filter: UInt8 = 0) -> [UInt8] { [filter] + pixels }
    func z(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 1024); var n = uLong(out.count)
        _ = compress2(&out, &n, data, uLong(data.count), 6)
        return Array(out[0..<Int(n)])
    }
    func chunk(_ type: String, _ body: [UInt8], badCrc: Bool = false) -> [UInt8] {
        let t = Array(type.utf8)
        let crc = UInt32(crc32(crc32(0, t, uInt(t.count)), body, uInt(body.count))) ^ (badCrc ? 1 : 0)
        return be(UInt32(body.count)) + t + body + be(crc)
    }
    let sig: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    func png(_ chunks: [UInt8]...) -> [UInt8] { chunks.reduce(sig, +) }
    var iend: [UInt8] { chunk("IEND", []) }

    func testDecodesValidAndTolerated() throws {
        let ok = png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw())), iend)
        XCTAssertEqual(try Png.decode(ok).argb, [0x280A_141E, 0x5032_3C46])
        _ = try Png.decode(png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw()))))
        _ = try Png.decode(ok + [1, 2, 3])
        _ = try Png.decode(png(chunk("IHDR", ihdr()), chunk("tEXt", [97, 0, 98]), chunk("IDAT", z(raw())), iend))
        let rgb = png(chunk("IHDR", ihdr(type: 2)), chunk("IDAT", z([0, 1, 2, 3, 4, 5, 6])), iend)
        XCTAssertEqual(try Png.decode(rgb).argb, [0xFF01_0203, 0xFF04_0506])
    }

    func testRejectsMalformed() {
        var badSig = png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw())), iend); badSig[1] = 0
        var badZ = z(raw()); badZ[badZ.count - 1] &+= 1
        let truncated = png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw())))
        let cases: [(String, [UInt8])] = [
            ("bad signature", badSig),
            ("crc", png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw()), badCrc: true), iend)),
            ("IHDR not first", png(chunk("tEXt", [65, 0, 66]), chunk("IHDR", ihdr()), chunk("IDAT", z(raw())), iend)),
            ("no IHDR", png(iend)),
            ("two IHDR", png(chunk("IHDR", ihdr()), chunk("IHDR", ihdr()), chunk("IDAT", z(raw())), iend)),
            ("IHDR length", png(chunk("IHDR", ihdr() + [0]), chunk("IDAT", z(raw())), iend)),
            ("truncated chunk", Array(truncated.dropLast(2))),
            ("trailing partial chunk", truncated + [0, 0, 0]),
            ("zlib", png(chunk("IHDR", ihdr()), chunk("IDAT", badZ), iend)),
            ("truncated zlib", png(chunk("IHDR", ihdr()), chunk("IDAT", Array(z(raw()).dropLast(4))), iend)),
            ("no IDAT", png(chunk("IHDR", ihdr()), iend)),
            ("short data", png(chunk("IHDR", ihdr(h: 2)), chunk("IDAT", z(raw())), iend)),
            ("long data", png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw() + [0])), iend)),
            ("filter 5", png(chunk("IHDR", ihdr()), chunk("IDAT", z(raw(filter: 5))), iend)),
            ("16-bit", png(chunk("IHDR", ihdr(depth: 16)), chunk("IDAT", z(raw() + pixels)), iend)),
            ("palette", png(chunk("IHDR", ihdr(type: 3)), chunk("PLTE", [1, 2, 3]), chunk("IDAT", z([0, 0, 0])), iend)),
            ("grey alpha", png(chunk("IHDR", ihdr(type: 4)), chunk("IDAT", z([0, 1, 2, 3, 4])), iend)),
            ("interlace", png(chunk("IHDR", ihdr(interlace: 1)), chunk("IDAT", z(raw())), iend)),
            ("huge", png(chunk("IHDR", ihdr(w: 0xFFFF_FFFF, h: 0xFFFF_FFFF)), chunk("IDAT", z([0, 0, 0])), iend)),
            ("huge negative", png(chunk("IHDR", ihdr(w: 0xC000_0000, h: 0xFFFF_FFFF)), chunk("IDAT", z(raw())), iend)),
            ("huge width", png(chunk("IHDR", ihdr(w: 0xFFFF_FFFF, h: 1)), chunk("IDAT", z(raw())), iend)),
            ("huge height", png(chunk("IHDR", ihdr(w: 1, h: 0x7FFF_FFFF)), chunk("IDAT", z(raw())), iend)),
            ("huge RGB", png(chunk("IHDR", ihdr(w: 0x7FFF_FFFF, h: 0x7FFF_FFFF, type: 2)), chunk("IDAT", z(raw())), iend)),
        ]
        for (name, data) in cases {
            XCTAssertThrowsError(try Png.decode(data), name) { XCTAssertTrue($0 is UnsupportedPNG, name) }
        }
    }

    func testEncodingIsCanonical() throws {
        let file = fixtures.appendingPathComponent("changed-pixels/baseline/en-US/Pixel 9-Home.png")
        // make.py's encode() wrote that baseline: re-encoding the decoded pixels reproduces it byte for byte.
        XCTAssertEqual(Png.encode(try Png.decode(bytes(file))), bytes(file))
    }

    func testBoxesMergeOnlyWhenCloserThan16() throws {
        func boxesFor(_ xs: [Int]) throws -> [Region] {
            let w = 60
            let base = [UInt32](repeating: 0xFF00_0000, count: w)
            var new = base; for x in xs { new[x] = 0xFFFF_FFFF }
            let a = tmp.appendingPathComponent("a.png"), b = tmp.appendingPathComponent("b.png")
            try Data(Png.encode(PngImage(width: w, height: 1, argb: base))).write(to: a)
            try Data(Png.encode(PngImage(width: w, height: 1, argb: new))).write(to: b)
            return try Compare.images(baseline: a, new: b, tolerance: Tolerance(), ignore: []).boxes
        }
        XCTAssertEqual(try boxesFor([0, 16]), [Region(x: 0, y: 0, width: 17, height: 1)])
        XCTAssertEqual(try boxesFor([0, 17]), [Region(x: 0, y: 0, width: 1, height: 1), Region(x: 17, y: 0, width: 1, height: 1)])
        XCTAssertEqual(try boxesFor([0, 15, 30]), [Region(x: 0, y: 0, width: 31, height: 1)])
    }

    // MARK: boxes: the fast merge must equal the plain one (8-connected components, pairwise union until stable)

    func naiveBoxes(_ mask: [Bool], _ w: Int, _ h: Int) -> [Region] {
        var seen = [Bool](repeating: false, count: mask.count)
        var comps: [[Int]] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var stack = [start]; seen[start] = true
            var box = [Int.max, Int.max, Int.min, Int.min]
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                box = [min(box[0], x), min(box[1], y), max(box[2], x + 1), max(box[3], y + 1)]
                for dy in -1...1 { for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0 && nx < w && ny >= 0 && ny < h && mask[ny * w + nx] && !seen[ny * w + nx] { seen[ny * w + nx] = true; stack.append(ny * w + nx) }
                } }
            }
            comps.append(box)
        }
        func gap(_ a: [Int], _ b: [Int]) -> Int { max(0, b[0] - a[2], a[0] - b[2], b[1] - a[3], a[1] - b[3]) }
        while true {
            var pair: (Int, Int)?
            outer: for i in comps.indices { for j in (i + 1)..<max(i + 1, comps.count) where gap(comps[i], comps[j]) < 16 { pair = (i, j); break outer } }
            guard let (i, j) = pair else { break }
            let a = comps[i], b = comps[j]
            comps[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
            comps.remove(at: j)
        }
        return comps.map { Region(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }
            .sorted { ($0.y, $0.x, $0.width, $0.height) < ($1.y, $1.x, $1.width, $1.height) }
    }

    func testFastBoxesEqualPlainOnes() {
        var rng = SplitMix(seed: 7)
        for n in 0..<400 {
            let w = 1 + rng.int(120), h = 1 + rng.int(120)
            var mask = [Bool](repeating: false, count: w * h)
            switch n % 4 {
            case 0: let p = rng.double() * 0.02; for i in mask.indices { mask[i] = rng.double() < p }
            case 1:
                for _ in 0..<(1 + rng.int(12)) {
                    let x0 = rng.int(w), y0 = rng.int(h), x1 = min(w, x0 + 1 + rng.int(30)), y1 = min(h, y0 + 1 + rng.int(30))
                    for y in y0..<y1 { for x in x0..<x1 where rng.int(3) > 0 { mask[y * w + x] = true } }
                }
            case 2: let step = 14 + rng.int(5); for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) { mask[y * w + x] = true } }
            default: let p = rng.double() * 0.3; for i in mask.indices { mask[i] = rng.double() < p }
            }
            XCTAssertEqual(naiveBoxes(mask, w, h), Compare.boxes(mask, w, h), "case \(n) \(w)x\(h)")
        }
    }

    func testManyScatteredChangesStayCheap() {
        let w = 1320, h = 2868
        func grid(_ step: Int) -> [Bool] {
            var m = [Bool](repeating: false, count: w * h)
            for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) { m[y * w + x] = true } }
            return m
        }
        let dense = Compare.boxesCounted(grid(2), w, h)
        XCTAssertEqual(dense.boxes, [Region(x: 0, y: 0, width: 1319, height: 2867)])
        XCTAssertLessThan(dense.work, 2_000_000)
        XCTAssertEqual(Compare.boxes(grid(16), w, h).count, 1)
        let sparse = Compare.boxesCounted(grid(17), w, h)
        XCTAssertEqual(sparse.boxes.count, 78 * 169)
        XCTAssertLessThan(sparse.work, 2_000_000)
    }
}

/// A small deterministic random generator for the box tests.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
