package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Duration
import java.util.zip.ZipFile

/**
 * `accept` (docs/wiki/Baseline-format.md): applies verify reports to the baseline without rendering. Changed and
 * added ids get the report's new image, removed ids lose theirs; nothing else in the baseline is touched.
 * Exit 0 applied (or nothing to do), 64 usage or invalid report, 1 refused (stale report, push failed).
 */
object Accept {
    const val DEFAULT_AUTHOR = "swiftshot <swiftshot@users.noreply.github.com>"
    /** The trailer that marks a commit made by `accept`; its value is the verified commit. */
    const val TRAILER = "Swiftshot-Accept"
    /** Download and extracted-zip size limit. */
    private const val MAX_BYTES = 2L * 1024 * 1024 * 1024
    private const val MAX_ENTRIES = 200_000

    /** A refusal (exit 1): the report doesn't fit the branch, or git couldn't finish. */
    private class Refused(message: String) : Exception(message)

    /** What one report does to one id: a new image (changed, added) or none (removed). */
    private class Change(val id: String, val kind: String, val report: String, val png: File?, val entry: Map<String, Any?>?, val fingerprint: Map<*, *>?) {
        fun sameAs(o: Change) = (png == null) == (o.png == null) && entry == o.entry &&
            (png == null || png.readBytes().contentEquals(o.png!!.readBytes()))
    }

    private class Report(val label: String, val commit: String, val changes: List<Change>)

    fun message(changed: Int, added: Int, removed: Int): String {
        val parts = listOf(changed to "changed", added to "added", removed to "removed").filter { it.first > 0 }.map { "${it.first} ${it.second}" }
        return "Update screenshot baseline (${parts.joinToString(", ")})"
    }

    fun run(
        from: List<String>, only: Set<String>?, push: Boolean, author: String?, baseline: File, log: Log,
        token: String? = System.getenv("SWIFTSHOT_ARTIFACT_TOKEN")?.takeIf { it.isNotEmpty() },
        gitEnv: Map<String, String> = emptyMap(),
    ): Int {
        val temps = mutableListOf<File>()
        return try {
            apply(from, only, push, author, baseline.absoluteFile.normalize(), log, token, gitEnv, temps)
        } catch (e: IllegalArgumentException) {
            log.error(e.message ?: "invalid input"); 64
        } catch (e: Refused) {
            log.error(e.message ?: "refused"); 1
        } catch (e: IOException) {
            log.error(e.message ?: e.toString()); 1
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            log.error("accept was interrupted; the baseline may be partly updated (git status shows what changed)"); 1
        } catch (e: Exception) {
            log.error("$e (the baseline may be partly updated; git status shows what changed)"); 1
        } finally {
            temps.forEach { it.deleteRecursively() }
        }
    }

    private fun usage(message: String): Nothing = throw UsageError(message)

    private fun apply(from: List<String>, only: Set<String>?, push: Boolean, author: String?, baseline: File, log: Log, token: String?, gitEnv: Map<String, String>, temps: MutableList<File>): Int {
        if (from.isEmpty()) usage("accept needs --from <report directory, .zip or URL>")
        val identity = parseAuthor(author ?: DEFAULT_AUTHOR)
        val top = Git(generateSequence(baseline) { it.parentFile }.first { it.isDirectory }, gitEnv).out("rev-parse", "--show-toplevel")
            ?: usage("$baseline is not in a git repository: accept checks the report against the branch")
        val git = Git(File(top), gitEnv)
        val head = git.out("rev-parse", "HEAD") ?: usage("The repository at $top has no commits")

        val reports = from.map { load(it, token, temps) }
        val changes = reports.flatMap { it.changes }.groupBy { it.id }
        only?.let { o ->
            val unknown = (o - changes.keys).sortedWith(CanonicalJson.utf8)
            if (unknown.isNotEmpty()) usage("--only: not changed, added or removed in the report: ${unknown.joinToString(", ")}")
        }
        // Several reports may name the same id (overlapping runs), but only with the same content.
        val selected = changes.filterKeys { only == null || it in only }.toSortedMap(CanonicalJson.utf8).map { (id, list) ->
            list.firstOrNull { !it.sameAs(list[0]) }?.let { usage("$id differs between ${list[0].report} and ${it.report}; accept them separately") }
            list[0]
        }
        for (commit in reports.map { it.commit }.distinct()) checkFresh(git, commit, head)

        if (selected.isEmpty()) {
            log.ok("Nothing to accept: the report has no changed, added or removed screenshots${if (only != null) " among --only" else ""}")
            return 0
        }
        val written = write(baseline, selected)
        val counts = listOf("changed", "added", "removed").map { k -> selected.count { it.kind == k } }
        val summary = message(counts[0], counts[1], counts[2])
        log.ok("${summary.removePrefix("Update screenshot baseline (").removeSuffix(")")} → $baseline")
        if (!push) return 0

        // Only the files accept wrote or deleted: other edits in the baseline directory stay out of the commit.
        val prefix = baseline.canonicalFile.relativeTo(File(top).canonicalFile).invariantSeparatorsPath.let { if (it.isEmpty()) "" else "$it/" }
        val all = written.map { ":(literal)$prefix$it" }
        // A deleted file git never knew can't be staged; leave it out.
        val tracked = git.run("ls-files", "-z", "--", ":(literal)${prefix.ifEmpty { "." }}").out.split('\u0000').filter { it.isNotEmpty() }.toSet()
        val specs = all.filter { File(top, it.removePrefix(":(literal)")).exists() || it.removePrefix(":(literal)") in tracked }.joinToString("\u0000")
        git.must("add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", input = specs)
        val ours = all.map { it.removePrefix(":(literal)") }.toSet()
        val staged = git.must("-c", "core.quotePath=false", "diff", "--cached", "--name-only", "--no-renames", "-z").split('\u0000').filter { it in ours }
        if (staged.isEmpty()) {
            log.ok("The baseline already matches the report; nothing to commit")
            return 0
        }
        val trailers = reports.map { it.commit }.distinct().joinToString("\n") { "$TRAILER: $it" }
        git.must("-c", "user.name=${identity.first}", "-c", "user.email=${identity.second}", "commit", "-q",
            "--author", "${identity.first} <${identity.second}>", "-m", summary, "-m", trailers, "--pathspec-from-file=-", "--pathspec-file-nul", input = staged.joinToString("\u0000") { ":(literal)$it" })
        val commit = git.out("rev-parse", "HEAD")
        val branch = git.out("symbolic-ref", "--short", "-q", "HEAD")
        val remote = branch?.let { git.out("config", "branch.$it.remote") }
        val merge = branch?.let { git.out("config", "branch.$it.merge") }
        val target = if (remote != null && merge != null) listOf(remote, "HEAD:$merge") else listOf("origin", "HEAD")
        val pushed = git.run("push", *target.toTypedArray())
        if (pushed.code != 0) throw Refused("Committed $commit, but git push ${target.joinToString(" ")} failed:\n${pushed.err.trim()}")
        log.ok("Committed $commit and pushed to ${target.joinToString(" ")}")
        return 0
    }

    /** The baseline files and baseline.json for [selected]; nothing else. */
    /** Writes the images, then baseline.json (temp file + rename); the paths it wrote or deleted, relative to [baseline]. */
    private fun write(baseline: File, selected: List<Change>): List<String> {
        val jsonFile = File(baseline, "baseline.json")
        val json = jsonFile.takeIf { it.isFile }?.let { runCatching { Json.parse(it.readText()) as Map<*, *> }.getOrElse { _ -> usage("$jsonFile is not valid JSON") } }
        fun map(key: String): Map<*, *>? = json?.get(key)?.let { v ->
            if (v !is Map<*, *> || v.values.any { it !is Map<*, *> }) usage("$jsonFile: \"$key\" must be an object of objects")
            v
        }
        val fingerprints = LinkedHashMap<String, Any?>()
        map("fingerprints")?.forEach { (k, v) -> fingerprints[k.toString()] = v }
        val images = LinkedHashMap<String, Any?>()
        map("images")?.forEach { (k, v) -> images[k.toString()] = v }
        val root = baseline.canonicalFile
        for (c in selected) if (!File(root, "${c.id}.png").canonicalFile.startsWith(root)) usage("${c.id}: outside the baseline directory")
        for (c in selected) {
            val target = File(root, "${c.id}.png")
            if (c.png == null) {
                target.delete()
                images.remove(c.id)
                var dir = target.parentFile
                while (dir != null && dir != root && dir.list()?.isEmpty() == true) { dir.delete(); dir = dir.parentFile }
            } else {
                target.parentFile.mkdirs()
                c.png.copyTo(target, overwrite = true)
                val fid = Fingerprints.id(c.fingerprint!!)
                fingerprints[fid] = c.fingerprint
                images[c.id] = c.entry!! + ("fingerprint" to fid)
            }
        }
        val referenced = images.values.mapNotNull { (it as? Map<*, *>)?.get("fingerprint") as String? }.toSet()
        root.mkdirs()
        val tmp = File(root, ".baseline.json.tmp")
        tmp.writeText(CanonicalJson.pretty(mapOf("schema" to 1, "fingerprints" to fingerprints.filterKeys { it in referenced }, "images" to images)))
        Files.move(tmp.toPath(), File(root, "baseline.json").toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        return selected.map { "${it.id}.png" } + "baseline.json"
    }

    /** The report must be from HEAD, or from a commit that only accept commits follow. */
    private fun checkFresh(git: Git, commit: String, head: String) {
        if (commit == head) return
        if (git.run("cat-file", "-e", "$commit^{commit}").code != 0)
            throw Refused("The report is from commit $commit, which this repository doesn't have (HEAD is $head). Run verify on $head and accept that report.")
        if (git.run("merge-base", "--is-ancestor", commit, head).code != 0)
            throw Refused("The report is from commit $commit, which is not an ancestor of HEAD $head. Run verify on $head and accept that report.")
        val log = git.out("log", "--format=%H%x1f%(trailers:key=$TRAILER,valueonly)%x1e", "$commit..$head").orEmpty()
        val others = log.split('\u001e').map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull { rec ->
            val (sha, trailer) = rec.split('\u001f', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            sha.takeIf { trailer.isBlank() }
        }
        if (others.isNotEmpty()) throw Refused(
            "The report is from commit $commit, but HEAD is $head and ${others.size} commit${if (others.size == 1) "" else "s"} since then " +
                "${if (others.size == 1) "is not a baseline commit" else "are not baseline commits"} made by accept (${others.take(3).joinToString(", ") { it.take(12) }}${if (others.size > 3) ", …" else ""}). " +
                "Run verify on $head and accept that report.",
        )
    }

    private fun parseAuthor(s: String): Pair<String, String> {
        val m = Regex("""^\s*([^<>]*?)\s*<([^<>\s]+@[^<>\s]+)>\s*$""").matchEntire(s)
        if (m == null || m.groupValues[1].isBlank()) usage("--author: \"Name <email>\", not \"$s\"")
        return m.groupValues[1] to m.groupValues[2]
    }

    // Reports

    private fun load(from: String, token: String?, temps: MutableList<File>): Report {
        val dir = when {
            from.startsWith("http://", true) || from.startsWith("https://", true) -> {
                val tmp = Files.createTempDirectory("swiftshot-accept").toFile().also(temps::add)
                val zip = File(tmp, "report.zip")
                download(from, zip, token)
                extracted(zip, File(tmp, "report"), from)
            }
            File(from).isDirectory -> File(from)
            File(from).isFile -> extracted(File(from), Files.createTempDirectory("swiftshot-accept").toFile().also(temps::add), from)
            else -> usage("--from $from: no such report directory or zip")
        }
        return read(dir, from)
    }

    /** Unzips [zip] into [dest]; the report is its root or its only top-level directory. */
    private fun extracted(zip: File, dest: File, label: String): File {
        try {
            unzip(zip, dest, label)
        } catch (e: UsageError) {
            throw e
        } catch (e: IOException) {
            usage("$label: damaged zip file (${e.message ?: e})")
        } catch (e: IllegalArgumentException) {
            // ZipFile's "MALFORMED" entry names that aren't UTF-8.
            usage("$label: damaged zip file or an entry name that isn't UTF-8 (${e.message ?: e})")
        }
        if (File(dest, "manifest.json").isFile) return dest
        val dirs = dest.listFiles().orEmpty().filter { it.isDirectory }
        dirs.singleOrNull()?.takeIf { File(it, "manifest.json").isFile }?.let { return it }
        usage("$label: no manifest.json in the zip (expected a verify report directory)")
    }

    private fun read(dir: File, label: String): Report {
        fun json(name: String): Map<*, *> {
            val f = File(dir, name)
            if (!f.isFile) usage("$label: no $name (expected a verify report directory)")
            return runCatching { Json.parse(f.readText()) as Map<*, *> }.getOrElse { _ -> usage("$label: $name is not valid JSON") }
        }
        val manifest = json("manifest.json")
        if (manifest["schema"] != 1 && (manifest["schema"] as? Number)?.toDouble() != 1.0) usage("$label: manifest.json schema ${manifest["schema"]} is not supported")
        val commit = manifest["commit"] as? String ?: usage("$label: manifest.json has no commit (verify ran outside a git checkout)")
        if (!Regex("[0-9a-f]{7,64}").matches(commit)) usage("$label: manifest.json commit \"$commit\" is not a commit hash")
        val ci = manifest["ci"] as? Boolean ?: usage("$label: manifest.json has no ci")
        val fingerprint = manifest["fingerprint"] as? Map<*, *> ?: usage("$label: manifest.json has no fingerprint")
        val ids = manifest["ids"] as? Map<*, *> ?: usage("$label: manifest.json has no ids")
        val shots = ((json("result.json")["screenshots"] as? List<*>).orEmpty()).mapNotNull { it as? Map<*, *> }.associateBy { it["id"] }
        val changes = mutableListOf<Change>()
        val seen = HashSet<String>()
        for (kind in listOf("changed", "added", "removed")) {
            val list = ids[kind] as? List<*> ?: usage("$label: manifest.json ids.$kind is missing")
            for (raw in list) {
                val id = raw as? String ?: usage("$label: manifest.json ids.$kind has a non-string id")
                checkId(id, label)
                if (!seen.add(id)) usage("$label: $id is listed twice in manifest.json")
                if (kind == "removed") { changes += Change(id, kind, label, null, null, null); continue }
                val shot = shots[id]
                if (shot == null || shot["status"] != kind) usage("$label: $id is $kind in manifest.json but not in result.json")
                val png = File(dir, "images/new/$id.png")
                if (!png.isFile) usage("$label: images/new/$id.png is missing")
                val platform = shot["platform"] as? String ?: usage("$label: $id has no platform in result.json")
                val fp = (fingerprint[platform] as? Map<*, *>)?.let { Fingerprints.forImage(it, shot) } ?: usage("$label: manifest.json has no $platform fingerprint for $id")
                val entry: Map<String, Any?> = Baseline.describe(shot) + ("local" to !ci) + ("fingerprint" to Fingerprints.id(fp))
                changes += Change(id, kind, label, png, entry, fp)
            }
        }
        return Report(label, commit, changes)
    }

    /** A screenshot id is a relative `/`-separated path; nothing that could leave the baseline directory. */
    private fun checkId(id: String, label: String) {
        val bad = id.isEmpty() || id.startsWith("/") || '\\' in id || '\u0000' in id || Regex("^[A-Za-z]:").containsMatchIn(id) ||
            id.split('/').any { it.isEmpty() || it == "." || it == ".." }
        if (bad) usage("$label: \"$id\" is not a valid screenshot id")
    }

    // Downloads and zips

    private fun download(url: String, dest: File, token: String?) {
        val client = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).connectTimeout(Duration.ofSeconds(30)).build()
        val origin = runCatching { URI(url) }.getOrElse { usage("--from $url: not a valid URL") }
        var uri = origin
        repeat(10) {
            val request = HttpRequest.newBuilder(uri).GET().header("User-Agent", "swiftshot").timeout(Duration.ofMinutes(10))
            // The token goes only to the host it was given for, never along a redirect to storage elsewhere.
            if (token != null && uri.scheme.equals(origin.scheme, true) && uri.host.equals(origin.host, true) && uri.port == origin.port)
                request.header("Authorization", "Bearer $token")
            val response = try {
                client.send(request.build(), HttpResponse.BodyHandlers.ofInputStream())
            } catch (e: IOException) {
                usage("--from $url: download failed: ${e.message ?: e}")
            }
            response.body().use { body ->
                val code = response.statusCode()
                val location = response.headers().firstValue("Location").orElse(null)
                when {
                    code in 300..399 && location != null -> uri = uri.resolve(location)
                    code == 200 -> {
                        try { capped(body, dest, url) } catch (e: IOException) { usage("--from $url: download failed: ${e.message ?: e}") }
                        return
                    }
                    else -> usage("--from $url: HTTP $code${if (code == 401 || code == 403 || code == 404) " (is SWIFTSHOT_ARTIFACT_TOKEN set and allowed to read it?)" else ""}")
                }
            }
        }
        usage("--from $url: too many redirects")
    }

    private fun capped(input: InputStream, dest: File, label: String, budget: LongArray = longArrayOf(MAX_BYTES)) {
        dest.outputStream().use { out ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                budget[0] -= n
                if (budget[0] < 0) usage("$label: larger than ${MAX_BYTES shr 30} GB")
                out.write(buf, 0, n)
            }
        }
    }

    /** Extracts [zip] into [dest]: no entry may leave it or be a symbolic link, at most 2 GB in all. */
    private fun unzip(zip: File, dest: File, label: String) {
        val links = symlinks(zip, label)
        dest.mkdirs()
        val root = dest.canonicalFile
        val budget = longArrayOf(MAX_BYTES)
        val z = try { ZipFile(zip) } catch (e: IOException) { usage("$label: not a zip file (${e.message})") }
        z.use {
            var count = 0
            for (e in z.entries()) {
                if (++count > MAX_ENTRIES) usage("$label: more than $MAX_ENTRIES entries")
                val name = e.name
                if (name in links) usage("$label: zip entry \"$name\" is a symbolic link")
                val target = File(root, name).canonicalFile
                val escapes = name.startsWith("/") || '\\' in name || Regex("^[A-Za-z]:").containsMatchIn(name) ||
                    name.split('/').any { it == ".." } || !(target == root || target.startsWith(root))
                if (escapes) usage("$label: zip entry \"$name\" points outside the report")
                if (e.isDirectory) { target.mkdirs(); continue }
                target.parentFile.mkdirs()
                z.getInputStream(e).use { input -> capped(input, target, label, budget) }
            }
        }
    }

    /** Names of entries the central directory marks as Unix symbolic links (made by Unix, mode S_IFLNK). */
    private fun symlinks(zip: File, label: String): Set<String> {
        fun u16(b: ByteArray, i: Int) = (b[i].toInt() and 0xff) or ((b[i + 1].toInt() and 0xff) shl 8)
        fun u32(b: ByteArray, i: Int) = (u16(b, i).toLong() or (u16(b, i + 2).toLong() shl 16))
        fun u64(b: ByteArray, i: Int) = u32(b, i) or (u32(b, i + 4) shl 32)
        val out = HashSet<String>()
        RandomAccessFile(zip, "r").use { f ->
            val length = f.length()
            val tail = minOf(length, 22L + 65535)
            val buf = ByteArray(tail.toInt())
            f.seek(length - tail); f.readFully(buf)
            val eocd = (buf.size - 22 downTo 0).firstOrNull { u32(buf, it) == 0x06054b50L } ?: usage("$label: not a zip file")
            var offset = u32(buf, eocd + 16)
            if (offset == 0xffffffffL) {
                val loc = eocd - 20
                if (loc < 0 || u32(buf, loc) != 0x07064b50L) usage("$label: damaged zip64 file")
                val z64 = ByteArray(56)
                f.seek(u64(buf, loc + 8)); f.readFully(z64)
                if (u32(z64, 0) != 0x06064b50L) usage("$label: damaged zip64 file")
                offset = u64(z64, 48)
            }
            if (offset !in 0 until length) usage("$label: damaged zip file")
            f.seek(offset)
            val h = ByteArray(46)
            while (f.filePointer + 46 <= length) {
                f.readFully(h)
                if (u32(h, 0) != 0x02014b50L) break
                val name = ByteArray(u16(h, 28)).also(f::readFully)
                f.seek(f.filePointer + u16(h, 30) + u16(h, 32))
                val madeBy = u16(h, 4) shr 8
                val mode = (u32(h, 38) shr 16).toInt()
                if (madeBy == 3 && (mode and 0xF000) == 0xA000) out += String(name, Charsets.UTF_8)
            }
        }
        return out
    }

    // git

    private class Result(val code: Int, val out: String, val err: String)

    private class Git(val dir: File, val env: Map<String, String>) {
        fun run(vararg args: String, input: String? = null): Result {
            val p = ProcessBuilder(listOf("git") + args).directory(dir)
            p.environment().putAll(env)
            p.environment()["GIT_TERMINAL_PROMPT"] = "0"
            val err = Files.createTempFile("swiftshot-git", ".err").toFile()
            try {
                p.redirectError(err)
                val proc = p.start()
                proc.outputStream.use { if (input != null) it.write(input.toByteArray()) }
                val out = proc.inputStream.bufferedReader().readText()
                return Result(proc.waitFor(), out, err.readText())
            } finally {
                err.delete()
            }
        }

        /** Trimmed output, null on failure or no output. */
        fun out(vararg args: String): String? = run(*args).takeIf { it.code == 0 }?.out?.trim()?.takeIf { it.isNotEmpty() }

        fun must(vararg args: String, input: String? = null): String {
            val r = run(*args, input = input)
            if (r.code != 0) throw Refused("git ${args.first { !it.startsWith("-") && "=" !in it }} failed:\n${(r.err + r.out).trim()}")
            return r.out
        }
    }
}
