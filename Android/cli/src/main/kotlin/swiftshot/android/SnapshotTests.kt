package swiftshot.android

import java.io.File
import java.util.Locale

/**
 * A `@Preview` function in a module's sources; [fqn] is `<owner class>.<function>`, the form of [Preview.composable].
 * [own]: the settings its `@Preview` annotations (direct or through multipreviews) set, leaving out those that set none.
 */
data class SourcePreview(val module: String, val fqn: String, val function: String, val isPrivate: Boolean = false, val own: List<PreviewOwn> = emptyList())

/** What one `@Preview` sets itself; null when it doesn't, [unreadable] when it sets one to something not read here. */
data class PreviewOwn(val device: String? = null, val locale: String? = null, val night: Boolean? = null, val fontScale: Double? = null, val unreadable: Boolean = false) {
    val isEmpty get() = this == PreviewOwn()
}

/** What a snapshot test renders. */
sealed interface Target {
    /** Calls these `@Preview` functions (possibly wrapped in a theme or layout). */
    data class Previews(val fqns: List<String>) : Target
    /**
     * Renders every preview in [packages] (all packages when empty), private ones only with [includePrivate]:
     * a preview scanner, Roborazzi's generated preview tests, Showkase.
     */
    data class AllPreviews(val packages: List<String> = emptyList(), val includePrivate: Boolean = true) : Target
    /** Anything else, with what it renders as written, e.g. `CheckoutScreen(state)`. */
    data class Uncovered(val call: String) : Target
}

/** One snapshot a test takes; [sourceSet] is the test source set's directory name (`test`, `desktopTest`, …). */
data class SnapshotTest(
    val module: String, val file: File, val line: Int, val tool: SnapshotTool,
    val target: Target, val device: DeviceSource, val settings: TestSettings, val sourceSet: String,
)

/**
 * Reads Paparazzi and Roborazzi tests from source: what each snapshot renders, and the device and settings
 * it renders with. Calls are resolved through the calling file's package and imports, and followed into helper
 * functions in any scanned source (the modules' tests and main sources, and the modules they depend on).
 * Anything not recognised counts as not covered.
 */
object SnapshotTests {
    /** The `@Preview`s AndroidX's multipreviews expand to (ui-tooling-preview, wear-tooling-preview). */
    private val multipreviewsBuiltIn: Map<String, List<PreviewOwn>> = run {
        fun devices(vararg d: String) = d.map { PreviewOwn(device = it) }
        mapOf(
            "PreviewLightDark" to listOf(PreviewOwn(), PreviewOwn(night = true)),
            "PreviewFontScale" to listOf(0.85, 1.0, 1.15, 1.3, 1.5, 1.8, 2.0).map { PreviewOwn(fontScale = it) },
            "PreviewScreenSizes" to devices("spec:width=411dp,height=891dp", "spec:width=673dp,height=841dp", "spec:width=1280dp,height=800dp,dpi=240", "spec:width=1920dp,height=1080dp,dpi=160"),
            "PreviewDynamicColors" to listOf(PreviewOwn()),
            "WearPreviewDevices" to devices("id:wearos_large_round", "id:wearos_small_round", "id:wearos_square"),
            "WearPreviewSmallRound" to devices("id:wearos_small_round"),
            "WearPreviewLargeRound" to devices("id:wearos_large_round"),
            "WearPreviewSquare" to devices("id:wearos_square"),
            "WearPreviewFontScales" to listOf(0.94, 1.0, 1.06, 1.12, 1.18, 1.24).map { PreviewOwn(device = "id:wearos_small_round", fontScale = it) },
        )
    }

    /** `Devices.X` constants that aren't `id:` + the name in lower case. */
    private val deviceConstants = mapOf(
        "PHONE" to "spec:width=411dp,height=891dp", "FOLDABLE" to "spec:width=673dp,height=841dp",
        "TABLET" to "spec:width=1280dp,height=800dp,dpi=240", "DESKTOP" to "spec:width=1920dp,height=1080dp,dpi=160",
    )

    /** The `@Preview` functions in the main/common sources of [module] and the modules it depends on with `project(...)`. */
    fun previews(module: SnapshotModule, all: Map<String, File>): List<SourcePreview> {
        val modules = linkedMapOf(module.path to module.dir)
        dependencies(module.path, module.dir, all).forEach { (p, d) -> modules.putIfAbsent(p, d) }
        val sources = modules.mapValues { (_, d) -> mainSources(d).map(::KotlinSource) }
        val multipreviews = multipreviews((all.values + module.dir).distinct().flatMap(::mainSources).filter { it.readText().contains("annotation") }.map(::KotlinSource))
        return sources.flatMap { (path, srcs) -> srcs.flatMap { previewsIn(path, it, multipreviews) } }
            .distinct().sortedWith(compareBy({ it.module }, { it.fqn }))
    }

    /** [all] is every project of the build (path → dir); by default read from the settings file above the modules. */
    fun scan(modules: List<SnapshotModule>, previews: List<SourcePreview>, all: Map<String, File>? = null): List<SnapshotTest> {
        if (modules.isEmpty()) return emptyList()
        return Scan(modules, Resolver(previews), all ?: projectsAround(modules)).tests()
    }

    private fun projectsAround(modules: List<SnapshotModule>): Map<String, File> {
        val own = modules.associate { it.path to it.dir }
        val root = generateSequence(modules.first().dir.absoluteFile) { it.parentFile }
            .filter { d -> listOf("settings.gradle.kts", "settings.gradle").any { File(d, it).isFile } }.lastOrNull() ?: return own
        return SnapshotModules.projects(root) + own
    }

    private fun sourceFiles(dir: File) = dir.walkTopDown().onEnter { it.name != "build" }.filter { it.isFile && (it.extension == "kt" || it.extension == "java") }.sortedBy { it.path }.toList()

    private fun mainSources(dir: File): List<File> = File(dir, "src").listFiles { f -> f.isDirectory && !f.name.contains("test", ignoreCase = true) }.orEmpty()
        .sortedBy { it.name }.flatMap(::sourceFiles).filter { it.extension == "kt" }

    private fun buildFile(dir: File) = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }

    /** Modules named by `project(":x")` or a type-safe `projects.x.y` accessor in the build file. */
    private fun dependencies(path: String, dir: File, all: Map<String, File>): Map<String, File> {
        val text = SnapshotModules.strip(buildFile(dir)?.readText() ?: return emptyMap())
        val paths = Regex("""\bproject\s*\(\s*(?:path\s*=\s*)?["'](:[^"']+)["']""").findAll(text).map { it.groupValues[1] }.toMutableList()
        fun accessor(p: String) = p.removePrefix(":").split(':').joinToString(".") { seg ->
            seg.split('-', '_').mapIndexed { i, s -> if (i == 0) s else s.replaceFirstChar(Char::uppercaseChar) }.joinToString("")
        }
        for (m in Regex("""\bprojects\.([\w.]+)""").findAll(text)) {
            val written = m.groupValues[1].split('.')
            all.keys.filter { written.take(accessor(it).split('.').size).joinToString(".") == accessor(it) }.maxByOrNull { it.length }?.let(paths::add)
        }
        return paths.distinct().filter { it != path }.mapNotNull { p -> all[p]?.let { p to it } }.toMap()
    }

    /** Annotation classes that carry `@Preview` (directly or through another multipreview) → the `@Preview`s they expand to. */
    private fun multipreviews(srcs: List<KotlinSource>): Map<String, List<PreviewOwn>> {
        val found = multipreviewsBuiltIn.toMutableMap()
        val declared = srcs.flatMap { src -> Regex("""\bannotation\s+class\s+(\w+)""").findAll(src.mask).map { it.groupValues[1] to (src to src.annotationsBefore(it.range.first)) }.toList() }
        var changed = true
        while (changed) {
            changed = false
            for ((n, d) in declared) if (n !in found && d.second.any { it.name == "Preview" || it.name in found }) { found[n] = own(d.first, d.second, found); changed = true }
        }
        return found
    }

    private fun own(src: KotlinSource, anns: List<Ann>, multipreviews: Map<String, List<PreviewOwn>>): List<PreviewOwn> =
        anns.flatMap { if (it.name == "Preview") listOf(own(src, it)) else multipreviews[it.name].orEmpty() }

    /** `@Preview(device = …, locale = …, uiMode = …, fontScale = …)` as written. */
    private fun own(src: KotlinSource, ann: Ann): PreviewOwn {
        var o = PreviewOwn()
        for ((name, range) in ann.open?.let(src::args).orEmpty()) {
            val v = src.text(range).trim()
            val literal = Regex("""^"([^"$\\]*)"$""").matchEntire(v)?.groupValues?.get(1)
            o = when (name) {
                "device" -> (literal ?: Regex("""^(?:[\w.]*\.)?Devices\.(\w+)$""").matchEntire(v)?.groupValues?.get(1)
                    ?.let { deviceConstants[it] ?: "id:" + it.lowercase().replace("wear_os_", "wearos_") })?.let { o.copy(device = it) }
                "locale" -> literal?.let { o.copy(locale = it) }
                "uiMode" -> night(v)?.let { o.copy(night = it.single()) }
                "fontScale" -> Regex("""^(\d+(?:\.\d+)?)[fF]?$""").matchEntire(v)?.groupValues?.get(1)?.toDouble()?.let { o.copy(fontScale = it) }
                else -> o
            } ?: o.copy(unreadable = true)
        }
        return o
    }

    /** A `uiMode` value's night bit, as one element (null when it leaves it unset); null when it can't be read. */
    private fun night(v: String): List<Boolean?>? {
        if (v.contains("UI_MODE_NIGHT_YES")) return listOf(true)
        if (v.contains("UI_MODE_NIGHT_NO")) return listOf(false)
        if (Regex("""^(?:[\w.]*\.)?UI_MODE_TYPE_\w+$""").matches(v)) return listOf(null)
        val n = Regex("""^(?:0[xX]([0-9a-fA-F]+)|(\d+))$""").matchEntire(v)?.let { it.groupValues[1].toIntOrNull(16) ?: it.groupValues[2].toIntOrNull() } ?: return null
        return listOf(when (n and 0x30) { 0x20 -> true; 0x10 -> false; else -> null })
    }

    private fun previewsIn(module: String, src: KotlinSource, multipreviews: Map<String, List<PreviewOwn>>): List<SourcePreview> = src.funs.mapNotNull { f ->
        val names = f.annotations.map { it.name }
        if ("Composable" !in names || names.none { it == "Preview" || it in multipreviews }) return@mapNotNull null
        if (src.funs.any { it.body != null && f.keyword in it.body }) return@mapNotNull null // local function
        // Modifiers between the annotations and `fun`.
        val modifiers = Regex("""(?:\b[a-z]+\s+)*$""").find(src.mask.substring(maxOf(0, f.keyword - 120), f.keyword))!!.value.split(Regex("\\s+"))
        SourcePreview(
            module, fqn(src, f), f.name,
            isPrivate = "private" in modifiers, own = own(src, f.annotations, multipreviews).filterNot { it.isEmpty },
        )
    }

    /** `<package>.<owner class>.<function>` for a function declared in [src]. */
    private fun fqn(src: KotlinSource, f: Decl): String {
        val chain = src.classes.filter { it.body != null && f.keyword in it.body }.sortedBy { it.body!!.first }.map { it.name }
        val owner = chain.joinToString("$").ifEmpty { src.facade }
        return listOf(src.pkg, owner).filter { it.isNotEmpty() }.joinToString(".") + "." + f.name
    }

    /** Matches called names to previews through the calling file's imports and package. */
    private class Resolver(previews: List<SourcePreview>) {
        private val byFunction = previews.groupBy { it.function }
        private val fqns = previews.map { it.fqn }.toSet()

        fun resolve(src: KotlinSource, name: String): String? {
            val parts = name.split('.')
            val fn = parts.last()
            if (parts.size == 1) {
                // A function of that name in the calling file (a test's own composable) is the one called.
                val local = src.funs.filter { it.name == fn }
                if (local.isNotEmpty() && local.none { fqn(src, it) in fqns }) return null
                src.imports[fn]?.let { fq -> return pick(fq.substringAfterLast('.'), listOf(fq.substringBeforeLast('.', ""))) }
                return pick(fn, listOf(src.pkg)) ?: pick(fn, src.stars)
            }
            val q = parts.dropLast(1).joinToString(".")
            val head = parts.first()
            val options = listOfNotNull(src.imports[head]?.let { (listOf(it) + parts.drop(1).dropLast(1)).joinToString(".") }, q, if (src.pkg.isEmpty()) null else "${src.pkg}.$q") +
                src.stars.map { "$it.$q" }
            return options.firstNotNullOfOrNull { pick(fn, listOf(it)) }
        }

        /** The one preview named [fn] at top level of a package in [quals] or in an object named by one; null if none or ambiguous. */
        private fun pick(fn: String, quals: List<String>): String? {
            val found = byFunction[fn].orEmpty().map { it.fqn }.distinct().filter { fqn ->
                val owner = fqn.substringBeforeLast('.')
                quals.any { q -> owner.substringBeforeLast('.', "") == q || owner.replace('$', '.') == q }
            }
            return found.singleOrNull() ?: found.filter { it.substringBeforeLast('.').endsWith("Kt") }.singleOrNull()
        }
    }

    /** One qualifier source in Robolectric's order; [value] null when it can't be read. [fromPreview]: set from a preview's own device. */
    private class Layer(val value: String?, val label: String?, val expression: String, val fromPreview: Boolean = false)

    /** A recognised snapshot call; [content] is the composable lambda it renders; [scannedReceiver] for `preview.captureRoboImage(…)`. */
    private class Site(val pos: Int, val end: Int, val tool: SnapshotTool, val content: IntRange?, val receiver: String?, val fn: Decl?, val scannedReceiver: Boolean = false)

    /** A function on a call path: [cut] is where the path leaves it, through [call] (null at the snapshot itself). */
    private class Link(val fs: FileScan, val decl: Decl?, val cut: Int, val call: Call?)

    /** From a test function down to a snapshot call ([site]), or to a helper that can't be followed ([unfollowed]). */
    private class Path(val links: List<Link>, val site: Site?, val unfollowed: String? = null)

    /** A source file with the snapshot calls in it. [moduleDir] is its module's; [isTest] for snapshot modules' test sources. */
    private class FileScan(val src: KotlinSource, val module: String, val moduleDir: File, val sourceSet: String, val isTest: Boolean, val tools: Set<SnapshotTool>) {
        val mask = src.mask
        val java = src.java
        val paparazzi: Map<String, Int> = Regex(if (java) """\bPaparazzi\s+(\w+)\s*=\s*new\s+(?:app\.cash\.paparazzi\.)?Paparazzi\s*\("""
            else """\b(?:val|var)\s+(\w+)\s*(?::\s*[\w.]+\s*)?=\s*(?:app\.cash\.paparazzi\.)?Paparazzi\s*\(""")
            .findAll(mask).associate { it.groupValues[1] to it.range.last }
        /** Parameters typed `Paparazzi` (`fun shot(rule: Paparazzi)`): the caller passes the rule in. */
        val paparazziParams = Regex("""[(,]\s*(\w+)\s*:\s*(?:app\.cash\.paparazzi\.)?Paparazzi\b(?!\s*\()""").findAll(mask).map { it.groupValues[1] }.toSet()
        /** Values a scanned preview is passed in as: `preview: ComposablePreview<…>`, `component: ShowkaseBrowserComponent`. */
        val scannedValues = Regex("""\b(\w+)\s*:\s*(?:ComposablePreview\s*<|ShowkaseBrowserComponent\b)""").findAll(mask).map { it.groupValues[1] }.toSet()
        /** What the file's preview scanners (or Showkase) return; null when there is none. */
        val scanned: Target? = scanned()
        val sites: List<Site> = sites()

        fun isTest(fn: Decl) = fn.annotations.any { it.name == "Test" || it.name.endsWith("Test") || it.name == "TestFactory" || it.name == "Theory" }
        fun isBefore(fn: Decl) = fn.annotations.any { it.name in setOf("Before", "BeforeEach", "BeforeTest") }
        fun helper(fn: Decl) = !java && !isTest(fn) && !isBefore(fn)
        fun befores(cls: Decl?): List<Decl> = if (cls == null) emptyList() else src.funs.filter { it.body != null && src.classAt(it.keyword) == cls && isBefore(it) }

        /** Calls made directly in [fn]'s body, leaving out the snapshot calls themselves. */
        val callsIn = HashMap<Decl, List<Call>>()
        fun calls(fn: Decl) = callsIn.getOrPut(fn) { src.calls(fn.body!!).filter { c -> src.fnAt(c.nameAt) == fn && sites.none { it.pos == c.start } } }

        private fun sites(): List<Site> {
            val out = mutableListOf<Site>()
            val imported = src.imports.values.any { it.startsWith("app.cash.paparazzi") }
            for (m in Regex("""\b(\w+)\s*\.\s*(snapshot|gif)\s*(?=[({])""").findAll(mask)) {
                val recv = m.groupValues[1]
                val fn = src.fnAt(m.range.first)
                val extension = recv == "this" && fn?.receiver == "Paparazzi"
                if (recv !in paparazzi && recv !in paparazziParams && !extension && !(imported && recv.contains("paparazzi", ignoreCase = true))) continue
                val (end, _, lambda) = src.callAt(m.range.last + 1)
                val content = if (m.groupValues[2] == "snapshot" && !java) lambda else null
                out += Site(m.range.first, end, SnapshotTool.PAPARAZZI, content, recv, fn)
            }
            // `fun Paparazzi.snapAll() = snapshot { … }`: the implicit receiver is the rule.
            for (m in Regex("""(?<![\w.`])(snapshot|gif)\s*(?=[({])""").findAll(mask)) {
                val fn = src.fnAt(m.range.first) ?: continue
                if (fn.receiver != "Paparazzi" || src.isDeclaration(m.range.first)) continue
                val (end, _, lambda) = src.callAt(m.range.last + 1)
                out += Site(m.range.first, end, SnapshotTool.PAPARAZZI, if (m.groupValues[1] == "snapshot") lambda else null, "this", fn)
            }
            for (m in Regex("""\b(captureRoboImage|captureScreenRoboImage|captureRoboGif|captureRoboLastImage|captureRoboAllImage)\s*(?=[({])""").findAll(mask)) {
                if (src.isDeclaration(m.range.first)) continue
                val start = src.chainStart(m.range.first)
                val receiver = mask.substring(start, m.range.first)
                val (end, _, lambda) = src.callAt(m.range.last + 1)
                val fn = src.fnAt(m.range.first)
                val name = m.groupValues[1]
                val scannedReceiver = name == "captureRoboImage" && lambda == null && Regex("""^\s*(\w+)\s*\.\s*$""").find(receiver)?.groupValues?.get(1) in scannedValues
                val content = when {
                    java || scannedReceiver -> null
                    name == "captureRoboImage" && lambda != null -> lambda
                    (name == "captureRoboImage" && Regex("""\bonRoot\s*\([^()]*\)\s*\.\s*$""").containsMatchIn(receiver)) ||
                        (name == "captureScreenRoboImage" && lambda == null) -> setContent(fn, m.range.first)
                    else -> null
                }
                out += Site(start, end, SnapshotTool.ROBORAZZI, content, null, fn, scannedReceiver)
            }
            return out
        }

        /** The last `setContent { … }` before [pos] in [fn], else in the class's `@Before` functions. */
        fun setContent(fn: Decl?, pos: Int): IntRange? {
            val re = Regex("""\bsetContent\s*\{""")
            fun last(range: IntRange, before: Int) = re.findAll(mask).filter { it.range.first in range && it.range.first < before }.lastOrNull()
                ?.let { val o = it.range.last; o + 1 until src.close(o) }
            fn?.body?.let { b -> last(b, pos)?.let { return it } }
            return befores(src.classAt(pos)).firstNotNullOfOrNull { b -> last(b.body!!, Int.MAX_VALUE) }
        }

        private fun scanned(): Target? {
            val found = mutableListOf<Target>()
            for (m in Regex("""\b(?:\w*ComposablePreviewScanner|JvmAnnotationScanner)\s*\(\s*\)""").findAll(mask)) {
                var packages = emptyList<String>()
                var private = false
                var filtered = false
                for ((name, args) in src.calledOn(m.range.last + 1)) when {
                    name == "scanPackageTrees" -> packages = args?.let { src.literals(it) } ?: run { filtered = true; emptyList() }
                    name == "includePrivatePreviews" -> private = true
                    name == "scanAllPackages" || name == "getPreviews" || name.startsWith("includeAnnotationInfo") || name in harmlessListCalls -> {}
                    else -> filtered = true
                }
                found += if (filtered) Target.Uncovered("filtered previews") else Target.AllPreviews(packages, private)
            }
            // Showkase lists the previews its processor can call, so public ones only.
            if (Regex("""\bShowkase\w*\b""").containsMatchIn(mask)) found += Target.AllPreviews(emptyList(), includePrivate = false)
            return found.distinct().let { if (it.size > 1) Target.Uncovered("filtered previews") else it.firstOrNull() }
        }
    }

    private class Scan(val modules: List<SnapshotModule>, val resolver: Resolver, val all: Map<String, File>) {
        val tests: List<FileScan> = modules.flatMap { m ->
            // testFixtures holds helpers other modules' tests call: read with the library sources, not as tests.
            File(m.dir, "src").listFiles { f -> f.isDirectory && f.name.contains("test", ignoreCase = true) && f.name != "testFixtures" }.orEmpty().sortedBy { it.name }
                .flatMap { d -> sourceFiles(d).map { FileScan(KotlinSource(it), m.path, m.dir, d.name, true, m.tools) } }
        }

        /** Main sources of the snapshot modules and of every module they depend on (and its test fixtures). */
        val library: List<FileScan> = run {
            val seen = linkedMapOf<String, File>()
            val queue = ArrayDeque(modules.map { it.path to it.dir })
            while (queue.isNotEmpty()) {
                val (p, d) = queue.removeFirst()
                if (seen.putIfAbsent(p, d) != null) continue
                dependencies(p, d, all).forEach { queue.addLast(it.key to it.value) }
            }
            seen.flatMap { (p, d) ->
                File(d, "src").listFiles { f -> f.isDirectory && (!f.name.contains("test", ignoreCase = true) || f.name == "testFixtures") }.orEmpty().sortedBy { it.name }
                    .flatMap { s -> sourceFiles(s).filter { it.extension == "kt" }.map { FileScan(KotlinSource(it), p, d, s.name, false, emptySet()) } }
            }
        }
        val files = tests + library

        val classIndex: Map<String, List<Pair<FileScan, Decl>>> = files.flatMap { f -> f.src.classes.map { it.name to (f to it) } }.groupBy({ it.first }, { it.second })

        /** Functions that take a snapshot, directly or through other such functions, by name. */
        val helpers: Map<String, List<Pair<FileScan, Decl>>> = run {
            val fns = files.flatMap { f -> f.src.funs.filter { it.body != null && f.helper(it) }.map { f to it } }
            val set = fns.filter { (f, d) -> f.sites.any { f.src.fnAt(it.pos) == d } }.toMutableSet()
            var changed = true
            while (changed) {
                val names = set.map { it.second.name }.toSet()
                val more = fns.filter { it !in set && it.first.calls(it.second).any { c -> c.name in names } }
                changed = more.isNotEmpty(); set += more
            }
            set.groupBy({ it.second.name }, { it })
        }

        /**
         * Functions that look like they take a snapshot (a `snapshot`, `gif` or `captureRobo…` call) in a way not read here.
         * A test calling one counts as not covered, so it isn't lost from the total.
         */
        val opaque: Map<String, List<Pair<FileScan, Decl>>> = files.flatMap { f ->
            f.src.funs.filter { d -> d.body != null && f.helper(d) && helpers[d.name]?.none { it.second === d } != false &&
                Regex("""\b(?:snapshot|gif)\s*[({]|\bcapture\w*RoboImage\b|\bcaptureRobo\w+""").containsMatchIn(f.mask.substring(d.body.first, minOf(d.body.last + 1, f.mask.length))) }
                .map { f to it }
        }.groupBy({ it.second.name }, { it })

        /** The helper a call in [fs] means; null when the name isn't a helper here, [ambiguous] when it can't be told. */
        val ambiguous = Pair<FileScan?, Decl?>(null, null)
        fun helperFor(fs: FileScan, name: String, index: Map<String, List<Pair<FileScan, Decl>>> = helpers): Pair<FileScan?, Decl?>? {
            val c = index[name] ?: return null
            c.firstOrNull { it.first === fs }?.let { return it }
            fs.src.imports[name]?.let { fq -> return c.filter { it.first.src.pkg == fq.substringBeforeLast('.', "") }.firstOrNull() }
            for (pick in listOf<(Pair<FileScan, Decl>) -> Boolean>(
                { it.first.src.pkg == fs.src.pkg }, { it.first.src.pkg in fs.src.stars }, { it.first.module == fs.module }, { true },
            )) c.filter(pick).let { if (it.size == 1) return it.single() }
            return ambiguous
        }

        fun paths(fs: FileScan, decl: Decl, prefix: List<Link>, seen: Set<Decl>): List<Path> {
            val out = mutableListOf<Path>()
            for (site in fs.sites.filter { fs.src.fnAt(it.pos) == decl }) out += Path(prefix + Link(fs, decl, site.pos, null), site)
            for (c in fs.calls(decl)) {
                val link = Link(fs, decl, c.start, c)
                val (hf, hd) = helperFor(fs, c.name) ?: run {
                    if (helperFor(fs, c.name, opaque) != null) out += Path(prefix + link, null, c.name)
                    null
                } ?: continue
                when {
                    hf == null || hd == null -> out += Path(prefix + link, null, c.name)
                    hd in seen || seen.size > 8 -> {}
                    else -> out += paths(hf, hd, prefix + link, seen + hd)
                }
            }
            return out.sortedBy { it.links[prefix.size].cut }
        }

        fun tests(): List<SnapshotTest> {
            val out = mutableListOf<Pair<FileScan, SnapshotTest>>()
            val reached = HashSet<Site>()
            for (m in modules) generated(m)?.let { out += it }
            for (fs in tests) {
                val noSnapshot = mutableListOf<Decl>()
                for (fn in fs.src.funs.filter { it.body != null && (fs.isTest(it) || fs.isBefore(it)) }) {
                    val ps = paths(fs, fn, emptyList(), setOf(fn))
                    ps.mapNotNullTo(reached) { it.site }
                    ps.flatMap(::expand).forEach { out += fs to it }
                    if (ps.isEmpty() && fs.isTest(fn)) noSnapshot += fn
                }
                val captured = ruleCaptures(fs, noSnapshot)
                captured.forEach { out += fs to it.second }
                for (fn in noSnapshot - captured.map { it.first }.toSet()) unknownHelper(fs, fn)?.let { out += fs to it }
            }
            // Snapshot calls no test here reaches: outside functions, or in helpers called from elsewhere.
            for (fs in tests) for (site in fs.sites) if (site !in reached) {
                out += fs to expand(Path(listOf(Link(fs, site.fn, site.pos, null)), site)).first()
            }
            val order = modules.map { it.path }
            return out.sortedWith(compareBy({ order.indexOf(it.second.module) }, { !it.second.file.name.startsWith("build.gradle") }, { it.second.sourceSet }, { it.second.file.path }, { it.second.line }))
                .map { it.second }
        }

        /** One test per path and per element of the lists it loops over. */
        fun expand(path: Path): List<SnapshotTest> {
            val labels = mutableListOf<List<String>>()
            val loops = mutableListOf<Pair<Int, Loop>>()
            for ((level, l) in path.links.withIndex()) {
                val body = l.decl?.body ?: continue
                for (loop in l.fs.src.loops(body, l.call?.start ?: l.cut)) {
                    val elements = elements(l.fs, loop.over)
                        ?: return listOf(unfollowed(path, if (l.fs.helper(l.decl)) "helper ${l.decl.name}" else "loop over ${collapse(l.fs.src.text(loop.over))}"))
                    labels += elements
                    loops += level to loop
                }
            }
            val combos = labels.fold(listOf(emptyList<String>())) { acc, e -> acc.flatMap { a -> e.map { a + it } } }
            return combos.map { test(path, it, loops.zip(it).toMap()) }
        }

        /** The elements of `listOf(…)`, a `val` holding one, or an enum's entries (`X.entries`, `X.values()`). */
        fun elements(fs: FileScan, range: IntRange): List<String>? {
            val text = fs.src.text(range).trim().replace(Regex("""\s*\.\s*(?:entries|values\(\)|toList\(\))$"""), "")
            fun listArgs(f: FileScan, at: IntRange): List<String>? {
                val t = f.src.text(at).trim()
                if (!Regex("""^(?:listOf|arrayOf|setOf|mutableListOf)\s*\(""").containsMatchIn(t)) return null
                val open = f.src.mask.indexOf('(', at.first)
                return f.src.args(open).map { collapse(f.src.text(it.second)) }
            }
            listArgs(fs, range)?.let { return it }
            val name = Regex("""^(?:\w+\.)*(\w+)$""").matchEntire(text)?.groupValues?.get(1) ?: return null
            (listOf(fs) + files).firstNotNullOfOrNull { f -> f.src.constant(name)?.let { listArgs(f, it) } }?.let { return it }
            val (ef, enum) = classIndex[name].orEmpty().firstOrNull { it.second.isEnum && it.second.body != null } ?: return null
            val body = enum.body!!
            var end = body.last
            var i = body.first + 1
            while (i < body.last) { val c = ef.src.mask[i]; if (c in "([{") { i = ef.src.close(i) + 1; continue }; if (c == ';') { end = i; break }; i++ }
            return ef.src.split(body.first + 1 until end, ",").map { collapse(ef.src.text(it)) }.filter { it.isNotEmpty() }
        }

        /** A test counted as not covered, with [why] (`helper captureX`, `loop over devices`) as call and device. */
        fun unfollowed(path: Path, why: String): SnapshotTest {
            val root = path.links.first()
            val tool = path.site?.tool ?: toolOf(root.fs)
            return SnapshotTest(root.fs.module, root.fs.src.file, root.fs.src.line(root.call?.start ?: root.cut), tool,
                Target.Uncovered(why), DeviceSource.Unresolved(why), TestSettings(), root.fs.sourceSet)
        }

        fun toolOf(fs: FileScan) = fs.tools.singleOrNull()
            ?: if (Regex("""\bPaparazzi\b|app\.cash\.paparazzi""").containsMatchIn(fs.mask)) SnapshotTool.PAPARAZZI else SnapshotTool.ROBORAZZI

        /**
         * A test that snapshots through a helper no scanned source defines: counted as not covered rather than dropped.
         * A call counts when it is named like one (`captureMultiDevice`, `snapshot…`) or, in a file using a snapshot API,
         * is a function imported from the project.
         */
        fun unknownHelper(fs: FileScan, fn: Decl): SnapshotTest? {
            // Instrumented tests run on a device, where neither tool runs: a `snapshot…` helper there is another library's.
            if (instrumented(fs.sourceSet)) return null
            val usesApi = Regex("""\bapp\.cash\.paparazzi\b|\btakahirom\.roborazzi\b|\bPaparazzi\s*\(|\bRoborazziRule\b""").containsMatchIn(fs.mask)
            val call = fs.calls(fn).firstOrNull { c ->
                Regex("""(?i)capture|snapshot|screenshot|^snap""").containsMatchIn(c.name) ||
                    usesApi && c.name.first().isLowerCase() && fs.src.imports[c.name]?.let { fq -> libraryPackages.none { fq.startsWith(it) } } == true
            } ?: return null
            return unfollowed(Path(listOf(Link(fs, fn, call.start, call)), null), "helper ${call.name}")
        }

        /** [bound]: the element each loop on the path runs with in this test, by (link index, loop). */
        fun test(path: Path, labels: List<String>, bound: Map<Pair<Int, Loop>, String> = emptyMap()): SnapshotTest {
            path.unfollowed?.let { return unfollowed(path, "helper $it") }
            val site = path.site!!
            val root = path.links.first()
            val fs = root.fs
            val pos = root.call?.start ?: root.cut
            val content = content(path, site)
            var (device, settings) = when {
                path.links.last().fs.java -> DeviceSource.Unresolved("Java test") to TestSettings()
                // The path starts in a helper no test here calls: the test that sets its device is somewhere else.
                root.decl != null && fs.helper(root.decl) -> DeviceSource.Unresolved("helper ${root.decl.name}") to TestSettings()
                site.tool == SnapshotTool.PAPARAZZI -> paparazziDevice(path, site)
                else -> roborazziDevice(path, site, bound)
            }
            if (content.target !is Target.Uncovered) {
                if (content.forcedSize) device = DeviceSource.Unresolved("DeviceConfigurationOverride.ForcedSize")
                val o = content.settings
                settings = TestSettings(o.locale ?: settings.locale, o.night ?: settings.night, o.fontScale ?: settings.fontScale,
                    settings.fromPreview - setOfNotNull("locale".takeIf { o.locale != null }, "night".takeIf { o.night != null }, "fontScale".takeIf { o.fontScale != null }))
            }
            val d = device
            if (labels.isNotEmpty() && d is DeviceSource.Unresolved) device = DeviceSource.Unresolved("${d.expression} for ${labels.joinToString(", ")}")
            return SnapshotTest(fs.module, fs.src.file, fs.src.line(pos), site.tool, content.target, device, settings, fs.sourceSet)
        }

        class Content(val target: Target, val settings: TestSettings = TestSettings(), val forcedSize: Boolean = false)

        /** What the snapshot renders, following lambda parameters (`content()`) back up the path to the lambda the caller passed. */
        fun content(path: Path, site: Site): Content {
            val root = path.links.first()
            val leaf = path.links.last()
            val rootCall = if (path.links.size > 1) collapse(root.fs.src.text(root.call!!.start until root.call.end)) else null
            val scanned = path.links.reversed().firstNotNullOfOrNull { it.fs.scanned }
            if (site.scannedReceiver) return Content(scanned ?: Target.Uncovered(rootCall ?: collapse(leaf.fs.src.text(site.pos until site.end))))
            val range = site.content ?: return Content(Target.Uncovered(rootCall ?: collapse(leaf.fs.src.text(site.pos until site.end))))
            val found = linkedSetOf<String>()
            var scannedCall = false
            var ok = true
            var badOverride = false
            var override = TestSettings()
            var forced = false

            /** The lambda passed for parameter [param] of the function at [level]: (file, range, level of the caller). */
            fun argument(param: String, level: Int): Triple<FileScan, IntRange, Int>? {
                if (level == 0) return null
                val caller = path.links[level - 1]
                val call = caller.call ?: return null
                val callee = path.links[level].decl ?: return null
                val idx = callee.params.indexOf(param)
                val args = call.open?.let { caller.fs.src.args(it) }.orEmpty()
                val positional = args.filter { it.first == null }.map { it.second }
                val value = args.firstOrNull { it.first == param }?.second ?: positional.getOrNull(idx)
                    ?: (if (idx == callee.params.lastIndex) call.lambda?.let { return Triple(caller.fs, it, level - 1) } else null) ?: return null
                val m = caller.fs.src.mask
                val open = (value.first..value.last).firstOrNull { !m[it].isWhitespace() } ?: return null
                if (m[open] == '{') return Triple(caller.fs, open + 1 until caller.fs.src.close(open), level - 1)
                val name = caller.fs.src.text(value).trim()
                if (caller.decl != null && name in caller.decl.params) return argument(name, level - 1)
                return null
            }

            fun readOverride(f: FileScan, n: Node) {
                val args = n.args?.let { f.src.args(it.first - 1) }.orEmpty()
                val expr = (args.firstOrNull { it.first == "override" } ?: args.firstOrNull { it.first == null })?.second ?: run { badOverride = true; return }
                for (piece in f.src.split(expr, "then")) {
                    val t = f.src.text(piece).trim()
                    val m = Regex("""^(?:[\w.]*DeviceConfigurationOverride\s*\.\s*)?(\w+)\s*\((.*)\)$""", RegexOption.DOT_MATCHES_ALL).matchEntire(t) ?: run { badOverride = true; return }
                    val v = m.groupValues[2].trim()
                    when (m.groupValues[1]) {
                        "ForcedSize" -> forced = true
                        "FontScale" -> override = override.copy(fontScale = Regex("""^(\d+(?:\.\d+)?)[fF]?$""").matchEntire(v)?.groupValues?.get(1)?.toDouble() ?: run { badOverride = true; return })
                        "DarkMode" -> override = override.copy(night = v.toBooleanStrictOrNull() ?: run { badOverride = true; return })
                        "Locales" -> override = override.copy(locale = Regex("""^LocaleList\s*\(\s*(?:Locale\s*\(\s*)?"([\w-]+)"\s*\)?\s*\)$""").matchEntire(v)?.groupValues?.get(1)
                            ?.let { Locale.forLanguageTag(it.replace('_', '-')).toLanguageTag() } ?: run { badOverride = true; return })
                        else -> badOverride = true
                    }
                }
            }

            fun visit(n: Node, f: FileScan, level: Int) {
                if (n.assigned) return
                resolver.resolve(f.src, n.name)?.let { found += it; return }
                val parts = n.name.split('.')
                if (parts[0] in f.scannedValues && n.called && n.lambda == null && (parts.size == 1 || parts.size == 2 && parts[1] in setOf("invoke", "component"))) { scannedCall = true; return }
                val decl = path.links[level].decl
                if (decl != null && parts[0] in decl.params && n.lambda == null && (parts.size == 1 || parts.size == 2 && parts[1] == "invoke")) {
                    val (af, ar, al) = argument(parts[0], level) ?: run { ok = false; return }
                    af.src.nodes(ar.first, ar.last + 1).forEach { visit(it, af, al) }
                    return
                }
                val last = parts.last()
                if (last in effects) return
                if (last.first().isLowerCase()) {
                    // A lowercase call with a trailing lambda (`remember {}`, `run {}`) passes through; one without may draw anything.
                    if (n.lambda == null) { if (last !in harmless) ok = false; return }
                    n.children.forEach { visit(it, f, level) }; return
                }
                if (last == "DeviceConfigurationOverride" && n.lambda != null) readOverride(f, n)
                else if (n.lambda == null || n.argLambda) { ok = false; return }
                val before = found.size
                val scannedBefore = scannedCall
                n.children.forEach { visit(it, f, level) }
                if (found.size == before && scannedCall == scannedBefore) ok = false
            }
            leaf.fs.src.nodes(range.first, range.last + 1).forEach { visit(it, leaf.fs, path.links.lastIndex) }
            val uncovered = Target.Uncovered(rootCall ?: collapse(leaf.fs.src.text(range)))
            val target = when {
                ok && found.isNotEmpty() && !scannedCall -> Target.Previews(found.toList())
                ok && scannedCall && found.isEmpty() -> scanned ?: uncovered
                else -> uncovered
            }.let { if (badOverride && it !is Target.Uncovered) Target.Uncovered("DeviceConfigurationOverride") else it }
            return Content(target, override, forced)
        }

        /** Each function body on the path up to where the path leaves it, outermost first. */
        fun scopes(path: Path) = path.links.mapNotNull { l -> l.decl?.body?.let { l.fs to (it.first until (l.call?.start ?: l.cut)) } }

        fun rootClass(path: Path) = path.links.first().let { it.fs.src.classAt(it.decl?.keyword ?: it.cut) }

        fun paparazziDevice(path: Path, site: Site): Pair<DeviceSource, TestSettings> {
            val root = path.links.first()
            val leaf = path.links.last()
            val update = Regex("""\bunsafeUpdateConfig\s*\(""")
            val scopes = scopes(path).reversed() + root.fs.befores(rootClass(path)).map { root.fs to it.body!! }
            // Closest setting of each: unsafeUpdateConfig in the test (then helpers, @Before), then the constructor.
            var device: Pair<FileScan, IntRange>? = null
            var mode: Pair<FileScan, IntRange>? = null
            for ((f, scope) in scopes) {
                val m = update.findAll(f.mask).lastOrNull { it.range.first in scope } ?: continue
                val args = f.src.args(m.range.last)
                if (device == null) device = args.firstOrNull { it.first == "deviceConfig" }?.let { f to it.second }
                if (mode == null) mode = args.firstOrNull { it.first == "renderingMode" }?.let { f to it.second }
            }
            // The rule: a field in the snapshot's file, else one the path's calls pass along (`paparazzi.snapAll { }`).
            val ctor = leaf.fs.paparazzi[site.receiver]?.let { leaf.fs to it }
                ?: path.links.reversed().firstNotNullOfOrNull { l ->
                    l.call?.let { c -> Regex("""\w+""").findAll(l.fs.mask.substring(c.start, c.end)).map { it.value }.firstOrNull { it in l.fs.paparazzi }?.let { l.fs to l.fs.paparazzi.getValue(it) } }
                }
                ?: return DeviceSource.Unresolved(site.receiver ?: "paparazzi") to TestSettings()
            val (cf, open) = ctor
            val args = cf.src.args(open)
            if (device == null) device = args.firstOrNull { it.first == "deviceConfig" }?.let { cf to it.second }
            if (mode == null) mode = args.firstOrNull { it.first == "renderingMode" }?.let { cf to it.second }
            mode?.let { (f, r) -> f.src.text(r).trim().substringAfterLast('.') }?.takeIf { it != "NORMAL" }?.let {
                return DeviceSource.Unresolved("renderingMode=$it") to TestSettings()
            }
            device?.let { (f, r) -> return deviceConfig(f, r) }
            if (args.any { it.first == null }) return DeviceSource.Unresolved(collapse(cf.src.text(open..cf.src.close(open)))) to TestSettings()
            return DeviceSource.ToolDefault(TestDevices.paparazziDefault(), SnapshotTool.PAPARAZZI) to TestSettings()
        }

        fun deviceConfig(f: FileScan, range: IntRange): Pair<DeviceSource, TestSettings> {
            val text = f.src.text(range).trim()
            if (fromPreview.containsMatchIn(text)) return DeviceSource.FromPreview(builderFallback()) to TestSettings()
            val resolved = f.src.constant(text)?.let { f.src.text(it).trim() } ?: text
            return TestDevices.parseDeviceConfig(resolved)
        }

        /**
         * The device a project's own `DeviceConfigBuilder` (ComposablePreviewScanner's Paparazzi recipe, copied into the
         * project) returns for a preview without one: its `?: return DeviceConfig(…)`.
         */
        fun builderFallback(): DeviceSource? {
            val (f, d) = classIndex["DeviceConfigBuilder"].orEmpty().firstOrNull { it.second.body != null } ?: return null
            val m = Regex("""\?:\s*return\s+""").findAll(f.mask).firstOrNull { it.range.first in d.body!! } ?: return null
            val start = f.src.skipWs(m.range.last + 1)
            return TestDevices.parseDeviceConfig(f.src.text(start..f.src.exprEndAt(start)).trim()).first as? DeviceSource.Read
        }

        fun roborazziDevice(path: Path, site: Site, bound: Map<Pair<Int, Loop>, String> = emptyMap()): Pair<DeviceSource, TestSettings> {
            val root = path.links.first()
            val fs = root.fs
            if (!android(fs.sourceSet)) return DeviceSource.Unresolved(fs.sourceSet) to TestSettings()
            val cls = rootClass(path)
            // (file, range, link index; -1 for @Before functions)
            val scopes = fs.befores(cls).map { Triple(fs, it.body!!, -1) } +
                path.links.mapIndexedNotNull { i, l -> l.decl?.body?.let { Triple(l.fs, it.first until (l.call?.start ?: l.cut), i) } }
            val layers = mutableListOf<Layer>()
            properties(fs.moduleDir, fs.sourceSet, fs.src.pkg)?.let { layers += Layer(it, null, it) }
            layers += classLayers(fs, cls, 0)
            root.decl?.let { d -> config(fs.src, d)?.let(layers::add) }
            var fontScale: Double? = null
            var builder = site.scannedReceiver
            val setQualifiers = Regex("""\bsetQualifiers\s*\(""")
            for ((f, scope, level) in scopes) {
                val inPreview = fromPreview.containsMatchIn(f.mask.substring(scope.first, minOf(scope.last + 1, f.mask.length)))
                builder = builder || inPreview
                for (m in setQualifiers.findAll(f.mask).filter { it.range.first in scope }) f.src.args(m.range.last).firstOrNull()?.let {
                    var l = layer(f.src, it.second)
                    if (l.value == null && level >= 0) stringValue(path, level, it.second, m.range.first, bound)?.let { v -> l = Layer(v, null, l.expression) }
                    layers += if (l.value == null && inPreview) Layer(null, null, l.expression, fromPreview = true) else l
                }
                val fs2 = Regex("""\bsetFontScale\s*\(\s*(\d+(?:\.\d+)?)[fF]?\s*\)""").findAll(f.mask).lastOrNull { it.range.first in scope }
                if (fs2 != null) fontScale = fs2.groupValues[1].toDouble()
            }
            // Qualifiers set elsewhere in the class (a rule, a helper not on the path) apply in an order not read here.
            cls?.body?.let { b ->
                setQualifiers.findAll(fs.mask).firstOrNull { m ->
                    m.range.first in b && scopes.none { (f, r) -> f === fs && m.range.first in r } && fs.src.fnAt(m.range.first)?.let(fs::isTest) != true
                }?.let { m -> layers += Layer(null, null, collapse(fs.src.text(m.range.first..fs.src.close(m.range.last)))) }
            }
            val options = composeOptions(path.links.last().fs, site) ?: return DeviceSource.Unresolved("RoborazziComposeOptions") to TestSettings()
            // A preview's own device wins; previews without one render on what the rest of the setup gives.
            if (builder || options.device) return DeviceSource.FromPreview(fold(layers.filter { !it.fromPreview }).first.takeUnless { it is DeviceSource.Unresolved }) to options.settings
            var (source, settings) = fold(layers)
            fontScale?.let { settings = settings.copy(fontScale = it) }
            val o = options.settings
            val own = o.fromPreview
            return source to TestSettings(
                (o.locale ?: settings.locale).takeUnless { "locale" in own }, (o.night ?: settings.night).takeUnless { "night" in own },
                (o.fontScale ?: settings.fontScale).takeUnless { "fontScale" in own }, own,
            )
        }

        /** What `RoborazziComposeOptions { … }` in a capture call sets; [device] when it takes each preview's device. */
        class ComposeOptions(val settings: TestSettings = TestSettings(), val device: Boolean = false)

        /** The capture call's `roborazziComposeOptions = RoborazziComposeOptions { … }`; null when it sets something not read here. */
        fun composeOptions(f: FileScan, site: Site): ComposeOptions? {
            val m = Regex("""\broborazziComposeOptions\s*=\s*""").findAll(f.mask).firstOrNull { it.range.first in site.pos until site.end } ?: return ComposeOptions()
            val open = Regex("""^RoborazziComposeOptions\s*\{""").find(f.mask.substring(m.range.last + 1))?.let { m.range.last + it.range.last + 1 } ?: return null
            var settings = TestSettings()
            var device = false
            var after = open
            for (c in f.src.calls(open + 1 until f.src.close(open))) {
                if (c.start < after) continue
                after = c.end
                val v = c.open?.let { f.src.text(it + 1 until f.src.close(it)).trim() } ?: return null
                val own = Regex("""\bpreviewInfo\b""").containsMatchIn(v)
                when (c.name) {
                    "uiMode" -> settings = if (own) settings.copy(fromPreview = settings.fromPreview + "night") else settings.copy(night = night(v)?.single() ?: return null)
                    "fontScale" -> settings = if (own) settings.copy(fromPreview = settings.fromPreview + "fontScale")
                        else settings.copy(fontScale = Regex("""^(\d+(?:\.\d+)?)[fF]?$""").matchEntire(v)?.groupValues?.get(1)?.toDouble() ?: return null)
                    "locale" -> settings = if (own) settings.copy(fromPreview = settings.fromPreview + "locale")
                        else settings.copy(locale = Regex("""^"([\w-]+)"$""").matchEntire(v)?.groupValues?.get(1)?.let { Locale.forLanguageTag(it).toLanguageTag() } ?: return null)
                    "previewDevice" -> if (own) device = true else return null
                    "inspectionMode" -> {}
                    else -> return null
                }
            }
            return ComposeOptions(settings, device)
        }

        /**
         * A string the path builds from literals, or null: a literal, a template of names that resolve, an enum entry's
         * property (`Devices.PHONE.spec`, `it.spec` in a loop over `Devices.entries`), a parameter's argument, a local `val`,
         * or a value destructured from an Android Studio device spec by a parser of the shape [specComponent] reads.
         */
        fun stringValue(path: Path, level: Int, range: IntRange, pos: Int, bound: Map<Pair<Int, Loop>, String>, depth: Int = 0): String? {
            if (depth > 8) return null
            val l = path.links[level]
            val t = l.fs.src.text(range).trim()
            Regex("""^"([^"\\]*)"$""").matchEntire(t)?.let { lit ->
                val out = StringBuilder()
                var last = 0
                val body = lit.groupValues[1]
                for (m in Regex("""\$\{\s*(\w+)\s*}|\$(\w+)""").findAll(body)) {
                    out.append(body, last, m.range.first)
                    out.append(nameValue(path, level, m.groupValues[1].ifEmpty { m.groupValues[2] }, pos, bound, depth + 1) ?: return null)
                    last = m.range.last + 1
                }
                if (body.substring(last).contains('$')) return null
                return out.append(body.substring(last)).toString()
            }
            val parts = Regex("""^(\w+(?:\s*\.\s*\w+)*)$""").matchEntire(t)?.groupValues?.get(1)?.split(Regex("""\s*\.\s*""")) ?: return null
            if (parts.size == 1) return nameValue(path, level, parts[0], pos, bound, depth + 1)
            if (parts.size == 2) {
                // `it.spec` inside a loop over an enum's entries.
                val (key, element) = bound.entries.firstOrNull { (k, _) -> k.first == level && pos in k.second.body && loopVariable(l.fs.src, k.second) == parts[0] } ?: return null
                val enum = l.fs.src.text(key.second.over).trim().replace(Regex("""\s*\.\s*(?:entries|values\(\))$"""), "").substringAfterLast('.')
                return enumProperty(enum, element.substringBefore('(').trim(), parts[1])
            }
            return if (parts.size == 3) enumProperty(parts[0], parts[1], parts[2]) else null
        }

        /** The variable a loop binds each element to: `forEach { d -> }`, `forEach { }` (`it`), `forEachIndexed { i, d -> }`, `for (d in …)`. */
        fun loopVariable(src: KotlinSource, loop: Loop): String {
            Regex("""\bfor\s*\(\s*(\w+)\s+in\s*$""").find(src.mask.substring(maxOf(0, loop.over.first - 80), loop.over.first))?.let { return it.groupValues[1] }
            val head = src.mask.substring(loop.body.first + 1, minOf(loop.body.last, loop.body.first + 120))
            Regex("""^\s*(?:\w+\s*,\s*)?(\w+)\s*->""").find(head)?.let { return it.groupValues[1] }
            return "it"
        }

        fun nameValue(path: Path, level: Int, name: String, pos: Int, bound: Map<Pair<Int, Loop>, String>, depth: Int): String? {
            val l = path.links[level]
            val src = l.fs.src
            val body = l.decl?.body ?: return null
            val before = body.first until minOf(pos, body.last)
            // val (a, b, c) = parse(spec)
            Regex("""\bval\s*\(([^()]*)\)\s*=\s*(\w+)\s*\(""").findAll(src.mask).lastOrNull { it.range.first in before && name in it.groupValues[1].split(',').map(String::trim) }?.let { m ->
                val arg = src.args(m.range.last).singleOrNull()?.takeIf { it.first == null } ?: return null
                val spec = stringValue(path, level, arg.second, m.range.first, bound, depth + 1) ?: return null
                return specComponent(m.groupValues[2], m.groupValues[1].split(',').map(String::trim).indexOf(name), spec)
            }
            Regex("""\b(?:val|var)\s+${Regex.escape(name)}\s*(?::[^=\n]+)?=(?!=)""").findAll(src.mask).lastOrNull { it.range.first in before }?.let { m ->
                val start = src.skipWs(m.range.last + 1)
                return stringValue(path, level, start..src.exprEndAt(start), m.range.first, bound, depth + 1)
            }
            val decl = l.decl
            if (level == 0 || name !in decl.params) return null
            val caller = path.links[level - 1]
            val call = caller.call ?: return null
            val args = call.open?.let { caller.fs.src.args(it) }.orEmpty()
            val value = args.firstOrNull { it.first == name }?.second ?: args.filter { it.first == null }.map { it.second }.getOrNull(decl.params.indexOf(name)) ?: return null
            return stringValue(path, level - 1, value, call.start, bound, depth + 1)
        }

        /** The string literal an enum entry passes for constructor property [prop]: `PHONE("phone", "spec:…")`. */
        fun enumProperty(enum: String, entry: String, prop: String): String? {
            val (f, d) = classIndex[enum].orEmpty().singleOrNull { it.second.isEnum && it.second.body != null } ?: return null
            val src = f.src
            val header = src.mask.indexOf('(', d.keyword).takeIf { it in d.keyword until d.body!!.first } ?: return null
            val props = src.args(header).map { Regex("""^\s*(?:(?:val|var)\s+)?(\w+)\s*:""").find(src.text(it.second))?.groupValues?.get(1) }
            val at = Regex("""(?<![\w.])${Regex.escape(entry)}\s*\(""").findAll(src.mask).firstOrNull { it.range.first in d.body!! } ?: return null
            val args = src.args(at.range.last)
            val value = args.firstOrNull { it.first == prop }?.second ?: args.filter { it.first == null }.map { it.second }.getOrNull(props.indexOf(prop).takeIf { it >= 0 } ?: return null) ?: return null
            return Regex("""^"([^"$\\]*)"$""").matchEntire(src.text(value).trim())?.groupValues?.get(1)
        }

        /**
         * Component [index] of what [fn] returns for an Android Studio device [spec], when [fn] is a parser of Now in Android's
         * shape (`extractSpecs`): `spec.substringAfter("spec:").split(",").map { it.split("=") }.associate { it[0] to it[1] }`, then
         * `val width = specs["width"]?.toInt() ?: 640` per value, returned as `Specs(width, height, dpi)` of a data class.
         * Evaluated as that code does; null when [fn] differs or it would throw.
         */
        fun specComponent(fn: String, index: Int, spec: String): String? {
            val (f, d) = files.flatMap { f -> f.src.funs.filter { it.name == fn && it.body != null }.map { f to it } }.singleOrNull() ?: return null
            val p = d.params.singleOrNull() ?: return null
            val body = f.src.text(d.body!!)
            val map = Regex("""\bval\s+(\w+)\s*=\s*${Regex.escape(p)}\s*\.\s*substringAfter\(\s*"spec:"\s*\)\s*\.\s*split\(\s*","\s*\)\s*\.\s*map\s*\{\s*it\s*\.\s*split\(\s*"="\s*\)\s*}\s*\.\s*associate\s*\{\s*it\s*\[\s*0\s*]\s+to\s+it\s*\[\s*1\s*]\s*}""")
                .find(body)?.groupValues?.get(1) ?: return null
            val ret = Regex("""\breturn\s+(\w+)\s*\(([^()]*)\)""").findAll(body).singleOrNull() ?: return null
            val (cf, cd) = classIndex[ret.groupValues[1]].orEmpty().singleOrNull() ?: return null
            if (!Regex("""\bdata\s+$""").containsMatchIn(cf.src.mask.substring(maxOf(0, cd.keyword - 12), cd.keyword))) return null
            val header = cf.src.mask.indexOf('(', cd.keyword).takeIf { it > cd.keyword && (cd.body == null || it < cd.body.first) } ?: return null
            val props = cf.src.args(header).map { Regex("""^\s*val\s+(\w+)\s*:\s*Int\s*$""").find(cf.src.text(it.second))?.groupValues?.get(1) ?: return null }
            val values = ret.groupValues[2].split(',').map(String::trim).filter(String::isNotEmpty)
            if (values.size != props.size || values.any { !Regex("""\w+""").matches(it) }) return null
            val v = values.getOrNull(index) ?: return null
            val m = Regex("""(?m)\bval\s+${Regex.escape(v)}\s*=\s*${Regex.escape(map)}\s*\[\s*"(\w+)"\s*]\s*\?\.\s*toInt\(\)\s*\?:\s*(-?\d+)\s*$""").find(body) ?: return null
            val specs = spec.substringAfter("spec:").split(",").map { it.split("=") }.associate { (it.getOrNull(1) ?: return null).let { v1 -> it[0] to v1 } }
            return (specs[m.groupValues[1]]?.let { it.toIntOrNull() ?: return null } ?: m.groupValues[2].toInt()).toString()
        }

        fun classLayers(f: FileScan, cls: Decl?, depth: Int): List<Layer> {
            if (cls == null) return emptyList()
            val sup = cls.superclass
            val parent = when {
                sup == null -> emptyList()
                depth > 5 -> listOf(Layer(null, null, "@Config of $sup"))
                else -> classIndex[sup].orEmpty().sortedBy { it.first.module != f.module }.firstOrNull()?.let { (pf, pd) -> classLayers(pf, pd, depth + 1) }
                    ?: listOf(Layer(null, null, "@Config of $sup"))
            }
            return parent + listOfNotNull(config(f.src, cls))
        }

        /** `roborazzi { generateComposePreviewRobolectricTests { enable = true } }` in a module's build file. */
        fun generated(module: SnapshotModule): Pair<FileScan, SnapshotTest>? {
            val file = buildFile(module.dir) ?: return null
            val src = KotlinSource(file)
            val m = Regex("""\bgenerateComposePreviewRobolectricTests\s*\{""").findAll(src.mask).firstOrNull { m ->
                Regex("""\benable\s*(?:=\s*|\.set\s*\(\s*|\(\s*)true\b""").containsMatchIn(src.mask.substring(m.range.last, src.close(m.range.last)))
            } ?: return null
            val open = m.range.last
            val device = DeviceSource.FromPreview(generatedFallback(module, src, open + 1 until src.close(open)))
            val fs = FileScan(src, module.path, module.dir, "test", false, module.tools)
            return fs to SnapshotTest(module.path, file, src.line(m.range.first), SnapshotTool.ROBORAZZI, generatedTarget(src, open), device, TestSettings(), "test")
        }

        /**
         * Where Roborazzi's generated tests render previews without a device: the generated `@Config(qualifiers = …)`,
         * from `robolectricConfig` (its value is Kotlin source); when not set, the extension's convention
         * `RobolectricDeviceQualifiers.Pixel4a` (GenerateComposePreviewRobolectricTestsExtension, roborazzi 4c9b207f).
         */
        fun generatedFallback(module: SnapshotModule, src: KotlinSource, block: IntRange): DeviceSource? {
            val layers = mutableListOf<Layer>()
            properties(module.dir, "test", "")?.let { layers += Layer(it, null, it) }
            val set = Regex("""\brobolectricConfig\b""").containsMatchIn(src.mask.substring(block.first, block.last + 1))
            val q = if (!set) "RobolectricDeviceQualifiers.Pixel4a"
                else Regex("""["']qualifiers["']\s*(?:to|:|,)\s*"((?:[^"\\]|\\.)*)"""").find(src.text(block))?.groupValues?.get(1)?.replace("\\\"", "\"")
            if (q != null) {
                val constant = Regex("""^(?:[\w.]*\.)?RobolectricDeviceQualifiers\.(\w+)$""").matchEntire(q.trim())
                val literal = Regex("""^"([^"$\\]*)"$""").matchEntire(q.trim())
                layers += when {
                    constant != null -> TestDevices.robolectricConstant(constant.groupValues[1])?.let { Layer(it, "RobolectricDeviceQualifiers.${constant.groupValues[1]}", q) } ?: Layer(null, null, q)
                    literal != null -> Layer(literal.groupValues[1], null, q)
                    else -> Layer(null, null, q)
                }
            }
            return fold(layers).first.takeUnless { it is DeviceSource.Unresolved }
        }

        /**
         * The previews Roborazzi's generated tests render: `packages`, and `includePrivatePreviews` (false by default
         * in Roborazzi's GenerateComposePreviewRobolectricTestsExtension). An annotation filter or a custom tester
         * picks previews in ways not read here.
         */
        fun generatedTarget(src: KotlinSource, open: Int): Target {
            val block = open + 1 until src.close(open)
            val m = src.mask
            fun setting(name: String) = Regex("""\b$name\b\s*(?:=|\.set\s*\(|\(|\.addAll\s*\()""").findAll(m).firstOrNull { it.range.first in block }
            if (setting("annotationFilter") != null || setting("testerQualifiedClassName") != null) return Target.Uncovered("filtered previews")
            val private = setting("includePrivatePreviews")?.let { Regex("""^\s*(true|false)\b""").find(m.substring(it.range.last + 1))?.groupValues?.get(1) ?: return Target.Uncovered("filtered previews") } == "true"
            val packages = setting("packages")?.let { s ->
                val start = src.skipWs(s.range.last + 1)
                src.literals(start..src.exprEndAt(start)) ?: return Target.Uncovered("filtered previews")
            } ?: emptyList()
            return Target.AllPreviews(packages, private)
        }

        /** Tests in a class whose `RoborazziRule` captures by itself (a capture type other than `None`): (test function, test). */
        fun ruleCaptures(fs: FileScan, candidates: List<Decl>): List<Pair<Decl, SnapshotTest>> {
            if (fs.java) return emptyList()
            val out = mutableListOf<Pair<Decl, SnapshotTest>>()
            for (m in Regex("""\bRoborazziRule\s*\(""").findAll(fs.mask)) {
                val open = m.range.last
                val args = fs.mask.substring(open, fs.src.close(open))
                val type = Regex("""\bCaptureType\s*\.\s*(\w+)""").find(args)?.groupValues?.get(1)
                if (type == null || type == "None") continue
                val cls = fs.src.classAt(m.range.first) ?: continue
                val onRoot = Regex("""\bcaptureRoot\s*=\s*[\w.]*\bonRoot\s*\(""").containsMatchIn(args)
                for (fn in candidates.filter { fs.src.classAt(it.keyword) == cls }) {
                    val set = Regex("""\bsetContent\s*\{""").findAll(fs.mask).lastOrNull { it.range.first in fn.body!! }
                    val pos = set?.range?.first ?: fn.keyword
                    val content = set?.let { val o = it.range.last; o + 1 until fs.src.close(o) }?.takeIf { onRoot }
                    val site = Site(pos, set?.let { fs.src.close(it.range.last) + 1 } ?: fn.keyword, SnapshotTool.ROBORAZZI, content, null, fn)
                    val path = Path(listOf(Link(fs, fn, pos, null)), site)
                    val t = test(path, emptyList())
                    out += fn to if (content == null) t.copy(target = Target.Uncovered(fn.name)) else t
                }
            }
            return out
        }
    }

    private fun config(s: KotlinSource, d: Decl): Layer? {
        // `@Config`, or Robolectric's imported under another name (`import org.robolectric.annotation.Config as RobolectricConfig`).
        val ann = d.annotations.lastOrNull { it.name == "Config" || s.imports[it.name] == "org.robolectric.annotation.Config" } ?: return null
        val q = s.args(ann.open ?: return null).firstOrNull { it.first == "qualifiers" } ?: return null
        return layer(s, q.second)
    }

    /** A qualifier expression: string literals, `RobolectricDeviceQualifiers.X` and constants joined with `+`. */
    private fun layer(s: KotlinSource, range: IntRange): Layer {
        val text = collapse(s.text(range))
        val (value, label) = qualifierString(s, range, 0) ?: return Layer(null, null, text)
        return Layer(value, label, text)
    }

    private fun qualifierString(s: KotlinSource, range: IntRange, depth: Int): Pair<String, String?>? {
        if (depth > 3) return null
        var label: String? = null
        val value = StringBuilder()
        for ((n, p) in s.split(range, "+").withIndex()) {
            val t = s.text(p).trim()
            val literal = Regex(""""([^"$\\]*)"""").matchEntire(t)
            val named = Regex("""(?:[\w.]*\.)?RobolectricDeviceQualifiers\.(\w+)""").matchEntire(t)
            when {
                literal != null -> value.append(literal.groupValues[1])
                named != null -> {
                    value.append(TestDevices.robolectricConstant(named.groupValues[1]) ?: return null)
                    if (n == 0) label = "RobolectricDeviceQualifiers.${named.groupValues[1]}"
                }
                else -> {
                    val (v, l) = s.constant(t)?.let { qualifierString(s, it, depth + 1) } ?: return null
                    value.append(v)
                    if (n == 0) label = l
                }
            }
        }
        return value.toString() to label
    }

    /** Robolectric's order: an absolute value replaces what came before, a `+` value merges onto it, an unreadable one makes it unknown. */
    private fun fold(layers: List<Layer>): Pair<DeviceSource, TestSettings> {
        var cur: String? = ""
        var label: String? = null
        var unknown = ""
        for (l in layers) when {
            l.value == null -> { cur = null; label = null; unknown = l.expression }
            l.value.trim().startsWith("+") -> cur = cur?.let { merge(it, l.value) }
            else -> { cur = l.value; label = l.label }
        }
        val q = cur ?: return DeviceSource.Unresolved(unknown) to TestSettings()
        val (source, settings) = TestDevices.parseQualifiers(q)
        if (source is DeviceSource.Read && label != null && (TestDevices.parseQualifiers(label).first as? DeviceSource.Read)?.screen == source.screen) return source.copy(label = label) to settings
        return source to settings
    }

    /** `qualifiers=` from the nearest `robolectric.properties` that sets it, from the package's directory up to the resources root. */
    private fun properties(moduleDir: File, sourceSet: String, pkg: String): String? {
        val root = File(moduleDir, "src/$sourceSet/resources")
        val parts = pkg.split('.').filter { it.isNotEmpty() }
        for (n in parts.size downTo 0) {
            val f = File(root, (parts.take(n) + "robolectric.properties").joinToString("/"))
            if (!f.isFile) continue
            Regex("""(?m)^\s*qualifiers\s*[=:]\s*(.*?)\s*$""").find(f.readText())?.let { return it.groupValues[1] }
        }
        return null
    }

    private fun instrumented(sourceSet: String) = listOf("androidTest", "androidInstrumentedTest", "androidDeviceTest").any { sourceSet.startsWith(it) }

    private fun android(sourceSet: String) = sourceSet.startsWith("test") || sourceSet.startsWith("androidUnitTest") || sourceSet.startsWith("androidHostTest")

    private val effects = setOf("LaunchedEffect", "SideEffect", "DisposableEffect")
    /** Lowercase calls that draw nothing. */
    private val harmless = setOf("println", "print", "require", "requireNotNull", "check", "checkNotNull", "assert")
    /** Calls on a scanner's result that keep every preview. */
    private val harmlessListCalls = setOf("map", "toList", "toTypedArray", "toMutableList", "asSequence", "asIterable", "mapIndexed", "toSet")
    /** Packages whose functions are never a project's snapshot helper. */
    private val libraryPackages = listOf("androidx.", "android.", "kotlin.", "kotlinx.", "java.", "javax.", "org.junit.", "org.robolectric.", "com.google.common.", "org.hamcrest.", "io.mockk.", "org.mockito.")
    private val fromPreview = Regex("""\b(?:DeviceConfigBuilder|RobolectricDeviceQualifierBuilder)\b|\bpreviewInfo\b""")

    private fun collapse(s: String) = s.trim().replace(Regex("\\s+"), " ").let { if (it.length > 120) it.take(119) + "…" else it }

    /** [base] with Robolectric's `+` qualifiers applied: each given qualifier replaces the base's of the same kind. */
    private fun merge(base: String, plus: String): String {
        val b = groups(base); val p = groups(plus.trim().removePrefix("+"))
        val kinds = p.map(::kind).toSet()
        return (b.filter { kind(it) !in kinds } + p).joinToString("-")
    }

    private fun groups(q: String): List<String> {
        val out = mutableListOf<String>()
        for (t in q.split('-').filter { it.isNotEmpty() }) {
            if (t.length == 3 && t[0] in "rR" && t.drop(1).all(Char::isLetter) && out.lastOrNull()?.let(::kind) == "locale") out[out.lastIndex] += "-$t" else out += t
        }
        return out
    }

    private val kinds = mapOf(
        "size" to "small normal large xlarge", "long" to "long notlong", "round" to "round notround", "orientation" to "land port square",
        "night" to "night notnight", "dir" to "ldltr ldrtl", "gamut" to "widecg nowidecg", "hdr" to "highdr lowdr",
        "uimode" to "car desk television appliance watch vrheadset", "touch" to "notouch finger stylus", "keys" to "keysexposed keyshidden keyssoft",
        "keyboard" to "nokeys qwerty 12key", "navstate" to "navexposed navhidden", "nav" to "nonav dpad trackball wheel",
        "density" to "ldpi mdpi tvdpi hdpi xhdpi xxhdpi xxxhdpi nodpi anydpi", "gender" to "feminine masculine neuter",
    ).flatMap { (k, v) -> v.split(' ').map { it to k } }.toMap()

    private fun kind(t: String): String {
        val l = t.lowercase()
        kinds[l]?.let { return it }
        for ((re, k) in listOf("""w\d+dp""" to "w", """h\d+dp""" to "h", """sw\d+dp""" to "sw", """mcc\d+""" to "mcc", """mnc\d+""" to "mnc", """v\d+""" to "v", """\d+dpi""" to "density", """\d+x\d+""" to "px"))
            if (Regex(re).matches(l)) return k
        if (l.startsWith("b+") || l.substringBefore('-').let { it.length in 2..3 && it.all(Char::isLetter) }) return "locale"
        return l
    }
}
