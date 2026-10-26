// Puts screenshots into device bezels (CoreGraphics, CoreText, ImageIO).
//
// The screen opening of a bezel is found from its alpha channel: every pixel that is not fully
// opaque and connected to the image's centre. That region includes the anti-aliased inner edge,
// so the screenshot is drawn under all of it (clipped to the region, not to a rectangle) and the
// bezel on top blends its edge pixels over the screen: no transparent seam at the rounded
// corners, and an opaque Dynamic Island or camera stays the bezel's. Inside the opening the
// output pixels are the screenshot's own, byte for byte.

import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum FrameError: Error, CustomStringConvertible {
    case unreadable(String)
    case noOpening(String)
    var description: String {
        switch self {
        case .unreadable(let path): return "\(path): not a readable image"
        case .noOpening(let path): return "\(path): no screen opening found (not a device bezel?)"
        }
    }
}

/// A decoded bezel and its screen opening.
final class Bezel {
    let image: CGImage
    /// Pixel rectangle of the opening, top-left origin.
    let opening: CGRect
    /// DeviceGray, opening-sized: 255 where the screen shows through.
    let mask: CGImage
    var size: CGSize { CGSize(width: image.width, height: image.height) }

    init(image: CGImage, opening: CGRect, mask: CGImage) { self.image = image; self.opening = opening; self.mask = mask }

    convenience init(path: String) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FrameError.unreadable(path) }
        try self.init(image: image, name: path)
    }

    convenience init(image source: CGImage, name: String) throws {
        let (w, h) = (source.width, source.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: Framer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FrameError.unreadable(name) }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = ctx.makeImage() else { throw FrameError.unreadable(name) }
        var alpha = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { alpha[i] = pixels[i * 4 + 3] }
        guard let found = Framer.opening(alpha: alpha, width: w, height: h),
              let mask = Framer.grayImage(found.mask, width: Int(found.rect.width), height: Int(found.rect.height)) else { throw FrameError.noOpening(name) }
        self.init(image: image, opening: found.rect, mask: mask)
    }
}

enum Framer {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated(unsafe) private static var missingFonts = Set<String>()
    private static let missingFontsLock = NSLock()

    // MARK: Opening

    /// The see-through region connected to the centre (or, if the centre is opaque, to the
    /// nearest see-through pixel on the centre row): its bounding box and a mask of it. Nil when
    /// there is none or it reaches the image border (then it is the outside, not a screen).
    static func opening(alpha: [UInt8], width w: Int, height h: Int) -> (rect: CGRect, mask: [UInt8])? {
        guard w > 2, h > 2, alpha.count == w * h else { return nil }
        let cy = h / 2
        var seed: Int?
        for d in 0..<(w / 2) {
            if alpha[cy * w + w / 2 + d] < 255 { seed = cy * w + w / 2 + d; break }
            if alpha[cy * w + w / 2 - d] < 255 { seed = cy * w + w / 2 - d; break }
        }
        guard let start = seed else { return nil }
        // Scanline flood fill.
        var inside = [Bool](repeating: false, count: w * h)
        var stack = [start]
        var minX = w, maxX = -1, minY = h, maxY = -1, count = 0
        while let p = stack.popLast() {
            let y = p / w
            var x0 = p % w
            if inside[p] { continue }
            while x0 > 0, alpha[y * w + x0 - 1] < 255, !inside[y * w + x0 - 1] { x0 -= 1 }
            var x = x0
            var aboveOpen = false, belowOpen = false
            while x < w, alpha[y * w + x] < 255, !inside[y * w + x] {
                inside[y * w + x] = true; count += 1
                if y > 0 {
                    let q = (y - 1) * w + x, open = alpha[q] < 255 && !inside[q]
                    if open && !aboveOpen { stack.append(q) }
                    aboveOpen = open
                }
                if y < h - 1 {
                    let q = (y + 1) * w + x, open = alpha[q] < 255 && !inside[q]
                    if open && !belowOpen { stack.append(q) }
                    belowOpen = open
                }
                x += 1
            }
            minX = min(minX, x0); maxX = max(maxX, x - 1); minY = min(minY, y); maxY = max(maxY, y)
        }
        guard minX > 0, minY > 0, maxX < w - 1, maxY < h - 1, count * 20 > w * h else { return nil }
        let rw = maxX - minX + 1, rh = maxY - minY + 1
        var mask = [UInt8](repeating: 0, count: rw * rh)
        for y in 0..<rh {
            for x in 0..<rw where inside[(minY + y) * w + minX + x] { mask[y * rw + x] = 255 }
        }
        return (CGRect(x: minX, y: minY, width: rw, height: rh), mask)
    }

    static func grayImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Whether a `width`×`height` screenshot is a full screen for this opening: the same aspect
    /// ratio (0.5 %) at a similar size. Partial-size previews (sizeThatFits, fixed layouts,
    /// full-length captures) are not.
    static func fits(width: Int, height: Int, opening: CGSize) -> Bool {
        guard width > 0, height > 0, opening.width > 0, opening.height > 0 else { return false }
        let a = Double(width) / Double(height), b = Double(opening.width) / Double(opening.height)
        let scale = Double(width) / Double(opening.width)
        return abs(a / b - 1) < 0.005 && (0.5...2).contains(scale)
    }

    // MARK: Compositing

    static func load(_ path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw FrameError.unreadable(path) }
        return image
    }

    /// The device with the screenshot in it, bezel-sized, transparent around the device.
    static func plain(_ shot: CGImage, in bezel: Bezel) -> CGImage? {
        let w = bezel.image.width, h = bezel.image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let o = bezel.opening
        let screen = CGRect(x: o.minX, y: CGFloat(h) - o.maxY, width: o.width, height: o.height)
        ctx.interpolationQuality = shot.width == Int(o.width) && shot.height == Int(o.height) ? .none : .high
        ctx.saveGState()
        ctx.clip(to: screen, mask: bezel.mask)
        ctx.draw(shot, in: screen)
        ctx.restoreGState()
        ctx.draw(bezel.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: App Store

    /// Everything the App Store layout needs, already resolved for one screenshot.
    struct StoreStyle {
        enum Background { case color(CGColor), image(CGImage) }
        struct Text { var text: String; var color: CGColor; var font: CTFont }
        var background: Background
        var title: Text?
        var keyword: Text?
        var padding: (h: Double, v: Double)
        var titleBelowImage = false
        var stackTitle = false
        var showCompleteFrame = true
        var titleMinHeight = 0.0
        var interlineSpacing = 0.0
    }

    /// Where things go on the canvas (top-left origin, pixels).
    struct StoreLayout { var text: CGRect?; var device: CGRect; var fontScale: Double }

    /// The text: keyword then title, on one line or stacked, centred, wrapped to the width.
    static func attributed(_ style: StoreStyle, scale: Double) -> NSAttributedString? {
        let parts = [style.keyword, style.title].compactMap { $0 }.filter { !$0.text.isEmpty }
        guard !parts.isEmpty else { return nil }
        let result = NSMutableAttributedString()
        var alignment = CTTextAlignment.center
        var spacing = CGFloat(style.interlineSpacing)
        let paragraph = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &spacing) { s in
                CTParagraphStyleCreate([
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a.baseAddress!),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: s.baseAddress!),
                ], 2)
            }
        }
        for (i, part) in parts.enumerated() {
            let font = CTFontCreateCopyWithAttributes(part.font, CTFontGetSize(part.font) * scale, nil, nil)
            if i > 0 { result.append(NSAttributedString(string: style.stackTitle ? "\n" : " ", attributes: [.init(kCTFontAttributeName as String): font])) }
            result.append(NSAttributedString(string: part.text.replacingOccurrences(of: "\\n", with: "\n"), attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): part.color,
                .init(kCTParagraphStyleAttributeName as String): paragraph,
            ]))
        }
        result.addAttribute(.init(kCTParagraphStyleAttributeName as String), value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func textSize(_ text: NSAttributedString, width: Double) -> CGSize {
        let setter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// Widest single word, so a long word shrinks the text instead of breaking mid-word.
    static func widestWord(_ text: NSAttributedString) -> Double {
        var widest = 0.0
        let string = text.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { _, range, _, _ in
            let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
            widest = max(widest, CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        return widest
    }

    static func layout(canvas: CGSize, device: CGSize, style: StoreStyle) -> StoreLayout {
        let W = Double(canvas.width), H = Double(canvas.height)
        let (hp, vp) = style.padding
        let textWidth = W - 2 * hp
        // Text: shrink until it fits in at most ~30 % of the height and no word is too wide.
        var scale = 1.0
        var measured = CGSize.zero
        if let text = attributed(style, scale: 1) {
            var current = text
            while true {
                measured = textSize(current, width: textWidth)
                if (Double(measured.height) <= H * 0.3 && widestWord(current) <= textWidth) || scale < 0.25 { break }
                scale *= 0.92
                current = attributed(style, scale: scale)!
            }
        }
        let hasText = measured.height > 0
        let textArea = hasText ? max(Double(measured.height), style.titleMinHeight) : 0
        let gap = hasText ? vp : 0
        let availableW = W - 2 * hp, availableH = H - 2 * vp - textArea - gap
        let dw = Double(device.width), dh = Double(device.height)
        let s = style.showCompleteFrame ? min(availableW / dw, max(availableH, 1) / dh) : availableW / dw
        let devW = dw * s, devH = dh * s
        // A complete device and its text are centred as a group; a cut-off device runs off the
        // edge away from the text.
        let group = textArea + gap + devH
        let top = style.showCompleteFrame ? max(vp, (H - group) / 2) : vp
        var textY: Double, deviceY: Double
        if style.titleBelowImage {
            deviceY = style.showCompleteFrame ? top : H - vp - textArea - gap - devH
            textY = deviceY + devH + gap
        } else {
            textY = top
            deviceY = top + textArea + gap
        }
        let text = hasText ? CGRect(x: hp, y: textY + (textArea - Double(measured.height)) / 2, width: textWidth, height: Double(measured.height)) : nil
        return StoreLayout(text: text, device: CGRect(x: (W - devW) / 2, y: deviceY, width: devW, height: devH), fontScale: scale)
    }

    /// An App Store screenshot: opaque, `canvas`-sized, background, text and the framed device.
    static func appStore(device: CGImage, canvas: (width: Int, height: Int), style: StoreStyle) -> CGImage? {
        let (W, H) = canvas
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: W, height: H)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(full)
        switch style.background {
        case .color(let color): ctx.setFillColor(color); ctx.fill(full)
        case .image(let image):
            // Aspect fill, centred (like frameit).
            let s = max(Double(W) / Double(image.width), Double(H) / Double(image.height))
            let w = Double(image.width) * s, h = Double(image.height) * s
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: (Double(W) - w) / 2, y: (Double(H) - h) / 2, width: w, height: h))
        }
        let l = layout(canvas: CGSize(width: W, height: H), device: CGSize(width: device.width, height: device.height), style: style)
        ctx.interpolationQuality = .high
        ctx.draw(device, in: CGRect(x: l.device.minX, y: Double(H) - l.device.maxY, width: l.device.width, height: l.device.height))
        if let rect = l.text, let text = attributed(style, scale: l.fontScale) {
            let path = CGPath(rect: CGRect(x: rect.minX, y: Double(H) - rect.maxY, width: rect.width, height: rect.height + 1), transform: nil)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), path, nil)
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
        }
        return ctx.makeImage()
    }

    // MARK: Colours, fonts, files

    /// "#RGB", "#RRGGBB" or "#RRGGBBAA".
    static func color(_ hex: String) -> CGColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let n = s.count == 6 ? (v << 8) | 0xFF : v
        func c(_ shift: UInt64) -> CGFloat { CGFloat((n >> shift) & 0xFF) / 255 }
        return CGColor(colorSpace: sRGB, components: [c(24), c(16), c(8), c(0)])
    }

    /// Relative luminance of a background (an image: its average colour).
    static func luminance(_ background: StoreStyle.Background) -> Double {
        var rgb: [Double]
        switch background {
        case .color(let color):
            let c = color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1, 1]
            rgb = [c[0], c[1], c[2]].map(Double.init)
        case .image(let image):
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.interpolationQuality = .medium
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            rgb = px.prefix(3).map { Double($0) / 255 }
        }
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// A font file (.ttf/.otf/.ttc) or a font name; nil: the system font (bold for titles), with
    /// the language's own fallbacks (Arabic, CJK…).
    static func font(_ spec: String?, size: Double, bold: Bool, language: String) -> CTFont {
        if let spec, !spec.isEmpty {
            if FileManager.default.fileExists(atPath: spec),
               let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: spec) as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first {
                return CTFontCreateWithFontDescriptor(first, size, nil)
            }
            let font = CTFontCreateWithName(spec as CFString, size, nil)
            if (CTFontCopyPostScriptName(font) as String) == spec || (CTFontCopyFamilyName(font) as String) == spec { return font }
            missingFontsLock.lock(); let first = missingFonts.insert(spec).inserted; missingFontsLock.unlock()
            if first { Log.warn("Font '\(spec)' not found; using the system font") }
        }
        return CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, language as CFString)
            ?? CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    }

    static func writePNG(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, "public.png" as CFString, 1, nil) else { throw CLIError("Cannot write \(path)") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at: temp); throw CLIError("Cannot write \(path)") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }
}
