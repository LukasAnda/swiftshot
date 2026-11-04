package swiftshot.android

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream
import java.nio.file.Files
import java.util.zip.ZipFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The files and workflow commands each CI gets (docs/wiki/Baseline-format.md, "Native CI output"). */
class NativeOutputTest {
    private val root = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "baseline")
    private val tmp: File = Files.createTempDirectory("swiftshot-native").toFile().canonicalFile
    private val stdout = ByteArrayOutputStream()
    private val out = PrintStream(stdout, true)

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    private fun entry(status: String, id: String, message: String? = null) = mapOf("id" to id, "status" to status) + (message?.let { mapOf("message" to it) } ?: emptyMap())

    private fun verification(ci: Ci, entries: List<Map<String, Any?>>): Verification {
        val errors = entries.filter { it["status"] == "error" }.map { mapOf("id" to it["id"], "message" to it["message"]) }
        return Verification(entries, errors, emptyList(), emptyMap(), emptyList(), false, 0, BaselineEnv(GitInfo(null, null), "1.0.0-test", ci), "hash")
    }

    /** The report directory of [v] as verify writes it, with a few more files. */
    private fun report(v: Verification): File = File(tmp, "report").also { BaselineReport.write(v, it); File(it, "images/new/en-US").mkdirs(); File(it, "images/new/en-US/A.png").writeBytes(byteArrayOf(1, 2, 3)) }

    private fun ci(provider: String) = Ci(provider, null, null, null, null, null, null, true)
    private val failed = listOf(entry("changed", "en-US/A"), entry("added", "en-US/B"), entry("unchanged", "en-US/C"))

    private fun lines() = stdout.toString().lines().filter { it.isNotEmpty() }

    private fun run(v: Verification, env: Map<String, String>, report: File = report(v), log: Log = Log(false)) = NativeOutput.write(v, v.env.ci, report, env, out, log)

    @Test fun githubAppendsTheSummaryAndAnnotatesTheFirstTen() {
        val entries = (1..12).map { entry("added", "en-US/N%02d".format(it)) } + entry("error", "en-US/E", "50% bad: a,b\nnext")
        val v = verification(ci("github"), entries)
        val step = File(tmp, "step.md").also { it.writeText("before\n") }
        run(v, mapOf("GITHUB_STEP_SUMMARY" to step.path))
        assertEquals("before\n" + Summary.markdown(v, v.env.ci), step.readText())
        // The error row sorts first; nine added rows follow.
        assertEquals(listOf("::error title=Render error::en-US/E: 50%25 bad: a,b%0Anext") + (1..9).map { "::error title=added screenshot::en-US/N%02d".format(it) }, lines())
    }

    @Test fun githubDataEscapes() {
        val v = verification(ci("github"), listOf(entry("changed", "en-US/100%\r\nx")))
        run(v, emptyMap())
        assertEquals(listOf("::error title=changed screenshot::en-US/100%25%0D%0Ax"), lines())
    }

    @Test fun githubWithoutStepSummaryOnlyAnnotates() {
        run(verification(ci("github"), failed), emptyMap())
        assertEquals(listOf("::error title=changed screenshot::en-US/A", "::error title=added screenshot::en-US/B"), lines())
    }

    @Test fun azurePrintsPublishSummaryAndIssue() {
        val v = verification(ci("azure"), failed)
        val r = report(v)
        run(v, emptyMap(), r)
        assertEquals(listOf(
            "##vso[results.publish type=JUnit;mergeResults=false;runTitle=swiftshot;resultFiles=${r.path}/junit.xml]",
            "##vso[task.uploadsummary]${r.path}/summary.md",
            "##vso[task.logissue type=error]Screenshots: 1 changed · 1 added · 0 removed · 0 errors · 1 unchanged",
        ), lines())
    }

    @Test fun azurePassedHasNoIssue() {
        val v = verification(ci("azure"), listOf(entry("unchanged", "en-US/C")))
        run(v, emptyMap())
        assertEquals(2, lines().size)
    }

    @Test fun bitbucketCopiesJunit() {
        val v = verification(ci("bitbucket"), failed)
        val r = report(v)
        run(v, mapOf("BITBUCKET_CLONE_DIR" to File(tmp, "clone").path), r)
        assertEquals(File(r, "junit.xml").readText(), File(tmp, "clone/test-results/swiftshot/junit.xml").readText())
        assertEquals(emptyList(), lines())
    }

    @Test fun bitriseWritesTestResultsAndZip() {
        val v = verification(ci("bitrise"), failed)
        val r = report(v)
        run(v, mapOf("BITRISE_TEST_RESULT_DIR" to File(tmp, "tests").path, "BITRISE_DEPLOY_DIR" to File(tmp, "deploy").path), r)
        assertEquals(File(r, "junit.xml").readText(), File(tmp, "tests/swiftshot/junit.xml").readText())
        assertEquals("""{"test-name":"swiftshot"}""", File(tmp, "tests/swiftshot/test-info.json").readText())
        val names = ZipFile(File(tmp, "deploy/swiftshot-report.zip")).use { z -> z.entries().asSequence().map { it.name }.toList() }
        assertEquals(names.sortedWith(CanonicalJson.utf8), names)
        assertTrue("manifest.json" in names && "summary.md" in names && "index.html" in names && "images/new/en-US/A.png" in names, names.toString())
        assertFalse(names.any { it.startsWith("/") || it.endsWith("/") })
    }

    @Test fun bitriseZipIsDeterministic() {
        val v = verification(ci("bitrise"), failed)
        val r = report(v)
        run(v, mapOf("BITRISE_DEPLOY_DIR" to File(tmp, "d1").path), r)
        run(v, mapOf("BITRISE_DEPLOY_DIR" to File(tmp, "d2").path), r)
        assertTrue(File(tmp, "d1/swiftshot-report.zip").readBytes().contentEquals(File(tmp, "d2/swiftshot-report.zip").readBytes()))
    }

    @Test fun nothingWithoutTheVariableOrForOtherProviders() {
        for (p in listOf("gitlab", "codemagic", "circleci", "jenkins")) {
            val v = verification(ci(p), failed)
            run(v, mapOf("GITHUB_STEP_SUMMARY" to File(tmp, "step.md").path, "BITRISE_DEPLOY_DIR" to File(tmp, "deploy").path, "BITBUCKET_CLONE_DIR" to File(tmp, "clone").path))
        }
        run(verification(ci("bitbucket"), failed), emptyMap())
        run(verification(ci("bitrise"), failed), emptyMap())
        assertEquals(emptyList(), lines())
        assertEquals(listOf("report"), tmp.list()!!.toList())
        NativeOutput.write(verification(ci("github"), failed), null, File(tmp, "report"), mapOf("GITHUB_STEP_SUMMARY" to File(tmp, "step.md").path), out, Log(false))
        assertFalse(File(tmp, "step.md").exists())
    }

    @Test fun nativeOutputFailureIsWarning() {
        val v = verification(ci("github"), failed)
        val warnings = mutableListOf<String>()
        val log = object : Log(false) { override fun warn(s: String) { warnings += s } }
        run(v, mapOf("GITHUB_STEP_SUMMARY" to File(tmp, "no/such/dir/step.md").path), log = log)
        assertEquals(1, warnings.size, warnings.toString())
        assertTrue(warnings[0].startsWith("Could not write the github CI output: "), warnings[0])
    }

    @Test fun verifyExitCodeIsUnchangedByAFailingNativeOutput() {
        val case = File(root, "changed-pixels")
        val vars = mapOf("SWIFTSHOT_COMMIT" to "0123456789abcdef0123456789abcdef01234567", "SWIFTSHOT_BRANCH" to "feature/x", "GITHUB_ACTIONS" to "true")
        val env = BaselineEnv.detect(tmp, vars, { null }, "1.0.0-test")
        val config = CompareConfig.from(Options.parse(listOf("--project-dir", tmp.path, "--config", File(case, "config.json").path)))
        val code = Baseline.verify(File(case, "output"), File(case, "baseline"), File(tmp, "verify-report"), config, env, Log(false),
            mapOf("GITHUB_STEP_SUMMARY" to File(tmp, "no/such/dir/step.md").path), out)
        assertEquals(1, code)
        assertTrue(File(tmp, "verify-report/summary.md").isFile)
        assertEquals(listOf("::error title=changed screenshot::en-US/Pixel 9-Home"), lines())
    }
}
