package swiftshot.android

import java.io.File

data class MigrationResult(val config: LinkedHashMap<String, Any?>, val report: List<String>, val covered: Int, val total: Int)

/**
 * `swiftshot init` in a project with Paparazzi or Roborazzi tests: a config that renders what those tests render
 * (each tested preview on its tests' devices and settings, everything else skipped) and a report of what was read.
 * The report's headers end in `:`, their items are indented two spaces, the last line is the summary.
 */
object Migration {
    /** What `init` writes without the tools, used when no device can be read. */
    val defaultDevices = listOf("Pixel 10 Pro", "Pixel 9 Pro Fold", "Pixel Tablet")

    /** Null when the project has neither tool. */
    fun run(root: File): MigrationResult? {
        val all = SnapshotModules.projects(root)
        val modules = SnapshotModules.find(root, all).ifEmpty { return null }
        val sources = SnapshotTests.Sources(all)
        val previews = modules.flatMap { SnapshotTests.previews(it, all, sources) }.distinct()
        return plan(root, modules, SnapshotTests.scan(modules, previews, all, sources), previews, all, sources)
    }

    private fun platform(t: SnapshotTest) = when {
        t.sourceSet.startsWith("desktop") || t.sourceSet.startsWith("jvm") -> "desktop"
        t.sourceSet.startsWith("ios") -> "ios"
        else -> "android"
    }

    private fun screen(d: DeviceSource?): Screen? = when (d) {
        is DeviceSource.Read -> d.screen
        is DeviceSource.ToolDefault -> d.screen
        else -> null
    }

    /** The Swiftshot device a test renders on; null when it's each preview's own with no readable fallback, or unresolved. */
    private fun name(d: DeviceSource?): String? = when (d) {
        is DeviceSource.Read -> TestDevices.deviceName(d.screen, d.label)
        is DeviceSource.ToolDefault -> TestDevices.deviceName(d.screen)
        is DeviceSource.FromPreview -> name(d.fallback)
        else -> null
    }

    private fun toolDefault(tool: SnapshotTool) = if (tool == SnapshotTool.PAPARAZZI) "Paparazzi default" else "Robolectric default"

    private val enFirst = compareBy<String>({ it != "en-US" }, { it })

    private fun scale(d: Double) = if (d == Math.floor(d)) d.toLong().toString() else d.toString()

    /** A test that renders a preview with its own device and settings rather than the preview's: a direct call, or a scanner on a fixed device or with settings set. */
    private fun fixes(t: SnapshotTest) = t.target is Target.Previews ||
        t.target is Target.AllPreviews && (t.device is DeviceSource.Read || t.device is DeviceSource.ToolDefault || t.settings.copy(fromPreview = emptySet()) != TestSettings())

    private val platformOrder = listOf("android", "desktop", "ios")

    /** The platforms a module's build targets. */
    private fun platforms(dir: File): Set<String> {
        val b = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }?.let { SnapshotModules.strip(it.readText()) } ?: ""
        val kmp = b.contains("kotlin.multiplatform") || b.contains("kotlin(\"multiplatform\")")
        return setOfNotNull(
            "android".takeIf { !kmp || b.contains("android") },
            "desktop".takeIf { kmp && Regex("""\bjvm\s*\(""").containsMatchIn(b) },
            "ios".takeIf { kmp && b.contains("ios") },
        )
    }

    /** Whether a test that renders [p] with its own settings ([fixes]) renders it with a device, locale, night mode or font scale other than its own. */
    private fun replaces(p: SourcePreview, t: SnapshotTest): Boolean = p.own.any { o ->
        val s = screen(t.device)
        val own = t.settings.fromPreview
        o.unreadable ||
            o.device != null && s != null && Devices.fromPreview(o.device).let { it == null || it.width != s.widthPx || it.height != s.heightPx || it.density != s.densityDpi || it.round != s.round } ||
            o.locale != null && "locale" !in own && !o.locale.replace("-r", "-").equals(t.settings.locale ?: "", ignoreCase = true) ||
            o.night != null && "night" !in own && o.night != (t.settings.night ?: false) ||
            o.fontScale != null && "fontScale" !in own && o.fontScale != (t.settings.fontScale ?: 1.0)
    }

    fun plan(
        root: File, modules: List<SnapshotModule>, tests: List<SnapshotTest>, previews: List<SourcePreview>,
        all: Map<String, File> = SnapshotModules.projects(root), sources: SnapshotTests.Sources = SnapshotTests.Sources(all),
    ): MigrationResult {
        val covered = tests.filter { it.target !is Target.Uncovered }
        val scans = covered.filter { it.target is Target.AllPreviews }
        // What a preview scanner in a module sees: the previews of the module and of the modules it depends on.
        val visible = scans.map { it.module }.distinct().associateWith { m -> modules.first { it.path == m }.let { SnapshotTests.previews(it, all, sources) }.map { it.fqn }.toSet() }
        fun inPackages(fqn: String, packages: List<String>) = packages.isEmpty() || packages.any { fqn.startsWith("$it.") }
        fun covers(t: SnapshotTest, p: SourcePreview) = when (val g = t.target) {
            is Target.Previews -> p.fqn in g.fqns
            is Target.AllPreviews -> p.fqn in visible[t.module].orEmpty() && (g.includePrivate || !p.isPrivate) && inPackages(p.fqn, g.packages)
            else -> false
        }
        val covering = previews.associateWith { p -> covered.filter { covers(it, p) }.toSet() }
        val byFqn = previews.groupBy { it.fqn }

        val stringLanguages = (modules.map { it.dir } + previews.mapNotNull { all[it.module] }).distinct().flatMap { Init.languages(it) }.distinct()
            .sortedWith(enFirst).ifEmpty { listOf("en-US") }
        val anyLocale = covered.any { it.settings.locale != null }
        val overrides = mutableListOf<String>()
        // Rule → combinations its unions render that no test takes.
        val extras = linkedMapOf<String, List<String>>()
        // A rendered rule without devices for Android tests renders on the top-level devices.
        var needsDevices = false
        // Tests with a rule that has no devices of its own.
        val onTopLevel = mutableSetOf<SnapshotTest>()

        fun rule(pattern: String, ts: Set<SnapshotTest>, p: SourcePreview? = null): LinkedHashMap<String, Any?> {
            if (ts.isEmpty()) return linkedMapOf("preview" to pattern, "skip" to true)
            val override = p != null && ts.any { fixes(it) && replaces(p, it) }
            if (override) overrides += p!!.fqn
            // Tests whose device can't be read render something unknown: reported under Devices, not here.
            val taken = ts.filter { platform(it) == "android" && it.device !is DeviceSource.Unresolved }.map { t ->
                val own = t.settings.fromPreview
                listOf(name(t.device) ?: "top-level devices", if ("locale" in own) "own locale" else t.settings.locale ?: "en-US",
                    if ("night" in own) "own uiMode" else if (t.settings.night == true) "dark" else "light", if ("fontScale" in own) "own font scale" else scale(t.settings.fontScale ?: 1.0) + "x")
            }.toSet()
            val product = (0..3).fold(listOf(emptyList<String>())) { acc, i -> acc.flatMap { c -> taken.map { it[i] }.distinct().map { c + it } } }
            product.filter { it !in taken }.takeIf { it.isNotEmpty() }?.let { extras[pattern] = it.map { c -> c.joinToString(" / ") } }
            // What tests take from each preview's own @Preview isn't the rule's to set.
            val locales = ts.filter { "locale" !in it.settings.fromPreview }.map { it.settings.locale }
            val appearances = ts.filter { "night" !in it.settings.fromPreview }.map { if (it.settings.night == true) "dark" else "light" }.distinct().sortedBy { it == "dark" }
            val scales = ts.filter { "fontScale" !in it.settings.fromPreview }.map { it.settings.fontScale ?: 1.0 }.distinct().sorted()
            val devices = ts.filter { platform(it) == "android" }.mapNotNull { name(it.device) }.distinct()
            if (devices.isEmpty() && ts.any { platform(it) == "android" }) { needsDevices = true; onTopLevel += ts }
            return linkedMapOf<String, Any?>(
                "preview" to pattern,
                "devices" to devices.ifEmpty { null },
                // Once any test sets a locale, every rule says which it renders (the default en-US where a test sets none).
                "languages" to if (anyLocale || override && p!!.own.any { it.locale != null || it.unreadable }) locales.map { it ?: "en-US" }.distinct().sortedWith(enFirst).ifEmpty { null } else null,
                "appearances" to appearances.takeIf { (override || it != listOf("light")) && it.isNotEmpty() },
                "font_scales" to scales.takeIf { (override || it != listOf(1.0)) && it.isNotEmpty() },
                "override_preview" to if (override) true else null,
            ).filterValues { it != null }.let { LinkedHashMap(it) }
        }

        // Package rules for preview scanners, the more specific package first; a catch-all for scanners of every package.
        val packages = scans.flatMap { (it.target as Target.AllPreviews).packages }.distinct().sortedWith(compareBy({ -it.length }, { it }))
        val globTests = packages.associateWith { pkg -> scans.filter { inPackages("$pkg.x", (it.target as Target.AllPreviews).packages) }.toSet() }
        val everything = scans.filter { (it.target as Target.AllPreviews).packages.isEmpty() }.toSet()
        fun implied(p: SourcePreview) = packages.firstOrNull { p.fqn.startsWith("$it.") }?.let { globTests.getValue(it) } ?: everything
        // A preview gets its own rule when the tests that render it aren't the ones the package rules give it.
        // So does one a scanner renders on a fixed device or with settings that replace the preview's own.
        val specific = previews.filter { p -> covering.getValue(p) != implied(p) || covering.getValue(p).any { it.target is Target.AllPreviews && fixes(it) && replaces(p, it) } }.distinctBy { it.fqn }.sortedBy { it.fqn }
            .map { p -> rule(p.fqn, byFqn.getValue(p.fqn).flatMap { covering.getValue(it) }.toSet(), p) }
        val screens = specific + packages.map { rule("$it.*", globTests.getValue(it)) } + rule("*", everything)

        val android = covered.filter { platform(it) == "android" }
        // Device name → round.
        val concrete = android.mapNotNull { t -> name(t.device)?.let { it to (screenOf(t.device)?.round == true) } }.distinct()
        val flat = concrete.filter { !it.second }.map { it.first }
        val fallback = needsDevices && flat.isEmpty()
        val renderModules = previews.filter { covering.getValue(it).isNotEmpty() }.map { it.module }.distinct().sorted()
        val desktop = covered.any { platform(it) == "desktop" }
        val ios = covered.any { platform(it) == "ios" }
        val projectPlatforms = renderModules.mapNotNull { all[it] }.flatMap(::platforms).toSet()
        val testPlatforms = covered.map(::platform).toSet()
        val narrower = testPlatforms.isNotEmpty() && projectPlatforms.containsAll(testPlatforms) && testPlatforms != projectPlatforms
        // Previews tested on fewer platforms than the config renders: rules can't say per platform.
        val renderedPlatforms = if (narrower) testPlatforms else projectPlatforms + testPlatforms
        val mixed = previews.distinctBy { it.fqn }.mapNotNull { p ->
            val on = byFqn.getValue(p.fqn).flatMap { covering.getValue(it) }.map(::platform).toSet()
            if (on.isEmpty() || on == renderedPlatforms) null else p.fqn to on
        }
        val fastlane = File(root, "fastlane").isDirectory
        val config = linkedMapOf<String, Any?>(
            "modules" to renderModules.ifEmpty { null },
            "devices" to if (!needsDevices) null else flat.ifEmpty { defaultDevices },
            "watch_devices" to concrete.filter { it.second }.map { it.first }.ifEmpty { null },
            "desktop_devices" to if (desktop) Devices.defaultDesktop else null,
            "ios_devices" to if (ios) Ios.defaultDevices else null,
            "platforms" to if (narrower) platformOrder.filter { it in testPlatforms } else null,
            // The locale the tests render when they set none.
            "languages" to listOf("en-US"),
            "output_directory" to if (fastlane) "fastlane/metadata/android" else "screenshots",
            "layout" to if (fastlane) "fastlane" else null,
            "clear_previous_screenshots" to true,
            "screens" to screens,
        ).filterValues { it != null }.let { LinkedHashMap(it) }

        val report = mutableListOf<String>()
        fun rel(f: File) = f.absoluteFile.relativeToOrSelf(root.absoluteFile).path
        fun at(t: SnapshotTest) = "${rel(t.file)}:${t.line}"
        report += "Modules:"
        for (m in modules) {
            val tools = m.tools.sorted().joinToString(", ") { it.name.lowercase().replaceFirstChar(Char::uppercaseChar) }
            val note = if (covered.none { it.module == m.path } && m.path !in renderModules) ": not rendered (no tests on previews)" else ""
            report += "  ${m.path}  $tools (${m.via.joinToString(", ")})$note"
        }
        for (m in renderModules.filter { r -> modules.none { it.path == r } }) report += "  $m  previews the tests call"

        report += "Devices:"
        val order = listOf(DeviceSource.Read::class, DeviceSource.ToolDefault::class, DeviceSource.FromPreview::class, DeviceSource.Unresolved::class)
        val sources = android.groupBy { it.device }.entries.sortedBy { order.indexOf(it.key::class) }
        for ((d, ts) in sources) report += when (d) {
            is DeviceSource.Read -> "  ${d.label} → ${name(d)}"
            is DeviceSource.ToolDefault -> "  ${toolDefault(d.tool)} → ${name(d)} (tool default)"
            is DeviceSource.FromPreview -> "  @Preview device → each preview's own (from @Preview); previews without one: " + when (val f = d.fallback) {
                null -> "can't be read, top-level devices"
                is DeviceSource.ToolDefault -> "${name(f)} (tool default)"
                is DeviceSource.Read -> "${name(f)} (${f.label})"
                else -> "top-level devices"
            }
            is DeviceSource.Unresolved -> "  ${d.expression} → unresolved (${ts.joinToString(", ") { at(it) }}); " +
                if (ts.all { it in onTopLevel }) "renders on the top-level devices" else if (ts.none { it in onTopLevel }) "its previews render on the devices other tests give them"
                else "renders on the top-level devices where no other test gives its previews a device"
        }
        if (android.isEmpty() && covered.none { platform(it) != "android" }) report += "  none (no test renders a preview)"
        for (p in listOf("desktop", "ios")) covered.filter { platform(it) == p }.map { it.sourceSet }.distinct().forEach { report += "  $it → ${p}_devices (Swiftshot's defaults)" }
        if (fallback) report += "  No test's device could be read: using Swiftshot's default devices"

        report += "Settings:"
        val tested = covered.map { it.settings.locale ?: "en-US" }.distinct().sortedWith(enFirst)
        report += if (anyLocale) "  languages: ${tested.joinToString(", ")} (from tests; en-US where a test sets none)"
            else "  languages: en-US (no test sets a locale)"
        stringLanguages.filter { it !in tested.ifEmpty { listOf("en-US") } }.takeIf { it.isNotEmpty() }?.let { report += "  string resources also have ${it.joinToString(", ")}: add them to languages to render them" }
        report += if (covered.any { it.settings.night == true }) "  appearances: " + covered.map { if (it.settings.night == true) "dark" else "light" }.distinct().sortedBy { it == "dark" }.joinToString(", ") + " (from tests)"
            else "  appearances: light (no test uses night mode)"
        report += if (covered.any { it.settings.fontScale != null && it.settings.fontScale != 1.0 }) "  font scales: " + covered.map { it.settings.fontScale ?: 1.0 }.distinct().sorted().joinToString(", ") { scale(it) } + " (from tests)"
            else "  font scales: 1 (no test sets one)"
        val own = listOf("locale" to "locale", "night" to "uiMode", "fontScale" to "fontScale").filter { (k, _) -> covered.any { k in it.settings.fromPreview } }
        if (own.isNotEmpty()) report += "  each preview's own ${own.joinToString(", ") { it.second }} (from @Preview, as the tests apply previewInfo)"
        if (overrides.isNotEmpty()) report += "  override_preview for ${overrides.joinToString(", ")}: the tests replace the preview's own device, locale, uiMode or fontScale"

        if (renderedPlatforms.size > 1 || narrower) {
            report += "Platforms:"
            val also = projectPlatforms - testPlatforms
            report += "  ${platformOrder.filter { it in renderedPlatforms }.joinToString(", ")} (from tests" + (if (also.isEmpty()) ")" else "; the project also has ${platformOrder.filter { it in also }.joinToString(", ")})")
            for ((fqn, on) in mixed) report += "  $fqn: tested on ${platformOrder.filter { it in on }.joinToString(", ")}; also renders on ${platformOrder.filter { it in renderedPlatforms - on }.joinToString(", ")}"
        }
        if (extras.isNotEmpty()) {
            report += "Extra combinations:"
            for ((pattern, combos) in extras) report += "  $pattern: also renders ${combos.joinToString("; ")} (no test takes them)"
        }

        val uncovered = tests.filter { it.target is Target.Uncovered }
        if (uncovered.isNotEmpty()) {
            report += "Not covered:"
            for (t in uncovered) report += "  ${at(t)}  ${(t.target as Target.Uncovered).call} has no @Preview — add a @Preview with the same arguments to include it"
        }
        val untested = previews.filter { covering.getValue(it).isEmpty() }
        if (untested.isNotEmpty()) {
            report += "Not tested, skipped:"
            for (p in untested) report += "  ${p.fqn} (${p.module})"
        }
        val missing = tests.size - covered.size
        report += "${covered.size} of ${tests.size} snapshot tests are covered by previews" +
            if (missing == 0) "" else "; $missing ${if (missing == 1) "isn't" else "aren't"} (listed above)"
        return MigrationResult(config, report, covered.size, tests.size)
    }

    private fun screenOf(d: DeviceSource): Screen? = screen(d) ?: (d as? DeviceSource.FromPreview)?.fallback?.let(::screenOf)

    fun markdown(result: MigrationResult): String = buildString {
        append("# Swiftshot migration\n")
        for (line in result.report) when {
            line.startsWith("  ") -> append("- ").append(line.trim()).append('\n')
            line.endsWith(":") -> append("\n## ").append(line.removeSuffix(":")).append("\n\n")
            else -> append('\n').append(line).append('\n')
        }
    }

    /** The report through [log]: warnings for what isn't covered or can't be read. */
    fun print(result: MigrationResult, log: Log) {
        var warn = false
        for (line in result.report) when {
            line.startsWith("  ") -> if (warn || line.contains("unresolved") || line.contains("could be read")) log.warn(line.trim()) else log.plain(line)
            line.endsWith(":") -> { warn = line == "Not covered:"; log.step(line.removeSuffix(":")) }
            else -> if (result.covered < result.total) log.warn(line) else log.ok(line)
        }
    }
}
