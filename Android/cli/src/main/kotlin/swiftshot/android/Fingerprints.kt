package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File

/**
 * The renderer fingerprint of docs/wiki/Baseline-format.md (Fingerprint): what produced a run's pixels, per platform.
 * The values come from the resolved classpath and the tools the run used.
 */
object Fingerprints {
    /** This run's host, detected once (`SWIFTSHOT_HOST` overrides it). */
    val host: String by lazy { System.getenv("SWIFTSHOT_HOST") ?: hostOf(System.getProperty("os.name").orEmpty(), System.getProperty("os.arch").orEmpty()) }

    internal fun hostOf(os: String, arch: String): String {
        val o = when {
            os.startsWith("Mac") -> "macos"
            os.startsWith("Linux") -> "linux"
            os.startsWith("Windows") -> "windows"
            else -> os.lowercase().replace(' ', '_')
        }
        val a = when (arch.lowercase()) {
            "aarch64", "arm64" -> "arm64"
            "amd64", "x86_64", "x64" -> "x64"
            else -> arch.lowercase()
        }
        return "$o-$a"
    }

    /** The Swiftshot version (`SWIFTSHOT_VERSION_OVERRIDE` overrides it). */
    fun version(): String = System.getenv("SWIFTSHOT_VERSION_OVERRIDE") ?: VERSION

    /** Fingerprint id: the first 12 hex digits of its hash. */
    fun id(fp: Map<*, *>): String = CanonicalJson.hash(fp).take(12)

    private fun base(platform: String, host: String, mode: String) =
        linkedMapOf<String, Any?>("platform" to platform, "host" to host, "swiftshot" to version(), "mode" to mode)

    /** Android: layoutlib and Compose from the first module's resolved classpath (by path), the renderer's JDK. */
    fun android(modules: List<Module>, java: File?, host: String = this.host): Map<String, Any?> {
        val fp = base("android", host, "headless")
        val sorted = modules.sortedBy { it.path }
        sorted.firstNotNullOfOrNull { m -> (m.json["layoutlibRuntime"] as String?)?.let { layoutlib(File(it)) } }?.let { fp["layoutlib"] = it }
        sorted.firstNotNullOfOrNull { m ->
            val components = (m.json["components"] as List<*>?).orEmpty().map { it.toString() }
            component(components, "androidx.compose.ui:ui", "androidx.compose.ui:ui-android")
                ?: versionIn(m.classpath, "androidx.compose.ui", "ui-android", "ui")
        }?.let { fp["compose"] = it }
        java?.let(::jdk)?.let { fp["jdk"] = it }
        return fp
    }

    /** Desktop (Compose Multiplatform JVM): Skiko and Compose from the classpath, the renderer's JDK. */
    fun desktop(modules: List<Module>, java: File?, host: String = this.host): Map<String, Any?> {
        val fp = base("desktop", host, "headless")
        val sorted = modules.sortedBy { it.path }
        sorted.firstNotNullOfOrNull { versionIn(it.classpath, "org.jetbrains.skiko", "skiko-awt") }?.let { fp["skiko"] = it }
        sorted.firstNotNullOfOrNull { versionIn(it.classpath, "org.jetbrains.compose.ui", "ui-desktop", "ui") }?.let { fp["compose"] = it }
        java?.let(::jdk)?.let { fp["jdk"] = it }
        return fp
    }

    /** Flutter: the SDK's version, the renderer (`impeller`, `skia` or `exact-ios`) and the font files used. */
    fun flutter(sdk: File, renderer: String, fonts: Collection<String>, host: String = this.host): Map<String, Any?> {
        val fp = base("flutter", host, if (renderer == "exact-ios") "exact-ios" else "headless")
        flutterVersion(sdk)?.let { fp["flutter"] = it }
        fp["renderer"] = renderer
        fp["fonts"] = fonts.map { File(it).name }.distinct().sortedWith(CanonicalJson.utf8)
        return fp
    }

    /** iOS when the iOS renderer didn't report its own: what this side knows. */
    fun iosFallback(host: String = this.host): Map<String, Any?> = base("ios", host, "no-boot")

    fun flutterVersion(sdk: File): String? {
        File(sdk, "bin/cache/flutter.version.json").takeIf { it.isFile }?.let { f ->
            runCatching { (Json.parse(f.readText()) as Map<*, *>)["frameworkVersion"] as String? }.getOrNull()?.let { return it }
        }
        return File(sdk, "version").takeIf { it.isFile }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
    }

    /** `…/layoutlib-runtime/16.2.3/<hash>/layoutlib-runtime-16.2.3-mac-arm.jar` → 16.2.3. */
    fun layoutlib(jar: File): String? =
        cachePathVersion(jar, "com.android.tools.layoutlib", "layoutlib-runtime")
            ?: Regex("""^layoutlib-runtime-(\d[\w.]*?)(-(mac|linux|win)[\w-]*)?\.jar$""").find(jar.name)?.groupValues?.get(1)

    /** A `group:artifact:version` among the resolved components. */
    internal fun component(components: List<String>, vararg coordinates: String): String? =
        coordinates.firstNotNullOfOrNull { c -> components.firstOrNull { it.startsWith("$c:") }?.removePrefix("$c:")?.takeIf { it.isNotEmpty() } }

    /**
     * The version of the first of [artifacts] (in order) on [classpath]: from a Gradle cache path
     * (`…/<group>/<artifact>/<version>/<hash>/<file>`), else from a file named `<artifact>-<version>.jar`.
     */
    internal fun versionIn(classpath: List<File>, group: String, vararg artifacts: String): String? {
        for (artifact in artifacts) {
            classpath.firstNotNullOfOrNull { cachePathVersion(it, group, artifact) }?.let { return it }
            val name = Regex("^${Regex.escape(artifact)}-(\\d[^/]*?)\\.(jar|aar)$")
            classpath.firstNotNullOfOrNull { name.find(it.name)?.groupValues?.get(1) }?.let { return it }
        }
        return null
    }

    private fun cachePathVersion(f: File, group: String, artifact: String): String? {
        val parts = f.invariantSeparatorsPath.split('/')
        for (i in 0 until parts.size - 2) if (parts[i] == group && parts[i + 1] == artifact) return parts[i + 2]
        return null
    }

    /** The JDK of a `bin/java`: its `release` file, else `java -version`. */
    fun jdk(java: File): String? {
        File(java.absoluteFile.parentFile?.parentFile, "release").takeIf { it.isFile }?.readLines()
            ?.firstOrNull { it.startsWith("JAVA_VERSION=") }?.substringAfter('=')?.trim('"')?.let { return it }
        if (File(System.getProperty("java.home"), "bin/java").absoluteFile == java.absoluteFile) return System.getProperty("java.version")
        return runCatching {
            val p = ProcessBuilder(java.path, "-version").redirectErrorStream(true).start()
            val text = p.inputStream.bufferedReader().readText(); p.waitFor()
            Regex("version \"([^\"]+)\"").find(text)?.groupValues?.get(1)
        }.getOrNull()
    }

    /**
     * The pixel-relevant differences between a baseline fingerprint and this run's for the same platform, as
     * `<platform> <field>: baseline <value>, this run <value>`. `swiftshot` compares its first two parts; `host`
     * is ignored when this run renders with the exact iOS renderer.
     */
    fun mismatches(baseline: Map<*, *>, run: Map<*, *>): List<String> {
        val platform = run["platform"]
        val exactIos = platform == "ios" || run["renderer"] == "exact-ios"
        val out = mutableListOf<String>()
        for (k in (baseline.keys + run.keys).map { it.toString() }.distinct().sortedWith(CanonicalJson.utf8)) {
            val a = baseline[k]
            val b = run[k]
            if (k == "host" && exactIos) continue
            if (k == "swiftshot" && a is String && b is String && a.split('.').take(2) == b.split('.').take(2)) continue
            if (a != b) out += "$platform $k: baseline ${show(a)}, this run ${show(b)}"
        }
        return out
    }

    private fun show(v: Any?): String = when (v) {
        null -> "none"
        is List<*> -> v.joinToString(", ")
        else -> v.toString()
    }
}
