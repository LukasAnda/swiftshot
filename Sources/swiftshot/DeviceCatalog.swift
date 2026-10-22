// Device geometry for virtual rendering.
//
// Screen size and scale come straight from the CoreSimulator device-type bundle
// (capabilities.plist), so every device Xcode knows about works. Safe-area insets are not
// stored there; they come from (in priority order):
//   1. the calibration cache (~/Library/Caches/swiftshot/calibration.json), filled by
//      `swiftshot calibrate`, which measures a real booted simulator,
//   2. the built-in table (measured by the same calibration, shipped with the tool),
//   3. a heuristic based on the device's Face ID capability.
// That means CI never has to boot a simulator just to learn a device's geometry.

import Foundation

enum DeviceCatalog {
    static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/swiftshot/calibration.json")
    }

    static func loadCache() -> [String: DeviceProfile] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: DeviceProfile].self, from: data)) ?? [:]
    }

    static func saveCache(_ cache: [String: DeviceProfile]) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(cache).write(to: cacheURL, options: .atomic)
    }

    static func cacheKey(device: String, runtime: String) -> String { "\(device)@\(runtime)" }

    struct Screen { let width: Double; let height: Double; let scale: Double; let corner: Double; let faceID: Bool }

    static func screen(of type: SimDeviceType) -> Screen? {
        let url = URL(fileURLWithPath: type.bundlePath).appendingPathComponent("Contents/Resources/capabilities.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let caps = plist["capabilities"] as? [String: Any] else { return nil }
        let profileURL = URL(fileURLWithPath: type.bundlePath).appendingPathComponent("Contents/Resources/profile.plist")
        let profile = (try? Data(contentsOf: profileURL)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let faceID = ((profile?["supportedFeatures"] as? [String: Any])?["com.apple.pearl-id"] as? Bool) ?? false
        func number(_ dict: [String: Any]?, _ keys: String...) -> Double? {
            for key in keys { if let n = dict?[key] as? NSNumber { return n.doubleValue } }
            return nil
        }
        let corner = number(caps, "DeviceCornerRadius") ?? 0
        func make(_ w: Double, _ h: Double, _ s: Double, _ c: Double) -> Screen {
            Screen(width: min(w, h) / s, height: max(w, h) / s, scale: s, corner: c, faceID: faceID)
        }
        // Newer device types: a `displays` array; the main one is "primary" (or the integrated panel).
        if let displays = caps["displays"] as? [[String: Any]],
           let primary = displays.first(where: { ($0["deviceName"] as? String) == "primary" })
                ?? displays.first(where: { ($0["displayType"] as? String) == "integrated" }),
           let w = number(primary, "width"), let h = number(primary, "height"), let s = number(primary, "scale") {
            return make(w, h, s, number(primary, "cornerRadiusUL") ?? corner)
        }
        // Older device types: MobileGestalt-style screen dimensions, or mainScreen* in profile.plist.
        let dims = caps["ScreenDimensionsCapability"] as? [String: Any]
        if let w = number(dims, "main-screen-width"), let h = number(dims, "main-screen-height"), let s = number(dims, "main-screen-scale") {
            return make(w, h, s, corner)
        }
        if let w = number(profile, "mainScreenWidth"), let h = number(profile, "mainScreenHeight"), let s = number(profile, "mainScreenScale") {
            return make(w, h, s, corner)
        }
        Log.debug("\(type.name): no screen size in \(url.path) (keys: \(caps.keys.sorted().joined(separator: ", ")))")
        return nil
    }

    /// Why `screen(of:)` found nothing, for the error message.
    static func screenDiagnostics(_ type: SimDeviceType) -> String {
        let url = URL(fileURLWithPath: type.bundlePath).appendingPathComponent("Contents/Resources/capabilities.plist")
        guard let data = try? Data(contentsOf: url) else { return "cannot read \(url.path)" }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return "\(url.path) is not a dictionary plist" }
        let caps = plist["capabilities"] as? [String: Any] ?? [:]
        let screenish = caps.keys.filter { $0.localizedCaseInsensitiveContains("screen") || $0.localizedCaseInsensitiveContains("display") }.sorted()
        return "\(url.path): top-level keys [\(plist.keys.sorted().joined(separator: ", "))], screen keys [\(screenish.joined(separator: ", "))]"
    }

    static func heuristicSafeArea(idiom: String, screen: Screen) -> (Insets, Insets) {
        let faceID = screen.faceID || (idiom == "phone" && screen.height >= 812)
        switch (idiom, faceID) {
        case ("phone", true):
            let top: Double = screen.corner >= 55 ? 62 : 47
            return (Insets(top: top, left: 0, bottom: 34, right: 0), Insets(top: 0, left: top, bottom: 21, right: top))
        case ("phone", false):
            return (Insets(top: 20, left: 0, bottom: 0, right: 0), .zero)
        case (_, true):
            return (Insets(top: 32, left: 0, bottom: 20, right: 0), Insets(top: 32, left: 0, bottom: 20, right: 0))
        default:
            return (Insets(top: 24, left: 0, bottom: 0, right: 0), Insets(top: 24, left: 0, bottom: 0, right: 0))
        }
    }

    /// Resolves a profile without booting anything.
    static func profile(for type: SimDeviceType, runtime: String, cache: [String: DeviceProfile]) -> (DeviceProfile, source: String)? {
        if let cached = cache[cacheKey(device: type.name, runtime: runtime)] { return (cached, "calibrated") }
        let family = (type.productFamily ?? "").lowercased()
        let idiom = family.contains("ipad") ? "pad" : family.contains("watch") ? "watch" : "phone"
        guard var screen = screen(of: type) else { return nil }
        var panel: (Double, Double)?
        if let logical = BuiltInDevices.logicalSize[type.name] {
            panel = (screen.width * screen.scale, screen.height * screen.scale)
            screen = Screen(width: logical.width, height: logical.height, scale: 3, corner: screen.corner, faceID: screen.faceID)
        }
        func withPanel(_ p: DeviceProfile) -> DeviceProfile {
            var p = p; p.panelWidth = panel?.0; p.panelHeight = panel?.1; return p
        }
        let major = runtime.split(separator: ".").first.map(String.init) ?? runtime
        if let known = BuiltInDevices.table["\(type.name)@\(major)"] ?? BuiltInDevices.table[type.name] {
            return (withPanel(DeviceProfile(name: type.name, idiom: idiom, width: screen.width, height: screen.height, scale: screen.scale,
                                  safeArea: known.0, landscapeSafeArea: known.1, cornerRadius: screen.corner)), "built-in")
        }
        let (portrait, landscape) = idiom == "watch" ? (Insets.zero, Insets.zero) : heuristicSafeArea(idiom: idiom, screen: screen)
        return (withPanel(DeviceProfile(name: type.name, idiom: idiom, width: screen.width, height: screen.height, scale: screen.scale,
                              safeArea: portrait, landscapeSafeArea: landscape, cornerRadius: screen.corner)), "heuristic")
    }
}
