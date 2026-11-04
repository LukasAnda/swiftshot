package swiftshot.android

import java.io.File
import java.io.PrintStream
import java.time.LocalDateTime
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * What each CI reads from a verify run besides the report files (docs/wiki/Baseline-format.md, "Native CI output").
 * [env] is the process environment, read once by the caller; [out] is stdout (workflow commands). A failure is one
 * warning: it never changes verify's exit code.
 */
object NativeOutput {
    private const val MAX_ANNOTATIONS = 10

    fun write(v: Verification, ci: Ci?, reportDir: File, env: Map<String, String>, out: PrintStream, log: Log) {
        val provider = ci?.provider ?: return
        fun set(k: String) = env[k]?.takeIf { it.isNotEmpty() }
        try {
            val report = reportDir.absoluteFile.normalize()
            when (provider) {
                "github" -> {
                    for ((status, id) in Summary.rows(v).take(MAX_ANNOTATIONS)) {
                        if (status == "error") {
                            val message = v.entries.first { it["id"] == id && it["status"] == "error" }["message"]
                            out.println("::error title=Render error::${data("$id: $message")}")
                        } else {
                            out.println("::error title=${data("$status screenshot", title = true)}::${data(id)}")
                        }
                    }
                    set("GITHUB_STEP_SUMMARY")?.let { File(it).appendText(File(report, "summary.md").readText()) }
                }
                "azure" -> {
                    out.println("##vso[results.publish type=JUnit;mergeResults=false;runTitle=swiftshot;resultFiles=${File(report, "junit.xml").path}]")
                    out.println("##vso[task.uploadsummary]${File(report, "summary.md").path}")
                    if (v.status != "passed") out.println("##vso[task.logissue type=error]Screenshots: ${Summary.counts(v)}")
                }
                "bitbucket" -> set("BITBUCKET_CLONE_DIR")?.let { dir ->
                    File(report, "junit.xml").copyTo(File(dir, "test-results/swiftshot/junit.xml").also { it.parentFile.mkdirs() }, overwrite = true)
                }
                "bitrise" -> {
                    set("BITRISE_TEST_RESULT_DIR")?.let { dir ->
                        val target = File(dir, "swiftshot").also { it.mkdirs() }
                        File(report, "junit.xml").copyTo(File(target, "junit.xml"), overwrite = true)
                        File(target, "test-info.json").writeText("""{"test-name":"swiftshot"}""")
                    }
                    set("BITRISE_DEPLOY_DIR")?.let { dir ->
                        File(dir).mkdirs()
                        zip(report, File(dir, "swiftshot-report.zip"))
                    }
                }
            }
        } catch (e: Exception) {
            log.warn("Could not write the $provider CI output: ${e.message ?: e}")
        }
    }

    /** A workflow command's data (and, for a property such as the title, also `:` and `,`). */
    private fun data(s: String, title: Boolean = false): String {
        val b = StringBuilder()
        for (c in s) when {
            c == '%' -> b.append("%25")
            c == '\r' -> b.append("%0D")
            c == '\n' -> b.append("%0A")
            title && c == ':' -> b.append("%3A")
            title && c == ',' -> b.append("%2C")
            else -> b.append(c)
        }
        return b.toString()
    }

    /** The report directory's files at the zip's root (as `accept --from` reads them): sorted, one fixed timestamp. */
    fun zip(dir: File, to: File) {
        val files = dir.walkTopDown().filter { it.isFile && it.canonicalFile != to.canonicalFile }.map { it.relativeTo(dir).invariantSeparatorsPath to it }
            .sortedWith(compareBy(CanonicalJson.utf8) { it.first }).toList()
        ZipOutputStream(to.outputStream().buffered()).use { z ->
            for ((name, f) in files) {
                z.putNextEntry(ZipEntry(name).also { it.timeLocal = LocalDateTime.of(1980, 1, 1, 0, 0) })
                f.inputStream().use { it.copyTo(z) }
                z.closeEntry()
            }
        }
    }
}
