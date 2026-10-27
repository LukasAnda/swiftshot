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
    private val output = File(o.output).let { if (it.isAbsolute) it else File(root, o.output) }.normalize()

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
        if (o.clear) output.listFiles()?.forEach { if (it.isDirectory) it.deleteRecursively() else if (it.name.endsWith(".png") || it.name == "screenshots.html" || it.name == "swiftshot-report.json") it.delete() }
        val dir = File(root, ".dart_tool/swiftshot").apply { deleteRecursively(); mkdirs() }
        generate(dir, pkg, public, pubspec, languages, devices)
        val processes = if (o.parallel > 0) o.parallel else maxOf(1, minOf(languages.size, Runtime.getRuntime().availableProcessors()))
        log.step("${public.size} preview declarations, ${devices.size} devices, ${languages.size} languages, $processes tester processes")
        val t0 = System.nanoTime()
        val tests = languages.map { File(dir, "${file(it)}_test.dart").relativeTo(root).path }
        val cmd = listOf(File(sdk, "bin/flutter").path, "test", "--no-pub", "--concurrency=$processes", "--reporter=compact") + tests
        val pubGet = ProcessBuilder(File(sdk, "bin/flutter").path, "pub", "get").directory(root).redirectErrorStream(true).also { it.environment()["FLUTTER_ROOT"] = sdk.path }.start()
        val pubOut = pubGet.inputStream.bufferedReader().readText()
        if (pubGet.waitFor() != 0) throw CliError("flutter pub get failed:\n${pubOut.takeLast(3000)}")
        val p = ProcessBuilder(cmd).directory(root).redirectErrorStream(true).also { it.environment()["FLUTTER_ROOT"] = sdk.path }.start()
        val out = StringBuilder()
        p.inputStream.bufferedReader().forEachLine { line -> out.appendLine(line); if (o.verbose) log.step(line) }
        val status = p.waitFor()
        val results = languages.flatMap { lang ->
            File(dir, "${file(lang)}.results.jsonl").takeIf { it.isFile }?.readLines().orEmpty().filter { it.isNotBlank() }.map { Json.parse(it) as Map<*, *> }
        }
        val ok = results.filter { it["ok"] == true }
        for (r in results.filter { it["ok"] != true }) log.warn("${r["preview"]} · ${r["device"]} · ${r["language"]}: ${r["error"]} (${r["script"]}:${r["line"]})")
        if (status != 0 && results.isEmpty()) throw CliError("flutter test failed:\n${out.toString().lines().filter { it.isNotBlank() }.takeLast(40).joinToString("\n")}")
        log.ok("${ok.size} screenshots in ${"%.1f".format(Locale.ROOT, (System.nanoTime() - t0) / 1e9)}s (flutter test)")
        report(ok, results.filter { it["ok"] != true })
        log.ok("${ok.size} screenshots in ${"%.1f".format(Locale.ROOT, log.seconds)}s → $output")
        return if (ok.isNotEmpty() && ok.size == results.size) 0 else 1
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
                    "insets" to listOf(status, 0.0, if (d.type == "watch") 0.0 else 24.0, 0.0))
            }
        }
    }

    private fun file(language: String) = "swiftshot_" + language.lowercase().replace(Regex("[^a-z0-9]"), "_")

    private fun generate(dir: File, pkg: String, previews: List<DartScanner.Found>, pubspec: String, languages: List<String>, devices: List<Map<String, Any?>>) {
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
                "results" to File(dir, "${file(lang)}.results.jsonl").path,
                "fonts" to fonts.forLanguage(lang, ios = devices.any { it["platform"] == "ios" }, android = devices.any { it["platform"] == "android" }),
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

    private fun report(ok: List<Map<*, *>>, failed: List<Map<*, *>>) {
        val shots = ok.sortedWith(compareBy({ it["language"] as String }, { it["device"] as String }, { it["preview"] as String }, { it["appearance"] as String })).map { r ->
            val (w, h) = (r["size"] as String).split('x').map { it.toInt() }
            linkedMapOf<String, Any?>("file" to File(r["file"] as String).relativeTo(output).path, "preview" to r["preview"], "device" to r["device"],
                "language" to r["language"], "appearance" to r["appearance"], "fontScale" to r["fontScale"], "width" to w, "height" to h,
                "millis" to r["millis"], "platform" to "flutter", "source" to "${r["script"]}:${r["line"]}")
        }
        val errors = failed.map { "${it["preview"]} · ${it["device"]} · ${it["language"]}: ${it["error"]}" }
        output.mkdirs()
        File(output, "swiftshot-report.json").writeText(Json.write(linkedMapOf("platform" to "flutter", "totalSeconds" to log.seconds, "screenshots" to shots, "errors" to errors), "  ") + "\n")
        if (o.html) Gallery.write(output, shots, log.seconds)
    }

    companion object {
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
