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
        val settings = listOf("settings.gradle.kts", "settings.gradle").map { File(root, it) }.firstOrNull { it.isFile }
            ?: throw CliError("No settings.gradle(.kts) in $root.")
        val modules = modules(settings.readText()).filter { isAndroid(File(root, it.trim(':').replace(':', '/'))) }
        val wear = modules.filter { isWear(File(root, it.trim(':').replace(':', '/'))) }
        val languages = modules.flatMap { languages(File(root, it.trim(':').replace(':', '/'))) }.distinct()
            .sortedWith(compareBy({ it != "en-US" }, { it })).ifEmpty { listOf("en-US") }
        val fastlane = File(root, "fastlane").isDirectory
        val config = linkedMapOf<String, Any?>(
            "modules" to modules.ifEmpty { null },
            "devices" to listOf("Pixel 10 Pro", "Pixel 9 Pro Fold", "Pixel Tablet"),
            "watch_devices" to if (wear.isNotEmpty()) Devices.defaultWatch else null,
            "languages" to languages,
            "appearances" to listOf("light", "dark"),
            "output_directory" to if (fastlane) "fastlane/metadata/android" else "screenshots",
            "layout" to if (fastlane) "fastlane" else null,
            "clear_previous_screenshots" to true,
        ).filterValues { it != null }
        target.writeText(Json.write(config, "  ") + "\n")
        log.ok("Wrote $target")
        println(target.readText().trim())
        return 0
    }

    /** `include(":app", ":wear")`, `include ':app'`, one per line or several in one call. */
    fun modules(settings: String): List<String> =
        Regex("""include\s*\(?([^)\n]*)\)?""").findAll(settings).flatMap { m ->
            Regex("""["']([^"']+)["']""").findAll(m.groupValues[1]).map { it.groupValues[1] }
        }.map { if (it.startsWith(":")) it else ":$it" }.distinct().toList()

    private fun buildText(dir: File) = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }?.readText() ?: ""

    private fun isAndroid(dir: File): Boolean {
        val b = buildText(dir)
        return b.contains("com.android.application") || b.contains("com.android.library") ||
            b.contains("android.application") || b.contains("android.library") || b.contains("android {")
    }

    private fun isWear(dir: File): Boolean {
        val b = buildText(dir)
        val manifest = File(dir, "src/main/AndroidManifest.xml").takeIf { it.isFile }?.readText() ?: ""
        return b.contains("wear") && (b.contains("compose") || manifest.contains("android.hardware.type.watch")) ||
            manifest.contains("android.hardware.type.watch")
    }

    /** `values-de`, `values-pt-rBR`, `values-b+sr+Latn` with a strings file → BCP 47 tags. */
    fun languages(module: File): List<String> {
        val res = File(module, "src/main/res")
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
