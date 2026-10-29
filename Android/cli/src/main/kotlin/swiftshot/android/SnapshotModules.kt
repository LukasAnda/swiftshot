package swiftshot.android

import java.io.File

enum class SnapshotTool { PAPARAZZI, ROBORAZZI }

/** A Gradle module that takes screenshots with Paparazzi or Roborazzi, and how that was found. */
data class SnapshotModule(val path: String, val dir: File, val tools: Set<SnapshotTool>, val via: List<String>)

/**
 * Finds the modules that use Paparazzi or Roborazzi by reading settings, build scripts, version
 * catalogs, convention plugins and test sources. Gradle is never run.
 */
object SnapshotModules {
    private val ids = mapOf(
        "app.cash.paparazzi" to SnapshotTool.PAPARAZZI,
        "io.github.takahirom.roborazzi" to SnapshotTool.ROBORAZZI,
    )
    private val importPrefixes = mapOf(
        "app.cash.paparazzi" to SnapshotTool.PAPARAZZI,
        "com.github.takahirom.roborazzi" to SnapshotTool.ROBORAZZI,
        "io.github.takahirom.roborazzi" to SnapshotTool.ROBORAZZI,
    )
    private val skipped = setOf("build", ".gradle", ".git", "node_modules", ".idea")

    /** Gradle path → directory, from settings (include, projectDir = file(...), includeBuild). */
    fun projects(root: File): Map<String, File> {
        val result = linkedMapOf<String, File>()
        fun add(build: File, prefix: String, depth: Int) {
            val settings = settings(build) ?: return
            val text = settings.readText()
            Init.projects(text, build).forEach { (p, d) -> result[prefix + p] = d }
            if (depth > 2) return
            for (inc in Init.includedBuilds(text, build)) {
                if (!inc.isDirectory || inc == build || isPluginBuild(inc)) continue
                val name = ":" + inc.name
                result.putIfAbsent(prefix + name, inc)
                add(inc, prefix + name, depth + 1)
            }
        }
        add(root.absoluteFile.normalize(), "", 0)
        return result
    }

    fun find(root: File): List<SnapshotModule> {
        val ctx = Context(root.absoluteFile.normalize())
        return projects(root).mapNotNull { (path, dir) -> module(ctx, path, dir) }.sortedBy { it.path }
    }

    private fun settings(dir: File) = listOf("settings.gradle.kts", "settings.gradle").map { File(dir, it) }.firstOrNull { it.isFile }

    private fun buildFile(dir: File) = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }

    private fun isPluginBuild(dir: File) = walk(dir).filter { it.name == "build.gradle.kts" || it.name == "build.gradle" }
        .any { f -> strip(f.readText()).let { it.contains("gradlePlugin") || it.contains("kotlin-dsl") || it.contains("java-gradle-plugin") } }

    private fun walk(dir: File) = dir.walkTopDown().onEnter { it.name !in skipped }.filter { it.isFile }

    private fun module(ctx: Context, path: String, dir: File): SnapshotModule? {
        if (!dir.isDirectory) return null
        val tools = linkedSetOf<SnapshotTool>()
        val via = linkedSetOf<String>()
        buildFile(dir)?.let { f ->
            val text = strip(f.readText())
            for ((id, tool) in ids) if (applies(text, id)) { tools += tool; via += "plugin $id" }
            for (m in Regex("""\b(\w+)\.plugins\.([A-Za-z0-9_.]+)""").findAll(text)) {
                val written = m.groupValues[2]
                val id = ctx.catalogs[m.groupValues[1]]?.let { resolve(it, written) } ?: continue
                ids[id]?.let { tools += it; via += "alias ${m.groupValues[1]}.plugins.${key(ctx.catalogs.getValue(m.groupValues[1]), written)}" }
                ctx.conventions[id]?.let { tools += it; via += "convention plugin $id" }
            }
            for ((id, found) in ctx.conventions) if (applies(text, id)) { tools += found; via += "convention plugin $id" }
        }
        val src = File(dir, "src")
        if (src.isDirectory) {
            val imported = src.listFiles { f -> f.isDirectory && f.name.contains("test", ignoreCase = true) }.orEmpty().flatMap { walk(it).toList() }
                .filter { it.extension == "kt" || it.extension == "java" }
                .flatMap { f -> Regex("""(?m)^\s*import\s+([\w.]+)""").findAll(strip(f.readText())).map { it.groupValues[1] }.toList() }
                .mapNotNull { i -> importPrefixes.entries.firstOrNull { i == it.key || i.startsWith(it.key + ".") }?.value }
            if (imported.isNotEmpty()) { tools += imported; via += "imports" }
        }
        return if (tools.isEmpty()) null else SnapshotModule(path, dir, tools, via.toList())
    }

    /** The dotted accessor trimmed to the catalog entry it names (`roborazzi.plugin.get` → `roborazzi.plugin`). */
    private fun key(catalog: Map<String, String>, written: String): String =
        written.split('.').let { parts -> (parts.size downTo 1).map { parts.take(it).joinToString(".") }.first { it in catalog } }

    private fun resolve(catalog: Map<String, String>, written: String): String? =
        written.split('.').let { parts -> (parts.size downTo 1).map { parts.take(it).joinToString(".") }.firstOrNull { it in catalog } }?.let { catalog[it] }

    /** `id("x")`, `id 'x'`, `apply plugin: 'x'`, `apply(plugin = "x")`, `pluginManager.apply("x")`, `apply("x")`. */
    internal fun applies(text: String, id: String): Boolean =
        Regex("""\b(?:id|apply|plugin)\b\s*\(?\s*(?:(?:plugin)\s*[:=]\s*)?["']${Regex.escape(id)}["']""").containsMatchIn(text)

    /** Everything the settings and build files declare, read once per `find`. */
    private class Context(val root: File) {
        /** Catalog accessor (`libs`) → (dotted plugin alias → plugin id). */
        val catalogs: Map<String, Map<String, String>> = catalogs(root)

        /** Convention plugin id → the tools it applies. */
        val conventions: Map<String, Set<SnapshotTool>> = conventions(root, catalogs)
    }

    private fun catalogs(root: File): Map<String, Map<String, String>> {
        val files = File(root, "gradle").listFiles { f -> f.isFile && f.name.endsWith(".versions.toml") }.orEmpty()
        return files.associate { f ->
            val name = f.name.removeSuffix(".versions.toml")
            val plugins = linkedMapOf<String, String>()
            var inPlugins = false
            for (line in strip(f.readText(), hash = true).lines()) {
                val t = line.trim()
                if (t.startsWith("[")) { inPlugins = t == "[plugins]"; continue }
                if (!inPlugins) continue
                val m = Regex("""^([A-Za-z0-9_.-]+)\s*=\s*(.*)$""").find(t) ?: continue
                val id = Regex("""\bid\s*=\s*["']([^"']+)["']""").find(m.groupValues[2])?.groupValues?.get(1)
                    ?: Regex("""^["']([^"':]+):[^"']*["']""").find(m.groupValues[2])?.groupValues?.get(1) ?: continue
                plugins[m.groupValues[1].replace(Regex("[-_]"), ".")] = id
            }
            name to plugins
        }
    }

    private fun conventions(root: File, catalogs: Map<String, Map<String, String>>): Map<String, Set<SnapshotTool>> {
        val builds = (listOf(File(root, "buildSrc"), File(root, "build-logic")) +
            (settings(root)?.let { Init.includedBuilds(it.readText(), root) } ?: emptyList()))
            .filter { it.isDirectory }.distinct()
        // id → source text that defines it
        val sources = linkedMapOf<String, String>()
        for (b in builds) {
            val files = walk(b).toList()
            val scripts = files.filter { it.name.endsWith(".kt") || it.name.endsWith(".java") || it.name.endsWith(".groovy") || it.name.endsWith(".gradle.kts") || it.name.endsWith(".gradle") }
            for (f in files.filter { it.name == "build.gradle.kts" || it.name == "build.gradle" }) {
                // Innermost blocks holding both: register("x") { … }, create("x") { … }, x { … }.
                for (block in Regex("""\{([^{}]*)\}""").findAll(strip(f.readText())).map { it.groupValues[1] }) {
                    val cls = Regex("""implementationClass\s*=\s*["']([^"']+)["']""").find(block)?.groupValues?.get(1)?.substringAfterLast('.') ?: continue
                    val m = Regex("""\bid\s*=?\s*(?:["']([^"']+)["']|(\w+)\.plugins\.([A-Za-z0-9_.]+))""").find(block) ?: continue
                    val id = m.groupValues[1].ifEmpty { catalogs[m.groupValues[2]]?.let { resolve(it, m.groupValues[3]) } } ?: continue
                    val decl = Regex("""\b(?:class|object)\s+${Regex.escape(cls)}\b""")
                    sources[id] = scripts.filter { it.name.endsWith(".kt") || it.name.endsWith(".java") || it.name.endsWith(".groovy") }
                        .map { strip(it.readText()) }.filter { decl.containsMatchIn(it) }.joinToString("\n")
                }
            }
            // Precompiled script plugins: src/main/{kotlin,groovy,java}/<package>/<name>.gradle.kts
            for (f in scripts.filter { it.name.endsWith(".gradle.kts") || it.name.endsWith(".gradle") }) {
                if (f.parentFile.parentFile?.name != "src" && !f.path.contains("/src/main/")) continue
                val text = strip(f.readText())
                val pkg = Regex("""(?m)^\s*package\s+([\w.]+)""").find(text)?.groupValues?.get(1)
                val name = f.name.removeSuffix(".gradle.kts").removeSuffix(".gradle")
                sources[(pkg?.let { "$it." } ?: "") + name] = text
            }
        }
        val result = linkedMapOf<String, Set<SnapshotTool>>()
        fun tools(id: String, text: String): Set<SnapshotTool> {
            val found = linkedSetOf<SnapshotTool>()
            for ((tool, t) in ids) if (applies(text, tool)) found += t
            for (c in catalogs.values) for (m in Regex("""findPlugin\s*\(\s*["']([^"']+)["']""").findAll(text)) {
                resolve(c, m.groupValues[1].replace(Regex("[-_]"), "."))?.let { ids[it]?.let(found::add) }
            }
            for (c in catalogs) for (m in Regex("""\b${Regex.escape(c.key)}\.plugins\.([A-Za-z0-9_.]+)""").findAll(text)) {
                resolve(c.value, m.groupValues[1])?.let { ids[it]?.let(found::add) }
            }
            return found
        }
        for ((id, text) in sources) tools(id, text).takeIf { it.isNotEmpty() }?.let { result[id] = it }
        // Convention plugins that apply other convention plugins.
        var changed = true
        while (changed) {
            changed = false
            for ((id, text) in sources) {
                val inherited = result.filterKeys { it != id && applies(text, it) }.values.flatten().toSet()
                if (inherited.isNotEmpty() && !(result[id] ?: emptySet()).containsAll(inherited)) { result[id] = (result[id] ?: emptySet()) + inherited; changed = true }
            }
        }
        return result
    }

    /** The source with `//`, `/* */` (and with [hash], `#`) comments blanked; strings are kept. */
    internal fun strip(src: String, hash: Boolean = false): String {
        val out = src.toCharArray()
        val n = src.length
        fun blank(a: Int, b: Int) { for (k in a until minOf(b, n)) if (out[k] != '\n') out[k] = ' ' }
        var i = 0
        while (i < n) {
            val c = src[i]
            when {
                src.startsWith("//", i) && !hash -> { val e = src.indexOf('\n', i).let { if (it < 0) n else it }; blank(i, e); i = e }
                c == '#' && hash -> { val e = src.indexOf('\n', i).let { if (it < 0) n else it }; blank(i, e); i = e }
                src.startsWith("/*", i) && !hash -> { val e = src.indexOf("*/", i + 2).let { if (it < 0) n else it + 2 }; blank(i, e); i = e }
                c == '"' || c == '\'' -> {
                    val q = if (src.startsWith("$c$c$c", i)) "$c$c$c" else "$c"
                    var j = i + q.length
                    while (j < n && !src.startsWith(q, j)) { if (src[j] == '\\' && q.length == 1) j++ else if (q.length == 1 && src[j] == '\n') break; j++ }
                    i = minOf(n, j + q.length)
                }
                else -> i++
            }
        }
        return String(out)
    }
}
