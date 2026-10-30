package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** A `screens` rule's comparison settings (rules without them still decide which rule applies first). */
data class CompareRule(val preview: String, val tolerance: Tolerance? = null, val ignoreRegions: List<List<Double>>? = null)

/** The comparison config of docs/wiki/Baseline-format.md: the global `tolerance` and the `screens` rules in order. */
data class CompareConfig(val tolerance: Tolerance?, val rules: List<CompareRule>) {
    /** The tolerance and the ignored pixels for a screenshot of [preview], rendered in [mode] at [scale] px per pt/dp. */
    fun forShot(preview: String, mode: String?, scale: Double): Pair<Tolerance, List<Region>> {
        val rule = rules.firstOrNull { Baseline.glob(it.preview, preview) }
        val t = rule?.tolerance ?: tolerance ?: if (mode == "device") Tolerance(0, 1) else Tolerance()
        return t to rule?.ignoreRegions.orEmpty().map { Compare.ignoreRegion(it, scale) }
    }

    /** configHash: the hash of the normalized config. */
    fun hash(): String {
        fun tol(t: Tolerance?) = mapOf("max_channel_delta" to (t?.maxChannelDelta ?: 0), "pixels" to (t?.pixels ?: 0))
        val screens = rules.map { r ->
            buildMap<String, Any?> {
                put("preview", r.preview)
                r.tolerance?.let { put("tolerance", tol(it)) }
                r.ignoreRegions?.let { put("ignore_regions", it) }
            }
        }
        return CanonicalJson.hash(mapOf("screens" to screens, "tolerance" to tol(tolerance)))
    }

    companion object {
        fun from(o: Options) = CompareConfig(o.tolerance, o.screens.map { CompareRule(it.preview, it.tolerance, it.ignoreRegions) })
    }
}

/** Commit and branch: `SWIFTSHOT_COMMIT`/`SWIFTSHOT_BRANCH`, else git; null when unknown. */
data class GitInfo(val commit: String?, val branch: String?) {
    companion object {
        fun detect(dir: File): GitInfo {
            fun git(vararg args: String): String? = runCatching {
                val p = ProcessBuilder(listOf("git") + args).directory(dir).redirectErrorStream(false).start()
                p.errorStream.close()
                val out = p.inputStream.bufferedReader().readText().trim()
                if (p.waitFor() == 0) out.takeIf { it.isNotEmpty() } else null
            }.getOrNull()
            val commit = System.getenv("SWIFTSHOT_COMMIT") ?: git("rev-parse", "HEAD")
            val branch = System.getenv("SWIFTSHOT_BRANCH") ?: git("rev-parse", "--abbrev-ref", "HEAD")?.takeIf { it != "HEAD" }
            return GitInfo(commit, branch)
        }
    }
}

/** What a verify run records about where it ran. */
data class BaselineEnv(val git: GitInfo, val version: String, val ci: Boolean) {
    companion object {
        fun detect(dir: File) = BaselineEnv(GitInfo.detect(dir), Fingerprints.version(), ci())

        /** `SWIFTSHOT_CI` (`true`/`false`), else `CI` set to true (full CI detection comes later). */
        fun ci(): Boolean {
            System.getenv("SWIFTSHOT_CI")?.let { return it.equals("true", true) || it == "1" }
            return System.getenv("CI").let { it.equals("true", true) || it == "1" }
        }
    }
}

/** The outcome of comparing one run with the baseline (written as result.json, manifest.json, junit.xml). */
class Verification(
    val entries: List<Map<String, Any?>>,
    /** Every `{"id", "message"}` of an `error` entry, then the run's errors without id. */
    val errors: List<Map<String, Any?>>,
    val unattributed: List<Map<String, Any?>>,
    val fingerprint: Map<String, Any?>,
    val mismatches: List<String>,
    val localBaseline: Boolean,
    val strays: Int,
    val env: BaselineEnv,
    val configHash: String,
) {
    val counts: Map<String, Int> = listOf("unchanged", "changed", "added", "removed").associateWith { k -> entries.count { it["status"] == k } } +
        ("errors" to errors.size)
    val failures get() = counts.getValue("changed") + counts.getValue("added") + counts.getValue("removed")
    val status get() = if (errors.isNotEmpty()) "error" else if (failures > 0) "failed" else "passed"
    val exitCode get() = when (status) { "error" -> 2; "failed" -> 1; else -> 0 }
    /** This run's host: the one in its fingerprints (one run, one host). */
    val host: String? get() = fingerprint.values.mapNotNull { (it as? Map<*, *>)?.get("host") as String? }.minWithOrNull(CanonicalJson.utf8)
    fun ids(status: String) = entries.filter { it["status"] == status }.map { it["id"] as String }
}

/**
 * `verify` and `record` (docs/wiki/Baseline-format.md): a finished run's output directory (its PNGs and
 * swiftshot-report.json) against the baseline directory (its PNGs and baseline.json).
 */
object Baseline {
    /** Run inputs, as the report lists them. */
    private class Run(output: File) {
        val report = File(output, "swiftshot-report.json").let { f ->
            if (!f.isFile) throw CliError("No swiftshot-report.json in $output") else Json.parse(f.readText()) as Map<*, *>
        }
        val shots: Map<String, Map<*, *>> = (report["screenshots"] as List<*>?).orEmpty().map { it as Map<*, *> }
            .filter { it["id"] is String }.associateBy { it["id"] as String }
        private val errorList = (report["errors"] as List<*>?).orEmpty().map { e -> if (e is Map<*, *>) e else mapOf("message" to e.toString()) }
        /** The first message per id. */
        val failed = LinkedHashMap<String, String>().also { m -> for (e in errorList) (e["id"] as String?)?.let { m.putIfAbsent(it, e["message"].toString()) } }
        val unattributed = errorList.filter { it["id"] !is String }.map { mapOf("message" to it["message"]?.toString()) }
        val scope = report["scope"] as Map<*, *>? ?: emptyMap<String, Any?>()
        @Suppress("UNCHECKED_CAST")
        val fingerprint = (report["fingerprint"] as Map<String, Any?>?) ?: emptyMap()
        fun mode(platform: Any?) = ((fingerprint[platform as String?] as Map<*, *>?)?.get("mode")) as String?
    }

    /** The baseline: baseline.json and every PNG under the directory (by id). */
    private class Stored(val dir: File) {
        val json = File(dir, "baseline.json").takeIf { it.isFile }?.let { Json.parse(it.readText()) as Map<*, *> }
        val fingerprints: Map<*, *> = json?.get("fingerprints") as Map<*, *>? ?: emptyMap<String, Any?>()
        val images: Map<String, Map<*, *>> = (json?.get("images") as Map<*, *>?).orEmpty().entries.associate { (k, v) -> k as String to v as Map<*, *> }
        val files: Set<String> = if (!dir.isDirectory) emptySet() else dir.walkTopDown().filter { it.isFile && it.name.endsWith(".png") }
            .map { it.relativeTo(dir).invariantSeparatorsPath.removeSuffix(".png") }.toSet()
    }

    private val DESCRIPTIVE = listOf("platform", "module", "device", "language", "appearance", "preview", "fontScale", "textSize", "runtime")

    internal fun describe(meta: Map<*, *>): MutableMap<String, Any?> {
        val d = LinkedHashMap<String, Any?>()
        for (k in DESCRIPTIVE) if (meta.containsKey(k)) d[k] = meta[k]
        if (d["platform"] == "ios" && !d.containsKey("textSize")) d["textSize"] = "default"
        return d
    }

    /** `*` = any run of characters, whole name, ASCII case-insensitive. */
    fun glob(pattern: String, name: String): Boolean {
        fun lower(s: String) = buildString { for (c in s) append(if (c in 'A'..'Z') c + 32 else c) }
        val parts = lower(pattern).split('*')
        val s = lower(name)
        if (parts.size == 1) return s == parts[0]
        if (!s.startsWith(parts[0]) || !s.endsWith(parts.last()) || s.length < parts[0].length + parts.last().length) return false
        var i = parts[0].length
        val end = s.length - parts.last().length
        for (p in parts.subList(1, parts.size - 1)) {
            val k = s.indexOf(p, i).takeIf { it >= 0 && it + p.length <= end } ?: return false
            i = k + p.length
        }
        return true
    }

    private fun decimal(v: Any?) = (v as? Number)?.toDouble()?.let { java.math.BigDecimal(it.toString()).stripTrailingZeros() }

    /** Whether a baseline image lies inside the run's scope (a list missing from the scope matches nothing). */
    internal fun inScope(image: Map<*, *>, scope: Map<*, *>): Boolean {
        for ((field, key) in listOf("platform" to "platforms", "device" to "devices", "language" to "languages", "appearance" to "appearances",
            "fontScale" to "fontScales", "textSize" to "textSizes", "module" to "modules", "runtime" to "runtimes")) {
            if (!image.containsKey(field)) continue
            val values = scope[key] as List<*>? ?: return false
            val v = image[field]
            val hit = if (field == "fontScale") decimal(v).let { d -> d != null && values.any { decimal(it)?.compareTo(d) == 0 } } else v in values
            if (!hit) return false
        }
        val globs = (scope["previewFilter"] as List<*>?).orEmpty().map { it.toString() }
        return globs.isEmpty() || globs.any { glob(it, image["preview"]?.toString() ?: "") }
    }

    /** Compares the run in [output] with [baseline], writes the report directory and says what it found; the exit code. */
    fun verify(output: File, baseline: File, report: File, config: CompareConfig, env: BaselineEnv, log: Log): Int {
        val start = System.nanoTime()
        val v = evaluate(output, baseline, report, config, env)
        BaselineReport.writeTimings((System.nanoTime() - start) / 1e9, report)
        for ((kind, line) in BaselineReport.summary(v, report)) when (kind) {
            "warn" -> log.warn(line)
            "error" -> log.error(line)
            "ok" -> log.ok(line)
            else -> log.plain(line)
        }
        return v.exitCode
    }

    /** The comparison: statuses in id order, report files written into [report]. */
    fun evaluate(output: File, baseline: File, report: File, config: CompareConfig, env: BaselineEnv): Verification {
        val run = Run(output)
        val stored = Stored(baseline)
        val stray = stored.files - stored.images.keys
        val ids = (run.shots.keys + stored.images.keys + run.failed.keys + stray.intersect(run.shots.keys)).sortedWith(CanonicalJson.utf8)
        BaselineReport.clear(report)
        val pool = Executors.newFixedThreadPool(maxOf(1, minOf(Runtime.getRuntime().availableProcessors(), 4)))
        val pending = ArrayList<Future<Map<String, Any?>>>()
        val compared = ArrayList<Map<*, *>>()
        var local = false
        try {
            for (id in ids) {
                val b = stored.images[id]
                val o = run.shots[id]
                if (o == null && id !in run.failed && (!inScope(b!!, run.scope) || run.unattributed.isNotEmpty())) continue
                if (b != null) {
                    compared += b
                    if (b["local"] == true) local = true
                }
                val e = LinkedHashMap<String, Any?>((o ?: b)?.let(::describe) ?: emptyMap())
                e["id"] = id
                val error = run.failed[id]
                    ?: if (o != null && !File(output, "$id.png").isFile) "output image missing"
                    else if (b != null && id !in stored.files) "baseline image missing"
                    else if (b == null && id in stored.files) "baseline image not in baseline.json"
                    else null
                when {
                    error != null -> { e["status"] = "error"; e["message"] = error; pending += done(e) }
                    o == null -> {
                        e["status"] = "removed"; e["baseline"] = "images/baseline/$id.png"
                        File(baseline, "$id.png").copyTo(File(report, "images/baseline/$id.png"), overwrite = true)
                        pending += done(e)
                    }
                    b == null -> {
                        e["status"] = "added"; e["new"] = "images/new/$id.png"
                        File(output, "$id.png").copyTo(File(report, "images/new/$id.png"), overwrite = true)
                        pending += done(e)
                    }
                    else -> pending += pool.submit(Callable { compare(e, id, o, output, baseline, report, config, run) })
                }
            }
            val entries = pending.map { it.get() }
            // Each image against the fingerprint this run gives it (its own runtime's build).
            val mismatches = compared.flatMap { b ->
                val fp = stored.fingerprints[b["fingerprint"] as String?] as Map<*, *>? ?: return@flatMap emptyList()
                (run.fingerprint[fp["platform"] as String?] as Map<*, *>?)?.let { Fingerprints.mismatches(fp, Fingerprints.forImage(it, b)) }.orEmpty()
            }.distinct().sortedWith(CanonicalJson.utf8)
            val errors = entries.filter { it["status"] == "error" }.map { linkedMapOf("id" to it["id"], "message" to it["message"]) } + run.unattributed
            val listed = entries.map { it["id"] as String }.toSet()
            val v = Verification(entries, errors, run.unattributed, run.fingerprint, mismatches, local, (stray - listed).size, env, config.hash())
            BaselineReport.write(v, report)
            return v
        } finally {
            pool.shutdownNow()
        }
    }

    private fun done(e: Map<String, Any?>): Future<Map<String, Any?>> = java.util.concurrent.CompletableFuture.completedFuture(e)

    /** Both PNGs present: equal bytes, else decode and compare; a changed shot's images are written right away. */
    private fun compare(e: MutableMap<String, Any?>, id: String, o: Map<*, *>, output: File, baseline: File, report: File, config: CompareConfig, run: Run): Map<String, Any?> {
        val a = File(baseline, "$id.png").readBytes()
        val b = File(output, "$id.png").readBytes()
        if (a.contentEquals(b)) { e["status"] = "unchanged"; return e }
        val (base, new) = try { Png.decode(a) to Png.decode(b) } catch (_: UnsupportedPngException) {
            e["status"] = "error"; e["message"] = "unsupported PNG"; return e
        }
        val (tolerance, ignore) = config.forShot(o["preview"]?.toString() ?: "", run.mode(o["platform"]), (o["scale"] as Number?)?.toDouble() ?: 1.0)
        val diff = Compare.images(base, new, tolerance, ignore)
        if (diff.status == "unchanged") {
            e["status"] = "unchanged"
            if (diff.pixels > 0) { e["reason"] = "tolerance"; e["pixels"] = diff.pixels }
            return e
        }
        e["status"] = "changed"
        e["reason"] = diff.reason
        e["pixels"] = diff.pixels
        e["boxes"] = diff.boxes.map { listOf(it.x, it.y, it.width, it.height) }
        e["baseline"] = "images/baseline/$id.png"
        e["new"] = "images/new/$id.png"
        e["diff"] = "images/diff/$id.png"
        diff.baselineSize?.let { e["baselineSize"] = it }
        diff.newSize?.let { e["newSize"] = it }
        write(File(report, "images/baseline/$id.png"), a)
        write(File(report, "images/new/$id.png"), b)
        write(File(report, "images/diff/$id.png"), Png.encode(diff.diffImage!!))
        return e
    }

    private fun write(f: File, bytes: ByteArray) { f.parentFile.mkdirs(); f.writeBytes(bytes) }

    /**
     * `record`: the run's screenshots become the baseline. Rendered ids are copied in (local = ![ci]); baseline images
     * in the run's scope that it didn't render (and that have no render error) are deleted, as a verify would report
     * them removed; images outside the scope stay. Exit 2 when the run had errors, else 0.
     */
    fun record(output: File, baseline: File, ci: Boolean, log: Log): Int {
        val run = Run(output)
        if (run.shots.isEmpty() && (run.failed.isNotEmpty() || run.unattributed.isNotEmpty())) {
            for ((id, message) in run.failed) log.error("$id: $message")
            for (e in run.unattributed) log.error(e["message"].toString())
            log.error("Nothing rendered; the baseline is unchanged")
            return 2
        }
        val stored = Stored(baseline)
        val images = sortedMapOf<String, Map<String, Any?>>(CanonicalJson.utf8)
        val fingerprints = HashMap<String, Map<*, *>>()
        for ((id, b) in stored.images) {
            @Suppress("UNCHECKED_CAST")
            images[id] = b as Map<String, Any?>
            (b["fingerprint"] as String?)?.let { f -> (stored.fingerprints[f] as Map<*, *>?)?.let { fingerprints[f] = it } }
        }
        var removed = 0
        if (run.unattributed.isEmpty()) for ((id, b) in stored.images) {
            if (id in run.shots || id in run.failed || !inScope(b, run.scope)) continue
            images.remove(id)
            File(baseline, "$id.png").delete()
            removed++
        }
        var written = 0
        val missing = mutableListOf<String>()
        for ((id, o) in run.shots) {
            val png = File(output, "$id.png")
            if (!png.isFile) { missing += id; continue }
            val platform = o["platform"] as String?
            val fp = (run.fingerprint[platform] as Map<*, *>?)?.let { Fingerprints.forImage(it, o) } ?: mapOf("platform" to platform)
            val fid = Fingerprints.id(fp)
            fingerprints[fid] = fp
            images[id] = describe(o).apply { put("fingerprint", fid); put("local", !ci) }
            png.copyTo(File(baseline, "$id.png"), overwrite = true)
            written++
        }
        val referenced = images.values.mapNotNull { it["fingerprint"] as String? }.toSet()
        val json = mapOf("schema" to 1, "fingerprints" to fingerprints.filterKeys { it in referenced }, "images" to images)
        baseline.mkdirs()
        File(baseline, "baseline.json").writeText(CanonicalJson.pretty(json))
        for (id in missing) log.error("$id: output image missing")
        for ((id, message) in run.failed) log.error("$id: $message")
        for (e in run.unattributed) log.error(e["message"].toString())
        log.ok("Recorded $written screenshots${if (removed > 0) ", removed $removed" else ""}${if (ci) "" else " (locally: verify will say so until CI records them)"} → $baseline")
        return if (run.failed.isNotEmpty() || run.unattributed.isNotEmpty() || missing.isNotEmpty()) 2 else 0
    }
}
