package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File

/**
 * `swiftshot init` for a Gradle project: writes swiftshot.json with the Android modules, the
 * languages the app has strings for, Play Store devices, and fastlane's folder layout when the
 * project already uses fastlane. Nothing is built.
 */
object Init {
    fun run(o: Options, force: Boolean, log: Log): Int {
        val root = File(o.projectDir).absoluteFile.normalize()
        val target = File(root, "swiftshot.json")
        if (target.exists() && !force) throw CliError("$target already exists. --force overwrites it.")
        if (!File(root, "gradlew").isFile && Flutter.isProject(root)) return write(target, flutter(root), log)
        val settings = listOf("settings.gradle.kts", "settings.gradle").map { File(root, it) }.firstOrNull { it.isFile }
            ?: throw CliError("No settings.gradle(.kts) in $root.")
        val text = settings.readText()
        val dirs = projects(text, root)
        val dir = { m: String -> dirs[m] ?: File(root, m.trim(':').replace(':', '/')) }
        val all = modules(text).filter { isAndroid(dir(it)) || isMultiplatform(dir(it)) }
        // The modules with previews (an app module that only hosts a shared one has none).
        val modules = all.filter { hasPreviews(dir(it)) }.ifEmpty { all }
        val desktop = modules.any { buildText(dir(it)).contains(Regex("""\bjvm\s*\(""")) }
        val ios = modules.any { buildText(dir(it)).contains("iosSimulatorArm64") }
        val wear = modules.filter { isWear(dir(it)) }
        val languages = modules.flatMap { languages(dir(it)) }.distinct()
            .sortedWith(compareBy({ it != "en-US" }, { it })).ifEmpty { listOf("en-US") }
        val fastlane = File(root, "fastlane").isDirectory
        val config = linkedMapOf<String, Any?>(
            "modules" to modules.ifEmpty { null },
            "devices" to listOf("Pixel 10 Pro", "Pixel 9 Pro Fold", "Pixel Tablet"),
            "watch_devices" to if (wear.isNotEmpty()) Devices.defaultWatch else null,
            "desktop_devices" to if (desktop) Devices.defaultDesktop else null,
            "ios_devices" to if (ios) Ios.defaultDevices else null,
            "languages" to languages,
            "appearances" to listOf("light", "dark"),
            "output_directory" to if (fastlane) "fastlane/metadata/android" else "screenshots",
            "layout" to if (fastlane) "fastlane" else null,
            "clear_previous_screenshots" to true,
        ).filterValues { it != null }
        return write(target, config, log)
    }

    private fun write(target: File, config: Map<String, Any?>, log: Log): Int {
        target.writeText(Json.write(config, "  ") + "\n")
        log.ok("Wrote $target")
        println(target.readText().trim())
        return 0
    }

    /** A Flutter project: the languages of its gen-l10n ARB files, an iPhone, an iPad, a Pixel and a Pixel tablet. */
    fun flutter(root: File): Map<String, Any?> {
        val arbDir = File(root, "l10n.yaml").takeIf { it.isFile }?.readText()
            ?.let { Regex("""(?m)^arb-dir:\s*(\S+)""").find(it)?.groupValues?.get(1) } ?: "lib/l10n"
        val languages = File(root, arbDir).listFiles { f -> f.extension == "arb" }.orEmpty()
            .mapNotNull { Regex("""_([a-z]{2,3}(?:_[A-Za-z0-9]+)*)\.arb$""").find(it.name)?.groupValues?.get(1)?.replace('_', '-') }
            .map { if (it == "en") "en-US" else it }.distinct()
            .sortedWith(compareBy({ it != "en-US" }, { it })).ifEmpty { listOf("en-US") }
        return linkedMapOf(
            "devices" to listOf("iPhone 17 Pro Max", "iPad Pro 13-inch (M5)", "Pixel 10 Pro", "Pixel Tablet"),
            "languages" to languages,
            "appearances" to listOf("light", "dark"),
            "output_directory" to "screenshots",
            "clear_previous_screenshots" to true,
        )
    }

    /** `include(":app", ":wear")`, `include ':app'`, one per line or several in one call. */
    fun modules(settings: String): List<String> =
        Regex("""include\s*\(?([^)\n]*)\)?""").findAll(settings).flatMap { m ->
            Regex("""["']([^"']+)["']""").findAll(m.groupValues[1]).map { it.groupValues[1] }
        }.map { if (it.startsWith(":")) it else ":$it" }.distinct().toList()

    /** Module path → directory: the default `a/b` for `:a:b`, or the `project(":a:b").projectDir = file("x")` override. */
    fun projects(settings: String, root: File): Map<String, File> {
        val text = SnapshotModules.strip(settings)
        val overrides = Regex("""(?:find)?[Pp]roject\s*\(\s*["']([^"']+)["']\s*\)\s*\??\.projectDir\s*=\s*([^\n]+)""").findAll(text).associate { m ->
            val path = m.groupValues[1].let { if (it.startsWith(":")) it else ":$it" }
            val rel = Regex("""["']([^"']*)["']""").findAll(m.groupValues[2]).lastOrNull()?.groupValues?.get(1) ?: ""
            path to File(rel).let { if (it.isAbsolute) it else File(root, rel) }.normalize()
        }
        return modules(text).associateWith { overrides[it] ?: File(root, it.trim(':').replace(':', '/')) }
    }

    /** Directories named by `includeBuild("x")`. */
    fun includedBuilds(settings: String, root: File): List<File> =
        Regex("""includeBuild\s*\(?\s*["']([^"']+)["']""").findAll(SnapshotModules.strip(settings))
            .map { File(root, it.groupValues[1]).normalize() }.distinct().toList()

    private fun buildText(dir: File) = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }?.readText() ?: ""

    private fun isAndroid(dir: File): Boolean {
        val b = buildText(dir)
        return b.contains("com.android.application") || b.contains("com.android.library") ||
            b.contains("android.application") || b.contains("android.library") || b.contains("android {")
    }

    private fun isMultiplatform(dir: File) = buildText(dir).let { it.contains("kotlin.multiplatform") || it.contains("kotlin(\"multiplatform\")") }

    private fun hasPreviews(dir: File): Boolean = File(dir, "src").walkTopDown()
        .filter { it.isFile && it.extension == "kt" }.any { it.readText().contains("@Preview") }

    private fun isWear(dir: File): Boolean {
        val b = buildText(dir)
        val manifest = File(dir, "src/main/AndroidManifest.xml").takeIf { it.isFile }?.readText() ?: ""
        return b.contains("wear") && (b.contains("compose") || manifest.contains("android.hardware.type.watch")) ||
            manifest.contains("android.hardware.type.watch")
    }

    /** `values-de`, `values-pt-rBR`, `values-b+sr+Latn` with a strings file → BCP 47 tags. */
    fun languages(module: File): List<String> =
        (listOf("src/main/res", "src/androidMain/res") + listOf("src/commonMain/composeResources")).flatMap { languages(module, it) }.distinct()

    private fun languages(module: File, path: String): List<String> {
        val res = File(module, path)
        val dirs = res.listFiles { f -> f.isDirectory && f.name.startsWith("values") }?.toList() ?: return emptyList()
        val tags = dirs.filter { d -> d.listFiles { f -> f.name.startsWith("strings") && f.name.endsWith(".xml") }?.isNotEmpty() == true }
            .mapNotNull { tag(it.name.removePrefix("values")) }
        val hasDefault = File(res, "values").listFiles { f -> f.name.startsWith("strings") }?.isNotEmpty() == true
        return (if (hasDefault) listOf("en-US") else emptyList()) + tags.filter { it != "en" && it != "en-US" }
    }

    fun tag(qualifiers: String): String? {
        if (qualifiers.isEmpty()) return null
        for (q in qualifiers.trimStart('-').split('-').let { listOf(it.joinToString("-")) }) {
            if (q.startsWith("b+")) return q.removePrefix("b+").split('+').joinToString("-")
            val parts = q.split('-')
            val lang = parts[0]
            if (!Regex("[a-z]{2,3}").matches(lang)) return null
            val region = parts.getOrNull(1)?.takeIf { it.startsWith("r") && it.length == 3 }?.substring(1)
            if (parts.size > 1 && region == null) return null // values-night, values-v31, values-de-land…
            return if (region != null) "$lang-$region" else lang
        }
        return null
    }
}
