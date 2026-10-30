package swiftshot.android

import java.io.File

/**
 * swiftshot-report.json as docs/wiki/Baseline-format.md extends it: per-screenshot `id`, `platform` and `scale`,
 * errors as `{"id", "message"}`, the run's `scope` and `fingerprint`; canonical JSON.
 */
object RunReport {
    /** A screenshot's id: its path relative to the output directory, `/`-separated, without `.png`. */
    fun id(output: File, file: File): String = file.relativeTo(output).invariantSeparatorsPath.removeSuffix(".png")

    /** The id of a file under [output], or null when it lies elsewhere. */
    fun idOrNull(output: File, file: File): String? {
        val f = (if (file.isAbsolute) file else File(output, file.path)).normalize()
        return f.relativeToOrNull(output.normalize())?.invariantSeparatorsPath?.takeIf { !it.startsWith("..") && it.endsWith(".png") }?.removeSuffix(".png")
    }

    fun write(
        output: File, platform: String?, seconds: Double, screenshots: List<Map<String, Any?>>, errors: List<Map<String, Any?>>,
        scope: Map<String, Any?>, fingerprint: Map<String, Map<String, Any?>>,
    ) {
        output.mkdirs()
        val report = linkedMapOf<String, Any?>(
            "totalSeconds" to seconds,
            "screenshots" to screenshots.sortedWith(compareBy(CanonicalJson.utf8) { it["id"] as String }),
            "errors" to errors, "scope" to scope, "fingerprint" to fingerprint,
        )
        platform?.let { report["platform"] = it }
        File(output, "swiftshot-report.json").writeText(CanonicalJson.pretty(report))
    }

    /** A run that failed as a whole (no screenshots): one error without id. */
    fun writeFailure(output: File, platform: String, message: String, seconds: Double) =
        write(output, platform, seconds, emptyList(), listOf(mapOf("message" to message)), emptyMap(), emptyMap())
}

/**
 * A run's `scope`: the requested matrix ∪ the values actually rendered. Requested values are added by the runner
 * (flags, config lists, every value named in a `screens` rule, resolved); rendered ones from the report entries.
 */
class ScopeBuilder(private val previewFilter: List<String>) {
    val platforms = HashSet<String>()
    val modules = HashSet<String>()
    val runtimes = HashSet<String>()
    val devices = HashSet<String>()
    val languages = HashSet<String>()
    val appearances = HashSet<String>()
    val textSizes = HashSet<String>()
    val fontScales = HashSet<Double>()
    val previews = HashSet<String>()

    /** The values of one report screenshot. */
    fun shot(s: Map<String, Any?>) {
        val platform = s["platform"] as String?
        platform?.let { platforms += it }
        (s["module"] as String?)?.let { modules += it }
        (s["runtime"] as String?)?.let { runtimes += it }
        (s["device"] as String?)?.let { devices += it }
        (s["language"] as String?)?.let { languages += it }
        (s["appearance"] as String?)?.let { appearances += it }
        (s["preview"] as String?)?.let { previews += it }
        (s["fontScale"] as Number?)?.let { fontScales += it.toDouble() }
        if (platform == "ios") textSizes += (s["textSize"] as String?) ?: "default"
    }

    /** Another renderer's scope (the iOS renderer's report), merged in. */
    fun merge(scope: Map<*, *>) {
        fun strings(k: String) = (scope[k] as List<*>?).orEmpty().map { it.toString() }
        platforms += strings("platforms"); modules += strings("modules"); runtimes += strings("runtimes"); devices += strings("devices")
        languages += strings("languages"); appearances += strings("appearances"); textSizes += strings("textSizes"); previews += strings("previews")
        (scope["fontScales"] as List<*>?).orEmpty().forEach { (it as? Number)?.let { n -> fontScales += n.toDouble() } }
    }

    fun toJson(): Map<String, Any?> {
        fun sorted(s: Set<String>) = s.sortedWith(CanonicalJson.utf8)
        val out = linkedMapOf<String, Any?>(
            "platforms" to sorted(platforms), "modules" to sorted(modules), "runtimes" to sorted(runtimes),
            "devices" to sorted(devices), "languages" to sorted(languages), "appearances" to sorted(appearances),
            "previews" to sorted(previews), "previewFilter" to previewFilter.sortedWith(CanonicalJson.utf8),
        )
        if ("ios" in platforms) out["textSizes"] = sorted(textSizes + if (textSizes.isEmpty()) setOf("default") else emptySet())
        if (platforms.any { it == "android" || it == "desktop" || it == "flutter" }) out["fontScales"] = fontScales.sorted()
        return out
    }
}
