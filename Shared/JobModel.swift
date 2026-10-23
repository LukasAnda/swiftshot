// Shared between the macOS host CLI and the in-simulator agent.
// The host writes a `Job` as JSON, the agent reads it and writes back a `JobResult`.

import Foundation

struct Insets: Codable, Equatable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
    static let zero = Insets(top: 0, left: 0, bottom: 0, right: 0)
}

/// What the device's display reports to UIKit (UIScreen._displayInfoProvider and the screen's
/// periphery insets). Only a booted device has a display; without one (no-boot rendering) the
/// agent reports these values itself. Some layout depends on them, e.g. the floating tab bar's
/// bottom padding on phones with a home indicator.
struct DisplayInfo: Codable, Equatable {
    var safeAreaPortrait: Insets
    var safeAreaPortraitUpsideDown: Insets
    var safeAreaLandscapeLeft: Insets
    var safeAreaLandscapeRight: Insets
    var periphery: Insets
    var homeAffordanceOverlayAllowance: Double
    var systemMinimumMargin: Double
    var artworkSubtype: Int
    var screenPeriphery: Insets
    var screenDisplayPeriphery: Insets
    /// UIStatusBarManager: 0 horizontal (along the top), 1 vertical (a side rail, e.g. iPhone Duo).
    var statusBarAxis: Int? = nil
    /// statusBarFrame height and UIStatusBarManager.statusBarHeight (they differ with a rail).
    var statusBarFrameHeight: Double? = nil
    var statusBarHeight: Double? = nil
    /// Private traits a scene with a status bar rail has: _UITraitSystemVerticalBarAllowed and
    /// _UITraitSystemVerticalBarHorizontalEdge (navigation bars then use inline large titles).
    var verticalBarAllowed: Int? = nil
    var verticalBarEdge: Int? = nil
    /// UIWindow._sceneSafeAreaCornerInsets: four corner sizes (width, height pairs).
    var cornerInsets: [Double]? = nil
    /// The scene's resolved bar position trait (_UITraitSceneBarPosition): alignment insets
    /// (top, left, bottom, right), then top, bottom, leading and trailing bar size classes.
    var barPosition: [Double]? = nil
    /// UIScreen._exclusionArea rect (x, y, width, height in points): the Dynamic Island.
    var exclusionArea: [Double]? = nil
    /// The camera region SpringBoard gives the scene (an exclusion _UISceneRegion named
    /// "…Camera", x, y, width, height in points) on a device with one (iPhone Duo's cover camera).
    /// SpringBoard's status bar avoids it rather than the screen's exclusion area, which sits a
    /// fraction of a point off (Duo: {399.67, 29.33, 37, 37} vs {399, 30, 37, 37}).
    var cameraRegion: [Double]? = nil
}

/// Geometry of a device, in points.
struct DeviceProfile: Codable {
    var name: String
    var idiom: String              // "phone" | "pad"
    var width: Double              // portrait width (pt)
    var height: Double             // portrait height (pt)
    var scale: Double
    var safeArea: Insets           // portrait safe area
    var landscapeSafeArea: Insets
    var cornerRadius: Double
    /// Per-corner display radii (top left, bottom left, bottom right, top right) when they differ
    /// from `cornerRadius` (iPhone Duo: 8 on the hinge side). Sheets follow them.
    var cornerRadii: [Double]? = nil
    /// Panel size in pixels when it differs from size × scale (the "mini" phones render at @3x and
    /// are downsampled by the system to a smaller panel).
    var panelWidth: Double? = nil
    var panelHeight: Double? = nil
    /// Display data for rendering without a booted device (see DisplayInfo).
    var display: DisplayInfo? = nil
    /// The system's default Dynamic Type size on this model (watches differ by case size, e.g.
    /// 46 mm: XL), as UIContentSizeCategory raw value. Rendering without a booted device uses it.
    var contentSizeCategory: String? = nil

    /// Devices rendered on the same host must share the native scale, otherwise text, symbols and
    /// glass are rasterized at the host's scale. iPhones and iPads of one scale share a host
    /// (idiom is a trait override); watches always have their own.
    var hostGroup: String { "\(idiom == "watch" ? "watch" : "")@\(String(format: "%.2f", panelWidth.map { $0 / width } ?? scale))" }
}

enum JobMode: String, Codable {
    /// Render every preview for every device profile off-screen, in-process.
    case virtual
    /// Show each preview full-screen on the real simulator screen and hand over to the host
    /// (which grabs the framebuffer with `simctl io screenshot`, status bar included).
    case device
    /// Report the real screen metrics/safe areas of this simulator.
    case calibrate
    /// Only list discovered previews.
    case list
}

/// Per-screenshot overrides. The first rule whose `preview` pattern (exact name or `*` glob,
/// case-insensitive) matches a preview applies to it; nil fields inherit the global setting.
struct ScreenRule: Codable {
    var preview: String
    var appearances: [String]?
    var languages: [String]?
    var devices: [String]?
    var iosVersions: [String]?
    var textSizes: [String]?
    var fullLength: Bool?
    var delay: Double?
    var skip: Bool?

    enum CodingKeys: String, CodingKey {
        case preview, appearances, languages, devices, iosVersions = "ios_versions", textSizes = "text_sizes",
             fullLength = "full_length", delay, skip
    }

    func matches(_ name: String) -> Bool { globMatch(preview, name) }
}

func globMatch(_ pattern: String, _ name: String) -> Bool {
    if !pattern.contains("*") { return pattern.caseInsensitiveCompare(name) == .orderedSame }
    let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
    return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
}

/// "27" matches 27.0 and 27.1, "26.5" matches 26.5.
func versionMatches(_ wanted: String, _ version: String) -> Bool {
    version == wanted || version.hasPrefix(wanted + ".")
}

struct Job: Codable {
    var mode: JobMode
    var outputDir: String
    var language: String
    var runtime: String
    var devices: [DeviceProfile]
    var appearances: [String]          // "light" | "dark"
    var previewFilter: [String]        // empty = all; otherwise substring/glob matches against preview name
    var format: String                 // "png" | "jpeg"
    var settleFrames: Int              // run-loop turns to wait before capturing
    var settleDelay: Double            // extra seconds to wait before capturing (images, animations)
    var controlDir: String?            // device mode handshake directory
    var fileNamePattern: String        // e.g. "{device}-{preview}{appearance}"
    var includeRuntimeInName: Bool
    // Optional so that an older host and a newer agent (or vice versa) still understand each other.
    var screenRules: [ScreenRule]? = nil
    var targetPlatform: String? = nil    // "ios" (default) | "watchos"
    /// Where the agent writes its JobResult (stdout is only a fallback: a watch app's console
    /// output can be lost when the simulator was just first-booted).
    var resultPath: String? = nil
    /// Dynamic Type sizes to render each preview at ("L", "AX3"…; "default" = the device's own).
    var textSizes: [String]? = nil
    /// Set when the whole process runs at one text size (watchOS: list cells follow the app-wide
    /// setting, not window traits); then only that size is rendered here.
    var processTextSize: String? = nil
    /// Grow full-screen previews to show the whole content of their scroll view.
    var fullLength: Bool? = nil
    /// Draw the system status bar like a device shows it (no-boot); nil (older host): yes.
    var statusBar: Bool? = nil
    /// The Mac's locale and time zone: a simulator formats its status bar clock with them.
    var statusBarLocale: String? = nil
    var statusBarTimeZone: String? = nil

    var rules: [ScreenRule] { screenRules ?? [] }
    var platform: String { targetPlatform ?? "ios" }

    func rule(for preview: String) -> ScreenRule? { rules.first { $0.matches(preview) } }

    /// Whether this preview is wanted at all in this process (language + runtime).
    func wants(_ preview: String) -> Bool {
        guard let r = rule(for: preview) else { return true }
        if r.skip == true { return false }
        if let langs = r.languages, !langs.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) { return false }
        if let versions = r.iosVersions, !versions.contains(where: { versionMatches($0, runtime) }) { return false }
        return true
    }

    func appearances(for preview: String) -> [String] {
        rule(for: preview)?.appearances ?? appearances
    }

    func textSizes(for preview: String) -> [String] {
        let sizes = rule(for: preview)?.textSizes ?? textSizes ?? ["default"]
        guard let only = processTextSize else { return sizes }
        return sizes.filter { $0.caseInsensitiveCompare(only) == .orderedSame }
    }

    func wants(_ preview: String, device: String) -> Bool {
        guard let devices = rule(for: preview)?.devices else { return true }
        return devices.contains { globMatch($0, device) }
    }

    func fullLength(for preview: String) -> Bool { rule(for: preview)?.fullLength ?? fullLength ?? false }

    func delay(for preview: String) -> Double { rule(for: preview)?.delay ?? settleDelay }
}

struct ShotRecord: Codable {
    var preview: String
    var device: String
    var appearance: String
    var textSize: String? = nil
    var language: String
    var runtime: String
    var file: String
    var width: Int
    var height: Int
    var renderMs: Double
}

struct JobResult: Codable {
    var previews: [String]
    var shots: [ShotRecord]
    var errors: [String]
    var calibration: DeviceProfile?
    var totalMs: Double
}

/// "XL" -> "UICTContentSizeCategoryXL", "AX2" -> "UICTContentSizeCategoryAccessibilityL"…
/// "default" (or empty) -> nil: whatever the device uses.
func contentSizeCategory(_ short: String) -> String? {
    if short.isEmpty || short.lowercased() == "default" { return nil }
    if short.hasPrefix("UICTContentSizeCategory") { return short }
    let ax = ["AX1": "AccessibilityM", "AX2": "AccessibilityL", "AX3": "AccessibilityXL", "AX4": "AccessibilityXXL", "AX5": "AccessibilityXXXL"]
    return "UICTContentSizeCategory" + (ax[short.uppercased()] ?? short.uppercased())
}

let textSizeNames = ["XS", "S", "M", "L", "XL", "XXL", "XXXL", "AX1", "AX2", "AX3", "AX4", "AX5"]
