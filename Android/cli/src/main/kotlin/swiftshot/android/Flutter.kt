package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.util.Locale

/**
 * Flutter projects: the `@Preview`s of `lib/` (Flutter's widget previews), rendered by one
 * `flutter test` run from files generated in `.dart_tool/swiftshot/`. The previews are found in
 * the sources here and each annotation is re-created from its own source text in a library with
 * the preview file's imports, so `Preview`, `MultiPreview`, custom subclasses and `transform()`
 * behave as in Flutter's previewer. Each language renders in its own tester process (its fonts).
 */
class Flutter(private val o: Options, private val log: Log) {
    private val root = File(o.projectDir).absoluteFile.normalize()
    val output: File = o.outputDir(flutter = true)
    /** The font files the tester processes were given (the fingerprint's `fonts`). */
    private val fontFiles = LinkedHashSet<String>()

    fun run(): Int {
        val pubspec = File(root, "pubspec.yaml").readText()
        val pkg = Regex("""(?m)^name:\s*([\w]+)""").find(pubspec)?.groupValues?.get(1) ?: throw CliError("pubspec.yaml has no name")
        if (!Regex("""(?m)^\s+flutter_test:""").containsMatchIn(pubspec))
            throw CliError("pubspec.yaml has no flutter_test dev dependency (dev_dependencies: flutter_test: sdk: flutter), which renders the previews.")
        val sdk = sdk()
        val previews = DartScanner.scan(File(root, "lib"))
        for (p in previews.filter { it.private }) log.warn("${p.file.relativeTo(root)}:${p.line}: ${p.reference} is private; previews must be public")
        val public = previews.filter { !it.private }
        if (o.command == "list") {
            for (p in public) println("  ${p.reference}  ${p.file.relativeTo(root)}:${p.line}  @${p.annotations.joinToString(" @")}")
            return 0
        }
        if (public.isEmpty()) throw CliError("No @Preview functions found in ${File(root, "lib")}.")
        val devices = devices()
        val languages = o.languages.map { it.replace('_', '-') }
        val iosDevices = devices.filter { it["platform"] == "ios" }.map { it["name"] as String }
        val exact = if (iosDevices.isEmpty() || o.flutterIos == "headless") null else FlutterIos(o, log, root, File(root, ".dart_tool/swiftshot"), sdk, output).let { f ->
            val why = f.unavailable()
            if (why != null) log.step("iPhones and iPads rendered headless ($why); on a Mac with Xcode they render exactly as on a device")
            f.takeIf { why == null }
        }
        if (o.clear) output.listFiles()?.forEach { if (it.isDirectory) it.deleteRecursively() else if (it.name.endsWith(".png") || it.name == "screenshots.html" || it.name == "swiftshot-report.json") it.delete() }
        // Generated anew each run; ios/ keeps the host app and its build stamp between runs.
        val dir = File(root, ".dart_tool/swiftshot").apply { listFiles()?.filter { it.name != "ios" }?.forEach { it.deleteRecursively() }; mkdirs() }
        generate(dir, pkg, public, pubspec, languages, devices, exact != null)
        val processes = if (o.parallel > 0) o.parallel else maxOf(1, minOf(languages.size, Runtime.getRuntime().availableProcessors()))
        log.step("${public.size} preview declarations, ${devices.size} devices, ${languages.size} languages, $processes tester processes")
        val t0 = System.nanoTime()
        val tests = languages.map { File(dir, "${file(it)}_test.dart").relativeTo(root).path }
        // Impeller, as phones render Flutter (its anti-aliasing and gradients); Skia where the
        // tester can't start it (a Linux machine without Vulkan).
        fun cmd(impeller: Boolean) = listOf(File(sdk, "bin/flutter").path, "test", "--no-pub", "--concurrency=$processes", "--reporter=compact") +
            (if (impeller) listOf("--enable-impeller") else emptyList()) + tests
        val pubGet = ProcessBuilder(File(sdk, "bin/flutter").path, "pub", "get").directory(root).redirectErrorStream(true).also { it.environment()["FLUTTER_ROOT"] = sdk.path }.start()
        val pubOut = pubGet.inputStream.bufferedReader().readText()
        if (pubGet.waitFor() != 0) throw CliError("flutter pub get failed:\n${pubOut.takeLast(3000)}")
        fun test(impeller: Boolean): Pair<Int, String> {
            val p = ProcessBuilder(cmd(impeller)).directory(root).redirectErrorStream(true).also { it.environment()["FLUTTER_ROOT"] = sdk.path }.start()
            val out = StringBuilder()
            p.inputStream.bufferedReader().forEachLine { line -> out.appendLine(line); if (o.verbose) log.step(line) }
            return p.waitFor() to out.toString()
        }
        fun results() = languages.flatMap { lang ->
            File(dir, "${file(lang)}.results.jsonl").takeIf { it.isFile }?.readLines().orEmpty().filter { it.isNotBlank() }.map { Json.parse(it) as Map<*, *> }
        }
        /** One headless pass over the generated jobs: Impeller, else Skia; its results, each with the renderer that made it. */
        fun headless(): Pair<Int, List<Map<*, *>>> {
            var (status, out) = test(impeller = true)
            var renderer = "impeller"
            if (results().isEmpty() && status != 0) {
                log.warn("flutter test could not render with Impeller here; rendering with Skia")
                test(impeller = false).let { status = it.first; out = it.second }
                renderer = "skia"
            }
            val results = results().map { LinkedHashMap<Any?, Any?>(it).apply { put("renderer", renderer) } }
            for (r in results.filter { it["ok"] == true && it["warning"] != null }) log.warn("${r["preview"]} · ${r["device"]} · ${r["language"]}: ${r["warning"]} (${r["script"]}:${r["line"]})")
            for (r in results.filter { it["ok"] != true }) log.warn("${r["preview"]} · ${r["device"]} · ${r["language"]}: ${r["error"]} (${r["script"]}:${r["line"]})")
            if (status != 0 && results.isEmpty()) throw CliError("flutter test failed:\n${out.lines().filter { it.isNotBlank() }.takeLast(40).joinToString("\n")}")
            return status to results
        }
        var results = headless().second
        var ok = results.filter { it["ok"] == true }
        log.ok("${ok.size} screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t0) / 1e9)}s (flutter test)")
        val manifest = File(dir, "previews.json").takeIf { it.isFile }?.let { (Json.parse(it.readText()) as List<*>).map { m -> m as Map<*, *> } }.orEmpty()
        var shots = ok
        var iosExact = false
        var iosErrors: List<Map<String, Any?>> = emptyList()
        if (exact != null) {
            // Self-sizing components: their size in points from the headless iPhone renders.
            val ratios = devices.associate { (it["name"] as String) to (it["ratio"] as Number).toDouble() }
            val measured = HashMap<String, Pair<Double, Double>>()
            for (r in ok) if (ratios[r["device"]] != null && (r["device"] as String) in iosDevices) {
                val (w, h) = (r["size"] as String).split('x').map { it.toDouble() / ratios[r["device"]]!! }
                measured.putIfAbsent(r["preview"] as String, w to h)
            }
            val t1 = System.nanoTime()
            val rendered = exact.run(manifest, measured, iosDevices)
            if (rendered != null) {
                iosExact = true
                iosErrors = exact.errors
                log.ok("${rendered.size} iOS screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t1) / 1e9)}s (Flutter's iOS engine, no simulator booted)")
                shots = ok.filter { (it["device"] as String) !in iosDevices } + rendered.map { s ->
                    mapOf("ok" to true, "file" to File(output, s.file).path, "preview" to s.preview, "device" to s.device, "language" to s.language,
                        "appearance" to s.appearance, "fontScale" to 1.0, "size" to "${s.width}x${s.height}", "millis" to 0, "script" to null, "line" to null,
                        "renderer" to "exact-ios")
                }
            } else {
                // The iOS engine couldn't render: iPhones and iPads headless after all.
                log.step("Rendering iPhones and iPads headless")
                val others = results.filter { (it["device"] as String) !in iosDevices }
                generate(dir, pkg, public, pubspec, languages, devices.filter { it["platform"] == "ios" }, false)
                results = others + headless().second
                ok = results.filter { it["ok"] == true }
                shots = ok
            }
        }
        // The system bars over full screens (components have none), where no system drew them.
        if (o.systemUi != "never") {
            val components = manifest.filter { it["component"] == true }.map { it["name"] as String }.toSet()
            val byName = devices.associateBy { it["name"] as String }
            val roboto = File(sdk, "bin/cache/artifacts/material_fonts/Roboto-Regular.ttf")
            for (r in ok) {
                val d = byName[r["device"]] ?: continue
                if ((r["preview"] as String) in components || (d["platform"] == "ios" && iosExact)) continue
                FlutterBars.draw(File(r["file"] as String), d, rtl(r["language"] as String), roboto)
            }
        }
        if (o.frame == "plain") frame(shots, devices, manifest)
        // The run's renderers; each screenshot names its own (an iPhone may have fallen back to headless).
        report(shots, results.filter { it["ok"] != true }, devices, manifest, Fingerprints.flutter(sdk, shots.map { it["renderer"] as String }, fontFiles), iosErrors)
        log.ok("${shots.size} screenshots in ${"%.1f".format(Locale.ROOT, log.seconds)}s → $output")
        return if (shots.isNotEmpty() && ok.size == results.size && iosErrors.isEmpty()) 0 else 1
    }

    /**
     * Full screens in their device (`<output>-framed/<language>/<name>_framed.png`, as the
     * Android and iOS renderers write them): Android Studio's device art for Android devices, the
     * iOS renderer's Apple bezels for iPhones and iPads (on a Mac). Components and full-length
     * screens stay unframed.
     */
    private fun frame(shots: List<Map<*, *>>, devices: List<Map<String, Any?>>, manifest: List<Map<*, *>>) {
        val components = manifest.filter { it["component"] == true }.map { it["name"] as String }.toSet()
        val byName = devices.associateBy { it["name"] as String }
        val framed = File(output.path + "-framed")
        fun target(file: File) = File(framed, file.relativeTo(output).path.removeSuffix(".png") + "_framed.png")
        val full = shots.filter { (it["preview"] as String) !in components }.mapNotNull { r ->
            val d = byName[r["device"]] ?: return@mapNotNull null
            val (w, h) = (r["size"] as String).split('x').map { it.toInt() }
            val ratio = (d["ratio"] as Number).toDouble()
            // A full-length screen is taller than its device: no frame fits it.
            if (Math.abs(h - (d["height"] as Number).toDouble() * ratio) > 2 || Math.abs(w - (d["width"] as Number).toDouble() * ratio) > 2) null else r to d
        }
        val arts = HashMap<String, FrameArt?>()
        var n = 0
        for ((r, d) in full.filter { it.second["platform"] == "android" }) {
            val art = arts.getOrPut(d["name"] as String) { Devices.resolve(listOf(d["name"] as String)).firstOrNull()?.let { Frames.art(it, log) } } ?: continue
            val file = File(r["file"] as String)
            val image = javax.imageio.ImageIO.read(file) ?: continue
            target(file).parentFile.mkdirs()
            javax.imageio.ImageIO.write(swiftshot.android.shared.Frame.compose(image, art.toJson()), "png", target(file))
            n++
        }
        val ios = full.filter { it.second["platform"] == "ios" }
        if (ios.isNotEmpty()) {
            val tool = Ios(o, log, output)
            if (!tool.available) log.warn("iPhone and iPad frames need the iOS renderer on a Mac (Apple's bezels); left unframed")
            else {
                // The iOS renderer's frame command, on a copy of just these screenshots.
                val stage = File(root, ".dart_tool/swiftshot/frames").apply { deleteRecursively(); mkdirs() }
                for ((r, _) in ios) { val f = File(r["file"] as String); f.copyTo(File(stage, f.relativeTo(output).path), overwrite = true) }
                if (tool.frame(stage, framed)) n += ios.size
                stage.deleteRecursively()
            }
        }
        if (n > 0) log.ok("$n framed → $framed")
    }

    /** The SDK: --flutter-root, FLUTTER_ROOT, the project's fvm version, then `flutter` on the PATH. */
    fun sdk(): File {
        fun valid(f: File?) = f?.takeIf { File(it, "bin/flutter").isFile }?.canonicalFile
        o.flutterRoot?.let { return valid(File(it)) ?: throw CliError("No Flutter SDK at $it") }
        valid(System.getenv("FLUTTER_ROOT")?.let(::File))?.let { return it }
        valid(File(root, ".fvm/flutter_sdk"))?.let { return it }
        File(root, ".fvmrc").takeIf { it.isFile }?.let { rc ->
            val version = (runCatching { Json.parse(rc.readText()) as Map<*, *> }.getOrNull()?.get("flutter") as String?)
            val cache = System.getenv("FVM_CACHE_PATH") ?: "${System.getProperty("user.home")}/fvm"
            if (version != null) valid(File(cache, "versions/$version"))?.let { return it }
        }
        for (dir in System.getenv("PATH").orEmpty().split(File.pathSeparator)) {
            val flutter = File(dir, "flutter")
            if (flutter.isFile) valid(flutter.canonicalFile.parentFile.parentFile)?.let { return it }
        }
        throw CliError("No Flutter SDK found: set FLUTTER_ROOT, pass --flutter-root, or put flutter on the PATH.")
    }

    /** iPhones and iPads by their iOS names, everything else from the Android catalog. */
    private fun devices(): List<Map<String, Any?>> = o.devices.ifEmpty { listOf("iPhone 17 Pro Max", "Pixel 10 Pro") }.flatMap { name ->
        AppleDevices.matching(name).map { it.toJson() }.ifEmpty {
            Devices.resolve(listOf(name)).map { d ->
                val dp = d.density / 160.0
                val status = SystemBars.statusDp(d)
                linkedMapOf("name" to d.name, "platform" to "android", "width" to d.width / dp, "height" to d.height / dp, "ratio" to dp,
                    "insets" to listOf(status, 0.0, if (d.type == "watch") 0.0 else 24.0, 0.0), "cutout" to d.cutout, "corner" to d.corner,
                    "folder" to d.playFolder)
            }
        }
    }

    /** The screens rules, as the Dart renderer reads them (the first matching one applies). */
    private fun rules() = o.screens.map { r ->
        linkedMapOf("preview" to r.preview, "devices" to r.devices, "languages" to r.languages, "appearances" to r.appearances,
            "fontScales" to r.fontScales, "fullLength" to r.fullLength, "delay" to r.delay, "skip" to r.skip)
    }

    private fun rtl(tag: String) = tag.substringBefore('-').substringBefore('_') in setOf("ar", "fa", "he", "iw", "ur", "ps", "sd", "ug", "yi", "dv", "ckb")

    private fun file(language: String) = "swiftshot_" + language.lowercase().replace(Regex("[^a-z0-9]"), "_")

    private fun generate(dir: File, pkg: String, previews: List<DartScanner.Found>, pubspec: String, languages: List<String>, devices: List<Map<String, Any?>>, iosExact: Boolean) {
        File(dir, "swiftshot_flutter.dart").writeText(Flutter::class.java.getResource("/flutter/swiftshot_flutter.dart")!!.readText())
        val lib = File(root, "lib")
        val byFile = previews.groupBy { it.library }
        val libs = byFile.entries.mapIndexed { i, (library, found) ->
            val name = "previews_$i.dart"
            File(dir, name).writeText(DartScanner.library(library, lib, pkg, found, root))
            name
        }
        val l10n = Regex("""(?m)^\s+flutter_localizations:""").containsMatchIn(pubspec)
        val entries = buildString {
            appendLine("// Generated by Swiftshot: every preview of the project, rendered by swiftshot_flutter.dart.")
            appendLine("// ignore_for_file: type=lint")
            appendLine("import 'swiftshot_flutter.dart' as swiftshot;")
            if (l10n) appendLine("import 'package:flutter_localizations/flutter_localizations.dart' as swiftshot_l10n;")
            libs.forEachIndexed { i, n -> appendLine("import '$n' as p$i;") }
            appendLine()
            appendLine("List<swiftshot.Entry> entries() => [")
            libs.indices.forEach { appendLine("  ...p$it.swiftshotEntries(),") }
            appendLine("];")
            appendLine()
            appendLine("void setUp() {")
            if (l10n) appendLine("  swiftshot.kDefaultLocalizations = () => swiftshot_l10n.GlobalMaterialLocalizations.delegates;")
            if (l10n) appendLine("  swiftshot.kHasGlobalLocalizations = true;")
            appendLine("}")
        }
        File(dir, "swiftshot_entries.dart").writeText(entries)
        val fonts = Fonts(File(sdk(), "bin/cache/artifacts/material_fonts"), log)
        for (lang in languages) {
            val job = linkedMapOf(
                "language" to lang, "languages" to languages, "devices" to devices, "appearances" to o.appearances,
                "fontScales" to o.fontScales, "previews" to o.previews, "output" to output.path, "delay" to o.delay,
                "fullLength" to o.fullLength, "layout" to o.layout, "rules" to rules(),
                "results" to File(dir, "${file(lang)}.results.jsonl").path, "manifest" to File(dir, "previews.json").path,
                // iPhones and iPads render on the iOS engine: here only the components it needs measured.
                "iosMeasureOnly" to iosExact,
                "fonts" to fonts.forLanguage(lang, ios = devices.any { it["platform"] == "ios" }, android = devices.any { it["platform"] == "android" })
                    .also { m -> m.values.forEach { fontFiles += it } },
            )
            File(dir, "${file(lang)}.json").writeText(Json.write(job, "  "))
            File(dir, "${file(lang)}_test.dart").writeText(
                """
                // Generated by Swiftshot: the $lang screenshots.
                import 'swiftshot_flutter.dart' as swiftshot;
                import 'swiftshot_entries.dart';

                void main() {
                  setUp();
                  swiftshot.run(entries(), '${File(dir, "${file(lang)}.json").path.replace("\\", "/")}');
                }
                """.trimIndent() + "\n"
            )
        }
    }

    private fun report(ok: List<Map<*, *>>, failed: List<Map<*, *>>, devices: List<Map<String, Any?>>, manifest: List<Map<*, *>>, fingerprint: Map<String, Any?>,
                       iosErrors: List<Map<String, Any?>> = emptyList()) {
        val ratios = devices.associate { (it["name"] as String) to (it["ratio"] as Number?)?.toDouble() }
        val shots = ok.map { reportShot(it, output, ratios[it["device"]]) }.sortedWith(compareBy(CanonicalJson.utf8) { it["id"] as String })
        val errors = failed.sortedWith(compareBy({ it["language"].toString() }, { it["device"].toString() }, { it["preview"].toString() })).map { r ->
            val id = (r["file"] as String?)?.let { RunReport.idOrNull(output, File(it)) }
            val message = r["error"]?.toString() ?: "failed"
            if (id != null) linkedMapOf<String, Any?>("id" to id, "message" to message)
            else linkedMapOf<String, Any?>("message" to "${r["preview"]} · ${r["device"]} · ${r["language"]}: $message")
        } + iosErrors
        RunReport.write(output, "flutter", log.seconds, shots, errors, scope(devices, manifest, shots), mapOf("flutter" to fingerprint))
        if (o.html) Gallery.write(output, shots, log.seconds)
    }

    /** The run's scope: the devices, languages, appearances and font scales asked for (flags, config, `screens` rules) ∪ rendered. */
    internal fun scope(devices: List<Map<String, Any?>>, manifest: List<Map<*, *>>, shots: List<Map<String, Any?>>): Map<String, Any?> {
        val b = ScopeBuilder(o.previews)
        b.platforms += "flutter"
        b.devices += devices.map { it["name"] as String }
        for (r in o.screens) r.devices?.forEach { name ->
            b.devices += AppleDevices.matching(name).map { it.name }.ifEmpty { runCatching { Devices.resolve(listOf(name)).map { it.name } }.getOrDefault(emptyList()) }
        }
        b.languages += o.languages.map { it.replace('_', '-') } + o.screens.flatMap { it.languages.orEmpty() }
        b.appearances += o.appearances + o.screens.flatMap { it.appearances.orEmpty() }
        b.fontScales += o.fontScales + o.screens.flatMap { it.fontScales.orEmpty() }
        b.previews += manifest.mapNotNull { it["name"] as String? }.filter { n -> o.previews.isEmpty() || o.previews.any { glob(it).matches(n) } }
        shots.forEach(b::shot)
        return b.toJson()
    }

    companion object {
        /** One rendered result as a swiftshot-report.json screenshot (with its `renderer`). */
        internal fun reportShot(r: Map<*, *>, output: File, scale: Double?): Map<String, Any?> {
            val (w, h) = (r["size"] as String).split('x').map { it.toInt() }
            val file = File(r["file"] as String)
            return linkedMapOf<String, Any?>("file" to file.relativeTo(output).invariantSeparatorsPath, "id" to RunReport.id(output, file), "preview" to r["preview"], "device" to r["device"],
                "language" to r["language"], "appearance" to r["appearance"], "fontScale" to r["fontScale"], "width" to w, "height" to h,
                "millis" to r["millis"], "platform" to "flutter", "renderer" to r["renderer"], "source" to "${r["script"]}:${r["line"]}").apply { scale?.let { put("scale", it) } }
        }

        /** A Flutter app or package: pubspec.yaml depending on the Flutter SDK. */
        fun isProject(dir: File): Boolean {
            val pubspec = File(dir, "pubspec.yaml").takeIf { it.isFile }?.readText() ?: return false
            return Regex("""(?m)^\s+sdk:\s*flutter\s*$""").containsMatchIn(pubspec)
        }
    }
}

/** Fonts for a language's tester process: Roboto (Android), SF on a Mac (iOS), and a system font with the script for languages Roboto doesn't cover. */
class Fonts(private val material: File, private val log: Log) {
    private val home = System.getProperty("user.home")
    private fun first(vararg paths: String) = paths.map(::File).firstOrNull { it.isFile }?.path

    private val roboto = material.listFiles()?.filter { it.name.startsWith("Roboto-") }?.map { it.path }?.sorted().orEmpty()
    private val sf = listOfNotNull(first("/System/Library/Fonts/SFNS.ttf"), first("/System/Library/Fonts/SFNSItalic.ttf"))
    /** The families Flutter's typography asks for on iOS (Material's and Cupertino's). */
    private val iosFamilies = listOf("CupertinoSystemText", "CupertinoSystemDisplay")

    /**
     * One font with both the script and Latin, macOS first, then the usual Linux packages: the
     * test renderer falls back from neither a family to another nor a font to another (SF Arabic,
     * Geeza Pro or Noto Sans Arabic alone have no Latin, so "74%" would be boxes).
     */
    private val unicode = arrayOf("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/Library/Fonts/Arial Unicode.ttf")
    private val dejavu = arrayOf("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf", "/usr/share/fonts/gnu-free/FreeSans.otf")
    private val cjk = arrayOf("/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc", "/System/Library/Fonts/PingFang.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJKjp-Regular.otf", *unicode)
    private fun script(language: String): String? = when (language.substringBefore('-')) {
        "ar", "fa", "ur", "ps", "he", "yi" -> first(*unicode, *dejavu)
        "ja", "zh" -> first(*cjk)
        "ko" -> first("/System/Library/Fonts/AppleSDGothicNeo.ttc", *cjk)
        "th", "hi", "mr", "ne" -> first(*unicode, "/usr/share/fonts/truetype/freefont/FreeSans.ttf", "/usr/share/fonts/gnu-free/FreeSans.otf")
        else -> null
    }

    private val needsScript = setOf("ar", "fa", "ur", "ps", "he", "yi", "ja", "zh", "ko", "th", "hi", "mr", "ne")

    fun forLanguage(language: String, ios: Boolean = true, android: Boolean = true): Map<String, List<String>> {
        val lang = language.substringBefore('-')
        val special = if (lang in needsScript) script(language) else null
        if (lang in needsScript && special == null) log.warn("$language: no font with its script found on this machine; its text may render as boxes")
        return linkedMapOf<String, List<String>>().apply {
            if (android) put("Roboto", special?.let(::listOf) ?: roboto)
            if (ios) for (f in iosFamilies) put(f, special?.let(::listOf) ?: sf.ifEmpty { roboto })
            put("MaterialIcons", listOf(File(material, "MaterialIcons-Regular.otf").path))
        }
    }
}

/** The Android status bar's height in dp, as the Android renderer draws it: 24 dp, or the camera cutout and a little. */
object SystemBars {
    fun statusDp(d: Device): Double {
        val dp = d.density / 160.0
        val cutout = d.cutout ?: return 24.0
        return maxOf(24.0, (cutout[1] + cutout[3]) / dp + 4)
    }
}
