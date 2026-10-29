package swiftshot.android

import java.io.File

/** A `@Preview` function in a module's sources; [fqn] is `<owner class>.<function>`, the form of [Preview.composable]. */
data class SourcePreview(val module: String, val fqn: String, val function: String)

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
 * it renders with. Calls are resolved through the test file's package and imports; anything not recognised
 * counts as not covered.
 */
object SnapshotTests {
    private val multipreviewsBuiltIn = setOf(
        "Preview", "PreviewLightDark", "PreviewFontScale", "PreviewScreenSizes", "PreviewDynamicColors",
        "WearPreviewDevices", "WearPreviewSmallRound", "WearPreviewLargeRound", "WearPreviewSquare", "WearPreviewFontScales",
    )

    /** The `@Preview` functions in the main/common sources of [module] and the modules it depends on with `project(...)`. */
    fun previews(module: SnapshotModule, all: Map<String, File>): List<SourcePreview> {
        val modules = linkedMapOf(module.path to module.dir)
        dependencies(module, all).forEach { (p, d) -> modules.putIfAbsent(p, d) }
        val sources = modules.mapValues { (_, d) -> mainSources(d).map(::Src) }
        val multipreviews = multipreviews((all.values + module.dir).distinct().flatMap(::mainSources).filter { it.readText().contains("annotation") }.map(::Src))
        return sources.flatMap { (path, srcs) -> srcs.flatMap { previewsIn(path, it, multipreviews) } }
            .distinct().sortedWith(compareBy({ it.module }, { it.fqn }))
    }

    fun scan(modules: List<SnapshotModule>, previews: List<SourcePreview>): List<SnapshotTest> {
        val resolver = Resolver(previews)
        return modules.flatMap { ModuleScan(it, resolver).tests() }
    }

    private fun sourceFiles(dir: File) = dir.walkTopDown().onEnter { it.name != "build" }.filter { it.isFile && (it.extension == "kt" || it.extension == "java") }.sortedBy { it.path }.toList()

    private fun mainSources(dir: File): List<File> = File(dir, "src").listFiles { f -> f.isDirectory && !f.name.contains("test", ignoreCase = true) }.orEmpty()
        .sortedBy { it.name }.flatMap(::sourceFiles).filter { it.extension == "kt" }

    private fun buildFile(dir: File) = listOf("build.gradle.kts", "build.gradle").map { File(dir, it) }.firstOrNull { it.isFile }

    /** Modules named by `project(":x")` or a type-safe `projects.x.y` accessor in the build file. */
    private fun dependencies(module: SnapshotModule, all: Map<String, File>): Map<String, File> {
        val text = SnapshotModules.strip(buildFile(module.dir)?.readText() ?: return emptyMap())
        val paths = Regex("""\bproject\s*\(\s*(?:path\s*=\s*)?["'](:[^"']+)["']""").findAll(text).map { it.groupValues[1] }.toMutableList()
        fun accessor(path: String) = path.removePrefix(":").split(':').joinToString(".") { seg ->
            seg.split('-', '_').mapIndexed { i, s -> if (i == 0) s else s.replaceFirstChar(Char::uppercaseChar) }.joinToString("")
        }
        for (m in Regex("""\bprojects\.([\w.]+)""").findAll(text)) {
            val written = m.groupValues[1].split('.')
            all.keys.filter { written.take(accessor(it).split('.').size).joinToString(".") == accessor(it) }.maxByOrNull { it.length }?.let(paths::add)
        }
        return paths.distinct().filter { it != module.path }.mapNotNull { p -> all[p]?.let { p to it } }.toMap()
    }

    /** Names of annotation classes that carry `@Preview` (directly or through another multipreview). */
    private fun multipreviews(srcs: List<Src>): Set<String> {
        val names = multipreviewsBuiltIn.toMutableSet()
        val declared = srcs.flatMap { src -> Regex("""\bannotation\s+class\s+(\w+)""").findAll(src.mask).map { it.groupValues[1] to src.annotationsBefore(it.range.first).map { a -> a.name } }.toList() }
        var changed = true
        while (changed) { changed = false; for ((n, anns) in declared) if (n !in names && anns.any { it in names }) { names += n; changed = true } }
        return names
    }

    private fun previewsIn(module: String, src: Src, multipreviews: Set<String>): List<SourcePreview> = src.funs.mapNotNull { f ->
        val names = f.annotations.map { it.name }
        if ("Composable" !in names || names.none { it in multipreviews }) return@mapNotNull null
        if (src.funs.any { it.body != null && f.keyword in it.body }) return@mapNotNull null // local function
        val chain = src.classes.filter { it.body != null && f.keyword in it.body }.sortedBy { it.body!!.first }.map { it.name }
        val owner = chain.joinToString("$").ifEmpty { src.facade }
        SourcePreview(module, listOf(src.pkg, owner).filter { it.isNotEmpty() }.joinToString(".") + "." + f.name, f.name)
    }

    /** Matches called names to previews through the calling file's imports and package. */
    private class Resolver(previews: List<SourcePreview>) {
        private val byFunction = previews.groupBy { it.function }

        fun resolve(src: Src, name: String): String? {
            val parts = name.split('.')
            val fn = parts.last()
            if (parts.size == 1) {
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

    private class Layer(val value: String?, val label: String?, val expression: String)

    private class ModuleScan(val module: SnapshotModule, val resolver: Resolver) {
        val sets: List<Pair<String, List<Src>>> = File(module.dir, "src").listFiles { f -> f.isDirectory && f.name.contains("test", ignoreCase = true) }.orEmpty()
            .sortedBy { it.name }.map { d -> d.name to sourceFiles(d).map(::Src) }
        val classIndex: Map<String, Pair<Src, Decl>> = sets.flatMap { it.second }.flatMap { s -> s.classes.map { it.name to (s to it) } }.toMap()

        fun tests(): List<SnapshotTest> = generated() + sets.flatMap { (ss, srcs) -> srcs.flatMap { FileScan(it, ss).tests() } }

        /** `roborazzi { generateComposePreviewRobolectricTests { enable = true } }` in the build file. */
        fun generated(): List<SnapshotTest> {
            val file = buildFile(module.dir) ?: return emptyList()
            val src = Src(file)
            return Regex("""\bgenerateComposePreviewRobolectricTests\s*\{""").findAll(src.mask).mapNotNull { m ->
                val open = m.range.last
                val block = src.mask.substring(open, src.close(open))
                if (!Regex("""\benable\s*(?:=\s*|\.set\s*\(\s*|\(\s*)true\b""").containsMatchIn(block)) return@mapNotNull null
                SnapshotTest(module.path, file, src.line(m.range.first), SnapshotTool.ROBORAZZI, generatedTarget(src, open), DeviceSource.FromPreview, TestSettings(), "test")
            }.toList()
        }

        /**
         * The previews Roborazzi's generated tests render: `packages`, and `includePrivatePreviews` (false by default
         * in Roborazzi's GenerateComposePreviewRobolectricTestsExtension). An annotation filter or a custom tester
         * picks previews in ways not read here.
         */
        fun generatedTarget(src: Src, open: Int): Target {
            val block = open + 1 until src.close(open)
            val m = src.mask
            fun setting(name: String) = Regex("""\b$name\b\s*(?:=|\.set\s*\(|\(|\.addAll\s*\()""").findAll(m).firstOrNull { it.range.first in block }
            if (setting("annotationFilter") != null || setting("testerQualifiedClassName") != null) return Target.Uncovered("filtered previews")
            val private = setting("includePrivatePreviews")?.let { Regex("""^\s*(true|false)\b""").find(m.substring(it.range.last + 1))?.groupValues?.get(1) ?: return Target.Uncovered("filtered previews") } == "true"
            val packages = setting("packages")?.let { s ->
                val start = src.skipWs(s.range.last + 1)
                literals(src, start..src.exprEndAt(start)) ?: return Target.Uncovered("filtered previews")
            } ?: emptyList()
            return Target.AllPreviews(packages, private)
        }

        /** A recognised snapshot call; [content] is the composable lambda it renders, when there is one. */
        inner class Site(val pos: Int, val end: Int, val tool: SnapshotTool, val content: IntRange?, val receiver: String? = null, val fn: Decl?)

        inner class FileScan(val src: Src, val sourceSet: String) {
            val java = src.file.extension == "java"
            val mask = src.mask
            /** What the file's preview scanners (or Showkase) return; null when there is none. */
            val scanned: Target? = scanned()
            /** Values a scanned preview is passed in as: `preview: ComposablePreview<…>`, `component: ShowkaseBrowserComponent`. */
            val scannedValues = Regex("""\b(\w+)\s*:\s*(?:ComposablePreview\s*<|ShowkaseBrowserComponent\b)""").findAll(mask).map { it.groupValues[1] }.toSet()
            val paparazzi: Map<String, Int> = Regex(if (java) """\bPaparazzi\s+(\w+)\s*=\s*new\s+(?:app\.cash\.paparazzi\.)?Paparazzi\s*\("""
                else """\b(?:val|var)\s+(\w+)\s*(?::\s*[\w.]+\s*)?=\s*(?:app\.cash\.paparazzi\.)?Paparazzi\s*\(""")
                .findAll(mask).associate { it.groupValues[1] to it.range.last }

            fun fnAt(pos: Int) = src.funs.filter { it.body != null && pos in it.body }.maxByOrNull { it.body!!.first }
            fun classAt(pos: Int) = src.classes.filter { it.body != null && pos in it.body }.maxByOrNull { it.body!!.first }

            fun tests(): List<SnapshotTest> {
                val sites = sites()
                return (sites.flatMap { expand(it, sites) } + ruleCaptures(sites)).sortedBy { it.line }
            }

            fun sites(): List<Site> {
                val out = mutableListOf<Site>()
                val imported = src.imports.values.any { it.startsWith("app.cash.paparazzi") }
                for (m in Regex("""\b(\w+)\s*\.\s*(snapshot|gif)\s*(?=[({])""").findAll(mask)) {
                    val recv = m.groupValues[1]
                    if (recv !in paparazzi && !(imported && recv.contains("paparazzi", ignoreCase = true))) continue
                    val (end, lambda) = call(m.range.last + 1)
                    val content = if (m.groupValues[2] == "snapshot" && !java) lambda else null
                    out += Site(m.range.first, end, SnapshotTool.PAPARAZZI, content, recv, fnAt(m.range.first))
                }
                for (m in Regex("""\b(captureRoboImage|captureScreenRoboImage|captureRoboGif|captureRoboLastImage|captureRoboAllImage)\s*(?=[({])""").findAll(mask)) {
                    if (Regex("""\bfun\s+(?:<[^>]*>\s*)?(?:[\w<>?]+\.)?$""").containsMatchIn(mask.substring(maxOf(0, m.range.first - 80), m.range.first))) continue
                    val start = src.chainStart(m.range.first)
                    val receiver = mask.substring(start, m.range.first)
                    val (end, lambda) = call(m.range.last + 1)
                    val fn = fnAt(m.range.first)
                    val content = when {
                        java -> null
                        m.groupValues[1] == "captureRoboImage" && lambda != null -> lambda
                        (m.groupValues[1] == "captureRoboImage" && Regex("""\bonRoot\s*\([^()]*\)\s*\.\s*$""").containsMatchIn(receiver)) ||
                            (m.groupValues[1] == "captureScreenRoboImage" && lambda == null) -> setContent(fn, m.range.first)
                        else -> null
                    }
                    out += Site(start, end, SnapshotTool.ROBORAZZI, content, fn = fn)
                }
                return out
            }

            /** After a call name: (end of the call, inside of its trailing lambda). */
            fun call(from: Int): Pair<Int, IntRange?> {
                var i = from
                if (i < mask.length && mask[i] == '(') i = src.close(i) + 1
                val k = src.skipWs(i)
                if (k < mask.length && mask[k] == '{') return src.close(k) + 1 to (k + 1 until src.close(k))
                return i to null
            }

            /** The last `setContent { … }` before [pos] in [fn], else in the class's `@Before` functions. */
            fun setContent(fn: Decl?, pos: Int): IntRange? {
                val re = Regex("""\bsetContent\s*\{""")
                fun last(range: IntRange, before: Int) = re.findAll(mask).filter { it.range.first in range && it.range.first < before }.lastOrNull()
                    ?.let { val o = it.range.last; o + 1 until src.close(o) }
                fn?.body?.let { b -> last(b, pos)?.let { return it } }
                return befores(classAt(pos)).firstNotNullOfOrNull { b -> last(b.body!!, Int.MAX_VALUE) }
            }

            fun befores(cls: Decl?): List<Decl> = if (cls == null) emptyList() else src.funs.filter { f ->
                f.body != null && classAt(f.keyword) == cls && f.annotations.any { it.name in setOf("Before", "BeforeEach", "BeforeTest") }
            }

            fun isTest(fn: Decl) = fn.annotations.any { it.name == "Test" || it.name.endsWith("Test") || it.name == "TestFactory" || it.name == "Theory" }

            fun scanned(): Target? {
                val found = mutableListOf<Target>()
                for (m in Regex("""\b(?:\w*ComposablePreviewScanner|JvmAnnotationScanner)\s*\(\s*\)""").findAll(mask)) {
                    var packages = emptyList<String>()
                    var private = false
                    var filtered = false
                    for ((name, args) in src.calledOn(m.range.last + 1)) when {
                        name == "scanPackageTrees" -> packages = args?.let { literals(src, it) } ?: run { filtered = true; emptyList() }
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

            fun target(site: Site): Target {
                val text = collapse(src.code.substring(site.pos, site.end))
                val content = site.content ?: return Target.Uncovered(text)
                val found = linkedSetOf<String>()
                var scannedCall = false
                var ok = true
                fun visit(n: Node) {
                    if (n.assigned) return
                    resolver.resolve(src, n.name)?.let { found += it; return }
                    val parts = n.name.split('.')
                    if (parts[0] in scannedValues && n.called && (parts.size == 1 || parts.size == 2 && parts[1] in setOf("invoke", "component")) && n.lambda == null) { scannedCall = true; return }
                    val last = parts.last()
                    if (last in effects) return
                    if (last.first().isLowerCase()) {
                        // A lowercase call with a trailing lambda (`remember {}`, `run {}`) passes through; one without may draw anything.
                        if (n.lambda == null) { if (last !in harmless) ok = false; return }
                        n.children.forEach(::visit); return
                    }
                    if (n.lambda == null || n.argLambda) { ok = false; return }
                    val before = found.size
                    val scannedBefore = scannedCall
                    n.children.forEach(::visit)
                    if (found.size == before && scannedCall == scannedBefore) ok = false
                }
                src.nodes(content.first, content.last + 1).forEach(::visit)
                return when {
                    ok && found.isNotEmpty() && !scannedCall -> Target.Previews(found.toList())
                    ok && scannedCall && found.isEmpty() && scanned != null -> scanned
                    else -> Target.Uncovered(collapse(src.code.substring(content.first, content.last + 1)))
                }
            }

            fun test(site: Site, target: Target, pos: Int, bodies: List<Pair<Decl, Int>>): SnapshotTest {
                val outer = bodies.firstOrNull()?.first
                val (device, settings) = when {
                    java -> DeviceSource.Unresolved("Java test") to TestSettings()
                    // A helper never called from a test here: the test that sets its device is somewhere else.
                    outer != null && helper(outer) -> DeviceSource.Unresolved("helper ${outer.name}") to TestSettings()
                    site.tool == SnapshotTool.PAPARAZZI -> paparazziDevice(site.receiver!!, bodies, classAt(pos))
                    else -> roborazziDevice(bodies, classAt(pos))
                }
                return SnapshotTest(module.path, src.file, src.line(pos), site.tool, target, device, settings, sourceSet)
            }

            fun helper(fn: Decl) = !java && !isTest(fn) && !befores(classAt(fn.keyword)).contains(fn)

            /** Calls of [fn] in this file, outside its own body, that aren't snapshot calls themselves: (start, end). */
            fun callsOf(fn: Decl, sites: List<Site>): List<IntRange> {
                val name = if (Regex("""\w+""").matches(fn.name)) fn.name else "`${fn.name}`"
                return Regex("""(?<![\w`])${Regex.escape(name)}\s*(?=[({])""").findAll(mask).filter { m ->
                    m.range.first !in fn.body!! && sites.none { it.pos == src.chainStart(m.range.first) } &&
                        !Regex("""\bfun\s+(?:<[^>]*>\s*)?(?:[\w<>?]+\.)?$""").containsMatchIn(mask.substring(maxOf(0, m.range.first - 80), m.range.first))
                }.map { m -> src.chainStart(m.range.first) until call(m.range.last + 1).first }.toList()
            }

            /** The call paths from test functions down to [fn] (cut at [cut]): (bodies outer→inner, outermost call). */
            fun chains(fn: Decl, cut: Int, sites: List<Site>, seen: Set<Decl>): List<Pair<List<Pair<Decl, Int>>, IntRange?>> {
                val inner = listOf(fn to cut)
                if (!helper(fn) || fn in seen || seen.size > 5) return listOf(inner to null)
                val calls = callsOf(fn, sites)
                if (calls.isEmpty()) return listOf(inner to null)
                return calls.flatMap { c ->
                    val caller = fnAt(c.first) ?: return@flatMap listOf(inner to c)
                    chains(caller, c.first, sites, seen + fn).map { (outer, call) -> outer + inner to (call ?: c) }
                }
            }

            /** A site inside helper functions becomes one test per path of calls from a test function in this file. */
            fun expand(site: Site, sites: List<Site>): List<SnapshotTest> {
                val target = target(site)
                val fn = site.fn ?: return listOf(test(site, target, site.pos, emptyList()))
                return chains(fn, site.pos, sites, emptySet()).map { (bodies, c) ->
                    val pos = c?.first ?: site.pos
                    val t = if (target is Target.Uncovered && c != null) Target.Uncovered(collapse(src.code.substring(c.first, c.last + 1))) else target
                    test(site, t, pos, bodies)
                }
            }

            /** Tests in a class whose `RoborazziRule` captures by itself (a capture type other than `None`). */
            fun ruleCaptures(sites: List<Site>): List<SnapshotTest> {
                if (java) return emptyList()
                val out = mutableListOf<SnapshotTest>()
                for (m in Regex("""\bRoborazziRule\s*\(""").findAll(mask)) {
                    val open = m.range.last
                    val args = mask.substring(open, src.close(open))
                    val type = Regex("""\bCaptureType\s*\.\s*(\w+)""").find(args)?.groupValues?.get(1)
                    if (type == null || type == "None") continue
                    val cls = classAt(m.range.first) ?: continue
                    val onRoot = Regex("""\bcaptureRoot\s*=\s*[\w.]*\bonRoot\s*\(""").containsMatchIn(args)
                    for (fn in src.funs.filter { it.body != null && classAt(it.keyword) == cls && isTest(it) }) {
                        if (sites.any { it.pos in fn.body!! }) continue
                        val set = Regex("""\bsetContent\s*\{""").findAll(mask).lastOrNull { it.range.first in fn.body!! }
                        val pos = set?.range?.first ?: fn.keyword
                        val content = set?.let { val o = it.range.last; o + 1 until src.close(o) }?.takeIf { onRoot }
                        val site = Site(pos, set?.let { src.close(it.range.last) + 1 } ?: fn.keyword, SnapshotTool.ROBORAZZI, content, fn = fn)
                        val target = if (content == null) Target.Uncovered(fn.name) else target(site)
                        out += test(site, target, pos, listOf(fn to pos))
                    }
                }
                return out
            }

            fun paparazziDevice(recv: String, bodies: List<Pair<Decl, Int>>, cls: Decl?): Pair<DeviceSource, TestSettings> {
                val update = Regex("""\b${Regex.escape(recv)}\s*\.\s*unsafeUpdateConfig\s*\(""")
                val scopes = bodies.reversed().map { (f, cut) -> f.body!!.first until cut } + befores(cls).map { it.body!! }
                // Closest setting of each: unsafeUpdateConfig in the test (then helpers, @Before), then the constructor.
                var device: IntRange? = null
                var mode: IntRange? = null
                for (scope in scopes) {
                    val m = update.findAll(mask).lastOrNull { it.range.first in scope } ?: continue
                    val args = src.args(m.range.last)
                    if (device == null) device = args.firstOrNull { it.first == "deviceConfig" }?.second
                    if (mode == null) mode = args.firstOrNull { it.first == "renderingMode" }?.second
                }
                val ctor = paparazzi[recv] ?: return DeviceSource.Unresolved(recv) to TestSettings()
                val args = src.args(ctor)
                if (device == null) device = args.firstOrNull { it.first == "deviceConfig" }?.second
                if (mode == null) mode = args.firstOrNull { it.first == "renderingMode" }?.second
                mode?.let { src.code.substring(it.first, it.last + 1).trim().substringAfterLast('.') }?.takeIf { it != "NORMAL" }?.let {
                    return DeviceSource.Unresolved("renderingMode=$it") to TestSettings()
                }
                device?.let { return deviceConfig(it) }
                if (args.any { it.first == null }) return DeviceSource.Unresolved(collapse(src.code.substring(ctor, src.close(ctor) + 1))) to TestSettings()
                return DeviceSource.ToolDefault(TestDevices.paparazziDefault(), SnapshotTool.PAPARAZZI) to TestSettings()
            }

            fun deviceConfig(range: IntRange): Pair<DeviceSource, TestSettings> {
                val text = src.code.substring(range.first, range.last + 1).trim()
                if (fromPreview.containsMatchIn(text)) return DeviceSource.FromPreview to TestSettings()
                val resolved = src.constant(text)?.let { src.code.substring(it.first, it.last + 1).trim() } ?: text
                return TestDevices.parseDeviceConfig(resolved)
            }

            fun roborazziDevice(bodies: List<Pair<Decl, Int>>, cls: Decl?): Pair<DeviceSource, TestSettings> {
                if (!android(sourceSet)) return DeviceSource.Unresolved(sourceSet) to TestSettings()
                val befores = befores(cls)
                val scopes = befores.map { it.body!! } + bodies.map { (f, cut) -> f.body!!.first until cut }
                if (scopes.any { fromPreview.containsMatchIn(mask.substring(it.first, minOf(it.last + 1, mask.length))) }) return DeviceSource.FromPreview to TestSettings()
                val layers = mutableListOf<Layer>()
                properties()?.let { layers += Layer(it, null, it) }
                layers += classLayers(src, cls, 0)
                bodies.firstOrNull()?.first?.let { f -> config(src, f)?.let(layers::add) }
                val set = Regex("""\bsetQualifiers\s*\(""")
                var fontScale: Double? = null
                for (scope in scopes) {
                    for (m in set.findAll(mask).filter { it.range.first in scope }) src.args(m.range.last).firstOrNull()?.let { layers += layer(src, it.second) }
                    val fs = Regex("""\bsetFontScale\s*\(\s*(\d+(?:\.\d+)?)[fF]?\s*\)""").findAll(mask).lastOrNull { it.range.first in scope }
                    if (fs != null) fontScale = fs.groupValues[1].toDouble()
                }
                var cur: String? = ""
                var label: String? = null
                var unknown = ""
                for (l in layers) when {
                    l.value == null -> { cur = null; label = null; unknown = l.expression }
                    l.value.trim().startsWith("+") -> cur = cur?.let { merge(it, l.value) }
                    else -> { cur = l.value; label = l.label }
                }
                val q = cur ?: return DeviceSource.Unresolved(unknown) to TestSettings()
                var (source, settings) = TestDevices.parseQualifiers(q)
                if (source is DeviceSource.Read && label != null && (TestDevices.parseQualifiers(label).first as? DeviceSource.Read)?.screen == source.screen) source = source.copy(label = label)
                fontScale?.let { settings = settings.copy(fontScale = it) }
                return source to settings
            }

            /** `qualifiers=` from the nearest `robolectric.properties` that sets it, from the package's directory up to the resources root. */
            fun properties(): String? {
                val root = File(module.dir, "src/$sourceSet/resources")
                val parts = src.pkg.split('.').filter { it.isNotEmpty() }
                for (n in parts.size downTo 0) {
                    val f = File(root, (parts.take(n) + "robolectric.properties").joinToString("/"))
                    if (!f.isFile) continue
                    Regex("""(?m)^\s*qualifiers\s*[=:]\s*(.*?)\s*$""").find(f.readText())?.let { return it.groupValues[1] }
                }
                return null
            }

            fun classLayers(s: Src, cls: Decl?, depth: Int): List<Layer> {
                if (cls == null) return emptyList()
                val sup = cls.superclass
                val parent = when {
                    sup == null -> emptyList()
                    depth > 5 -> listOf(Layer(null, null, "@Config of $sup"))
                    else -> classIndex[sup]?.let { (ps, pd) -> classLayers(ps, pd, depth + 1) } ?: listOf(Layer(null, null, "@Config of $sup"))
                }
                return parent + listOfNotNull(config(s, cls))
            }
        }

        fun config(s: Src, d: Decl): Layer? {
            val ann = d.annotations.lastOrNull { it.name == "Config" } ?: return null
            val q = s.args(ann.open ?: return null).firstOrNull { it.first == "qualifiers" } ?: return null
            return layer(s, q.second)
        }

        /** A qualifier expression: string literals, `RobolectricDeviceQualifiers.X` and constants joined with `+`. */
        fun layer(s: Src, range: IntRange): Layer {
            val text = collapse(s.code.substring(range.first, range.last + 1))
            val (value, label) = s.qualifierString(range, 0) ?: return Layer(null, null, text)
            return Layer(value, label, text)
        }

        fun android(sourceSet: String) = sourceSet.startsWith("test") || sourceSet.startsWith("androidUnitTest") || sourceSet.startsWith("androidHostTest")
    }

    private val effects = setOf("LaunchedEffect", "SideEffect", "DisposableEffect")
    /** Lowercase calls that draw nothing. */
    private val harmless = setOf("println", "print", "require", "requireNotNull", "check", "checkNotNull", "assert")
    /** Calls on a scanner's result that keep every preview. */
    private val harmlessListCalls = setOf("map", "toList", "toTypedArray", "toMutableList", "asSequence", "asIterable", "mapIndexed", "toSet")

    /** The string literals of a list expression (`listOf("a", "b")`, `["a"]`, `"a"`); null when anything else is in it. */
    private fun literals(src: Src, range: IntRange): List<String>? {
        val text = src.code.substring(range.first, minOf(range.last + 1, src.code.length))
        val values = Regex(""""([^"$\\]*)"""").findAll(text).map { it.groupValues[1] }.toList()
        val rest = Regex(""""[^"$\\]*"""").replace(text, "").replace(Regex("""\b(?:listOf|arrayOf|setOf|mutableListOf)\b|\.set\b|\.addAll\b|[\s(),\[\]]"""), "")
        return if (rest.isEmpty()) values else null
    }
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

    private class Ann(val name: String, val open: Int?)

    /** A `fun` or class-like declaration; [body] is its `{ … }` (or expression body) range. */
    private class Decl(val name: String, val keyword: Int, val body: IntRange?, val annotations: List<Ann>, val superclass: String? = null)

    /** A call in composable content; [argLambda] when its argument list holds a lambda that calls something. */
    private class Node(val name: String, val called: Boolean, val lambda: IntRange?, val assigned: Boolean, val argLambda: Boolean, val children: List<Node>)

    private val keywords = setOf(
        "if", "else", "when", "try", "catch", "finally", "for", "while", "do", "return", "val", "var", "fun", "is", "in", "as",
        "null", "true", "false", "this", "super", "throw", "object", "class",
    )
    private val modifiers = setOf(
        "private", "public", "internal", "protected", "open", "abstract", "override", "final", "suspend", "inline", "data", "enum",
        "annotation", "sealed", "inner", "value", "companion", "operator", "infix", "tailrec", "external", "expect", "actual", "static", "fun",
    )

    /** A Kotlin (or Java) source file: [code] has comments blanked, [mask] also string contents; offsets match. */
    private class Src(val file: File) {
        val code: String
        val mask: String
        private val closeAt: IntArray
        private val openAt: IntArray
        private val lineStarts: List<Int>

        init {
            val text = file.readText()
            code = SnapshotModules.strip(text)
            mask = SnapshotModules.strip(text, strings = true)
            closeAt = IntArray(mask.length) { -1 }; openAt = IntArray(mask.length) { -1 }
            val stack = ArrayDeque<Int>()
            for ((i, c) in mask.withIndex()) when (c) {
                '(', '[', '{' -> stack.addLast(i)
                ')', ']', '}' -> stack.removeLastOrNull()?.let { closeAt[it] = i; openAt[i] = it }
            }
            lineStarts = listOf(0) + mask.indices.filter { mask[it] == '\n' }.map { it + 1 }
        }

        fun close(open: Int) = closeAt[open].let { if (it < 0) mask.length - 1 else it }
        fun line(pos: Int) = lineStarts.binarySearch(pos).let { if (it >= 0) it + 1 else -it - 1 }
        fun skipWs(from: Int): Int { var i = from; while (i < mask.length && mask[i].isWhitespace()) i++; return i }
        private fun skipWsBack(from: Int): Int { var i = from; while (i >= 0 && mask[i].isWhitespace()) i--; return i }

        val pkg = Regex("""(?m)^\s*package\s+([\w.]+)""").find(mask)?.groupValues?.get(1) ?: ""
        private val importLines = Regex("""(?m)^\s*import\s+(?:static\s+)?([\w.]+?)(\.\*)?(?:\s+as\s+(\w+))?\s*;?\s*$""").findAll(mask).toList()
        val imports: Map<String, String> = importLines.filter { it.groupValues[2].isEmpty() }.associate { m -> m.groupValues[3].ifEmpty { m.groupValues[1].substringAfterLast('.') } to m.groupValues[1] }
        val stars: List<String> = importLines.filter { it.groupValues[2].isNotEmpty() }.map { it.groupValues[1] }

        /** The Kotlin file facade class: `@file:JvmName`, else `<FileName>Kt`. */
        val facade: String = Regex("""@file\s*:\s*JvmName\s*\(\s*"([^"]+)"""").find(code)?.groupValues?.get(1)
            ?: (file.nameWithoutExtension.replaceFirstChar(Char::uppercaseChar).replace(Regex("[^A-Za-z0-9_]"), "_") + "Kt")

        val funs: List<Decl> = Regex("""\bfun\s+(?:<[^>]*>\s*)?(?:[\w<>?]+\.)*(\w+|`[^`\n]+`)\s*\(""").findAll(mask).map { m ->
            var i = skipWs(close(m.range.last) + 1)
            if (i < mask.length && mask[i] == ':') { i++; while (i < mask.length && mask[i] !in "{=\n;}") i = if (mask[i] in "([") close(i) + 1 else i + 1 }
            i = skipWs(i)
            val body = when {
                i < mask.length && mask[i] == '{' -> i..close(i)
                i < mask.length && mask[i] == '=' -> i..exprEnd(skipWs(i + 1))
                else -> null
            }
            Decl(m.groupValues[1].removeSurrounding("`"), m.range.first, body, annotationsBefore(m.range.first))
        }.toList()

        val classes: List<Decl> = Regex("""\b(?:(companion)\s+)?(class|object|interface)\b(?:\s+(\w+))?""").findAll(mask).mapNotNull { m ->
            if (m.range.first > 0 && mask[m.range.first - 1] in ":.") return@mapNotNull null
            val name = m.groups[3]?.value ?: if (m.groups[1] != null) "Companion" else return@mapNotNull null
            if (name in keywords) return@mapNotNull null
            var i = m.range.last + 1
            var delegation = -1
            var body: IntRange? = null
            while (i < mask.length) {
                val c = mask[i]
                when {
                    c == '{' -> { body = i..close(i); break }
                    c == '(' -> i = close(i) + 1
                    c == '<' -> { var d = 0; while (i < mask.length) { if (mask[i] == '<') d++; if (mask[i] == '>') d--; i++; if (d == 0) break } }
                    c in ";})=" -> break
                    c == '\n' -> {
                        val next = skipWs(i); val prev = skipWsBack(i)
                        if (next < mask.length && mask[next] in ":,{(" || prev >= 0 && mask[prev] in ":,") i = next else break
                    }
                    else -> { if (c == ':' && delegation < 0) delegation = i; i++ }
                }
            }
            val superclass = if (delegation < 0) null
                else Regex("""([\w.]+)\s*(?:<[^>]*>)?\s*\(""").find(mask.substring(delegation, body?.first ?: i))?.groupValues?.get(1)?.substringAfterLast('.')
            Decl(name, m.range.first, body, annotationsBefore(m.range.first), superclass)
        }.toList()

        fun exprEndAt(from: Int) = exprEnd(from)

        /** The calls chained after [from] (`.scanPackageTrees("a").getPreviews()`): (name, inside of its parentheses). */
        fun calledOn(from: Int): List<Pair<String, IntRange?>> {
            val out = mutableListOf<Pair<String, IntRange?>>()
            var k = from
            while (true) {
                var d = skipWs(k)
                if (d < mask.length && mask[d] in "?!") d++
                if (d >= mask.length || mask[d] != '.') return out
                val s = skipWs(d + 1)
                var e = s
                while (e < mask.length && (mask[e].isLetterOrDigit() || mask[e] == '_')) e++
                if (e == s) return out
                val name = mask.substring(s, e)
                var args: IntRange? = null
                var n = skipWs(e)
                if (n < mask.length && mask[n] == '(') { args = n + 1 until close(n); n = close(n) + 1 }
                val l = skipWs(n)
                if (l < mask.length && mask[l] == '{') n = close(l) + 1
                out += name to args
                k = n
            }
        }

        /** End of an expression body: a newline that doesn't continue the expression, or the enclosing block's end. */
        private fun exprEnd(from: Int): Int {
            var i = from
            while (i < mask.length) {
                val c = mask[i]
                when {
                    c in "([{" -> i = close(i) + 1
                    c in ")]};" -> return i - 1
                    c == '\n' -> { val n = skipWs(i); if (n < mask.length && mask[n] in ".?:+-*/|&") i = n else return i - 1 }
                    else -> i++
                }
            }
            return mask.length - 1
        }

        /** Annotations (and modifiers, skipped) written right before a declaration keyword at [pos]. */
        fun annotationsBefore(pos: Int): List<Ann> {
            val out = mutableListOf<Ann>()
            var i = pos
            while (true) {
                var j = skipWsBack(i - 1)
                if (j < 0) break
                var open: Int? = null
                if (mask[j] == ')') { open = openAt[j].takeIf { it >= 0 } ?: break; j = skipWsBack(open - 1) }
                var k = j
                while (k >= 0 && (mask[k].isLetterOrDigit() || mask[k] in "_.:")) k--
                val word = mask.substring(k + 1, j + 1)
                if (k >= 0 && mask[k] == '@' && word.isNotEmpty()) { out += Ann(word.substringAfter(':').substringAfterLast('.'), open); i = k; continue }
                if (open == null && word in modifiers) { i = k + 1; continue }
                break
            }
            return out.reversed()
        }

        /** Start of the receiver chain ending at [pos] (`composeTestRule.onRoot().` before `captureRoboImage`). */
        fun chainStart(pos: Int): Int {
            var s = pos
            while (true) {
                var j = skipWsBack(s - 1)
                if (j < 0 || mask[j] != '.') return s
                j = skipWsBack(j - 1)
                while (j >= 0 && mask[j] in "?!") j--
                if (j >= 0 && mask[j] == ')') j = skipWsBack(openAt[j] - 1)
                var k = j
                while (k >= 0 && (mask[k].isLetterOrDigit() || mask[k] == '_')) k--
                if (k == j) return s
                s = k + 1
            }
        }

        /** Arguments inside the parentheses opening at [open]: (name or null, value range). */
        fun args(open: Int): List<Pair<String?, IntRange>> {
            val end = close(open)
            val out = mutableListOf<Pair<String?, IntRange>>()
            var start = open + 1
            var i = start
            fun add(e: Int) {
                val part = mask.substring(start, e)
                if (part.isBlank()) return
                val named = Regex("""^\s*(\w+)\s*=(?!=)""").find(part)
                out += if (named != null) named.groupValues[1] to (start + named.range.last + 1 until e) else null to (start until e)
            }
            while (i < end) {
                when (mask[i]) { '(', '[', '{' -> { i = close(i) + 1; continue }; ',' -> { add(i); start = i + 1 } }
                i++
            }
            add(end)
            return out
        }

        /** The initializer of a `val`/`const val` named by [expr] (`DEVICE`, `Companion.DEVICE`), if declared once in this file. */
        fun constant(expr: String): IntRange? {
            val name = Regex("""^(?:\w+\.)*(\w+)$""").matchEntire(expr.trim())?.groupValues?.get(1) ?: return null
            val decls = Regex("""\b(?:val|var)\s+${Regex.escape(name)}\s*(?::[^=\n]+)?=(?!=)""").findAll(mask).toList()
            val d = decls.singleOrNull() ?: return null
            val start = skipWs(d.range.last + 1)
            return start..exprEnd(start)
        }

        fun qualifierString(range: IntRange, depth: Int): Pair<String, String?>? {
            if (depth > 3) return null
            val parts = mutableListOf<IntRange>()
            var start = range.first
            var i = range.first
            while (i <= range.last) {
                when (mask[i]) { '(', '[', '{' -> { i = close(i) + 1; continue }; '+' -> { parts += start until i; start = i + 1 } }
                i++
            }
            parts += start..range.last
            var label: String? = null
            val value = StringBuilder()
            for ((n, p) in parts.withIndex()) {
                val t = code.substring(p.first, p.last + 1).trim()
                val literal = Regex(""""([^"$\\]*)"""").matchEntire(t)
                val named = Regex("""(?:[\w.]*\.)?RobolectricDeviceQualifiers\.(\w+)""").matchEntire(t)
                when {
                    literal != null -> value.append(literal.groupValues[1])
                    named != null -> {
                        value.append(TestDevices.robolectricConstant(named.groupValues[1]) ?: return null)
                        if (n == 0) label = "RobolectricDeviceQualifiers.${named.groupValues[1]}"
                    }
                    else -> {
                        val (v, l) = constant(t)?.let { qualifierString(it, depth + 1) } ?: return null
                        value.append(v)
                        if (n == 0) label = l
                    }
                }
            }
            return value.toString() to label
        }

        /** The calls written in a composable lambda, nested by their trailing lambdas; argument lists aren't entered. */
        fun nodes(from: Int, to: Int): List<Node> {
            val out = mutableListOf<Node>()
            var i = from
            while (i < to) {
                val c = mask[i]
                when {
                    c == '{' -> { out += nodes(i + 1, close(i)); i = close(i) + 1 }
                    c == '(' || c == '[' -> i = close(i) + 1
                    c.isLetter() || c == '_' -> {
                        val start = i
                        val name = StringBuilder()
                        var j = i
                        while (true) {
                            val s = j
                            while (j < to && (mask[j].isLetterOrDigit() || mask[j] == '_')) j++
                            name.append(mask, s, j)
                            val d = skipWs(j)
                            if (d < to && mask[d] == '.' && skipWs(d + 1).let { it < to && (mask[it].isLetter() || mask[it] == '_') }) { name.append('.'); j = skipWs(d + 1) } else break
                        }
                        if (name.toString() in keywords) { i = j; continue }
                        var k = skipWs(j)
                        var called = false
                        var argLambda = false
                        if (k < to && mask[k] == '(') {
                            argLambda = Regex("""\{[^{}]*?[A-Za-z_]\w*\s*[({]""").containsMatchIn(mask.substring(k, close(k)))
                            k = close(k) + 1; called = true
                        }
                        var lambda: IntRange? = null
                        val l = skipWs(k)
                        if (l < to && mask[l] == '{') { lambda = l + 1 until close(l); k = close(l) + 1 }
                        if (!called && lambda == null) { i = j; continue }
                        // Calls chained on the result (`.also { }`) belong to this one.
                        while (true) {
                            var d = skipWs(k)
                            if (d < to && mask[d] in "?!") d++
                            if (d >= to || mask[d] != '.') break
                            var e = skipWs(d + 1)
                            while (e < to && (mask[e].isLetterOrDigit() || mask[e] == '_')) e++
                            e = skipWs(e)
                            if (e < to && mask[e] == '(') e = skipWs(close(e) + 1)
                            if (e < to && mask[e] == '{') e = close(e) + 1
                            k = e
                        }
                        val prev = skipWsBack(start - 1)
                        val assigned = prev >= 0 && mask[prev] == '=' && (prev == 0 || mask[prev - 1] !in "=!<>")
                        out += Node(name.toString(), called, lambda, assigned, argLambda, lambda?.let { nodes(it.first, it.last + 1) } ?: emptyList())
                        i = k
                    }
                    else -> i++
                }
            }
            return out
        }
    }
}
