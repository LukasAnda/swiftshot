import CoreGraphics
import ImageIO
import XCTest
@testable import swiftshot

/// Synthetic bezels and screenshots, drawn in the test: no network, no Apple images.
enum Fixture {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func temp(_ name: String = UUID().uuidString) -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftshot-frames-\(name)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A 200×300 "device": transparent outside, an opaque grey body with rounded corners, a
    /// see-through screen at (22, 22, 156, 256) with rounded (anti-aliased) corners and an
    /// opaque "island" near the top.
    static func bezel(width: Int = 200, height: Int = 300, inset: Int = 22) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.25, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: width - 20, height: height - 20), cornerWidth: 30, cornerHeight: 30, transform: nil))
        ctx.fillPath()
        ctx.setBlendMode(.clear)
        let screen = CGRect(x: inset, y: inset, width: width - 2 * inset, height: height - 2 * inset)
        ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: width / 2 - 20, y: height - inset - 20, width: 40, height: 10))   // island (CG y-up: near the top)
        return ctx.makeImage()!
    }

    /// Opaque noise, so any resampling or misplacement changes pixels.
    static func screenshot(width: Int, height: Int, seed: UInt32 = 1, flat: (UInt8, UInt8, UInt8)? = nil) -> CGImage {
        var px = [UInt8](repeating: 255, count: width * height * 4)
        var s = seed
        for i in 0..<(width * height) {
            for c in 0..<3 {
                if let flat { px[i * 4 + c] = [flat.0, flat.1, flat.2][c]; continue }
                s = s &* 1_664_525 &+ 1_013_904_223
                px[i * 4 + c] = UInt8(truncatingIfNeeded: s >> 24)
            }
        }
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return ctx.makeImage()!
    }

    static func write(_ image: CGImage, _ path: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// RGBA bytes (premultiplied, sRGB), top row first.
    static func pixels(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return px
    }

    static func alpha(_ image: CGImage) -> [UInt8] {
        let px = pixels(image)
        return (0..<(image.width * image.height)).map { px[$0 * 4 + 3] }
    }
}

final class OpeningTests: XCTestCase {
    func testFindsTheScreenOpening() throws {
        let image = Fixture.bezel()
        let found = try XCTUnwrap(Framer.opening(alpha: Fixture.alpha(image), width: 200, height: 300))
        XCTAssertEqual(found.rect, CGRect(x: 22, y: 22, width: 156, height: 256))
        let w = 156
        XCTAssertEqual(found.mask[128 * w + 78], 255, "centre of the screen")
        XCTAssertEqual(found.mask[0], 0, "outside the rounded corner")
        XCTAssertEqual(found.mask[15 * w + 78], 0, "the opaque island is the bezel's")   // island: rows 10…19 of the opening
        XCTAssertEqual(found.mask[5 * w + 78], 255, "between the island and the top edge")
    }

    /// The anti-aliased inner edge belongs to the opening: the screenshot goes under it.
    func testOpeningIncludesTheAntiAliasedEdge() throws {
        let image = Fixture.bezel()
        let alpha = Fixture.alpha(image)
        let found = try XCTUnwrap(Framer.opening(alpha: alpha, width: 200, height: 300))
        var partial = 0
        for y in 0..<256 {
            for x in 0..<156 {
                let a = alpha[(22 + y) * 200 + 22 + x]
                if a > 0 && a < 255 { partial += 1; XCTAssertEqual(found.mask[y * 156 + x], 255) }
                if a == 255 { XCTAssertEqual(found.mask[y * 156 + x], 0) }
            }
        }
        XCTAssertGreaterThan(partial, 0, "the fixture has anti-aliased corners")
    }

    func testNoOpening() {
        let opaque = [UInt8](repeating: 255, count: 100 * 100)
        XCTAssertNil(Framer.opening(alpha: opaque, width: 100, height: 100))
        let clear = [UInt8](repeating: 0, count: 100 * 100)
        XCTAssertNil(Framer.opening(alpha: clear, width: 100, height: 100), "reaches the border: the outside, not a screen")
    }

    /// An opaque centre (e.g. a camera) still finds the screen next to it.
    func testOpaqueCentre() throws {
        var alpha = Fixture.alpha(Fixture.bezel())
        for y in 140..<160 { for x in 90..<110 { alpha[y * 200 + x] = 255 } }
        XCTAssertEqual(try XCTUnwrap(Framer.opening(alpha: alpha, width: 200, height: 300)).rect, CGRect(x: 22, y: 22, width: 156, height: 256))
    }

    func testFits() {
        let o = CGSize(width: 1320, height: 2868)
        XCTAssertTrue(Framer.fits(width: 1320, height: 2868, opening: o))
        XCTAssertTrue(Framer.fits(width: 660, height: 1434, opening: o), "half size: scaled")
        XCTAssertFalse(Framer.fits(width: 1320, height: 400, opening: o), "sizeThatFits preview")
        XCTAssertFalse(Framer.fits(width: 1320, height: 6000, opening: o), "full-length capture")
        XCTAssertFalse(Framer.fits(width: 2868, height: 1320, opening: o), "landscape needs the landscape bezel")
        XCTAssertFalse(Framer.fits(width: 132, height: 287, opening: o), "far smaller")
    }
}

final class CompositingTests: XCTestCase {
    func testPlainFrameKeepsTheScreenshotExact() throws {
        let bezel = try Bezel(image: Fixture.bezel(), name: "fixture")
        let shot = Fixture.screenshot(width: 156, height: 256)
        let out = try XCTUnwrap(Framer.plain(shot, in: bezel))
        XCTAssertEqual(out.width, 200); XCTAssertEqual(out.height, 300)
        let o = Fixture.pixels(out), s = Fixture.pixels(shot), b = Fixture.pixels(bezel.image)
        var seeThrough = 0, exact = 0
        for y in 0..<300 {
            for x in 0..<200 {
                let i = (y * 200 + x) * 4
                if (22..<178).contains(x) && (22..<278).contains(y) && b[i + 3] == 0 {
                    // A see-through pixel of the screen: the screenshot's own value, byte for byte.
                    let j = ((y - 22) * 156 + x - 22) * 4
                    seeThrough += 1
                    if Array(o[i..<i + 3]) == Array(s[j..<j + 3]) && o[i + 3] == 255 { exact += 1 }
                }
                if b[i + 3] == 255 { XCTAssertEqual(Array(o[i..<i + 4]), Array(b[i..<i + 4]), "bezel pixel at \(x),\(y)") }
            }
        }
        XCTAssertGreaterThan(seeThrough, 30_000)
        XCTAssertEqual(exact, seeThrough)
        XCTAssertEqual(o[3], 0, "outside the device stays transparent")
    }

    /// No transparent seam where the screen meets the bezel: every pixel of the opening
    /// (anti-aliased edge included) is opaque in the output.
    func testNoHaloAtTheCorners() throws {
        let image = Fixture.bezel()
        let bezel = try Bezel(image: image, name: "fixture")
        let out = try XCTUnwrap(Framer.plain(Fixture.screenshot(width: 156, height: 256, flat: (255, 255, 255)), in: bezel))
        let found = try XCTUnwrap(Framer.opening(alpha: Fixture.alpha(image), width: 200, height: 300))
        let a = Fixture.alpha(out)
        for y in 0..<256 { for x in 0..<156 where found.mask[y * 156 + x] == 255 { XCTAssertEqual(a[(22 + y) * 200 + 22 + x], 255, "\(x),\(y)") } }
    }

    func testScalesAMatchingAspectRatio() throws {
        let bezel = try Bezel(image: Fixture.bezel(), name: "fixture")
        let out = try XCTUnwrap(Framer.plain(Fixture.screenshot(width: 312, height: 512, flat: (10, 200, 30)), in: bezel))
        let p = Fixture.pixels(out), i = (150 * 200 + 100) * 4
        XCTAssertEqual(Array(p[i..<i + 4]), [10, 200, 30, 255])
    }

    func testAppStoreImageIsOpaqueAndCanvasSized() throws {
        let bezel = try Bezel(image: Fixture.bezel(), name: "fixture")
        let device = try XCTUnwrap(Framer.plain(Fixture.screenshot(width: 156, height: 256), in: bezel))
        let style = Framer.StoreStyle(background: .color(Framer.color("#336699")!),
                                      title: .init(text: "Hello", color: Framer.color("#FFFFFF")!, font: Framer.font(nil, size: 40, bold: true, language: "en")),
                                      keyword: nil, padding: (20, 20))
        let image = try XCTUnwrap(Framer.appStore(device: device, canvas: (600, 1300), style: style))
        XCTAssertEqual(image.width, 600); XCTAssertEqual(image.height, 1300)
        XCTAssertTrue([.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo), "App Store Connect rejects alpha")
        let p = Fixture.pixels(image)
        XCTAssertEqual(Array(p[0..<3]), [0x33, 0x66, 0x99], "background")
    }

    func testTextNeverCoversTheDevice() {
        let font = Framer.font(nil, size: 120, bold: true, language: "en")
        let long = String(repeating: "Track every habit you care about ", count: 6)
        for below in [false, true] {
            for text in ["Short", long, "Supercalifragilisticexpialidocious"] {
                var style = Framer.StoreStyle(background: .color(Framer.color("#FFFFFF")!), title: .init(text: text, color: Framer.color("#000000")!, font: font),
                                              keyword: nil, padding: (60, 60))
                style.titleBelowImage = below
                let l = Framer.layout(canvas: CGSize(width: 1320, height: 2868), device: CGSize(width: 1470, height: 3000), style: style)
                let t = try! XCTUnwrap(l.text)
                XCTAssertFalse(t.intersects(l.device), "\(text.prefix(10)) below=\(below)")
                XCTAssertGreaterThanOrEqual(l.device.minY, 0); XCTAssertLessThanOrEqual(l.device.maxY, 2868)
                XCTAssertLessThanOrEqual(l.device.width, 1320 - 120 + 0.5)
                XCTAssertEqual(below, t.minY > l.device.maxY)
                XCTAssertLessThanOrEqual(t.width, 1320 - 120)
            }
        }
    }

    func testColors() {
        XCTAssertNotNil(Framer.color("#fff")); XCTAssertNotNil(Framer.color("#112233")); XCTAssertNotNil(Framer.color("#11223344"))
        XCTAssertNil(Framer.color("red")); XCTAssertNil(Framer.color("#12"))
        XCTAssertGreaterThan(Framer.luminance(.color(Framer.color("#F2F2F7")!)), 0.8)
        XCTAssertLessThan(Framer.luminance(.color(Framer.color("#1C1C1E")!)), 0.05)
    }
}

final class AppStoreSizeTests: XCTestCase {
    func testOwnSizeWhenAccepted() {
        XCTAssertTrue(AppStoreSizes.canvas(width: 1320, height: 2868, idiom: "phone") == (1320, 2868))   // 6.9"
        XCTAssertTrue(AppStoreSizes.canvas(width: 2868, height: 1320, idiom: "phone") == (2868, 1320))
        XCTAssertTrue(AppStoreSizes.canvas(width: 1206, height: 2622, idiom: "phone") == (1206, 2622))   // 6.3"
        XCTAssertTrue(AppStoreSizes.canvas(width: 2064, height: 2752, idiom: "pad") == (2064, 2752))     // 13"
        XCTAssertTrue(AppStoreSizes.canvas(width: 2752, height: 2064, idiom: "pad") == (2752, 2064))
        XCTAssertTrue(AppStoreSizes.canvas(width: 1488, height: 2266, idiom: "pad") == (1488, 2266))     // iPad mini
        XCTAssertTrue(AppStoreSizes.canvas(width: 1398, height: 2034, idiom: "phone") == (1398, 2034))   // iPhone Duo
    }

    func testOtherSizesGetTheClosestClass() {
        // Not an accepted size, 6.9"-like aspect: the largest 6.9" size.
        XCTAssertTrue(AppStoreSizes.canvas(width: 660, height: 1434, idiom: "phone") == (1320, 2868))
        // 3:4 iPad that isn't a listed size: 2064×2752 (the largest 3:4 one).
        XCTAssertTrue(AppStoreSizes.canvas(width: 1500, height: 2000, idiom: "pad") == (2064, 2752))
    }

    func testAccepts() {
        XCTAssertTrue(AppStoreSizes.accepts(width: 1170, height: 2532))
        XCTAssertTrue(AppStoreSizes.accepts(width: 2532, height: 1170))
        XCTAssertFalse(AppStoreSizes.accepts(width: 1470, height: 3000), "a plain frame")
        XCTAssertEqual(AppStoreSizes.idiom(of: "iPad Air 13-inch (M4)"), "pad")
        XCTAssertEqual(AppStoreSizes.idiom(of: "Apple Watch Ultra 3 (49mm)"), "watch")
        XCTAssertEqual(AppStoreSizes.idiom(of: "iPhone Duo"), "phone")
    }
}

final class BezelCatalogTests: XCTestCase {
    func testDeviceMapping() {
        XCTAssertEqual(BezelCatalog.model(for: "iPhone 17 Pro Max")?.pack, "Bezel-iPhone-17")
        XCTAssertEqual(BezelCatalog.model(for: "iPhone 17 Pro Max")?.model, "iPhone 17 Pro Max")
        XCTAssertEqual(BezelCatalog.model(for: "iphone air")?.pack, "Bezel-iPhone-17", "case-insensitive")
        XCTAssertEqual(BezelCatalog.model(for: "iPad Pro 13-inch (M4)")?.model, "iPad Pro (M5) 13\"", "same body as M5")
        XCTAssertEqual(BezelCatalog.model(for: "Apple Watch Series 10 (46mm)")?.model, "Apple Watch S11 - 46mm")
        XCTAssertEqual(BezelCatalog.model(for: "iPhone Duo")?.portrait, "Outer Closed Portrait")
        XCTAssertNil(BezelCatalog.model(for: "iPhone 16e"), "Apple ships no bezel for it")
        XCTAssertNil(BezelCatalog.model(for: "iPhone SE (3rd generation)"))
        XCTAssertNil(BezelCatalog.model(for: "Apple Watch SE 3 (44mm)"))
        for (device, model) in BezelCatalog.models {
            XCTAssertTrue(model.pack.hasPrefix("Bezel-"), device)
            XCTAssertFalse(model.defaultColor.isEmpty, device)
        }
    }

    func testEntriesFromApplesFileNames() {
        let files = [
            "PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png",
            "PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Landscape.png",
            "PNG/iPhone 17 Pro/iPhone 17 Pro - Silver - Portrait.png",
            "PNG/iPhone 17/iPhone 17 - Mist Blue - Portrait.png",
            "PNG/iPhone Duo - Night Sky - Outer Closed Portrait.png",
            "PNG/iPhone Duo - Night Sky - Inner Open Portrait.png",
            "PNG/iPhone Duo - Night Sky - Outer Open.png",
            "PNG/Ocean Band/AW Ultra 3 - Black + Ocean Band Black.png",
            "PNG/Sport Band/Apple Watch S11 - 46mm - Aluminum Jet Black + Sport Band Black.png",
            "PNG/Sport Band/Apple Watch S11 - 42mm - Aluminum Jet Black + Sport Band Black.png",
        ]
        let pm = BezelCatalog.entries(files, for: BezelCatalog.model(for: "iPhone 17 Pro Max")!)
        XCTAssertEqual(pm.map(\.orientation), ["Portrait", "Landscape"])
        XCTAssertEqual(Set(pm.map(\.color)), ["Deep Blue"])
        XCTAssertEqual(BezelCatalog.entries(files, for: BezelCatalog.model(for: "iPhone 17")!).map(\.color), ["Mist Blue"], "not the Pro's files")
        let duo = BezelCatalog.entries(files, for: BezelCatalog.model(for: "iPhone Duo")!)
        XCTAssertEqual(duo.map(\.path), ["PNG/iPhone Duo - Night Sky - Outer Closed Portrait.png"])
        let ultra = BezelCatalog.entries(files, for: BezelCatalog.model(for: "Apple Watch Ultra 3 (49mm)")!)
        XCTAssertEqual(ultra, [.init(model: "AW Ultra 3", color: "Black + Ocean Band Black", orientation: nil, path: "PNG/Ocean Band/AW Ultra 3 - Black + Ocean Band Black.png")])
        let s11 = BezelCatalog.entries(files, for: BezelCatalog.model(for: "Apple Watch Series 11 (46mm)")!)
        XCTAssertEqual(s11.map(\.color), ["Aluminum Jet Black + Sport Band Black"])
    }

    func testColorMatching() {
        let colors = ["Cosmic Orange", "Deep Blue", "Silver"]
        XCTAssertEqual(BezelCatalog.matchColor("deep blue", in: colors), "Deep Blue")
        XCTAssertEqual(BezelCatalog.matchColor("DEEP_BLUE", in: colors), "Deep Blue", "frameit's style")
        XCTAssertEqual(BezelCatalog.matchColor("orange", in: colors), "Cosmic Orange")
        XCTAssertNil(BezelCatalog.matchColor("Gold", in: colors))
        let watch = ["Natural + Alpine Loop Light Blue", "Black + Ocean Band Black", "Natural + Milanese Loop"]
        XCTAssertEqual(BezelCatalog.matchColor("Natural", in: watch), "Natural + Alpine Loop Light Blue", "first sorted")
        XCTAssertEqual(BezelCatalog.matchColor("Natural + Milanese Loop", in: watch), "Natural + Milanese Loop")
    }

    func testColorChoice() {
        let choices = ["Silver", "iPad Pro 13-inch (M5)=Space Black"]
        XCTAssertEqual(BezelCatalog.colorChoice(choices, device: "iPad Pro 13-inch (M5)"), "Space Black")
        XCTAssertEqual(BezelCatalog.colorChoice(choices, device: "iPhone 17 Pro Max"), "Silver")
        XCTAssertNil(BezelCatalog.colorChoice(["iPhone 17=Black"], device: "iPhone Air"))
    }

    func testDeviceFromFileName() {
        let known = ["iPad Pro 13-inch (M5)", "iPhone 17", "iPhone 17 Pro", "iPhone 17 Pro Max"]
        XCTAssertEqual(BezelCatalog.device(inFileName: "iPad Pro 13-inch (M5)-Stats landscape-dark", known: known), "iPad Pro 13-inch (M5)")
        XCTAssertEqual(BezelCatalog.device(inFileName: "iPhone 17 Pro Max-Welcome", known: known), "iPhone 17 Pro Max", "longest match")
        XCTAssertEqual(BezelCatalog.device(inFileName: "iPhone 17-Welcome", known: known), "iPhone 17")
        XCTAssertNil(BezelCatalog.device(inFileName: "Pixel 9-Welcome", known: known))
    }
}

final class FramefileTests: XCTestCase {
    let json = #"""
    {
      "device_frame_version": "latest",
      "default": {
        "keyword": { "color": "#545454" },
        "title": { "font": "fonts/Title.ttf", "color": "#123456", "font_size": 90 },
        "background": "background.jpg",
        "padding": 50,
        "show_complete_frame": false,
        "stack_title": false,
        "title_below_image": false
      },
      "data": [
        { "filter": "Welcome", "keyword": { "text": "Hello" }, "padding": "40x20" },
        { "filter": "iPad", "padding": "5%", "title": { "color": "#FFFFFF" } },
        { "filter": "de-DE", "background": "#000000", "use_platform": "IOS" }
      ]
    }
    """#

    func testFilterPrecedenceAndDeepMerge() throws {
        let file = try Framefile.parse(Data(json.utf8), path: "/project/fastlane/screenshots/Framefile.json")
        let plain = try file.style(for: "en-US/iPhone 17 Pro Max-Stats.png")
        XCTAssertEqual(plain.background, "/project/fastlane/screenshots/background.jpg", "relative to the Framefile")
        XCTAssertEqual(plain.title.font, "/project/fastlane/screenshots/fonts/Title.ttf")
        XCTAssertEqual(plain.padding?.h, .pixels(50))
        XCTAssertFalse(plain.showCompleteFrame)

        let welcome = try file.style(for: "en-US/iPhone 17 Pro Max-Welcome.png")
        XCTAssertEqual(welcome.keyword.text, "Hello")
        XCTAssertEqual(welcome.keyword.color, "#545454", "deep merge keeps the default's colour")
        XCTAssertEqual(welcome.padding?.h, .pixels(40)); XCTAssertEqual(welcome.padding?.v, .pixels(20))

        // Two filters match: both apply, the later one wins where they overlap.
        let both = try file.style(for: "de-DE/iPad Pro 13-inch (M5)-Welcome.png")
        XCTAssertEqual(both.padding?.h, .percent(5), "iPad comes after Welcome")
        XCTAssertEqual(both.title.color, "#FFFFFF")
        XCTAssertEqual(both.title.fontSize, 90)
        XCTAssertEqual(both.background, "#000000")
        XCTAssertEqual(both.keyword.text, "Hello")
        XCTAssertEqual(file.unsupportedKeys, ["use_platform"])
    }

    func testFiltersAreCaseSensitiveSubstrings() throws {
        let file = try Framefile.parse(Data(json.utf8), path: "/x/Framefile.json")
        XCTAssertNil(try file.style(for: "en-US/ipad-Welcome.png").title.color.flatMap { $0 == "#FFFFFF" ? $0 : nil }, "frameit: case-sensitive")
    }

    func testInvalidValues() {
        XCTAssertThrowsError(try Framefile.parse(Data("[1]".utf8), path: "F"))
        XCTAssertThrowsError(try Framefile.parse(Data(#"{"data": [{"title": {}}]}"#.utf8), path: "F"), "filter is required")
        let bad = [#"{"default": {"title": {"color": "red"}}}"#, #"{"default": {"padding": "lots"}}"#, #"{"default": {"stack_title": "yes"}}"#,
                   ##"{"default": {"background": "#12"}}"##]
        for text in bad {
            XCTAssertThrowsError(try Framefile.parse(Data(text.utf8), path: "F").style(for: "en-US/x.png"), text)
        }
    }

    func testLengths() {
        XCTAssertEqual(Length("10%")?.resolve(2000), 200)
        XCTAssertEqual(Length(30)?.resolve(2000), 30)
        XCTAssertEqual(Length("45")?.resolve(2000), 45)
        XCTAssertNil(Length("ten"))
    }

    func testPerLanguageFonts() throws {
        let text = #"{"default": {"title": {"fonts": [{"font": "ar.ttf", "supported": ["ar"]}, {"font": "other.ttf"}]}}}"#
        let style = try Framefile.parse(Data(text.utf8), path: "/f/Framefile.json").style(for: "ar/x.png")
        XCTAssertEqual(style.title.font(for: "ar"), "/f/ar.ttf")
        XCTAssertEqual(style.title.font(for: "de-DE"), "/f/other.ttf")
    }
}

final class StringsFileTests: XCTestCase {
    let text = """
    /* Titles */
    "Welcome" = "Build habits that stick";
    "Stats" = "See your progress";
    // a comment
    "Stats landscape" = "Your week \\"at a glance\\"";
    "Empty" = "";
    "Arabic" = "ابنِ عادات تدوم";
    """

    func check(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let table = try StringsFile.parse(data, path: "title.strings")
        XCTAssertEqual(table["Welcome"], "Build habits that stick", file: file, line: line)
        XCTAssertEqual(table["Stats landscape"], "Your week \"at a glance\"", file: file, line: line)
        XCTAssertEqual(table["Arabic"], "ابنِ عادات تدوم", file: file, line: line)
    }

    func testEncodings() throws {
        try check(Data(text.utf8))
        try check(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))
        try check(Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!)
        try check(Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!)
        try check(text.data(using: .utf16LittleEndian)!)   // no BOM
        try check(text.data(using: .utf16)!)               // Foundation's own (with BOM)
    }

    func testInvalidAndEmpty() {
        XCTAssertThrowsError(try StringsFile.parse(Data(#""a" = "b""#.utf8), path: "t.strings"), "missing semicolon")
        XCTAssertEqual(try StringsFile.parse(Data(), path: "t.strings"), [:])
        XCTAssertThrowsError(try StringsFile.parse(Data([0xFF, 0xFE, 0x00, 0xD8]), path: "t.strings"))
    }

    func testLookupPrefersTheLongestKey() throws {
        let table = try StringsFile.parse(Data(text.utf8), path: "t")
        XCTAssertEqual(StringsFile.lookup(table, fileName: "iPhone 17 Pro Max-Stats landscape-dark.png"), "Your week \"at a glance\"")
        XCTAssertEqual(StringsFile.lookup(table, fileName: "iPhone 17 Pro Max-Stats-dark.png"), "See your progress")
        XCTAssertEqual(StringsFile.lookup(table, fileName: "iPad-welcome.png"), "Build habits that stick", "case-insensitive")
        XCTAssertNil(StringsFile.lookup(table, fileName: "iPad-Empty.png"), "empty values don't count")
        XCTAssertNil(StringsFile.lookup(table, fileName: "iPad-Settings.png"))
    }
}

final class FrameRunTests: XCTestCase {
    /// A fake installed pack: the fixture bezel under Apple's file name for the 17 Pro Max.
    func pack(in dir: String) -> [String: BezelStore.Pack] {
        let files = ["PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png", "PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Silver - Portrait.png"]
        for f in files { Fixture.write(Fixture.bezel(), (dir as NSString).appendingPathComponent(f)) }
        return ["Bezel-iPhone-17": BezelStore.Pack(dir: dir, files: files)]
    }

    func request(_ root: String, _ file: String, device: String, mode: FrameMode, lang: String = "en-US") -> FrameRequest {
        FrameRequest(path: "\(root)/\(lang)/\(file)", relative: "\(lang)/\(file)", device: device, language: lang, appearance: "light", mode: mode)
    }

    func testPlainFramesAndMissingBezels() async throws {
        let root = Fixture.temp() + "/screenshots"
        Fixture.write(Fixture.screenshot(width: 156, height: 256), "\(root)/en-US/iPhone 17 Pro Max-Welcome.png")
        Fixture.write(Fixture.screenshot(width: 156, height: 60), "\(root)/en-US/iPhone 17 Pro Max-Row.png")
        Fixture.write(Fixture.screenshot(width: 156, height: 256), "\(root)/en-US/iPhone 16e-Welcome.png")
        let settings = FrameSettings(root: root, plainOutput: FrameSettings.defaultPlainOutput(for: root))
        let run = FrameRun(settings)
        let summary = try await run.run([
            request(root, "iPhone 17 Pro Max-Welcome.png", device: "iPhone 17 Pro Max", mode: .plain),
            request(root, "iPhone 17 Pro Max-Row.png", device: "iPhone 17 Pro Max", mode: .plain),
            request(root, "iPhone 16e-Welcome.png", device: "iPhone 16e", mode: .plain),
        ], packs: pack(in: Fixture.temp()))
        XCTAssertEqual(summary.plain, 1)
        XCTAssertEqual(summary.partial, 1)
        XCTAssertEqual(summary.missing, ["iPhone 16e"])
        XCTAssertTrue(summary.errors.isEmpty, "\(summary.errors)")
        let out = root + "-framed/en-US/iPhone 17 Pro Max-Welcome_framed.png"
        XCTAssertEqual(summary.framed["\(root)/en-US/iPhone 17 Pro Max-Welcome.png"], out)
        let image = try Framer.load(out)
        XCTAssertEqual(image.width, 200); XCTAssertEqual(image.height, 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/en-US/iPhone 17 Pro Max-Welcome_framed.png"), "plain frames stay out of deliver's folders")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "-framed/en-US/iPhone 16e-Welcome_framed.png"))
    }

    /// deliver uploads only *_framed.png from a folder that has any: a screenshot without a
    /// bezel (App Store size) gets a copy, so it isn't dropped. Watches stay as they are.
    func testAppStoreModeKeepsUnframedScreenshotsUploadable() async throws {
        let root = Fixture.temp() + "/screenshots"
        Fixture.write(Fixture.screenshot(width: 156, height: 256), "\(root)/en-US/iPhone 17 Pro Max-Welcome.png")
        Fixture.write(Fixture.screenshot(width: 1170, height: 2532, flat: (40, 40, 40)), "\(root)/en-US/iPhone 16e-Welcome.png")
        Fixture.write(Fixture.screenshot(width: 422, height: 514, flat: (0, 0, 0)), "\(root)/en-US/Apple Watch Ultra 3 (49mm)-List.png")
        try #""Welcome" = "Hello";"#.write(toFile: "\(root)/en-US/title.strings", atomically: true, encoding: .utf8)
        let run = FrameRun(FrameSettings(root: root, plainOutput: root + "-framed"))
        let summary = try await run.run([
            request(root, "iPhone 17 Pro Max-Welcome.png", device: "iPhone 17 Pro Max", mode: .appstore),
            request(root, "iPhone 16e-Welcome.png", device: "iPhone 16e", mode: .appstore),
            request(root, "Apple Watch Ultra 3 (49mm)-List.png", device: "Apple Watch Ultra 3 (49mm)", mode: .appstore),
        ], packs: pack(in: Fixture.temp()))
        XCTAssertEqual(summary.appStore, 1); XCTAssertEqual(summary.copies, 1); XCTAssertEqual(summary.watches, 1)
        XCTAssertTrue(summary.errors.isEmpty, "\(summary.errors)")
        let framed = try Framer.load(root + "/en-US/iPhone 17 Pro Max-Welcome_framed.png")
        // 156×256 isn't an App Store size: the accepted size of the closest aspect ratio (5.5").
        XCTAssertEqual(framed.width, 1242); XCTAssertEqual(framed.height, 2208)
        XCTAssertEqual(FileManager.default.contents(atPath: root + "/en-US/iPhone 16e-Welcome_framed.png"),
                       FileManager.default.contents(atPath: root + "/en-US/iPhone 16e-Welcome.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/en-US/Apple Watch Ultra 3 (49mm)-List_framed.png"))
    }

    func testColorChoiceAndFallback() async throws {
        let root = Fixture.temp() + "/screenshots"
        Fixture.write(Fixture.screenshot(width: 156, height: 256), "\(root)/en-US/iPhone 17 Pro Max-A.png")
        var settings = FrameSettings(root: root, plainOutput: root + "-framed")
        settings.colors = ["Gold"]     // not a 17 Pro Max colour: warns, uses the default
        let summary = try await FrameRun(settings).run([request(root, "iPhone 17 Pro Max-A.png", device: "iPhone 17 Pro Max", mode: .plain)], packs: pack(in: Fixture.temp()))
        XCTAssertEqual(summary.plain, 1)
    }

    /// A frame from an earlier run that this run doesn't make again is removed (deliver would
    /// upload it); a newer one is someone's current work and stays.
    func testStaleFramesAreRemoved() async throws {
        let root = Fixture.temp() + "/screenshots"
        let shot = "\(root)/en-US/iPhone 17 Pro Max-A.png", old = "\(root)/en-US/iPhone 17 Pro Max-A_framed.png"
        Fixture.write(Fixture.screenshot(width: 156, height: 256), old)
        Fixture.write(Fixture.screenshot(width: 156, height: 256), shot)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old)
        let run = FrameRun(FrameSettings(root: root, plainOutput: root + "-framed"))
        _ = try await run.run([request(root, "iPhone 17 Pro Max-A.png", device: "iPhone 17 Pro Max", mode: .none)], packs: [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
        Fixture.write(Fixture.screenshot(width: 156, height: 256), old)   // newer than the screenshot
        _ = try await run.run([request(root, "iPhone 17 Pro Max-A.png", device: "iPhone 17 Pro Max", mode: .none)], packs: [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: old))
    }

    func testRequestsFromAFolder() throws {
        let root = Fixture.temp() + "/shots"
        for f in ["en-US/iPad Pro 13-inch (M5)-Stats landscape-dark.png", "en-US/iPhone 17 Pro Max-Welcome.png", "en-US/iPhone 17 Pro Max-Welcome_framed.png", "de-DE/iPhone 17-Debug.png"] {
            Fixture.write(Fixture.screenshot(width: 4, height: 4), "\(root)/\(f)")
        }
        var options = Options()
        options.frame = .appstore
        options.screens = [try parseScreenRule("Debug: frame=none")]
        let known = Array(BezelCatalog.models.keys)
        let requests = try FrameRun.requests(in: root, options: options, knownDevices: known)
        XCTAssertEqual(requests.map(\.relative), ["de-DE/iPhone 17-Debug.png", "en-US/iPad Pro 13-inch (M5)-Stats landscape-dark.png", "en-US/iPhone 17 Pro Max-Welcome.png"],
                       "frames themselves are not inputs")
        XCTAssertEqual(requests.map(\.device), ["iPhone 17", "iPad Pro 13-inch (M5)", "iPhone 17 Pro Max"])
        XCTAssertEqual(requests.map(\.appearance), ["light", "dark", "light"])
        XCTAssertEqual(requests.map(\.mode), [.none, .appstore, .appstore])
    }

    func testRelativePath() {
        XCTAssertEqual(relativePath("/a/screenshots-framed/en-US/x.png", from: URL(fileURLWithPath: "/a/screenshots")), "../screenshots-framed/en-US/x.png")
        XCTAssertEqual(relativePath("/a/screenshots/en-US/x.png", from: URL(fileURLWithPath: "/a/screenshots")), "en-US/x.png")
    }
}

final class BezelStoreTests: XCTestCase {
    override func setUp() { BezelStore.base = Fixture.temp() }

    func testLicenseMustBeAccepted() throws {
        XCTAssertThrowsError(try BezelStore.ensureLicense(accept: false, interactive: false)) { error in
            XCTAssertTrue("\(error)".contains("--accept-bezel-license"))
        }
        XCTAssertFalse(BezelStore.licenseAccepted)
        try BezelStore.ensureLicense(accept: true, interactive: false)
        XCTAssertTrue(BezelStore.licenseAccepted)
        XCTAssertNoThrow(try BezelStore.ensureLicense(accept: false, interactive: false), "asked once")
    }

    func testInstalledPackIsVerified() throws {
        let dir = (BezelStore.root as NSString).appendingPathComponent("Bezel-Test")
        try FileManager.default.createDirectory(atPath: dir + "/PNG", withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: dir + "/PNG/a.png"))
        let manifest = BezelStore.Manifest(pack: "Bezel-Test", url: "u", etag: nil, files: [.init(path: "PNG/a.png", size: 3, sha256: "")])
        try JSONEncoder().encode(manifest).write(to: URL(fileURLWithPath: dir + "/manifest.json"))
        XCTAssertEqual(BezelStore.installed("Bezel-Test")?.files, ["PNG/a.png"])
        try Data([1, 2]).write(to: URL(fileURLWithPath: dir + "/PNG/a.png"))
        XCTAssertNil(BezelStore.installed("Bezel-Test"), "a truncated file means: download again")
        XCTAssertNil(BezelStore.installed("Bezel-Missing"))
    }

    func testPacksNeeded() {
        XCTAssertEqual(FrameRun.packs(devices: ["iPhone 17 Pro Max", "iPhone Air", "iPhone 16e"], modes: [.plain]), ["Bezel-iPhone-17"])
        XCTAssertEqual(FrameRun.packs(devices: ["Apple Watch Ultra 3 (49mm)"], modes: [.appstore]), [], "watches stay bare in App Store mode")
        XCTAssertEqual(FrameRun.packs(devices: ["Apple Watch Ultra 3 (49mm)"], modes: [.plain]), ["Bezel-Apple-Watch-Ultra-3-2025"])
        XCTAssertEqual(BezelCatalog.url("Bezel-iPad-Pro-(M5)").absoluteString, "https://devimages-cdn.apple.com/design/resources/download/Bezel-iPad-Pro-(M5).dmg")
    }
}
