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
        val modules = Gradle.prepare(o, log)
        log.ok("Built ${modules.joinToString(", ") { it.path }} in ${"%.1f".format(Locale.ROOT, log.seconds)}s")
        val found = modules.associateWith { m -> PreviewScanner(m.classDirs + m.classpath).scan(m.classDirs) }
            .filterValues { it.isNotEmpty() }
        if (found.isEmpty()) throw CliError("No @Preview functions found in ${modules.joinToString { it.path }}.")
        if (o.command == "list") {
            for ((m, previews) in found) {
                println("${m.path}${if (m.wear) " (Wear OS)" else ""}")
                for (p in previews) println("  ${p.name}  ${p.composable}${describe(p)}")
            }
            return 0
        }
        for (m in found.keys) if (!m.hasTooling) throw CliError(
            "${m.path} has no androidx.compose.ui:ui-tooling on its ${o.variant} classpath; add debugImplementation(\"androidx.compose.ui:ui-tooling\") as Android Studio's previews need it too."
        )
        val shots = found.flatMap { (m, previews) -> plan(m, previews) }
        if (shots.isEmpty()) throw CliError("Nothing to render: every preview is filtered out.")
        if (o.clear) clear()
        val javaBin = Java.find(o)
        val workerJar = workerJar()
        val byFile = shots.associateBy { it.file.path }
        val results = java.util.Collections.synchronizedList(mutableListOf<Pair<Shot, Result>>())
        val total = shots.size
        val done = java.util.concurrent.atomic.AtomicInteger()
        val cores = Runtime.getRuntime().availableProcessors()
        val memory = (java.lang.management.ManagementFactory.getOperatingSystemMXBean() as com.sun.management.OperatingSystemMXBean).totalMemorySize
        // Every module at once: the renderer processes are shared out by how much each has to do.
        val byModule = shots.groupBy { it.module }.mapValues { (m, list) -> groups(m, list) }
        val auto = minOf(maxOf(1, cores / 2), maxOf(1, (memory / (2L shl 30)).toInt()), 8)
        val budget = maxOf(if (o.parallel > 0) o.parallel else auto, byModule.size)
        val totalGroups = byModule.values.sumOf { it.size }
        val threads = byModule.map { (m, groups) ->
            val processes = maxOf(1, minOf(groups.size, Math.round(budget * groups.size.toDouble() / totalGroups).toInt()))
            log.step("${m.path}: ${groups.sumOf { (it["shots"] as List<*>).size }} screenshots in ${groups.size} groups, $processes renderer processes")
            kotlin.concurrent.thread(name = m.path) {
                val t0 = System.nanoTime()
                val readyMs = Pool(m, javaBin, workerJar, log).run(groups, processes) { r ->
                    val shot = byFile[r.file] ?: byFile[r.file.replace(Regex("_\\d+\\.png$"), ".png")]
                    if (shot != null) results += shot to r
                    val n = done.incrementAndGet()
                    if (!r.ok) log.warn("${shot?.let { "${it.preview.name} · ${it.device.name} · ${it.language}" } ?: r.file}: ${r.error}")
                    else if (o.verbose) log.step("[$n/$total] ${File(r.file).name} ${r.millis} ms")
                }
                val ok = results.count { it.first.module == m && it.second.ok }
                log.ok("${m.path}: $ok screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t0) / 1e9)}s (renderer start ${readyMs} ms)")
            }
        }
        threads.forEach { it.join() }
        val failed = results.filter { !it.second.ok }
        report(results)
        val ok = results.count { it.second.ok }
        log.ok("$ok screenshots in ${"%.1f".format(Locale.ROOT, log.seconds)}s → $output")
        return if (failed.isEmpty() && ok > 0) 0 else 1
    }

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
            val watch = m.wear || p.isWatchDevice
            val devices = when {
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
                full -> "vscroll"
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
                "rtl" to rtl(s.language),
                "night" to s.dark,
                "fontScale" to s.fontScale,
                "mode" to s.mode,
                "systemUi" to s.systemUi,
                "gestureNav" to (s.device.type != "watch" && s.device.type != "tv"),
                "theme" to if (s.dark) o.theme.replace(".Light.", ".") else o.theme,
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
                        "framed" to art(shot.device)?.let { framed(shot.file).path },
                    )
                },
            )
        }
    }

    private val arts = HashMap<String, FrameArt?>()
    private fun art(d: Device): FrameArt? = if (o.frame != "plain") null else synchronized(arts) { arts.getOrPut(d.id) { Frames.art(d, log) } }

    /** `<output>-framed/<lang>/<name>_framed.png`, as on iOS. */
    private fun framed(file: File): File {
        val rel = file.relativeTo(output).path.removeSuffix(".png")
        return File(output.path + "-framed", "${rel}_framed.png")
    }

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

    private fun report(results: List<Pair<Shot, Result>>) {
        output.mkdirs()
        val sorted = results.sortedWith(compareBy({ it.first.language }, { it.first.device.name }, { it.first.preview.name }, { it.first.dark }))
        val shots = sorted.filter { it.second.ok }.map { (s, r) ->
            val (w, h) = r.size.split('x').let { (it.getOrNull(0)?.toIntOrNull() ?: 0) to (it.getOrNull(1)?.toIntOrNull() ?: 0) }
            linkedMapOf(
                "file" to File(r.file).relativeTo(output).path, "module" to s.module.path, "preview" to s.preview.name,
                "composable" to s.preview.composable, "device" to s.device.name, "language" to s.language,
                "appearance" to if (s.dark) "dark" else "light", "fontScale" to s.fontScale, "width" to w, "height" to h, "millis" to r.millis,
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

    /** The worker jar ships next to this one (or in the build output while developing). */
    private fun workerJar(): File {
        System.getenv("SWIFTSHOT_ANDROID_WORKER")?.let { return File(it) }
        val self = File(Runner::class.java.protectionDomain.codeSource.location.toURI())
        listOf(File(self.parentFile, "swiftshot-android-worker.jar"), File(self.parentFile, "../../../worker/build/libs/swiftshot-android-worker.jar"))
            .firstOrNull { it.isFile }?.let { return it.canonicalFile }
        throw CliError("swiftshot-android-worker.jar not found next to ${self.name}")
    }
}
