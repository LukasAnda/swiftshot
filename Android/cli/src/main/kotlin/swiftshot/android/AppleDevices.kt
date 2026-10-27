package swiftshot.android

/**
 * iPhones and iPads for platforms that draw their own UI (Flutter): screen size in points, scale
 * and the portrait safe area, as `swiftshot devices` measures them on the simulator runtimes
 * (iOS 26.5–27.1). The "mini" phones show 375×812 pt on a 1080×2340 panel: scale 2.88.
 */
data class AppleDevice(val name: String, val width: Int, val height: Int, val scale: Double, val top: Int, val bottom: Int, val left: Int, val right: Int) {
    fun toJson() = linkedMapOf<String, Any?>("name" to name, "platform" to "ios", "width" to width, "height" to height, "ratio" to scale,
        "insets" to listOf(top, right, bottom, left))
}

object AppleDevices {
    val all = listOf(
        AppleDevice("iPad (A16)", 820, 1180, 2.0, 32, 25, 0, 0),
        AppleDevice("iPad Air 11-inch (M4)", 820, 1180, 2.0, 32, 25, 0, 0),
        AppleDevice("iPad Air 13-inch (M4)", 1024, 1366, 2.0, 32, 25, 0, 0),
        AppleDevice("iPad Pro 11-inch (M5)", 834, 1210, 2.0, 32, 25, 0, 0),
        AppleDevice("iPad Pro 13-inch (M5)", 1032, 1376, 2.0, 32, 25, 0, 0),
        AppleDevice("iPad mini (A17 Pro)", 744, 1133, 2.0, 32, 25, 0, 0),
        AppleDevice("iPhone 12 mini", 375, 812, 2.88, 50, 34, 0, 0),
        AppleDevice("iPhone 13 mini", 375, 812, 2.88, 50, 34, 0, 0),
        AppleDevice("iPhone 14", 390, 844, 3.0, 47, 34, 0, 0),
        AppleDevice("iPhone 15", 393, 852, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 15 Plus", 430, 932, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 15 Pro", 393, 852, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 15 Pro Max", 430, 932, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 16", 393, 852, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 16 Plus", 430, 932, 3.0, 59, 34, 0, 0),
        AppleDevice("iPhone 16 Pro", 402, 874, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 16 Pro Max", 440, 956, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 16e", 390, 844, 3.0, 47, 34, 0, 0),
        AppleDevice("iPhone 17", 402, 874, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 17 Pro", 402, 874, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 17 Pro Max", 440, 956, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 17e", 390, 844, 3.0, 47, 34, 0, 0),
        AppleDevice("iPhone 18 Pro", 402, 874, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone 18 Pro Max", 440, 956, 3.0, 62, 34, 0, 0),
        AppleDevice("iPhone Air", 420, 912, 3.0, 68, 34, 0, 0),
        AppleDevice("iPhone Duo", 466, 678, 3.0, 0, 34, 0, 84),
        AppleDevice("iPhone SE (3rd generation)", 375, 667, 2.0, 20, 0, 0, 0),
    )

    /** By name, ignoring case; `*` globs ("iPhone 17*"). */
    fun matching(name: String): List<AppleDevice> {
        val pattern = Regex("^" + Regex.escape(name).replace("*", "\\E.*\\Q") + "$", RegexOption.IGNORE_CASE)
        return all.filter { pattern.matches(it.name) }
    }
}
