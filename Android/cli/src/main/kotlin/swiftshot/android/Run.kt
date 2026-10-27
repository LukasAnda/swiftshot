package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

class Log(val verbose: Boolean) {
    private val start = System.nanoTime()
    private val tty = System.console() != null
    private fun t() = String.format(Locale.ROOT, "%6.1fs", (System.nanoTime() - start) / 1e9)
    private fun c(code: String, s: String) = if (tty) "\u001b[${code}m$s\u001b[0m" else s
    fun step(s: String) = System.err.println("${c("2", t())} ${c("36", "▸")} $s")
    fun ok(s: String) = System.err.println("${c("2", t())} ${c("32", "✔")} $s")
    fun warn(s: String) = System.err.println("${c("2", t())} ${c("33", "!")} $s")
    fun error(s: String) = System.err.println("${c("31", "error:")} $s")
    val seconds get() = (System.nanoTime() - start) / 1e9
}

/** One screenshot to take. */
data class Shot(
    val module: Module,
    val preview: Preview,
    val device: Device,
    val language: String,
    val dark: Boolean,
    val fontScale: Double,
    val mode: String,
    val systemUi: Boolean,
    val delayMs: Long,
    val file: File,
    val index: Int? = null,
)

class Runner(private val o: Options, private val log: Log) {
    private val output = File(o.output).absoluteFile

    fun run(): Int {
        val cores = Runtime.getRuntime().availableProcessors()
        val memory = (java.lang.management.ManagementFactory.getOperatingSystemMXBean() as com.sun.management.OperatingSystemMXBean).totalMemorySize
        val auto = minOf(cores, maxOf(1, (memory / (1536L shl 20)).toInt()), 8)
        val budgetAll = if (o.parallel > 0) o.parallel else auto
        // Renderer processes for last run's classpath start now, while Gradle builds; they are
        // used if the classpath comes out the same.
        val warm = if (o.command == "run") warmPools(budgetAll) else emptyMap()
        // Not on a Mac: iOS targets aren't prepared (Kotlin/Native can't build them here either).
        if (!Host.mac) {
            if ("ios" in o.platforms) throw CliError(iosOnly(null))
            if (o.platforms.isEmpty()) o.platforms = listOf("android", "desktop")
        }
        val prepared = try {
            Gradle.prepare(o, log).let { modules ->
                // An iOS module without a desktop target: its previews come from the Android one.
                val bare = modules.filter { it.ios && modules.none { d -> d.desktop && d.path == it.path } && modules.none { a -> a.platform == "android" && a.path == it.path } }
                if (bare.isEmpty() || o.platforms.isEmpty()) modules
                else Gradle.prepare(o, log, (Gradle.gradlePlatforms(o.platforms) + "android").distinct())
            }
        } catch (e: Exception) { warm.values.forEach { it.close() }; throw e }
        // iOS modules have no classes of their own: their previews are found on a JVM target,
        // which is prepared even when only iOS is asked for.
        val iosModules = prepared.filter { it.ios && (o.platforms.isEmpty() || "ios" in o.platforms) }
        val scanned = prepared.filter { !it.ios }
        val modules = scanned.filter { o.platforms.isEmpty() || it.platform in o.platforms }
        log.ok("Built ${(modules + iosModules).joinToString(", ") { it.label }} in ${"%.1f".format(Locale.ROOT, log.seconds)}s")
        if (!Host.mac && prepared.any { it.desktop || it.json["multiplatform"] == true }) log.step("Compose Multiplatform iOS targets need a Mac with Xcode; skipped here")
        val allFound = scanned.associateWith { m -> PreviewScanner(m.classDirs + m.classpath).scan(m.classDirs) }
            .filterValues { it.isNotEmpty() }
        val found = allFound.filterKeys { it in modules }
        if (found.isEmpty() && iosModules.isEmpty()) { warm.values.forEach { it.close() }; throw CliError("No @Preview functions found in ${modules.joinToString { it.path }}.") }
        if (o.command == "list") {
            for ((m, previews) in found) {
                println("${m.label}${if (m.wear) " (Wear OS)" else ""}")
                for (p in previews) println("  ${p.name}  ${p.composable}${describe(p)}")
            }
            for (m in iosModules) {
                val shared = allFound.entries.filter { it.key.path == m.path }.sortedBy { if (it.key.desktop) 0 else 1 }.firstOrNull()?.value.orEmpty()
                if (found.keys.any { it.path == m.path }) { println("${m.label}: the previews of ${m.path} above"); continue }
                println(m.label)
                for (p in shared) println("  ${p.name}  ${p.composable}${describe(p)}")
            }

            return 0
        }
        for (m in found.keys) if (!m.hasTooling) throw CliError(
            "${m.path} has no androidx.compose.ui:ui-tooling on its ${o.variant} classpath; add debugImplementation(\"androidx.compose.ui:ui-tooling\") as Android Studio's previews need it too."
        )
        val planned = found.flatMap { (m, previews) -> plan(m, previews) }
        if (planned.isEmpty() && iosModules.isEmpty()) throw CliError("Nothing to render: every preview is filtered out.")
        if (o.clear) clear()
        val measures = measures(iosModules, allFound)
        val measureSet = measures.toHashSet()
        val shots = planned + measures
        val javaBin = Java.find(o)
        val byFile = shots.associateBy { it.file.path }
        val results = java.util.Collections.synchronizedList(mutableListOf<Pair<Shot, Result>>())
        val total = planned.size
        val done = java.util.concurrent.atomic.AtomicInteger()
        // Every module at once: the renderer processes are shared out by how much each has to do.
        val byModule = shots.groupBy { it.module }.mapValues { (m, list) -> groups(m, list) }
        val budget = maxOf(budgetAll, byModule.size)
        val totalGroups = byModule.values.sumOf { it.size }
        val threads = byModule.map { (m, groups) ->
            val processes = maxOf(1, minOf(groups.size, Math.round(budget * groups.size.toDouble() / totalGroups).toInt()))
            // A target rendered only to measure iOS previews isn't reported.
            val reported = planned.any { it.module == m }
            if (reported) log.step("${m.label}: ${planned.count { it.module == m }} screenshots in ${groups.size} groups, $processes renderer processes")
            kotlin.concurrent.thread(name = m.label) {
                val t0 = System.nanoTime()
                val workerJar = workerJar(m)
                val pool = warm[m.label]?.takeIf { it.argfile == Pool(m, javaBin, workerJar, log).argfile } ?: Pool(m, javaBin, workerJar, log)
                pool.totalProcesses = budget
                val readyMs = pool.run(groups, processes) { r ->
                    val shot = byFile[r.file] ?: byFile[r.file.replace(Regex("_\\d+\\.png$"), ".png")]
                    if (shot != null) results += shot to r
                    val n = done.incrementAndGet()
                    if (!r.ok) log.warn("${shot?.let { "${it.preview.name} · ${it.device.name} · ${it.language}" } ?: r.file}: ${r.error}")
                    else if (o.verbose) log.step("[$n/$total] ${File(r.file).name} ${r.millis} ms")
                }
                val ok = results.count { it.first.module == m && it.second.ok && it.first !in measureSet }
                if (reported) log.ok("${m.label}: $ok screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t0) / 1e9)}s (renderer start ${readyMs} ms)")
            }
        }
        threads.forEach { it.join() }
        warm.values.forEach { it.close() }
        val measured = results.filter { it.first in measureSet }
        results.removeAll(measured)
        val iosShots = renderIos(iosModules, allFound, measured)
        measures.firstOrNull()?.file?.parentFile?.deleteRecursively()
        val failed = results.filter { !it.second.ok }
        report(results, iosShots)
        val ok = results.count { it.second.ok } + iosShots.size
        log.ok("$ok screenshots in ${"%.1f".format(Locale.ROOT, log.seconds)}s → $output")
        return if (failed.isEmpty() && ok > 0) 0 else 1
    }

    /** Pools started from the module descriptions the previous run left in each module's build folder. */
    private fun warmPools(budget: Int): Map<String, Pool> = runCatching {
        val root = File(o.projectDir).absoluteFile
        val files = root.walkTopDown().maxDepth(6)
            .onEnter { it.name != ".gradle" && it.name != "src" && it.name != "node_modules" && !it.name.startsWith(".") }
            .filter { it.extension == "json" && it.parentFile.name == o.variant && it.parentFile.parentFile.name == "swiftshot" }
            .toList()
        val modules = files.mapNotNull { runCatching { Module(Json.parse(it.readText()) as Map<*, *>) }.getOrNull() }
            .filter { o.modules.isEmpty() || it.path in o.modules }
            .filter { o.platforms.isEmpty() || it.platform in o.platforms }
            .filter { m -> (m.classpath + m.bootClasspath).all { it.exists() } }
        if (modules.isEmpty()) return emptyMap()
        val javaBin = Java.find(o)
        val each = maxOf(1, budget / modules.size)
        modules.associate { m -> m.label to Pool(m, javaBin, workerJar(m), log).also { it.totalProcesses = budget; it.warm(each) } }
    }.getOrDefault(emptyMap())

    private fun describe(p: Preview) = buildList {
        if (p.device.isNotEmpty()) add("device=${p.device}")
        if (p.locale.isNotEmpty()) add("locale=${p.locale}")
        p.night?.let { add(if (it) "dark" else "light") }
        if (p.fontScale != 1.0) add("fontScale=${p.fontScale}")
        if (p.showSystemUi) add("system UI")
        if (p.provider != null) add("parameters from ${p.provider.substringAfterLast('.')}")
    }.takeIf { it.isNotEmpty() }?.joinToString(", ", "  (", ")") ?: ""

    /** Every preview × device × language × appearance × font scale, with the preview's own settings winning. */
    fun plan(m: Module, previews: List<Preview>): List<Shot> {
        val shots = mutableListOf<Shot>()
        val names = HashMap<String, Int>()
        for (p in previews) {
            if (o.previews.isNotEmpty() && o.previews.none { glob(it).matches(p.name) }) continue
            val rule = o.rule(p.name)
            if (rule?.skip == true) continue
            val watch = !m.desktop && (m.wear || p.isWatchDevice)
            val devices = when {
                m.desktop -> Devices.resolveDesktop(rule?.devices?.filter { d -> Devices.desktop.any { glob(d).matches(it.name) || it.id == d } }?.ifEmpty { null }
                    ?: o.desktopDevices.ifEmpty { Devices.defaultDesktop })
                p.device.isNotEmpty() -> listOf(Devices.fromPreview(p.device) ?: throw CliError("${p.name}: unknown device \"${p.device}\""))
                rule?.devices != null -> Devices.resolve(rule.devices)
                watch -> Devices.resolve(o.watchDevices.ifEmpty { Devices.defaultWatch })
                else -> Devices.resolve(o.devices.ifEmpty { Devices.defaults })
            }.let { list -> if (p.widthDp > 0 || p.heightDp > 0) list.map { sized(it, p) } else list }
            val languages = if (p.locale.isNotEmpty()) listOf(bcp47(p.locale)) else rule?.languages ?: o.languages
            // Wear OS has no light mode: watch screens render once, dark, with no appearance suffix.
            val dark = p.night?.let { listOf(it) } ?: if (watch) listOf(true) else (rule?.appearances ?: o.appearances).map { it == "dark" }
            val scales = if (p.fontScale != 1.0) listOf(p.fontScale) else rule?.fontScales ?: o.fontScales
            val systemUi = when (o.systemUi) { "always" -> true; "never" -> false; else -> p.showSystemUi }
            val full = rule?.fullLength ?: o.fullLength
            val mode = when {
                full && !m.desktop -> "vscroll"
                systemUi -> "normal"
                else -> "shrink"
            }
            val delay = ((rule?.delay ?: o.delay) * 1000).roundToInt().toLong()
            for (device in devices) for (lang in languages) for (d in dark) for (s in scales) {
                // Two previews that would write the same file: the later one gets a number.
                var file = file(device, lang, p.name, d, s, (dark.size > 1 || d) && p.night == null && !watch, (scales.size > 1 || s != 1.0) && p.fontScale == 1.0)
                val n = names.merge(file.path, 1, Int::plus)!!
                if (n > 1) file = File(file.parentFile, file.nameWithoutExtension + " $n.png")
                shots += Shot(m, p, device, lang, d, s, mode, systemUi, delay, file)
            }
        }
        return shots
    }

    private fun sized(d: Device, p: Preview): Device {
        val w = if (p.widthDp > 0) (p.widthDp * d.density / 160.0).roundToInt() else d.width
        val h = if (p.heightDp > 0) (p.heightDp * d.density / 160.0).roundToInt() else d.height
        return d.copy(width = w, height = h)
    }

    private fun file(device: Device, lang: String, preview: String, dark: Boolean, scale: Double, withAppearance: Boolean, withScale: Boolean): File {
        val clean = { s: String -> s.replace('/', '-').replace(':', '-') }
        var base = "${clean(device.name)}-${clean(preview)}"
        if (withAppearance && dark) base += "-dark" else if (withAppearance) base += "-light"
        if (withScale) base += "-${fmt(scale)}x"
        return if (o.layout == "fastlane") File(output, "$lang/images/${device.playFolder}/$base.png") else File(output, "$lang/$base.png")
    }

    private fun fmt(d: Double) = if (d == Math.floor(d)) d.toInt().toString() else d.toString()

    /** Shots that can share one render session, as worker jobs. */
    private fun groups(m: Module, shots: List<Shot>): List<Map<String, Any?>> {
        if (m.desktop) return desktopGroups(shots)
        val appTest = File(Cache.root, "app").apply { mkdirs() }
        val runtime = Gradle.unpack(m.layoutlibRuntime)
        val resources = Gradle.unpack(m.layoutlibResources)
        return shots.groupBy { listOf(it.device, it.language, it.dark, it.fontScale, it.mode, it.systemUi) }.map { (_, list) ->
            val s = list.first()
            linkedMapOf(
                "layoutlibRuntime" to runtime.path,
                "layoutlibResources" to resources.path,
                "environment" to m.environment(appTest),
                "device" to s.device.toJson().apply { put("type", if (s.device.type == "watch") "watch" else s.device.type) },
                "locale" to qualifier(s.language),
                "languageTag" to s.language.replace('_', '-'),
                "rtl" to rtl(s.language),
                "night" to s.dark,
                "fontScale" to s.fontScale,
                "mode" to s.mode,
                "systemUi" to s.systemUi,
                "gestureNav" to (s.device.type != "watch" && s.device.type != "tv"),
                "theme" to theme(m, s.dark),
                "roundCorners" to o.roundCorners,
                "frame" to art(s.device)?.toJson(),
                "shots" to list.map { shot ->
                    linkedMapOf(
                        "composable" to shot.preview.composable,
                        "out" to shot.file.path,
                        "provider" to shot.preview.provider,
                        "providerLimit" to shot.preview.providerLimit,
                        "offsetMs" to shot.delayMs,
                        "background" to background(shot.preview),
                        // Only whole screens go into a frame; a component or a full-length capture would be stretched.
                        "framed" to art(shot.device)?.takeIf { shot.mode == "normal" }?.let { framed(shot.file).path },
                    )
                },
            )
        }
    }

    /** Desktop jobs: no layoutlib, the locale as a BCP 47 tag (the JVM's default locale). */
    private fun desktopGroups(shots: List<Shot>): List<Map<String, Any?>> =
        shots.groupBy { listOf(it.device, it.language, it.dark, it.fontScale, it.mode) }.map { (_, list) ->
            val s = list.first()
            linkedMapOf(
                "device" to s.device.toJson(),
                "locale" to s.language,
                "rtl" to rtl(s.language),
                "night" to s.dark,
                "fontScale" to s.fontScale,
                "mode" to s.mode,
                "shots" to list.map { shot ->
                    linkedMapOf(
                        "composable" to shot.preview.composable,
                        "out" to shot.file.path,
                        "provider" to shot.preview.provider,
                        "providerLimit" to shot.preview.providerLimit,
                        "background" to background(shot.preview),
                        // A declared size is kept in shrink mode, as Android Studio does.
                        "fixedWidth" to (shot.preview.widthDp > 0),
                        "fixedHeight" to (shot.preview.heightDp > 0),
                    )
                },
            )
        }

    private val arts = HashMap<String, FrameArt?>()
    private fun art(d: Device): FrameArt? = if (o.frame != "plain") null else synchronized(arts) { arts.getOrPut(d.id) { Frames.art(d, log) } }

    /** `<output>-framed/<lang>/<name>_framed.png`, as on iOS. */
    private fun framed(file: File): File {
        val rel = file.relativeTo(output).path.removeSuffix(".png")
        return File(output.path + "-framed", "${rel}_framed.png")
    }

    /**
     * The explicit `android_theme`, else the module's application theme (night variants come from
     * its values-night resources), else Material's own light or dark theme.
     */
    private fun theme(m: Module, dark: Boolean): String = o.theme ?: m.theme
        ?: if (dark) "android:Theme.Material.NoActionBar" else "android:Theme.Material.Light.NoActionBar"

    private fun background(p: Preview): String? {
        if (!p.showBackground) return null
        if (p.backgroundColor == 0L) return "#FFFFFFFF"
        return "#%08X".format(p.backgroundColor and 0xFFFFFFFFL)
    }

    /** `@Preview(locale = …)` is a resource qualifier (fr-rFR, b+sr+Latn); a BCP 47 tag passes through. */
    internal fun bcp47(locale: String): String {
        val l = locale.replace('_', '-')
        if (l.startsWith("b+")) return l.removePrefix("b+").replace('+', '-')
        return Regex("([a-zA-Z]{2,3})-r([a-zA-Z]{2})").matchEntire(l)?.let { "${it.groupValues[1]}-${it.groupValues[2].uppercase()}" } ?: l
    }

    /** BCP 47 to Android's resource qualifier: en-US → en-rUS, zh-Hans-CN → b+zh+Hans+CN. */
    internal fun qualifier(tag: String): String {
        val parts = tag.replace('_', '-').split('-')
        return when {
            parts.size == 1 -> parts[0]
            parts.size == 2 && parts[1].length == 2 -> "${parts[0]}-r${parts[1].uppercase()}"
            else -> "b+" + parts.joinToString("+")
        }
    }

    internal fun rtl(tag: String) = tag.substringBefore('-').substringBefore('_') in setOf("ar", "fa", "he", "iw", "ur", "ps", "sd", "ug", "yi", "dv", "ckb")

    private fun clear() {
        if (!output.isDirectory) return
        output.walkBottomUp().forEach { f ->
            if (f.isFile && (f.name.endsWith(".png") || f.name == "screenshots.html" || f.name == "swiftshot-report.json")) f.delete()
        }
    }

    /**
     * One desktop render per preview of each iOS module, at an iPhone's width, not reported: it
     * tells the iOS host app how many values each @PreviewParameter provider has and how large
     * a component preview is (iOS lays a preview out at the size it is given).
     */
    internal fun measures(iosModules: List<Module>, found: Map<Module, List<Preview>>): List<Shot> {
        val dir = File(Cache.root, "measure/${System.nanoTime()}")
        val phone = Device("measure", "measure", "window", 804, 1748, 320, 320, 320, "normal")
        return iosModules.flatMap { m ->
            val (jvm, previews) = found.entries.filter { it.key.path == m.path }.sortedBy { if (it.key.desktop) 0 else 1 }.firstOrNull() ?: return@flatMap emptyList()
            val device = if (jvm.desktop) phone else Devices.resolve(Devices.defaults).first()
            previews.filter { p -> (o.previews.isEmpty() || o.previews.any { glob(it).matches(p.name) }) && o.rule(p.name)?.skip != true }
                .mapIndexed { i, p ->
                    val systemUi = when (o.systemUi) { "always" -> true; "never" -> false; else -> p.showSystemUi }
                    Shot(jvm, p, sized(device, p), o.languages.firstOrNull() ?: "en-US", false, 1.0, if (systemUi) "normal" else "shrink", systemUi, 0, File(dir, "$i.png"))
                }
        }
    }

    /** Compose Multiplatform iOS targets, with the previews their module has on a JVM target. */
    private fun renderIos(iosModules: List<Module>, found: Map<Module, List<Preview>>, results: List<Pair<Shot, Result>>): List<Ios.Shot> {
        if (iosModules.isEmpty()) return emptyList()
        val ios = Ios(o, log, output)
        if (!ios.available) {
            log.warn("iOS targets need a Mac with Xcode and the swiftshot iOS renderer; skipped ${iosModules.joinToString { it.path }}")
            return emptyList()
        }
        val shots = mutableListOf<Ios.Shot>()
        for (m in iosModules) {
            val previews = found.entries.filter { it.key.path == m.path }.sortedBy { if (it.key.desktop) 0 else 1 }.firstOrNull()?.value
                ?.filter { p -> (o.previews.isEmpty() || o.previews.any { glob(it).matches(p.name) }) && o.rule(p.name)?.skip != true }
            if (previews == null) { log.warn("${m.label}: no JVM target to find its previews on (add jvm() or android)"); continue }
            // Values per @PreviewParameter provider, as the JVM renders found them (name_1.png…).
            val counts = HashMap<String, Int>()
            for ((s, r) in results) if (r.ok && s.preview.provider != null && s.module.path == m.path) {
                val index = Regex("_(\\d+)\\.png$").find(r.file)?.groupValues?.get(1)?.toInt() ?: 1
                counts.merge(s.preview.composable + "|" + s.preview.name, index, ::maxOf)
            }
            // Components (no system UI) at the size they measured, in points (= dp).
            val sizes = HashMap<String, Pair<Int, Int>>()
            for ((s, r) in results) if (r.ok && s.module.path == m.path && s.mode == "shrink") {
                val (w, h) = r.size.split('x').map { it.toIntOrNull() ?: 0 }.let { it.getOrElse(0) { 0 } to it.getOrElse(1) { 0 } }
                if (w > 0 && h > 0) sizes[s.preview.composable + "|" + s.preview.name] = (w * 160 / s.device.density) to (h * 160 / s.device.density)
            }
            val t0 = System.nanoTime()
            val rendered = ios.run(m, previews, counts, sizes)
            log.ok("${m.label}: ${rendered.size} screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t0) / 1e9)}s")
            shots += rendered
        }
        return shots
    }

    private fun report(results: List<Pair<Shot, Result>>, iosShots: List<Ios.Shot> = emptyList()) {
        output.mkdirs()
        val sorted = results.sortedWith(compareBy({ it.first.language }, { it.first.device.name }, { it.first.preview.name }, { it.first.dark }))
        val shots = sorted.filter { it.second.ok }.map { (s, r) ->
            val (w, h) = r.size.split('x').let { (it.getOrNull(0)?.toIntOrNull() ?: 0) to (it.getOrNull(1)?.toIntOrNull() ?: 0) }
            linkedMapOf(
                "file" to File(r.file).relativeTo(output).path, "module" to s.module.path, "preview" to s.preview.name,
                "composable" to s.preview.composable, "device" to s.device.name, "language" to s.language,
                "appearance" to if (s.dark) "dark" else "light", "fontScale" to s.fontScale, "width" to w, "height" to h, "millis" to r.millis,
                "platform" to s.module.platform,
            )
        } + iosShots.map { i ->
            linkedMapOf<String, Any?>(
                "file" to i.file, "preview" to i.preview, "device" to i.device, "language" to i.language,
                "appearance" to i.appearance, "width" to i.width, "height" to i.height, "platform" to "ios",
            )
        }
        val errors = sorted.filter { !it.second.ok }.map { (s, r) -> "${s.preview.name} · ${s.device.name} · ${s.language}: ${r.error}" }
        File(output, "swiftshot-report.json").writeText(
            Json.write(linkedMapOf("platform" to "android", "totalSeconds" to log.seconds, "screenshots" to shots, "errors" to errors), "  ") + "\n"
        )
        if (!o.html) return
        fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace("\"", "&quot;")
        val body = StringBuilder()
        for ((lang, group) in shots.groupBy { it["language"] as String }.toSortedMap()) {
            body.append("<h2>${esc(lang)}</h2>\n")
            for ((device, row) in group.groupBy { it["device"] as String }.toSortedMap()) {
                body.append("<h3>${esc(device)}</h3><div class=row>\n")
                for (s in row) {
                    val src = (s["file"] as String).split('/').joinToString("/") { java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
                    body.append("<figure><a href=\"$src\"><img loading=lazy src=\"$src\"></a><figcaption>${esc(s["preview"] as String)} · ${s["appearance"]} · ${s["width"]}×${s["height"]}</figcaption></figure>\n")
                }
                body.append("</div>\n")
            }
        }
        File(output, "screenshots.html").writeText(
            """
            <!doctype html><meta charset=utf-8><title>Screenshots</title>
            <style>body{font:14px system-ui,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}
            .row{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:220px}img{width:100%;border-radius:12px;box-shadow:0 2px 8px #0002;background:#fff}
            figcaption{font-size:12px;color:#555;margin-top:6px}h3{font-weight:500;color:#444}
            @media (prefers-color-scheme:dark){body{background:#111;color:#eee}figcaption,h3{color:#aaa}}</style>
            <h1>${shots.size} screenshots · ${"%.1f".format(Locale.ROOT, log.seconds)}s</h1>
            """.trimIndent() + "\n" + body
        )
    }

    /** The worker jars ship next to this one (or sit in the build output while developing). */
    private fun workerJar(m: Module): File {
        val (name, module) = if (m.desktop) "swiftshot-desktop-worker.jar" to "desktop-worker" else "swiftshot-android-worker.jar" to "worker"
        System.getenv(if (m.desktop) "SWIFTSHOT_DESKTOP_WORKER" else "SWIFTSHOT_ANDROID_WORKER")?.let { return File(it) }
        val self = File(Runner::class.java.protectionDomain.codeSource.location.toURI())
        listOf(File(self.parentFile, name), File(self.parentFile, "../../../$module/build/libs/$name"))
            .firstOrNull { it.isFile }?.let { return it.canonicalFile }
        throw CliError("$name not found next to ${self.name}")
    }
}
