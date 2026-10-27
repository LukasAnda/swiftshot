package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File

/** Per-screenshot settings: the first rule whose `preview` matches wins. */
data class ScreenRule(
    val preview: String,
    val appearances: List<String>? = null,
    val languages: List<String>? = null,
    val devices: List<String>? = null,
    val fontScales: List<Double>? = null,
    val fullLength: Boolean? = null,
    val delay: Double? = null,
    val skip: Boolean = false,
) {
    fun matches(name: String) = glob(preview).matches(name)
}

fun glob(pattern: String) = Regex(pattern.split('*').joinToString(".*") { Regex.escape(it) }, RegexOption.IGNORE_CASE)

class Options {
    var command = "run"
    var commandArgs = mutableListOf<String>()
    var projectDir = "."
    var modules: List<String> = emptyList()
    var variant = "debug"
    var devices: List<String> = emptyList()
    var watchDevices: List<String> = emptyList()
    var languages = listOf("en-US")
    var appearances = listOf("light")
    var fontScales = listOf(1.0)
    var previews: List<String> = emptyList()
    var output = "screenshots"
    var clear = false
    var html = true
    var layout = "swiftshot"
    var fullLength = false
    var delay = 0.0
    var systemUi = "preview"
    /** An explicit theme for every preview; otherwise each module's application theme. */
    var theme: String? = null
    var roundCorners = "black"
    var parallel = 0
    var gradleArgs: List<String> = emptyList()
    var javaHome: String? = null
    var screens: List<ScreenRule> = emptyList()
    var verbose = false
    var force = false
    var frame = "none"
    var config: String? = null

    fun rule(preview: String) = screens.firstOrNull { it.matches(preview) }

    companion object {
        val usage = """
            swiftshot (Android) — Play Store screenshots straight from your Jetpack Compose @Previews.

            USAGE
              swiftshot [run|list|devices] [options]

            COMMANDS
              run       Build, render every preview for every device × language × appearance (default)
              list      Build and print the previews that were found
              devices   List the devices and their screens
              init      Write a swiftshot.json for the project here: modules, languages and Play devices
                        detected (alias auto-setup; --force overwrites an existing one)

            PROJECT
              --project-dir <path>                  Gradle project (default: .)
              --modules ":app,:wear"                Modules to render (default: every Android module with previews)
              --variant <name>                      Build variant (default: debug)
              --gradle-arg <arg>                    Extra Gradle argument (repeatable)
              --java-home <path>                    JDK 21+ for the renderer (default: JAVA_HOME, then Android Studio's)

            MATRIX
              --devices "Pixel 10 Pro,Pixel 9 Pro Fold,Pixel Tablet"   Phones, foldables, tablets (default: Pixel 10 Pro, Pixel Tablet)
              --watch-devices "Wear OS Large Round"                    For Wear OS modules (default: Wear OS Large Round)
              --languages "en-US,de-DE"             Default: en-US
              --appearances "light,dark"            Default: light
              --font-scales "1,1.3,2"               Default: 1
              --previews "Welcome,Stats*"           Only previews matching these names or * globs
              --screen "<preview>: key=value …"     Per-screenshot settings (repeatable), e.g.
                                                    --screen "Stats: languages=de-DE devices=Pixel*"

            OUTPUT
              --output <dir>                        Default: screenshots
              --layout swiftshot|fastlane           fastlane: metadata/android/<locale>/images/<type>Screenshots
              --clear                               Delete existing screenshots first
              --no-html                             Do not write screenshots.html
              --full-length                         Grow scrolling screens to their whole content
              --delay <seconds>                     Advance the clock before capture (animations)
              --system-ui preview|always|never      Status and navigation bars (default: as the preview says)
              --frame plain|none                    Put each screenshot in its device (Android Studio's device art)
              --round-corners black|transparent     Outside round watch screens (default: black, as Play requires)
              --parallel <n>                        Renderer processes (default: from cores and memory)

              --config <file>                       Default: ./swiftshot.json
              -v, --verbose
        """.trimIndent()

        fun parse(args: List<String>): Options {
            val o = Options()
            var i = 0
            val positional = mutableListOf<String>()
            val flags = mutableListOf<Pair<String, String?>>()
            while (i < args.size) {
                val a = args[i]
                if (a.startsWith("-")) {
                    val boolean = a in setOf("--clear", "--no-html", "--full-length", "-v", "--verbose", "-h", "--help", "--force")
                    val (key, inline) = a.split('=', limit = 2).let { it[0] to it.getOrNull(1) }
                    val value = if (boolean || inline != null) inline else args.getOrNull(++i) ?: error("$a needs a value")
                    flags += key to value
                } else positional += a
                i++
            }
            if (flags.any { it.first == "-h" || it.first == "--help" }) { println(usage); kotlin.system.exitProcess(0) }
            positional.firstOrNull()?.let { o.command = it; o.commandArgs += positional.drop(1) }
            o.config = flags.lastOrNull { it.first == "--config" }?.second
            o.projectDir = flags.lastOrNull { it.first == "--project-dir" }?.second ?: "."
            val configFile = File(o.config ?: File(o.projectDir, "swiftshot.json").path)
            if (configFile.isFile) o.applyConfig(Json.parse(configFile.readText()) as Map<*, *>, configFile.absoluteFile.parentFile)
            else require(o.config == null) { "No config at ${o.config}" }
            // An explicit --config's project_dir is only a default: --project-dir still wins.
            if (o.config != null) flags.lastOrNull { it.first == "--project-dir" }?.second?.let { o.projectDir = it }
            val rules = mutableListOf<ScreenRule>()
            for ((k, v) in flags) when (k) {
                "--modules" -> o.modules = list(v)
                "--variant" -> o.variant = v!!
                "--devices" -> o.devices = list(v)
                "--watch-devices" -> o.watchDevices = list(v)
                "--languages" -> o.languages = list(v)
                "--appearances" -> o.appearances = list(v)
                "--font-scales" -> o.fontScales = list(v).map(String::toDouble)
                "--previews" -> o.previews = list(v)
                "--output" -> o.output = v!!
                "--layout" -> o.layout = v!!
                "--clear" -> o.clear = true
                "--no-html" -> o.html = false
                "--full-length" -> o.fullLength = true
                "--delay" -> o.delay = v!!.toDouble()
                "--system-ui" -> o.systemUi = v!!
                "--round-corners" -> o.roundCorners = v!!
                "--parallel" -> o.parallel = v!!.toInt()
                "--gradle-arg" -> o.gradleArgs = o.gradleArgs + v!!
                "--java-home" -> o.javaHome = v
                "--theme" -> o.theme = v!!
                "--screen" -> rules += screenFlag(v!!)
                "-v", "--verbose" -> o.verbose = true
                "--force" -> o.force = true
                "--frame" -> o.frame = v!!
                "--config", "--project-dir" -> Unit
                else -> error("Unknown option $k. `swiftshot --help` lists them.")
            }
            if (rules.isNotEmpty()) o.screens = rules + o.screens
            o.validate()
            return o
        }

        private fun list(v: String?) = v!!.split(',').map(String::trim).filter(String::isNotEmpty)

        /** `"Stats: languages=de-DE,ja devices=Pixel*"` */
        fun screenFlag(v: String): ScreenRule {
            val colon = v.indexOf(':')
            require(colon > 0) { "--screen needs \"<preview>: key=value …\"" }
            val values = v.substring(colon + 1).trim().split(Regex("\\s+")).filter(String::isNotEmpty).associate {
                val kv = it.split('=', limit = 2); require(kv.size == 2) { "--screen: bad \"$it\"" }; kv[0] to kv[1]
            }
            return rule(v.substring(0, colon).trim(), values.mapValues { (k, s) ->
                when (k) {
                    "skip", "full_length" -> s.toBoolean()
                    "delay" -> s.toDouble()
                    else -> list(s)
                }
            })
        }

        fun rule(preview: String, m: Map<String, Any?>): ScreenRule {
            for (k in m.keys) require(k in setOf("preview", "appearances", "languages", "devices", "font_scales", "full_length", "delay", "skip")) {
                "screens: unknown key \"$k\""
            }
            @Suppress("UNCHECKED_CAST")
            return ScreenRule(
                preview = preview,
                appearances = (m["appearances"] as List<*>?)?.map { it.toString() },
                languages = (m["languages"] as List<*>?)?.map { it.toString() },
                devices = (m["devices"] as List<*>?)?.map { it.toString() },
                fontScales = (m["font_scales"] as List<*>?)?.map { it.toString().toDouble() },
                fullLength = m["full_length"] as Boolean?,
                delay = (m["delay"] as Number?)?.toDouble(),
                skip = m["skip"] as Boolean? ?: false,
            )
        }
    }

    private fun applyConfig(c: Map<*, *>, base: File) {
        fun strings(k: String) = (c[k] as List<*>?)?.map { it.toString() }
        for (k in c.keys) require(k in configKeys) { "swiftshot.json: unknown key \"$k\"" }
        (c["project_dir"] as String?)?.let { projectDir = File(base, it).path }
        strings("modules")?.let { modules = it }
        (c["variant"] as String?)?.let { variant = it }
        strings("devices")?.let { devices = it }
        strings("watch_devices")?.let { watchDevices = it }
        strings("languages")?.let { languages = it }
        strings("appearances")?.let { appearances = it }
        (c["font_scales"] as List<*>?)?.let { l -> fontScales = l.map { it.toString().toDouble() } }
        strings("previews")?.let { previews = it }
        (c["output_directory"] as String?)?.let { output = File(base, it).path }
        (c["clear_previous_screenshots"] as Boolean?)?.let { clear = it }
        (c["html"] as Boolean?)?.let { html = it }
        (c["layout"] as String?)?.let { layout = it }
        (c["full_length"] as Boolean?)?.let { fullLength = it }
        (c["delay"] as Number?)?.let { delay = it.toDouble() }
        (c["system_ui"] as String?)?.let { systemUi = it }
        (c["android_theme"] as String?)?.let { theme = it }
        (c["round_corners"] as String?)?.let { roundCorners = it }
        (c["frame"] as String?)?.let { frame = it }
        (c["parallel"] as Number?)?.let { parallel = it.toInt() }
        strings("gradle_args")?.let { gradleArgs = it }
        (c["java_home"] as String?)?.let { javaHome = it }
        (c["screens"] as List<*>?)?.let { l -> screens = l.map { val m = it as Map<*, *>; rule(m["preview"] as String, m.mapKeys { e -> e.key.toString() }) } }
    }

    private fun validate() {
        require(command in setOf("run", "list", "devices", "init", "auto-setup", "emit-devices")) { "Unknown command \"$command\"" }
        for (a in appearances) require(a == "light" || a == "dark") { "appearances: light or dark, not \"$a\"" }
        require(layout == "swiftshot" || layout == "fastlane") { "layout: swiftshot or fastlane" }
        require(systemUi in setOf("preview", "always", "never")) { "system_ui: preview, always or never" }
        require(frame == "none" || frame == "plain") { "frame: plain or none (App Store-style frames are iOS only)" }
        require(roundCorners == "black" || roundCorners == "transparent") { "round_corners: black or transparent" }
        for (s in fontScales) require(s in 0.5..3.0) { "font_scales: $s is outside 0.5…3" }
    }

    /** Keys shared with the iOS side are accepted and ignored here, so one file can serve both. */
    private val configKeys = setOf(
        "project_dir", "modules", "variant", "devices", "watch_devices", "languages", "appearances", "font_scales",
        "previews", "output_directory", "clear_previous_screenshots", "html", "layout", "full_length", "delay",
        "system_ui", "android_theme", "round_corners", "frame", "parallel", "gradle_args", "java_home", "screens",
        "platform", "android",
    )
}
