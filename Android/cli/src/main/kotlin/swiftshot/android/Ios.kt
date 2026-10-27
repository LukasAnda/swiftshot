package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.security.MessageDigest

/**
 * Compose Multiplatform's iOS target. Kotlin/Native has no reflection, so the previews found on
 * the JVM targets get generated public wrappers in the module's iOS sources (private previews
 * become internal in a copy of the sources, so the wrappers can call them), each returning the
 * preview as a Compose UIViewController. Gradle links them into a dynamic framework; a generated
 * SwiftUI host app shows each one as a `#Preview`; Swiftshot's iOS pipeline renders those on
 * iOS devices, without a simulator.
 */
class Ios(private val o: Options, private val log: Log, private val output: File) {
    data class Shot(val file: String, val preview: String, val device: String, val language: String, val appearance: String, val width: Int, val height: Int)

    val available: Boolean
        get() = System.getProperty("os.name").lowercase().contains("mac") && File("/usr/bin/xcrun").canExecute() && swiftshot() != null

    /** The iOS renderer: the swiftshot binary next to this jar, else on PATH. */
    private fun swiftshot(): File? {
        val self = File(Ios::class.java.protectionDomain.codeSource.location.toURI()).parentFile
        val candidates = listOf(File(self, "swiftshot"), File(self, "../../../../bin/swiftshot")) +
            (System.getenv("PATH") ?: "").split(':').map { File(it, "swiftshot") }
        return candidates.firstOrNull { it.canExecute() && isNative(it) }?.canonicalFile
    }

    // On Linux the launcher script is named swiftshot too; the iOS renderer is the Mach-O binary.
    private fun isNative(f: File) = runCatching { f.inputStream().use { val b = ByteArray(4); it.read(b); b[0] == 0xCF.toByte() && b[1] == 0xFA.toByte() } }.getOrDefault(false)

    /**
     * Renders [previews] (found on a JVM target of [module]) for iOS. [counts] are how many values
     * each @PreviewParameter provider gave on the JVM, so each gets one #Preview per value.
     */
    fun run(module: Module, previews: List<Preview>, counts: Map<String, Int>, sizes: Map<String, Pair<Int, Int>> = emptyMap()): List<Shot> {
        val json = module.json
        val callable = previews.distinctBy { it.composable to it.name }
        if (callable.isEmpty()) return emptyList()
        log.step("${module.path} (ios): generating ${callable.size} previews for the iOS framework")
        val names = rewriteSources(json, callable)
        writeRegistry(File(json["registry"] as String), callable, names)
        Gradle.run(o, log, listOf("${module.path}:${json["linkTask"]}", "${module.path}:${json["resourcesTask"]}"), listOf("-Pswiftshot.ios=1"), "Linking the iOS framework")
        val app = hostApp(json, callable, counts, sizes)
        return render(app)
    }

    /**
     * Swiftshot's copy of the iOS compilation's source sets, in which each private preview is
     * internal (two private previews with one name in a package are renamed apart). Returns the
     * name to call for each preview.
     */
    private fun rewriteSources(json: Map<*, *>, previews: List<Preview>): Map<Preview, String> {
        val root = File(json["sources"] as String)
        val private = previews.filter { it.isPrivate && it.sourceFile != null }
        val names = callNames(previews)
        // Only the source folders that declare a private preview are copied (generated folders and
        // the rest stay as they are, so incremental compilation keeps working).
        val build = File(json["projectDir"] as String, "build").path
        val keep = HashSet<File>()
        @Suppress("UNCHECKED_CAST")
        val dirs = (json["sourceSets"] as Map<String, List<String>>).values.flatten().distinct().map(::File)
            .filter { it.isDirectory && !it.path.startsWith(build) }
        for (dir in dirs) {
            val files = dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
            val edits = files.associateWith { f -> private.filter { it.sourceFile == f.name } }.filterValues { it.isNotEmpty() }
                .mapValues { (f, here) -> rewrite(f.readText(), here, names) }.filter { (f, t) -> t != f.readText() }
            if (edits.isEmpty()) continue
            val target = File(root, md5(dir.absolutePath))
            for (f in dir.walkTopDown().filter { it.isFile }) {
                val out = File(target, f.relativeTo(dir).path)
                keep += out
                out.parentFile.mkdirs()
                val text = edits[f]
                if (text != null) { if (!out.isFile || out.readText() != text) out.writeText(text) }
                else if (!out.isFile || out.length() != f.length() || out.lastModified() < f.lastModified()) f.copyTo(out, overwrite = true)
            }
        }
        // Folders and files that no longer need a copy go.
        if (root.isDirectory) root.walkBottomUp().filter { (it.isFile && it !in keep) || (it.isDirectory && it != root && it.listFiles()?.isEmpty() == true) }.forEach { it.delete() }
        return names
    }

    private fun writeRegistry(dir: File, previews: List<Preview>, names: Map<Preview, String>) {
        val body = registry(previews, names)
        dir.mkdirs()
        val file = File(dir, "SwiftshotPreviews.kt")
        if (!file.isFile || file.readText() != body) file.writeText(body)
    }

    /** SwiftshotHost.app: the framework, its Compose resources, and a #Preview per preview. */
    private fun hostApp(json: Map<*, *>, previews: List<Preview>, counts: Map<String, Int>, sizes: Map<String, Pair<Int, Int>>): File {
        val framework = File(json["framework"] as String)
        val app = File(File(json["registry"] as String).parentFile, "SwiftshotHost.app")
        val swift = hostMain(previews, counts, sizes)
        val build = File(app.parentFile, "host")
        build.mkdirs()
        val main = File(build, "main.swift")
        val binary = File(app, "SwiftshotHost")
        app.mkdirs()
        val frameworks = File(app, "Frameworks")
        File(frameworks, "SwiftshotHost.framework").deleteRecursively()
        framework.copyRecursively(File(frameworks, "SwiftshotHost.framework"), overwrite = true)
        File(app, "compose-resources").deleteRecursively()
        File(json["resources"] as String).takeIf { it.isDirectory }?.copyRecursively(File(app, "compose-resources"), overwrite = true)
        // The languages the app declares: iOS lays an app out right to left only in a language
        // its bundle lists (as a real app's localizations do).
        val localizations = o.languages.flatMap { listOf(it.replace('_', '-'), it.substringBefore('-').substringBefore('_')) }.distinct()
            .joinToString("") { "<string>$it</string>" }
        File(app, "Info.plist").writeText(INFO_PLIST.replace("</dict></plist>", "<key>CFBundleLocalizations</key><array>$localizations</array>\n</dict></plist>"))
        if (!binary.isFile || !main.isFile || main.readText() != swift) {
            main.writeText(swift)
            log.step("Building the iOS host app")
            sh(listOf("xcrun", "-sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios17.0-simulator", "-Onone", "-module-name", "SwiftshotHostApp",
                "-F", frameworks.path, "-framework", "SwiftshotHost", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                main.path, "-o", binary.path), "the iOS host app")
        }
        sh(listOf("codesign", "-s", "-", "--force", "--deep", app.path), "signing the iOS host app")
        return app
    }

    /** Swiftshot's iOS pipeline on the host app, into the same output folder. */
    /**
     * Renders a host app's previews with the iOS renderer into [iosOut]: its exit status and its
     * report's screenshots (file relative to [iosOut], preview, device, language, appearance, size).
     */
    internal fun renderApp(app: File, devices: List<String>, iosOut: File, extra: List<String> = emptyList()): Pair<Int, List<Map<*, *>>> {
        val tool = swiftshot() ?: throw CliError("The iOS renderer (swiftshot) is not installed next to swiftshot-android.jar.")
        iosOut.deleteRecursively()
        val cmd = mutableListOf(tool.path, "--platform", "ios", "run", "--app", app.path,
            "--devices", devices.joinToString(","),
            "--languages", o.languages.joinToString(","), "--appearances", o.appearances.joinToString(","),
            "--output", iosOut.path, "--no-html")
        // Flutter's text-scale variants are "<name> @1.3x" in its host app.
        if (o.previews.isNotEmpty()) cmd += listOf("--previews", o.previews.flatMap { listOf(it, "$it @*") }.joinToString(","))
        cmd += extra
        if (o.iosVersions.isNotEmpty()) cmd += listOf("--ios", o.iosVersions.joinToString(","))
        if (o.verbose) cmd += "--verbose"
        log.step("Rendering for iOS")
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        p.inputStream.bufferedReader().forEachLine { System.err.println("  $it") }
        val status = p.waitFor()
        val report = File(iosOut, "swiftshot-report.json")
        if (!report.isFile) throw CliError("The iOS renderer failed (exit $status).")
        return status to ((Json.parse(report.readText()) as Map<*, *>)["screenshots"] as List<*>).map { it as Map<*, *> }
    }

    /** Existing screenshots in [dir] into their device (plain frames) under [framed]. */
    internal fun frame(dir: File, framed: File): Boolean {
        val tool = swiftshot() ?: return false
        val cmd = listOf(tool.path, "--platform", "ios", "frame", dir.path, "--frame", "plain", "--frame-output", framed.path) +
            if (o.acceptBezelLicense) listOf("--accept-bezel-license") else emptyList()
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText()
        if (p.waitFor() != 0) { log.warn("iOS frames failed:\n${out.lines().takeLast(10).joinToString("\n")}"); return false }
        return true
    }

    private fun render(app: File): List<Shot> {
        val iosOut = File(output, ".ios")
        val (status, shots) = renderApp(app, o.iosDevices.ifEmpty { defaultDevices }, iosOut)
        val result = mutableListOf<Shot>()
        for (s in shots) {
            val rel = s["file"] as String
            val target = File(output, rel)
            target.parentFile.mkdirs()
            File(iosOut, rel).copyTo(target, overwrite = true)
            result += Shot(rel, s["preview"] as String, s["device"] as String, s["language"] as String, s["appearance"] as String? ?: "light",
                (s["width"] as Number?)?.toInt() ?: 0, (s["height"] as Number?)?.toInt() ?: 0)
        }
        iosOut.deleteRecursively()
        if (status != 0) log.warn("iOS: some screenshots failed (exit $status)")
        return result
    }

    private fun sh(cmd: List<String>, what: String) {
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText()
        if (p.waitFor() != 0) throw CliError("Failed $what:\n${out.trim().lines().takeLast(30).joinToString("\n")}")
    }

    /** Groovy's String.md5(), which the init script uses to find the copy of a folder. */
    private fun md5(s: String) = MessageDigest.getInstance("MD5").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    companion object {
        val defaultDevices = listOf("iPhone 17 Pro Max", "iPad Pro 13-inch (M5)")

        /** The name each preview is called by: private previews sharing a name in one package are renamed apart. */
        internal fun callNames(previews: List<Preview>): Map<Preview, String> {
            val private = previews.filter { it.isPrivate && it.sourceFile != null }
            val clashes = private.groupBy { it.composable.substringBeforeLast('.').substringBeforeLast('.') + "." + it.function }.filterValues { it.size > 1 }.values.flatten().toSet()
            val names = HashMap<Preview, String>()
            for (p in previews) names[p] = if (p in clashes) "${p.function}__swiftshot${hash(p.composable).take(6)}" else p.function
            return names
        }

        /** A source file's text with each of its private previews [here] made internal under its call name. */
        internal fun rewrite(text: String, here: List<Preview>, names: Map<Preview, String>): String {
            var t = text
            val pkg = Regex("""^\s*package\s+([\w.]+)""", RegexOption.MULTILINE).find(t)?.groupValues?.get(1) ?: ""
            for (p in here) {
                if (!p.composable.startsWith("$pkg.")) continue
                val name = names[p]!!
                t = t.replace(Regex("""\bprivate(\s+)fun(\s+)${Regex.escape(p.function)}\b"""), "internal$1fun$2$name")
                if (name != p.function) t = t.replace(Regex("""\b${Regex.escape(p.function)}\s*\("""), "$name(")
            }
            return t
        }

        /** SwiftshotPreviews.kt: each preview as a Compose view controller. */
        internal fun registry(previews: List<Preview>, names: Map<Preview, String>): String = buildString {
            appendLine("// Generated by Swiftshot for its iOS host app: each preview as a Compose view controller.")
            appendLine("@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)")
            appendLine()
            appendLine("package swiftshot.generated")
            appendLine()
            appendLine("import androidx.compose.ui.window.ComposeUIViewController")
            appendLine("import platform.UIKit.UIViewController")
            appendLine()
            appendLine("private var swiftshotEarlier = emptySet<Any>()")
            appendLine()
            appendLine("/** Before a preview is shown: the recomposers running now are earlier previews'. */")
            appendLine("fun swiftshotComposeMark() { swiftshotEarlier = androidx.compose.runtime.Recomposer.runningRecomposers.value.toSet() }")
            appendLine()
            appendLine("/** Whether the preview's Compose has work left: a recomposition, or an animation waiting for its next frame. */")
            appendLine("fun swiftshotComposeBusy(): Boolean = androidx.compose.runtime.Recomposer.runningRecomposers.value.any { it !in swiftshotEarlier && it.hasPendingWork }")
            appendLine()
            previews.forEachIndexed { i, p ->
                val call = p.composable.substringBeforeLast('.').substringBeforeLast('.') + "." + names[p]!!
                val config = "configure = { enforceStrictPlistSanityCheck = false; parallelRendering = false }"
                if (p.provider != null) {
                    appendLine("fun swiftshotPreview$i(index: Int): UIViewController = ComposeUIViewController($config) {")
                    appendLine("    $call(${p.provider}().values.elementAt(index))")
                    appendLine("}")
                } else {
                    appendLine("fun swiftshotPreview$i(): UIViewController = ComposeUIViewController($config) { $call() }")
                }
            }
        }

        /** The host app's main.swift: a #Preview per preview (per provider value), at its measured size. */
        internal fun hostMain(previews: List<Preview>, counts: Map<String, Int>, sizes: Map<String, Pair<Int, Int>>): String = buildString {
            appendLine("import SwiftUI")
            appendLine("import SwiftshotHost")
            appendLine()
            appendLine("/// Marks this app as starting Swiftshot's agent from main, once every framework (Kotlin/Native's")
            appendLine("/// runtime among them) is initialized; without a simulator the agent would start earlier.")
            appendLine("@_cdecl(\"swiftshot_host_main\") public func swiftshotHostMain() {}")
            appendLine("@_cdecl(\"swiftshot_compose_busy\") public func swiftshotComposeBusy() -> Int32 { SwiftshotPreviewsKt.swiftshotComposeBusy() ? 1 : 0 }")
            appendLine("@_cdecl(\"swiftshot_compose_mark\") public func swiftshotComposeMark() { SwiftshotPreviewsKt.swiftshotComposeMark() }")
            appendLine()
            appendLine("struct SwiftshotHostApp: App { var body: some Scene { WindowGroup { Color.clear } } }")
            appendLine()
            previews.forEachIndexed { i, p ->
                val name = p.name.replace("\\", "\\\\").replace("\"", "\\\"")
                // A component (no system UI) at the size the JVM render measured, in points (= dp).
                val size = sizes[p.composable + "|" + p.name]
                val traits = size?.let { (w, h) -> ", traits: .fixedLayout(width: $w, height: $h)" } ?: ""
                if (p.provider != null) {
                    val n = minOf(counts[p.composable + "|" + p.name] ?: 1, p.providerLimit)
                    for (k in 0 until n) appendLine("#Preview(\"${name}_${k + 1}\"$traits) { SwiftshotPreviewsKt.swiftshotPreview$i(index: $k) }")
                } else appendLine("#Preview(\"$name\"$traits) { SwiftshotPreviewsKt.swiftshotPreview$i() }")
            }
            appendLine()
            appendLine("if let start = dlsym(UnsafeMutableRawPointer(bitPattern: -2), \"SwiftshotAgentStartNow\") {")
            appendLine("    unsafeBitCast(start, to: (@convention(c) () -> Void).self)()")
            appendLine("}")
            appendLine("SwiftshotHostApp.main()")
        }

        private fun hash(s: String) = MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

        const val INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.swiftshot.host</string>
<key>CFBundleExecutable</key><string>SwiftshotHost</string>
<key>CFBundleName</key><string>SwiftshotHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>CADisableMinimumFrameDurationOnPhone</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
<key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
</dict></plist>
"""
    }
}
