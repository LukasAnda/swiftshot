// Safe areas measured with `swiftshot calibrate` on real simulators (portrait, landscape),
// iOS 26.5 / 27.0 / 27.1. "<name>@<major>" entries override the plain name for that iOS major.
// Screen sizes/scales are not listed here: they are read from Xcode's device-type bundles.
// Devices missing here fall back to a heuristic; `swiftshot calibrate` makes them exact.
enum BuiltInDevices {
    static let table: [String: (Insets, Insets)] = [
        "iPad (A16)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPad Air 11-inch (M4)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPad Air 13-inch (M4)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPad Pro 11-inch (M5)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPad Pro 13-inch (M5)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPad mini (A17 Pro)": (Insets(top: 32, left: 0, bottom: 25, right: 0), Insets(top: 32, left: 0, bottom: 25, right: 0)),
        "iPhone 13 mini": (Insets(top: 50, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 50, bottom: 21, right: 50)),
        "iPhone 14": (Insets(top: 47, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 47, bottom: 21, right: 47)),
        "iPhone 15": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 15 Plus": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 15 Pro": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 15 Pro Max": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 16": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 16 Plus": (Insets(top: 59, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 59, bottom: 21, right: 59)),
        "iPhone 16 Pro": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 16 Pro Max": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 16e": (Insets(top: 47, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 47, bottom: 21, right: 47)),
        "iPhone 17": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 17 Pro": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 17 Pro Max": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 17e": (Insets(top: 47, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 47, bottom: 21, right: 47)),
        "iPhone 18 Pro": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone 18 Pro Max": (Insets(top: 62, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 62, bottom: 21, right: 62)),
        "iPhone Air": (Insets(top: 68, left: 0, bottom: 34, right: 0), Insets(top: 0, left: 68, bottom: 21, right: 68)),
        "iPhone Duo": (Insets(top: 0, left: 0, bottom: 34, right: 84), Insets(top: 0, left: 0, bottom: 0, right: 0)),
        "iPhone SE (3rd generation)": (Insets(top: 20, left: 0, bottom: 0, right: 0), Insets(top: 0, left: 0, bottom: 0, right: 0)),
    ]

    /// Devices whose UIKit point size isn't panel pixels / scale: the "mini" phones lay out at
    /// 375×812 pt @3x and the system downsamples to the 1080×2340 px panel (native scale 2.88).
    /// Rendering at 375×812 pt with scale 2.88 gives the panel-sized image directly (measured).
    static let logicalSize: [String: (width: Double, height: Double)] = [
        "iPhone 13 mini": (375, 812),
        "iPhone 12 mini": (375, 812),
    ]
}
