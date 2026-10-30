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
    /** The rule's devices, languages, appearances and font scales win over the preview's own. */
    val overridePreview: Boolean = false,
    /** verify: replaces the global `tolerance` for these screenshots. */
    val tolerance: Tolerance? = null,
    /** verify: `[x, y, w, h]` in points/dp whose pixels never differ. */
    val ignoreRegions: List<List<Double>>? = null,
) {
    fun matches(name: String) = glob(preview).matches(name)
    /** By display name, or by the fully qualified function (`com.example.UiKt.Checkout`) when the pattern has a `.`. */
    fun matches(p: Preview) = matches(p.name) || '.' in preview && matches(p.composable)
}

/** A usage error: wrong flags or settings for the command (exit 64 for verify and record). */
class UsageError(message: String) : IllegalArgumentException(message)

fun glob(pattern: String) = Regex(pattern.split('*').joinToString(".*") { Regex.escape(it) }, RegexOption.IGNORE_CASE)

class Options {
    var command = "run"
    var commandArgs = mutableListOf<String>()
    var projectDir = "."
    var modules: List<String> = emptyList()
    var variant = "debug"
    var devices: List<String> = emptyList()
    var watchDevices: List<String> = emptyList()
    var desktopDevices: List<String> = emptyList()
    var iosDevices: List<String> = emptyList()
    var iosVersions: List<String> = emptyList()
    /** android, desktop (and ios for Compose Multiplatform); empty: every platform the project has. */
    var platforms: List<String> = emptyList()
    var flutterRoot: String? = null
    var flutterIos = "exact"
    var acceptBezelLicense = false
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
    /** Said once before the run (iOS-only settings this renderer leaves to the Mac tool). */
    val notes = mutableListOf<String>()
    var frame = "none"
    var config: String? = null
    /** png; jpeg is the iOS tool's, and verify/record compare PNGs only. */
    var format = "png"
    /** verify/record: where the baseline lives (default screenshots-baseline) and where verify writes its report. */
    var baselineDirectory = "screenshots-baseline"
    var reportDirectory: String? = null
    /** verify: the global tolerance (null: exact, or channel delta 1 for booted simulators). */
    var tolerance: Tolerance? = null
    /** Whether `--frame` was passed (a config's frame is skipped by verify/record, a flag is an error). */
    private var frameFlag = false
    /** Where relative output, baseline and report paths from flags resolve: Flutter runs resolve them in the project. */
    private fun resolve(path: String, flutter: Boolean) = File(path).let { if (it.isAbsolute) it else if (flutter) File(File(projectDir).absoluteFile, path) else it.absoluteFile }.normalize()

    /** The output directory as the runner writes it (Flutter: relative to the project). */
    fun outputDir(flutter: Boolean): File = resolve(output, flutter)
    fun baselineDir(flutter: Boolean): File = resolve(baselineDirectory, flutter)
    fun reportDir(flutter: Boolean): File = reportDirectory?.let { resolve(it, flutter) } ?: File(outputDir(flutter).path + "-report")

    fun rule(p: Preview) = screens.firstOrNull { it.matches(p) }
    fun rule(preview: String) = screens.firstOrNull { it.matches(preview) }

    companion object {
        /** Flags without a value (parse and [command] read the command line alike). */
        val BOOLEAN_FLAGS = setOf("--clear", "--no-html", "--full-length", "-v", "--verbose", "-h", "--help", "--force", "--accept-bezel-license")

        val usage = """
            swiftshot — screenshot tests and Play Store screenshots from Jetpack Compose and Compose
            Multiplatform @Previews (Android and desktop; Compose Multiplatform iOS needs a Mac).

            USAGE
              swiftshot [run|verify|record|list|devices|init] [options]

            COMMANDS
              run       Build, render every preview for every device × language × appearance (default)
              verify    Render as run does, then compare with the baseline: exit 0 same, 1 differences,
                        2 errors, 64 usage error; the report goes to <output>-report
              record    Render as run does and write the screenshots into the baseline
              list      Build and print the previews that were found
              devices   List the devices and their screens
              init      Write a swiftshot.json for the project here: modules, languages and Play devices
                        detected (alias auto-setup; --force overwrites an existing one)

            PROJECT
              --project-dir <path>                  Gradle project (default: .)
              --platform android                    Accepted as on the Mac (iOS projects need the Mac tool)
              --modules ":app,:wear"                Modules to render (default: every Android module with previews)
              --variant <name>                      Build variant (default: debug)
              --gradle-arg <arg>                    Extra Gradle argument (repeatable)
              --java-home <path>                    JDK 21+ for the renderer (default: JAVA_HOME, then Android Studio's)
              --flutter-root <path>                 Flutter SDK for Flutter projects (default: FLUTTER_ROOT, fvm, then flutter on PATH)
              --flutter-ios exact|headless          Flutter on iPhones and iPads: Flutter's iOS engine on a Mac with Xcode
                                                    (exact, the default) or the headless renderer (faster, any OS)

            MATRIX
              --devices "Pixel 10 Pro,Pixel 9 Pro Fold,Pixel Tablet"   Phones, foldables, tablets (default: Pixel 10 Pro, Pixel Tablet)
              --watch-devices "Wear OS Large Round"                    For Wear OS modules (default: Wear OS Large Round)
              --desktop-devices "Desktop 1440×900 @2x"                 Window sizes for Compose Multiplatform desktop
              --ios-devices "iPhone 17 Pro Max,iPad Pro 13-inch (M5)" Compose Multiplatform iOS devices (macOS)
              --ios "27.0"                          iOS runtimes for Compose Multiplatform (default: newest installed)
              --platforms android,desktop,ios       Compose Multiplatform targets to render (default: all the project has)
              --languages "en-US,de-DE"             Default: en-US
              --appearances "light,dark"            Default: light
              --font-scales "1,1.3,2"               Default: 1
              --previews "Welcome,Stats*"           Only previews matching these names or * globs
              --screen "<preview>: key=value …"     Per-screenshot settings (repeatable), e.g.
                                                    --screen "Stats: languages=de-DE devices=Pixel*"
                                                    <preview> is a name, a * glob or a full function
                                                    (com.example.UiKt.Stats); override_preview=true
                                                    lets the rule beat the preview's own device/locale/uiMode/fontScale

            OUTPUT
              --output <dir>                        Default: screenshots
              --layout swiftshot|fastlane           fastlane: <output>/<locale>/images/<type>Screenshots
              --clear                               Delete existing screenshots first
              --no-html                             Do not write screenshots.html
              --full-length                         Grow scrolling screens to their whole content
              --delay <seconds>                     Advance the clock before capture (animations)
              --system-ui preview|always|never      Status and navigation bars (default: as the preview says)
              --frame plain|none                    Put each screenshot in its device (Android Studio's device art;
                                                    Apple's bezels for iPhones and iPads in Flutter projects, on a Mac)
              --accept-bezel-license                Accept Apple's bezel license (asked once) for iPhone and iPad frames
              --round-corners black|transparent     Outside round watch screens (default: black, as Play requires)
              --parallel <n>                        Renderer processes (default: from cores and memory)

            BASELINE (verify, record; PNG only, no frames)
              --baseline-directory <dir>            Default: screenshots-baseline
              --report-directory <dir>              Default: <output>-report
              (swiftshot.json: "tolerance": {"pixels": n, "max_channel_delta": d}; per screen also
               "tolerance" and "ignore_regions": [[x, y, w, h]] in dp)

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
                    val boolean = a in BOOLEAN_FLAGS
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
                "--desktop-devices" -> o.desktopDevices = list(v)
                "--ios-devices" -> o.iosDevices = list(v)
                "--ios" -> o.iosVersions = list(v)
                "--platforms" -> o.platforms = list(v)
                "--flutter-root" -> o.flutterRoot = v
                "--flutter-ios" -> o.flutterIos = v!!
                "--accept-bezel-license" -> o.acceptBezelLicense = true
                // As the Mac tool takes it: android is this renderer, ios needs the Mac one.
                "--platform" -> when (v) {
                    "android" -> {}
                    "ios" -> throw CliError(iosOnly(null))
                    else -> throw CliError("--platform: android or ios, not \"$v\"")
                }
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
                "--frame" -> { o.frame = v!!; o.frameFlag = true }
                "--format" -> o.format = v!!
                "--baseline-directory" -> o.baselineDirectory = v!!
                "--report-directory" -> o.reportDirectory = v!!
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
                    "skip", "full_length", "override_preview" -> s.toBoolean()
                    "delay" -> s.toDouble()
                    else -> list(s)
                }
            })
        }

        /** The command a command line runs (its first positional argument), as [parse] reads it. */
        fun command(args: List<String>): String {
            var i = 0
            while (i < args.size) {
                val a = args[i]
                if (!a.startsWith("-")) return a
                val boolean = a in BOOLEAN_FLAGS
                if (!boolean && '=' !in a) i++
                i++
            }
            return "run"
        }

        /** `{"pixels": n, "max_channel_delta": d}`: non-negative integers, nothing else. */
        fun tolerance(v: Any?, where: String): Tolerance {
            require(v is Map<*, *>) { "$where: an object like {\"pixels\": 5, \"max_channel_delta\": 1}" }
            for (k in v.keys) require(k == "pixels" || k == "max_channel_delta") { "$where: unknown key \"$k\" (pixels, max_channel_delta)" }
            fun count(k: String): Int {
                val n = v[k] ?: return 0
                require(n is Number && n.toDouble() >= 0 && n.toDouble() == Math.floor(n.toDouble()) && n.toDouble() <= Int.MAX_VALUE) { "$where.$k: a whole number ≥ 0, not $n" }
                return n.toInt()
            }
            return Tolerance(pixels = count("pixels"), maxChannelDelta = count("max_channel_delta"))
        }

        private fun regions(v: Any?, where: String): List<List<Double>> {
            require(v is List<*>) { "$where: a list of [x, y, w, h]" }
            return v.map { r ->
                require(r is List<*> && r.size == 4 && r.all { it is Number }) { "$where: each region is [x, y, w, h] in points/dp, not $r" }
                val d = r.map { (it as Number).toDouble() }
                require(d[2] >= 0 && d[3] >= 0) { "$where: width and height must be ≥ 0" }
                d
            }
        }

        fun rule(preview: String, m: Map<String, Any?>): ScreenRule {
            for (k in m.keys) require(k in setOf("preview", "appearances", "languages", "devices", "font_scales", "full_length", "delay", "skip", "override_preview", "tolerance", "ignore_regions")) {
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
                overridePreview = m["override_preview"] as Boolean? ?: false,
                tolerance = m["tolerance"]?.let { tolerance(it, "screens[$preview].tolerance") },
                ignoreRegions = m["ignore_regions"]?.let { regions(it, "screens[$preview].ignore_regions") },
            )
        }
    }

    private fun applyConfig(c: Map<*, *>, base: File) {
        fun strings(k: String) = (c[k] as List<*>?)?.map { it.toString() }
        val ios = c.keys.map { it.toString() }.filter { it in iosKeys }
        if (ios.isNotEmpty()) {
            // A config written for the iOS tool: here, the Gradle project's targets are rendered
            // and the iOS settings stay for a Mac.
            if (!File(base, "gradlew").isFile && !File(projectDir, "gradlew").isFile) throw CliError(iosOnly(base))
            notes += "swiftshot.json: ${ios.joinToString(", ")} ${if (ios.size == 1) "is" else "are"} for iOS on a Mac; ignored here"
        }
        for (k in c.keys) require(k in configKeys || k in iosKeys) { "swiftshot.json: unknown key \"$k\"" }
        if (c["frame"] == "appstore") notes += "swiftshot.json: App Store frames are iOS only; Android screenshots are framed with plain device art"
        (c["project_dir"] as String?)?.let { projectDir = File(base, it).path }
        strings("modules")?.let { modules = it }
        (c["variant"] as String?)?.let { variant = it }
        strings("devices")?.let { devices = it }
        strings("watch_devices")?.let { watchDevices = it }
        strings("desktop_devices")?.let { desktopDevices = it }
        strings("ios_devices")?.let { iosDevices = it }
        strings("ios_versions")?.let { iosVersions = it }
        strings("platforms")?.let { platforms = it }
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
        (c["frame"] as String?)?.let { frame = if (it == "appstore") "plain" else it }
        (c["parallel"] as Number?)?.let { parallel = it.toInt() }
        strings("gradle_args")?.let { gradleArgs = it }
        (c["java_home"] as String?)?.let { javaHome = it }
        (c["flutter_root"] as String?)?.let { flutterRoot = File(base, it).path }
        (c["flutter_ios"] as String?)?.let { flutterIos = it }
        (c["accept_bezel_license"] as Boolean?)?.let { acceptBezelLicense = it }
        (c["baseline_directory"] as String?)?.let { baselineDirectory = File(base, it).path }
        (c["report_directory"] as String?)?.let { reportDirectory = File(base, it).path }
        c["tolerance"]?.let { tolerance = tolerance(it, "tolerance") }
        (c["screens"] as List<*>?)?.let { l -> screens = l.map { val m = it as Map<*, *>; rule(m["preview"] as String, m.mapKeys { e -> e.key.toString() }) } }
    }

    private fun validate() {
        if (command in setOf("frame", "calibrate", "emit-table")) throw CliError("`swiftshot $command` is part of the iOS tool and needs a Mac with Xcode.")
        require(command in setOf("run", "verify", "record", "list", "devices", "init", "auto-setup", "emit-devices")) { "Unknown command \"$command\"" }
        if (command == "verify" || command == "record") {
            if (format != "png") throw UsageError("$command compares plain PNG screenshots; --format $format can't be used with it (drop --format, or use run).")
            if (frameFlag && frame != "none") throw UsageError("$command compares plain screenshots; device frames aren't written (drop --frame, or use run).")
            // A config's frame is for `run`: verify and record skip framing.
            frame = "none"
        } else require(format == "png") { "--format: png (JPEG is the iOS tool's)" }
        for (a in appearances) require(a == "light" || a == "dark") { "appearances: light or dark, not \"$a\"" }
        require(layout == "swiftshot" || layout == "fastlane") { "layout: swiftshot or fastlane" }
        require(systemUi in setOf("preview", "always", "never")) { "system_ui: preview, always or never" }
        require(frame == "none" || frame == "plain") { "frame: plain or none (App Store-style frames are iOS only)" }
        require(roundCorners == "black" || roundCorners == "transparent") { "round_corners: black or transparent" }
        for (p in platforms) require(p in setOf("android", "desktop", "ios")) { "platforms: android, desktop or ios, not \"$p\"" }
        require(flutterIos == "exact" || flutterIos == "headless") { "flutter_ios: exact or headless" }
        for (s in fontScales) require(s in 0.5..3.0) { "font_scales: $s is outside 0.5…3" }
    }

    /** The iOS tool's keys that mean nothing here (its config can be shared with a Gradle project). */
    private val iosKeys = setOf(
        "project", "workspace", "scheme", "configuration", "app", "derived_data", "xcodebuild_args", "mode", "format",
        "settle_frames", "shutdown_simulators", "download_missing_runtimes", "status_bar", "parallel_languages", "timeout",
        "device_set", "watch_scheme", "watch_app", "watchos_versions", "content_size", "text_sizes",
        "allow_unsupported_devices", "device_templates", "template_cache", "no_boot", "verbose", "frame_color", "framefile",
        "frame_background", "frame_cache", "frame_output",
    )

    /** The Android keys; unknown ones are rejected, so typos surface. */
    private val configKeys = setOf(
        "project_dir", "modules", "variant", "devices", "watch_devices", "desktop_devices", "ios_devices", "ios_versions", "platforms", "languages", "appearances", "font_scales",
        "previews", "output_directory", "clear_previous_screenshots", "html", "layout", "full_length", "delay",
        "system_ui", "android_theme", "round_corners", "frame", "parallel", "gradle_args", "java_home", "flutter_root", "flutter_ios", "accept_bezel_license", "screens",
        "platform", "android", "baseline_directory", "report_directory", "tolerance",
    )
}
