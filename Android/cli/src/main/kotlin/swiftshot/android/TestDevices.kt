package swiftshot.android

import swiftshot.android.shared.Json
import java.util.Locale
import kotlin.math.roundToInt

/** A screen as a snapshot test renders it: size in px (after orientation), layout density, shape. */
data class Screen(val widthPx: Int, val heightPx: Int, val densityDpi: Int, val round: Boolean = false, val landscape: Boolean = false)

/** Settings a test sets alongside its device; null when the test doesn't say. */
data class TestSettings(val locale: String? = null, val night: Boolean? = null, val fontScale: Double? = null)

/** Where a test's device came from. */
sealed interface DeviceSource {
    /** Read from the test: `DeviceConfig.PIXEL_5`, `w411dp-h891dp-xxhdpi`. */
    data class Read(val screen: Screen, val label: String) : DeviceSource
    /** The test doesn't pick one, so the tool's default. */
    data class ToolDefault(val screen: Screen, val tool: SnapshotTool) : DeviceSource
    data object FromPreview : DeviceSource
    data class Unresolved(val expression: String) : DeviceSource
}

/**
 * The exact screens Paparazzi's `DeviceConfig` and Robolectric's qualifiers render, from the values in
 * `paparazzi-devices.json` (taken from Paparazzi's and Roborazzi's sources, tags recorded in the file).
 */
object TestDevices {
    private val data by lazy {
        Json.parse(TestDevices::class.java.getResourceAsStream("/paparazzi-devices.json")!!.bufferedReader().readText()) as Map<*, *>
    }
    private val paparazzi get() = data["paparazzi"] as Map<*, *>
    private val robolectric get() = data["robolectric"] as Map<*, *>
    private val presets get() = paparazzi["presets"] as Map<*, *>
    private val constants get() = (data["robolectricDeviceQualifiers"] as Map<*, *>)["constants"] as Map<*, *>
    private fun Any?.int() = (this as Number).toInt()

    /** Paparazzi's `DeviceConfig` fields that decide the screen. */
    private data class Config(val width: Int, val height: Int, val density: Int, val landscape: Boolean, val round: Boolean) {
        // Paparazzi's currentWidth/currentHeight: portrait puts the short side across, landscape the long side.
        fun screen() = Screen(
            if (landscape) maxOf(width, height) else minOf(width, height),
            if (landscape) minOf(width, height) else maxOf(width, height), density, round, landscape,
        )
    }

    private fun config(m: Map<*, *>) = Config(m["width"].int(), m["height"].int(), m["density"].int(), m["orientation"] == "landscape", m["round"] as Boolean)

    fun paparazziPreset(name: String): Screen? = (presets[name] as Map<*, *>?)?.let { config(it).screen() }

    /** `Paparazzi()` without a `deviceConfig` renders `DeviceConfig.NEXUS_5`. */
    fun paparazziDefault(): Screen = paparazziPreset(paparazzi["default"] as String)!!

    /** Robolectric without qualifiers: the `normal` screen size at mdpi. */
    fun robolectricDefault(): Screen = (parseQualifiers("").first as DeviceSource.ToolDefault).screen

    private val ignored = setOf(
        "xdpi", "ydpi", "uiMode", "layoutDirection", "ratio", "size", "keyboard", "touchScreen", "keyboardState",
        "softButtons", "navigation", "released",
    )

    fun parseDeviceConfig(expression: String): Pair<DeviceSource, TestSettings> {
        val expr = expression.trim()
        val unresolved = DeviceSource.Unresolved(expr) to TestSettings()
        val m = Regex("""^(?:app\.cash\.paparazzi\.)?DeviceConfig(?:\.(\w+)(\s*\.\s*copy\s*\((.*)\))?|\s*\((.*)\))$""", RegexOption.DOT_MATCHES_ALL)
            .matchEntire(expr) ?: return unresolved
        val preset = m.groups[1]?.value
        var c = config((if (preset != null) presets[preset] else paparazzi["constructor"]) as Map<*, *>? ?: return unresolved)
        val args = split(m.groups[3]?.value ?: m.groups[4]?.value ?: "") ?: return unresolved
        var settings = TestSettings()
        var screenArgs = false
        for (arg in args) {
            val kv = Regex("""^(\w+)\s*=\s*(.+)$""", RegexOption.DOT_MATCHES_ALL).matchEntire(arg) ?: return unresolved
            val (name, value) = kv.destructured
            fun enum(type: String) = Regex("""^(?:[\w.]*\.)?$type\.(\w+)$""").matchEntire(value)?.groupValues?.get(1)
            when (name) {
                "screenWidth" -> c = c.copy(width = value.toIntOrNull() ?: return unresolved)
                "screenHeight" -> c = c.copy(height = value.toIntOrNull() ?: return unresolved)
                "density" -> c = c.copy(density = density(value) ?: return unresolved)
                "orientation" -> c = c.copy(landscape = when (enum("ScreenOrientation")) { "LANDSCAPE" -> true; "PORTRAIT" -> false; else -> return unresolved })
                "screenRound" -> c = c.copy(round = when (if (value == "null") "NOTROUND" else enum("ScreenRound")) { "ROUND" -> true; "NOTROUND" -> false; else -> return unresolved })
                "nightMode" -> settings = settings.copy(night = when (enum("NightMode")) { "NIGHT" -> true; "NOTNIGHT" -> false; else -> return unresolved })
                "locale" -> settings = settings.copy(locale = if (value == "null") null else Regex("""^"([\w+-]+)"$""").matchEntire(value)?.groupValues?.get(1)?.let(::bcp47) ?: return unresolved)
                "fontScale" -> settings = settings.copy(fontScale = Regex("""^(\d+(?:\.\d+)?)[fF]?$""").matchEntire(value)?.groupValues?.get(1)?.toDouble() ?: return unresolved)
                in ignored -> {}
                else -> return unresolved
            }
            if (name in setOf("screenWidth", "screenHeight", "density", "orientation", "screenRound")) screenArgs = true
        }
        val label = if (preset != null && !screenArgs) "DeviceConfig.$preset" else expr.replace(Regex("\\s+"), " ").replace("( ", "(").replace(", )", ")").replace(" )", ")")
        return DeviceSource.Read(c.screen(), label) to settings
    }

    private fun density(value: String): Int? {
        Regex("""^(?:[\w.]*\.)?Density\.create\((\d+)\)$""").matchEntire(value)?.let { return it.groupValues[1].toInt() }
        Regex("""^(?:[\w.]*\.)?Density\.DPI_(\d+)$""").matchEntire(value)?.let { return it.groupValues[1].toInt() }
        val name = Regex("""^(?:[\w.]*\.)?Density\.(\w+)$""").matchEntire(value)?.groupValues?.get(1) ?: return null
        return (paparazzi["densities"] as Map<*, *>)[name]?.int()
    }

    /** Named arguments split at top-level commas; null for anything that isn't plain `name = value`. */
    private fun split(args: String): List<String>? {
        val out = mutableListOf<String>()
        var depth = 0; var quoted = false; var start = 0
        for ((i, ch) in args.withIndex()) when {
            ch == '"' -> quoted = !quoted
            quoted -> {}
            ch == '(' -> depth++
            ch == ')' -> depth--
            ch == ',' && depth == 0 -> { out += args.substring(start, i).trim(); start = i + 1 }
        }
        if (quoted || depth != 0) return null
        out += args.substring(start).trim()
        return out.filter { it.isNotEmpty() }
    }

    /** A resource-qualifier locale (`de-rDE`, `b+sr+Latn`) as a BCP 47 tag (`de-DE`, `sr-Latn`). */
    private fun bcp47(q: String): String {
        val tag = if (q.startsWith("b+")) q.removePrefix("b+").replace('+', '-')
        else q.split('-').mapIndexed { i, p -> if (i > 0 && p.length == 3 && p[0] in "rR") p.substring(1) else p }.joinToString("-")
        return Locale.forLanguageTag(tag).toLanguageTag()
    }

    private val keywords = (
        "any ldltr ldrtl widecg nowidecg highdr lowdr car desk television appliance watch vrheadset notouch finger stylus " +
            "keysexposed keyshidden keyssoft nokeys qwerty 12key navexposed navhidden nonav dpad trackball wheel feminine masculine neuter"
        ).split(' ').toSet()

    fun parseQualifiers(qualifiers: String): Pair<DeviceSource, TestSettings> {
        val q = qualifiers.trim().removeSurrounding("\"")
        Regex("""^(?:com\.github\.takahirom\.roborazzi\.)?RobolectricDeviceQualifiers\.(\w+)$""").matchEntire(q)?.let {
            val value = constants[it.groupValues[1]] as String? ?: return DeviceSource.Unresolved(q) to TestSettings()
            val (source, settings) = parseQualifiers(value)
            return (if (source is DeviceSource.Read) source.copy(label = "RobolectricDeviceQualifiers.${it.groupValues[1]}") else source) to settings
        }
        val unresolved = DeviceSource.Unresolved(q) to TestSettings()
        if (!Regex("^[A-Za-z0-9+-]*$").matches(q)) return unresolved
        val densities = robolectric["densities"] as Map<*, *>
        val tokens = q.removePrefix("+").lowercase().split('-').filter { it.isNotEmpty() }
        val screenTokens = mutableListOf<String>()
        var wDp: Int? = null; var hDp: Int? = null; var dpi: Int? = null; var size: String? = null; var long: Boolean? = null
        var round = false; var land: Boolean? = null; var px: Pair<Int, Int>? = null
        var locale: String? = null; var night: Boolean? = null
        var i = 0
        while (i < tokens.size) {
            val t = tokens[i++]
            fun num(re: String) = Regex(re).matchEntire(t)?.groupValues?.get(1)?.toInt()
            val screen = when {
                Regex("""mcc\d+|mnc\d+|sw\d+dp|v\d+""").matches(t) || t in keywords -> false
                t.startsWith("b+") && locale == null -> { locale = bcp47(t); false }
                t.length in 2..3 && t.all(Char::isLetter) && locale == null -> {
                    val region = tokens.getOrNull(i)?.takeIf { it.length == 3 && it[0] == 'r' && it.all(Char::isLetter) }
                    if (region != null) i++
                    locale = bcp47(if (region != null) "$t-$region" else t); false
                }
                num("""w(\d+)dp""") != null -> { wDp = num("""w(\d+)dp"""); true }
                num("""h(\d+)dp""") != null -> { hDp = num("""h(\d+)dp"""); true }
                t in setOf("small", "normal", "large", "xlarge") -> { size = t; true }
                t == "long" || t == "notlong" -> { long = t == "long"; true }
                t == "round" || t == "notround" -> { round = t == "round"; true }
                t == "land" || t == "port" -> { land = t == "land"; true }
                t == "night" || t == "notnight" -> { night = t == "night"; false }
                t in densities -> { dpi = densities[t].int(); true }
                num("""(\d+)dpi""") != null -> { dpi = num("""(\d+)dpi"""); true }
                Regex("""(\d+)x(\d+)""").matches(t) -> { px = t.split('x').let { it[0].toInt() to it[1].toInt() }; true }
                else -> return unresolved
            }
            if (screen) screenTokens += t
        }
        val settings = TestSettings(locale = locale, night = night)
        // A `+` string adds to qualifiers set elsewhere (the class, robolectric.properties), so its screen isn't known.
        if (q.startsWith("+") && screenTokens.isNotEmpty()) return unresolved
        // Robolectric's DeviceConfig.applyRules: missing dp from the screen size, long stretches the default height 1.25×.
        val sizes = robolectric["screenSizes"] as Map<*, *>
        val dims = sizes[size ?: "normal"] as List<*>
        var w = wDp ?: dims[0].int()
        var h = hDp ?: if (long == true) (dims[1].int() * 1.25f).toInt() else dims[1].int()
        val density = dpi ?: robolectric["defaultDensity"].int()
        var pw = px?.first; var ph = px?.second
        val swap = (land == true && w < h) || (land == false && w > h)
        if (swap) { w = h.also { h = w }; if (pw != null) { pw = ph.also { ph = pw } } }
        // setPixels: (int) (dp * density), density = dpi * (1f / 160) in float.
        val scale = density * (1.0f / 160)
        val screen = Screen(pw ?: (w * scale).toInt(), ph ?: (h * scale).toInt(), density, round, land ?: (w > h))
        if (screenTokens.isEmpty()) return DeviceSource.ToolDefault(screen, SnapshotTool.ROBORAZZI) to settings
        return DeviceSource.Read(screen, screenTokens.joinToString("-")) to settings
    }

    /**
     * The catalog name when a device matches size, density and shape exactly (preferring one named like
     * [prefer], e.g. `PIXEL_5` or `DeviceConfig.PIXEL_5` → "Pixel 5"), else a `spec:` that renders the same px.
     */
    fun deviceName(screen: Screen, prefer: String? = null): String {
        fun key(s: String) = s.lowercase().filter(Char::isLetterOrDigit)
        val matches = Devices.all.filter { it.width == screen.widthPx && it.height == screen.heightPx && it.density == screen.densityDpi && it.round == screen.round }
        val wanted = prefer?.substringAfterLast('.')?.let(::key)
        (matches.firstOrNull { key(it.name) == wanted } ?: matches.firstOrNull())?.let { return it.name }
        val d = screen.densityDpi
        fun dp(px: Int): String {
            if (px * 160 % d == 0) return "${px * 160 / d}dp"
            val one = String.format(Locale.ROOT, "%.1f", px * 160.0 / d)
            return if ((one.toDouble() * d / 160).roundToInt() == px) "${one}dp" else "${px}px"
        }
        return "spec:width=${dp(screen.widthPx)},height=${dp(screen.heightPx)},dpi=$d" +
            (if (screen.round) ",isRound=true" else "") + (if (screen.landscape) ",orientation=landscape" else "")
    }
}
