// Which of Apple's Product Bezels (developer.apple.com/design/resources) frames which device.
//
// Apple publishes one disk image per product family, e.g. Bezel-iPhone-17.dmg, with Photoshop
// files and transparent PNGs named "<model> - <colour> - <orientation>.png" (watches have no
// orientation: "AW Ultra 3 - Black + Ocean Band Black.png"). The PNGs' screen opening is exactly
// the device's panel size, so a screenshot goes in 1:1. The images are licensed to the user, not
// to swiftshot, so nothing here ships them: BezelStore downloads a family on first use.

import Foundation

struct BezelModel: Equatable {
    /// Disk image name on devimages-cdn.apple.com, without ".dmg".
    let pack: String
    /// File name prefix of this model's PNGs.
    let model: String
    let defaultColor: String
    /// File name suffixes for the two orientations; nil: one upright image (watches).
    var portrait: String? = "Portrait"
    var landscape: String? = "Landscape"
}

enum BezelCatalog {
    /// Bumped when the table or the cache layout changes; part of the cache path.
    static let version = "1"
    static let licenseURL = "https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf"

    static func url(_ pack: String) -> URL {
        URL(string: "https://devimages-cdn.apple.com/design/resources/download/\(pack).dmg")!
    }

    /// Simulator device type name -> bezel. Models with the same body and screen as a newer one
    /// share its bezel (iPad Pro M4 / M5, iPad Air M2 / M3 / M4, Watch Series 10 / 11, Ultra / Ultra 2).
    static let models: [String: BezelModel] = {
        func phone(_ pack: String, _ model: String, _ color: String) -> BezelModel { BezelModel(pack: pack, model: model, defaultColor: color) }
        func watch(_ pack: String, _ model: String, _ color: String) -> BezelModel {
            BezelModel(pack: pack, model: model, defaultColor: color, portrait: nil, landscape: nil)
        }
        let ipadPro13 = phone("Bezel-iPad-Pro-(M5)", "iPad Pro (M5) 13\"", "Space Black")
        let ipadPro11 = phone("Bezel-iPad-Pro-(M5)", "iPad Pro (M5) 11\"", "Space Black")
        let ipadAir13 = phone("Bezel-iPad-Air-(M4)", "iPad Air 13\" (M4)", "Space Gray")
        let ipadAir11 = phone("Bezel-iPad-Air-(M4)", "iPad Air 11\" (M4)", "Space Gray")
        let s11small = watch("Bezel-Apple-Watch-Series-11-2025", "Apple Watch S11 - 42mm", "Aluminum Jet Black + Sport Band Black")
        let s11large = watch("Bezel-Apple-Watch-Series-11-2025", "Apple Watch S11 - 46mm", "Aluminum Jet Black + Sport Band Black")
        let ultra2 = watch("Bezel-Apple-Watch-Ultra-2-2024", "AW Ultra 2", "Black + Ocean Band Black")
        return [
            "iPhone 18 Pro Max": phone("Bezel-iPhone-18", "iPhone 18 Pro Max", "Black"),
            "iPhone 18 Pro": phone("Bezel-iPhone-18", "iPhone 18 Pro", "Black"),
            "iPhone 17 Pro Max": phone("Bezel-iPhone-17", "iPhone 17 Pro Max", "Deep Blue"),
            "iPhone 17 Pro": phone("Bezel-iPhone-17", "iPhone 17 Pro", "Deep Blue"),
            "iPhone 17": phone("Bezel-iPhone-17", "iPhone 17", "Black"),
            "iPhone Air": phone("Bezel-iPhone-17", "iPhone Air", "Space Black"),
            "iPhone 16 Pro Max": phone("Bezel-iPhone-16", "iPhone 16 Pro Max", "Black Titanium"),
            "iPhone 16 Pro": phone("Bezel-iPhone-16", "iPhone 16 Pro", "Black Titanium"),
            "iPhone 16 Plus": phone("Bezel-iPhone-16", "iPhone 16 Plus", "Black"),
            "iPhone 16": phone("Bezel-iPhone-16", "iPhone 16", "Black"),
            "iPhone Duo": BezelModel(pack: "Bezel-iPhone-Duo", model: "iPhone Duo", defaultColor: "Night Sky",
                                     portrait: "Outer Closed Portrait", landscape: "Outer Closed Landscape"),
            "iPad Pro 13-inch (M5)": ipadPro13, "iPad Pro 13-inch (M5) (16GB)": ipadPro13,
            "iPad Pro 13-inch (M4)": ipadPro13, "iPad Pro 13-inch (M4) (16GB)": ipadPro13,
            "iPad Pro 11-inch (M5)": ipadPro11, "iPad Pro 11-inch (M5) (16GB)": ipadPro11,
            "iPad Pro 11-inch (M4)": ipadPro11, "iPad Pro 11-inch (M4) (16GB)": ipadPro11,
            "iPad Air 13-inch (M4)": ipadAir13, "iPad Air 13-inch (M3)": ipadAir13, "iPad Air 13-inch (M2)": ipadAir13,
            "iPad Air 11-inch (M4)": ipadAir11, "iPad Air 11-inch (M3)": ipadAir11, "iPad Air 11-inch (M2)": ipadAir11,
            "iPad mini (A17 Pro)": phone("Bezel-iPad-mini-(A17-Pro)", "iPad mini (A17 Pro)", "Space Gray"),
            "iPad (A16)": phone("Bezel-iPad-(A16)", "iPad (A16)", "Silver"),
            "Apple Watch Ultra 3 (49mm)": watch("Bezel-Apple-Watch-Ultra-3-2025", "AW Ultra 3", "Black + Ocean Band Black"),
            "Apple Watch Ultra 2 (49mm)": ultra2, "Apple Watch Ultra (49mm)": ultra2,
            "Apple Watch Series 11 (42mm)": s11small, "Apple Watch Series 10 (42mm)": s11small,
            "Apple Watch Series 11 (46mm)": s11large, "Apple Watch Series 10 (46mm)": s11large,
        ]
    }()

    static func model(for device: String) -> BezelModel? {
        models[device] ?? models.first { $0.key.caseInsensitiveCompare(device) == .orderedSame }?.value
    }

    /// The device a screenshot file belongs to, from its name ("<device>-<preview>….png"): the
    /// longest known device name followed by "-". Device names contain dashes ("13-inch"), so
    /// the name can't simply be split.
    static func device(inFileName name: String, known: [String]) -> String? {
        known.filter { name.count > $0.count && name.lowercased().hasPrefix($0.lowercased() + "-") }.max { $0.count < $1.count }
    }

    /// One bezel image of an installed pack.
    struct Entry: Equatable { let model: String; let color: String; let orientation: String?; let path: String }

    /// Parses a pack's file names ("iPhone 17 Pro - Deep Blue - Portrait.png") for one model.
    static func entries(_ files: [String], for model: BezelModel) -> [Entry] {
        let suffixes = [model.portrait, model.landscape].compactMap { $0 }
        return files.compactMap { path in
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard path.lowercased().hasSuffix(".png"), name.hasPrefix(model.model + " - ") else { return nil }
            let rest = String(name.dropFirst(model.model.count + 3))
            if suffixes.isEmpty { return rest.contains(" - ") ? nil : Entry(model: model.model, color: rest, orientation: nil, path: path) }
            for suffix in suffixes where rest.hasSuffix(" - " + suffix) {
                return Entry(model: model.model, color: String(rest.dropLast(suffix.count + 3)), orientation: suffix, path: path)
            }
            return nil
        }
    }

    /// The colour of `available` that `wanted` names: equal ignoring case, spaces, "-" and "_"
    /// ("SPACE_BLACK", frameit's style, works), else the first (sorted) that starts with or
    /// contains it ("Natural" picks a natural titanium watch).
    static func matchColor(_ wanted: String, in available: [String]) -> String? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "+" } }
        let w = norm(wanted), sorted = available.sorted()
        guard !w.isEmpty else { return nil }
        return sorted.first { norm($0) == w } ?? sorted.first { norm($0).hasPrefix(w) } ?? sorted.first { norm($0).contains(w) }
    }

    /// `--frame-color` values: "Colour" for every device, or "Device=Colour" for one.
    static func colorChoice(_ choices: [String], device: String) -> String? {
        var global: String?
        for choice in choices {
            if let eq = choice.firstIndex(of: "=") {
                if choice[..<eq].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(device) == .orderedSame {
                    return choice[choice.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                }
            } else if global == nil {
                global = choice
            }
        }
        return global
    }
}

/// Screenshot sizes App Store Connect accepts, per display class (portrait; landscape is the
/// same sizes rotated). From developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications.
enum AppStoreSizes {
    struct DisplayClass { let name: String; let idiom: String; let sizes: [(Int, Int)] }

    static let classes: [DisplayClass] = [
        DisplayClass(name: "iPhone 6.9\"", idiom: "phone", sizes: [(1320, 2868), (1290, 2796), (1260, 2736)]),
        DisplayClass(name: "iPhone 6.5\"", idiom: "phone", sizes: [(1284, 2778), (1242, 2688)]),
        DisplayClass(name: "iPhone 6.3\"", idiom: "phone", sizes: [(1206, 2622), (1179, 2556)]),
        DisplayClass(name: "iPhone 6.1\"", idiom: "phone", sizes: [(1170, 2532), (1125, 2436), (1080, 2340)]),
        DisplayClass(name: "iPhone 5.5\"", idiom: "phone", sizes: [(1242, 2208)]),
        DisplayClass(name: "iPhone 4.7\"", idiom: "phone", sizes: [(750, 1334)]),
        DisplayClass(name: "iPhone 4\"", idiom: "phone", sizes: [(640, 1136)]),
        DisplayClass(name: "iPhone Duo", idiom: "phone", sizes: [(1398, 2034), (2007, 2853)]),
        DisplayClass(name: "iPad 13\"", idiom: "pad", sizes: [(2064, 2752), (2048, 2732)]),
        DisplayClass(name: "iPad 11\"", idiom: "pad", sizes: [(1668, 2420), (1668, 2388), (1640, 2360), (1488, 2266)]),
        DisplayClass(name: "iPad 10.5\"", idiom: "pad", sizes: [(1668, 2224)]),
        DisplayClass(name: "iPad 9.7\"", idiom: "pad", sizes: [(1536, 2048)]),
    ]

    static func idiom(of device: String) -> String {
        device.hasPrefix("iPad") ? "pad" : device.hasPrefix("Apple Watch") ? "watch" : "phone"
    }

    /// The canvas for an App Store screenshot of a `width`×`height` capture: the capture's own
    /// size when App Store Connect accepts it, otherwise the largest accepted size of the
    /// closest aspect ratio for the idiom. Orientation follows the capture.
    static func canvas(width: Int, height: Int, idiom: String) -> (width: Int, height: Int) {
        let landscape = width > height
        let short = min(width, height), long = max(width, height)
        let candidates = classes.filter { $0.idiom == (idiom == "pad" ? "pad" : "phone") }.flatMap(\.sizes)
        let pick: (Int, Int)
        if candidates.contains(where: { $0 == (short, long) }) {
            pick = (short, long)
        } else {
            let aspect = Double(short) / Double(long)
            func distance(_ s: (Int, Int)) -> Double { abs(Double(s.0) / Double(s.1) - aspect) }
            let best = candidates.map(distance).min() ?? 0
            pick = candidates.filter { distance($0) - best < 0.002 }.max { $0.0 * $0.1 < $1.0 * $1.1 } ?? (short, long)
        }
        return landscape ? (pick.1, pick.0) : pick
    }
}
