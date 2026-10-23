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
        if let path = ProcessInfo.processInfo.environment["SWIFTSHOT_CALIBRATION_CACHE"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser
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

    struct Screen { let width: Double; let height: Double; let scale: Double; let corner: Double; let faceID: Bool; var pitch: Double = 0; var radii: [Double]? = nil }

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
        // A booted device reports the corner radius rounded to hundredths (iPhone 16e: 47.33, not
        // the plist's 47.3333320…); sheets' corners follow it.
        func hundredths(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let corner = number(caps, "DeviceCornerRadius").map(hundredths) ?? 0
        func make(_ w: Double, _ h: Double, _ s: Double, _ c: Double) -> Screen {
            Screen(width: min(w, h) / s, height: max(w, h) / s, scale: s, corner: c, faceID: faceID)
        }
        // Newer device types: a `displays` array; the main one is "primary" (or the integrated panel).
        if let displays = caps["displays"] as? [[String: Any]],
           let primary = displays.first(where: { ($0["deviceName"] as? String) == "primary" })
                ?? displays.first(where: { ($0["displayType"] as? String) == "integrated" }),
           let w = number(primary, "width"), let h = number(primary, "height"), let s = number(primary, "scale") {
            // UIScreen reports the device type's DeviceCornerRadius; per-corner radii can differ
            // (iPhone Duo: 8 on the hinge side, 59 outside).
            var screen = make(w, h, s, corner > 0 ? corner : number(primary, "cornerRadiusUL").map(hundredths) ?? 0)
            screen.pitch = number(primary, "hdpi") ?? 0
            let radii = ["cornerRadiusUL", "cornerRadiusLL", "cornerRadiusLR", "cornerRadiusUR"].compactMap { number(primary, $0).map(hundredths) }
            if radii.count == 4, radii.contains(where: { $0 != screen.corner }) { screen.radii = radii }
            return screen
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
        if var cached = cache[cacheKey(device: type.name, runtime: runtime)] {
            if cached.display == nil { cached.display = builtInDisplay(type.name, runtime: runtime) }
            if cached.contentSizeCategory == nil { cached.contentSizeCategory = BuiltInDisplays.contentSizeCategory[type.name] }
            return (cached, "calibrated")
        }
        let family = (type.productFamily ?? "").lowercased()
        let idiom = family.contains("ipad") ? "pad" : family.contains("watch") ? "watch" : "phone"
        guard var screen = screen(of: type) else { return nil }
        var panel: (Double, Double)?
        if let logical = BuiltInDevices.logicalSize[type.name] {
            panel = (screen.width * screen.scale, screen.height * screen.scale)
            screen = Screen(width: logical.width, height: logical.height, scale: 3, corner: screen.corner, faceID: screen.faceID, radii: screen.radii)
        }
        func withPanel(_ p: DeviceProfile) -> DeviceProfile {
            var p = p; p.panelWidth = panel?.0; p.panelHeight = panel?.1; p.cornerRadii = screen.radii
            p.display = builtInDisplay(type.name, runtime: runtime)
            p.contentSizeCategory = BuiltInDisplays.contentSizeCategory[type.name]
            return p
        }
        let major = runtime.split(separator: ".").first.map(String.init) ?? runtime
        if let known = BuiltInDevices.table["\(type.name)@\(major)"] ?? BuiltInDevices.table[type.name] {
            return (withPanel(DeviceProfile(name: type.name, idiom: idiom, width: screen.width, height: screen.height, scale: screen.scale,
                                  safeArea: known.0, landscapeSafeArea: known.1, cornerRadius: screen.corner)), "built-in")
        }
        // The measured display data has the portrait safe area (in portrait coordinates for every
        // orientation); a landscape window gets the sensor housing on both sides.
        if idiom != "watch", let display = builtInDisplay(type.name, runtime: runtime), display.statusBarAxis == nil {
            let p = display.safeAreaPortrait
            let landscape = idiom == "pad" ? p : (p.top > 24 ? Insets(top: 0, left: p.top, bottom: min(p.bottom, 21), right: p.top) : .zero)
            return (withPanel(DeviceProfile(name: type.name, idiom: idiom, width: screen.width, height: screen.height, scale: screen.scale,
                                  safeArea: p, landscapeSafeArea: landscape, cornerRadius: screen.corner)), "built-in display")
        }
        let (portrait, landscape) = idiom == "watch" ? (BuiltInDisplays.watchSafeArea[type.name] ?? .zero, Insets.zero) : heuristicSafeArea(idiom: idiom, screen: screen)
        return (withPanel(DeviceProfile(name: type.name, idiom: idiom, width: screen.width, height: screen.height, scale: screen.scale,
                              safeArea: portrait, landscapeSafeArea: landscape, cornerRadius: screen.corner)), "heuristic")
    }

    /// Display data for no-boot rendering: "<name>@<major>" overrides "<name>".
    static func builtInDisplay(_ name: String, runtime: String) -> DisplayInfo? {
        let major = runtime.split(separator: ".").first.map(String.init) ?? runtime
        return BuiltInDisplays.table["\(name)@\(major)"] ?? BuiltInDisplays.table[name]
    }

    /// Swift source for BuiltInDisplays.swift from calibrated profiles (`calibrate --emit-table`).
    /// A device whose display data is the same on every measured runtime gets one entry. Devices
    /// this run didn't measure (e.g. not bootable on this machine's runtimes) keep their entries.
    static func displayTableSource(_ cache: [String: DeviceProfile], existing: [String: DisplayInfo], existingSizes: [String: String],
                                   existingSafeAreas: [String: Insets], header: String) -> String {
        var byDevice: [String: [(String, DisplayInfo)]] = [:]
        for (key, profile) in cache {
            guard let display = profile.display, let at = key.lastIndex(of: "@") else { continue }
            byDevice[String(key[..<at]), default: []].append((String(key[key.index(after: at)...]), display))
        }
        func lit(_ i: Insets) -> String { "Insets(top: \(i.top), left: \(i.left), bottom: \(i.bottom), right: \(i.right))" }
        func lit(_ d: DisplayInfo) -> String {
            "DisplayInfo(safeAreaPortrait: \(lit(d.safeAreaPortrait)), safeAreaPortraitUpsideDown: \(lit(d.safeAreaPortraitUpsideDown)), " +
            "safeAreaLandscapeLeft: \(lit(d.safeAreaLandscapeLeft)), safeAreaLandscapeRight: \(lit(d.safeAreaLandscapeRight)), " +
            "periphery: \(lit(d.periphery)), homeAffordanceOverlayAllowance: \(d.homeAffordanceOverlayAllowance), " +
            "systemMinimumMargin: \(d.systemMinimumMargin), artworkSubtype: \(d.artworkSubtype), " +
            "screenPeriphery: \(lit(d.screenPeriphery)), screenDisplayPeriphery: \(lit(d.screenDisplayPeriphery))" +
            (d.statusBarAxis.map { ", statusBarAxis: \($0)" } ?? "") + (d.statusBarFrameHeight.map { ", statusBarFrameHeight: \($0)" } ?? "") + (d.statusBarHeight.map { ", statusBarHeight: \($0)" } ?? "") +
            (d.verticalBarAllowed.map { ", verticalBarAllowed: \($0)" } ?? "") + (d.verticalBarEdge.map { ", verticalBarEdge: \($0)" } ?? "") +
            (d.cornerInsets.map { ", cornerInsets: \($0)" } ?? "") + (d.barPosition.map { ", barPosition: \($0)" } ?? "") +
            (d.exclusionArea.map { ", exclusionArea: \($0)" } ?? "") + ")"
        }
        var lines: [String] = []
        for (key, display) in existing where byDevice[key.split(separator: "@").first.map(String.init) ?? key] == nil {
            lines.append("        \"\(key)\": \(lit(display)),")
        }
        for (name, entries) in byDevice.sorted(by: { $0.key < $1.key }) {
            let sorted = entries.sorted { $0.0.compare($1.0, options: .numeric) == .orderedAscending }
            let newest = sorted.last!.1
            lines.append("        \"\(name)\": \(lit(newest)),")
            var seenMajors = Set<String>()
            for (runtime, display) in sorted where display != newest {
                let major = runtime.split(separator: ".").first.map(String.init) ?? runtime
                if seenMajors.insert(major).inserted { lines.append("        \"\(name)@\(major)\": \(lit(display)),") }
            }
        }
        lines.sort()
        var safeAreas = existingSafeAreas
        for (key, profile) in cache where profile.idiom == "watch" {
            guard let at = key.lastIndex(of: "@") else { continue }
            safeAreas[String(key[..<at])] = profile.safeArea
        }
        let safeAreaLines = safeAreas.sorted { $0.key < $1.key }.map { "        \"\($0.key)\": \(lit($0.value)),"}
        var sizes = existingSizes
        for (key, profile) in cache {
            guard let category = profile.contentSizeCategory, let at = key.lastIndex(of: "@") else { continue }
            sizes[String(key[..<at])] = category
        }
        let sizeLines = sizes.sorted { $0.key < $1.key }.map { "        \"\($0.key)\": \"\($0.value)\"," }
        return header + """
        enum BuiltInDisplays {
            static let table: [String: DisplayInfo] = [
        \(lines.joined(separator: "\n"))
            ]
            /// Default Dynamic Type size per model, where the system's default differs from L (watches).
            static let contentSizeCategory: [String: String] = [
        \(sizeLines.isEmpty ? "        :" : sizeLines.joined(separator: "\n"))
            ]
            /// Portrait safe area of watches (their status bar / clock row).
            static let watchSafeArea: [String: Insets] = [
        \(safeAreaLines.isEmpty ? "        :" : safeAreaLines.joined(separator: "\n"))
            ]
        }

        """
    }
}
