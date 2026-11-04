package swiftshot.android

import com.sun.net.httpserver.HttpServer
import swiftshot.android.shared.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream
import java.net.InetSocketAddress
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** `accept` (docs/wiki/Baseline-format.md) in temporary git repositories, with a local bare remote for `--push`. */
class AcceptTest {
    private val root = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "baseline")
    private val tmp: File = Files.createTempDirectory("swiftshot-accept").toFile().canonicalFile
    private val repo = File(tmp, "repo")
    private val baseline = File(repo, "screenshots-baseline")
    /** Neither the user's nor the system's git config: no signing, hooks or identity leak into the tests. */
    private val gitEnv = mapOf("GIT_CONFIG_GLOBAL" to "/dev/null", "GIT_CONFIG_NOSYSTEM" to "1")
    private val errors = ByteArrayOutputStream()

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    private fun git(dir: File, vararg args: String): String {
        val p = ProcessBuilder(listOf("git", "-c", "user.name=Test", "-c", "user.email=test@example.com") + args).directory(dir).redirectErrorStream(true)
        p.environment().putAll(gitEnv)
        val proc = p.start()
        val out = proc.inputStream.bufferedReader().readText()
        check(proc.waitFor() == 0) { "git ${args.joinToString(" ")}: $out" }
        return out.trim()
    }

    private fun head() = git(repo, "rev-parse", "HEAD")
    private fun commits() = git(repo, "rev-list", "--count", "HEAD").toInt()

    /** A repository whose baseline directory holds [case]'s baseline, committed. */
    private fun repoWith(case: String) {
        repo.mkdirs()
        git(repo, "init", "-q", "-b", "main")
        File(root, "$case/baseline").copyRecursively(baseline)
        File(repo, "README").writeText("app\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "initial")
    }

    /** [case]'s expected report directory, its manifest pointing at [commit]. */
    private fun report(case: String, commit: String = head(), name: String = case): File {
        val dir = File(tmp, "reports/$name")
        File(root, "$case/expected").copyRecursively(dir)
        setManifest(dir) { it["commit"] = commit }
        return dir
    }

    @Suppress("UNCHECKED_CAST")
    private fun setManifest(dir: File, change: (MutableMap<String, Any?>) -> Unit) {
        val f = File(dir, "manifest.json")
        val m = (Json.parse(f.readText()) as Map<String, Any?>).toMutableMap()
        change(m)
        f.writeText(CanonicalJson.pretty(m))
    }

    private fun json(f: File) = Json.parse(f.readText()) as Map<*, *>
    private fun images() = json(File(baseline, "baseline.json"))["images"] as Map<*, *>
    private fun bytes(f: File) = f.readBytes()

    private fun accept(vararg from: File, only: Set<String>? = null, push: Boolean = false, author: String? = null, token: String? = null, urls: List<String> = emptyList(), env: Map<String, String> = emptyMap(), branch: String? = null, extraGit: Map<String, String> = emptyMap()): Int {
        val old = System.err
        System.setErr(PrintStream(errors, true))
        try {
            return Accept.run(from.map { it.path } + urls, only, push, author, baseline, Log(false), branch = branch,
                env = env + (token?.let { mapOf("SWIFTSHOT_ARTIFACT_TOKEN" to it) } ?: emptyMap()), gitEnv = gitEnv + extraGit)
        } finally {
            System.setErr(old)
            old.print(errors.toString())
        }
    }

    private fun clean() = git(repo, "status", "--porcelain")

    @Test fun appliesChangedImageWithManifestFingerprintAndLeavesTheRestAlone() {
        repoWith("changed-pixels")
        val settingsBefore = bytes(File(baseline, "en-US/Pixel 9-Settings.png"))
        val before = images()
        val start = commits()
        assertEquals(0, accept(report("changed-pixels")))
        assertTrue(bytes(File(root, "changed-pixels/output/en-US/Pixel 9-Home.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Home.png"))))
        assertTrue(settingsBefore.contentEquals(bytes(File(baseline, "en-US/Pixel 9-Settings.png"))))
        val after = images()
        assertEquals(before["en-US/Pixel 9-Settings"], after["en-US/Pixel 9-Settings"])
        val home = after["en-US/Pixel 9-Home"] as Map<*, *>
        // The report's ci is false: an image accepted from a local verify is local.
        assertEquals(true, home["local"])
        assertEquals("241d8bd3b005", home["fingerprint"])
        assertEquals(CanonicalJson.pretty(mapOf("appearance" to "light", "device" to "Pixel 9", "fingerprint" to "241d8bd3b005", "fontScale" to 1, "language" to "en-US",
            "local" to true, "module" to ":app", "platform" to "android", "preview" to "Home")), CanonicalJson.pretty(home))
        val text = File(baseline, "baseline.json").readText()
        assertEquals(CanonicalJson.pretty(Json.parse(text)), text)
        // No --push: the files changed, nothing committed.
        assertEquals(start, commits())
        assertEquals(setOf("M screenshots-baseline/baseline.json", "M \"screenshots-baseline/en-US/Pixel 9-Home.png\""), clean().lines().map { it.trim() }.toSet())
    }

    @Test fun ciReportWritesNonLocalImages() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        setManifest(r) { it["ci"] = mapOf("buildUrl" to null, "provider" to "github", "pullRequest" to "7") }
        assertEquals(0, accept(r))
        assertEquals(false, (images()["en-US/Pixel 9-Home"] as Map<*, *>)["local"])
    }

    @Test fun ciMustBeNullOrAnObject() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        for ((label, change) in listOf<Pair<String, (MutableMap<String, Any?>) -> Unit>>("a boolean" to { it["ci"] = true }, "a string" to { it["ci"] = "github" }, "missing" to { it.remove("ci") })) {
            setManifest(r, change)
            errors.reset()
            assertEquals(64, accept(r), label)
            assertContains(errors.toString(), "manifest.json has no ci", false, label)
            assertEquals("", clean(), label)
        }
    }

    @Test fun addsNewImages() {
        repoWith("added")
        assertEquals(0, accept(report("added")))
        assertTrue(File(baseline, "en-US/Pixel 9-Onboarding.png").isFile)
        assertEquals("Onboarding", (images()["en-US/Pixel 9-Onboarding"] as Map<*, *>)["preview"])
    }

    @Test fun deletesRemovedImagesAndDropsUnreferencedFingerprints() {
        repoWith("split-run-ios")
        // Leave the iOS fingerprint with one image, then remove it: the fingerprint goes too.
        File(baseline, "en-US/iPhone 17 Pro-Home.png").delete()
        val bj = File(baseline, "baseline.json")
        @Suppress("UNCHECKED_CAST")
        val j = (json(bj) as Map<String, Any?>).toMutableMap()
        j["images"] = (j["images"] as Map<String, Any?>) - "en-US/iPhone 17 Pro-Home"
        bj.writeText(CanonicalJson.pretty(j))
        git(repo, "commit", "-qam", "one iOS image")
        assertEquals(0, accept(report("split-run-ios")))
        assertFalse(File(baseline, "en-US/iPhone 17 Pro-Settings.png").exists())
        assertFalse("en-US/iPhone 17 Pro-Settings" in images())
        assertEquals(setOf("241d8bd3b005"), (json(bj)["fingerprints"] as Map<*, *>).keys)
    }

    @Test fun acceptWarnsWhenAllRemovals() {
        repoWith("removed")
        val r = report("removed")
        setManifest(r) { m -> m["ids"] = (m["ids"] as Map<*, *>) + ("removed" to listOf("en-US/Pixel 9-Home", "en-US/Pixel 9-Legacy")) }
        assertEquals(0, accept(r))
        assertContains(errors.toString(), "Every change in the report is a removal (2 screenshots); check the run rendered what you expected")
        assertFalse(File(baseline, "en-US/Pixel 9-Legacy.png").exists())
    }

    @Test fun acceptWarnsWhenTheOnlyChangeIsOneRemoval() {
        repoWith("removed")
        assertEquals(0, accept(report("removed")))
        assertContains(errors.toString(), "is a removal (1 screenshot); check")
    }

    @Test fun interruptedAcceptExits2() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        Thread.currentThread().interrupt()
        try {
            assertEquals(2, accept(r))
            assertTrue(Thread.currentThread().isInterrupted, "the interrupt flag is restored")
        } finally {
            Thread.interrupted()
        }
        assertContains(errors.toString(), "accept was interrupted")
    }

    @Test fun nullImagesInBaselineJsonIsAUsageError() {
        repoWith("changed-pixels")
        val bj = File(baseline, "baseline.json")
        @Suppress("UNCHECKED_CAST")
        bj.writeText(CanonicalJson.pretty((json(bj) as Map<String, Any?>) + ("images" to null)))
        git(repo, "commit", "-qam", "null images")
        assertEquals(64, accept(report("changed-pixels")))
        assertContains(errors.toString(), "\"images\" must be an object")
    }

    @Test fun errorIdsAreNeverTouched() {
        repoWith("render-error")
        val files = baseline.walkTopDown().filter { it.isFile }.associate { it.path to it.readBytes().toList() }
        assertEquals(0, accept(report("render-error")))
        assertEquals(files, baseline.walkTopDown().filter { it.isFile }.associate { it.path to it.readBytes().toList() })
        assertContains(errors.toString(), "Nothing to accept")
    }

    @Test fun onlyRestrictsToTheGivenIds() {
        repoWith("tolerance")
        val clockBefore = bytes(File(baseline, "en-US/Pixel 9-Clock Large.png"))
        assertEquals(0, accept(report("tolerance"), only = setOf("en-US/Pixel 9-Settings")))
        assertTrue(clockBefore.contentEquals(bytes(File(baseline, "en-US/Pixel 9-Clock Large.png"))))
        assertTrue(bytes(File(root, "tolerance/output/en-US/Pixel 9-Settings.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Settings.png"))))
    }

    @Test fun unknownOnlyIdIsAUsageErrorAndWritesNothing() {
        repoWith("tolerance")
        assertEquals(64, accept(report("tolerance"), only = setOf("en-US/Pixel 9-Settings", "en-US/Pixel 9-Nope")))
        assertContains(errors.toString(), "en-US/Pixel 9-Nope")
        assertEquals("", clean())
    }

    @Test fun twoReportsFromSplitRunsApplyTogether() {
        repoWith("split-run-android")
        assertEquals(0, accept(report("split-run-android"), report("split-run-ios")))
        assertTrue(bytes(File(root, "split-run-android/output/en-US/Pixel 9-Settings.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Settings.png"))))
        assertFalse(File(baseline, "en-US/iPhone 17 Pro-Settings.png").exists())
        assertEquals(setOf("en-US/Pixel 9-Home", "en-US/Pixel 9-Settings", "en-US/iPhone 17 Pro-Home"), images().keys)
    }

    @Test fun conflictingReportsAreAUsageError() {
        repoWith("changed-pixels")
        val a = report("changed-pixels", name = "a")
        val b = report("changed-pixels", name = "b")
        File(root, "changed-pixels/output/en-US/Pixel 9-Settings.png").copyTo(File(b, "images/new/en-US/Pixel 9-Home.png"), overwrite = true)
        assertEquals(64, accept(a, b))
        assertContains(errors.toString(), "en-US/Pixel 9-Home")
        assertEquals("", clean())
        // The same report twice is no conflict.
        assertEquals(0, accept(a, report("changed-pixels", name = "c")))
    }

    @Test fun staleReportIsRefused() {
        repoWith("changed-pixels")
        val old = head()
        File(repo, "README").writeText("changed\n")
        git(repo, "commit", "-qam", "more work")
        assertEquals(1, accept(report("changed-pixels", commit = old)))
        val message = errors.toString()
        assertContains(message, old)
        assertContains(message, head())
        assertEquals("", clean())
    }

    @Test fun unknownManifestCommitIsRefused() {
        repoWith("changed-pixels")
        assertEquals(1, accept(report("changed-pixels", commit = "0123456789abcdef0123456789abcdef01234567")))
        assertEquals("", clean())
    }

    @Test fun onlyAcceptCommitsSinceTheReportAreAllowed() {
        repoWith("split-run-android")
        val verified = head()
        File(baseline, "en-US/Pixel 9-Home.png").copyTo(File(baseline, "en-US/Pixel 9-Home-copy.png"))
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "Update screenshot baseline (1 added)", "-m", "Swiftshot-Accept: 1111111111111111111111111111111111111111")
        assertEquals(0, accept(report("split-run-android", commit = verified)))
        git(repo, "checkout", "-q", "--", ".")
        // Any other commit after it makes the report stale again.
        File(repo, "README").writeText("x\n")
        git(repo, "commit", "-qam", "work")
        assertEquals(1, accept(report("split-run-ios", commit = verified)))
    }

    @Test fun pushCommitsOnceAsTheBotAndPushes() {
        repoWith("split-run-android")
        val remote = File(tmp, "remote.git")
        git(tmp, "init", "-q", "--bare", "-b", "main", remote.path)
        git(repo, "remote", "add", "origin", remote.path)
        git(repo, "push", "-q", "-u", "origin", "main")
        val verified = head()
        assertEquals(0, accept(report("split-run-android"), report("split-run-ios"), push = true))
        assertEquals(1, git(repo, "rev-list", "--count", "$verified..HEAD").toInt())
        assertEquals("swiftshot <swiftshot@users.noreply.github.com>", git(repo, "log", "-1", "--format=%an <%ae>"))
        assertEquals("Update screenshot baseline (1 changed, 1 removed)", git(repo, "log", "-1", "--format=%s"))
        assertEquals(verified, git(repo, "log", "-1", "--format=%(trailers:key=Swiftshot-Accept,valueonly)"))
        assertEquals(head(), git(remote, "rev-parse", "main"))
        assertEquals("", clean())
        // The accept commit doesn't make the report stale: accepting it again has nothing left to do.
        assertEquals(0, accept(report("split-run-android", commit = verified, name = "again"), push = true))
        assertEquals(1, git(repo, "rev-list", "--count", "$verified..HEAD").toInt())
    }

    @Test fun authorOverride() {
        repoWith("added")
        val remote = File(tmp, "remote.git")
        git(tmp, "init", "-q", "--bare", "-b", "main", remote.path)
        git(repo, "remote", "add", "origin", remote.path)
        git(repo, "push", "-q", "origin", "main")
        // No upstream: pushed to origin's branch of the same name.
        assertEquals(0, accept(report("added"), push = true, author = "Release Bot <bot@example.com>"))
        assertEquals("Release Bot <bot@example.com>", git(repo, "log", "-1", "--format=%an <%ae>"))
        assertEquals("Update screenshot baseline (1 added)", git(repo, "log", "-1", "--format=%s"))
        assertEquals(head(), git(remote, "rev-parse", "main"))
        assertEquals(64, accept(report("added", name = "bad"), push = true, author = "no email"))
    }

    @Test fun commitMessageCounts() {
        assertEquals("Update screenshot baseline (3 changed, 1 added)", Accept.message(3, 1, 0))
        assertEquals("Update screenshot baseline (2 removed)", Accept.message(0, 0, 2))
        assertEquals("Update screenshot baseline (1 changed, 2 added, 3 removed)", Accept.message(1, 2, 3))
    }

    @Test fun nothingToApplyWithPushMakesNoCommit() {
        repoWith("unchanged")
        val start = commits()
        assertEquals(0, accept(report("unchanged"), push = true))
        assertEquals(start, commits())
    }

    @Test fun reportIdsMustStayInsideTheBaseline() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        setManifest(r) { it["ids"] = mapOf("added" to emptyList<String>(), "changed" to listOf("../escape"), "removed" to emptyList<String>()) }
        assertEquals(64, accept(r))
        assertEquals("", clean())
    }

    private fun zip(dir: File, out: File, prefix: String = "", extra: List<Pair<String, ByteArray>> = emptyList()): File {
        ZipOutputStream(out.outputStream()).use { z ->
            for (f in dir.walkTopDown().filter { it.isFile }) {
                z.putNextEntry(ZipEntry(prefix + f.relativeTo(dir).invariantSeparatorsPath)); f.inputStream().use { it.copyTo(z) }; z.closeEntry()
            }
            for ((name, data) in extra) { z.putNextEntry(ZipEntry(name)); z.write(data); z.closeEntry() }
        }
        return out
    }

    @Test fun acceptsAZipOfTheReport() {
        repoWith("changed-pixels")
        assertEquals(0, accept(zip(report("changed-pixels"), File(tmp, "report.zip"))))
        assertTrue(bytes(File(root, "changed-pixels/output/en-US/Pixel 9-Home.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Home.png"))))
    }

    @Test fun bitriseZipIsAcceptable() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        val ci = Ci("bitrise", null, null, null, null, null, null, true)
        val v = Verification(emptyList(), emptyList(), emptyList(), emptyMap(), emptyList(), false, 0, BaselineEnv(GitInfo(null, null), "1.0.0-test", ci), "hash")
        NativeOutput.write(v, ci, r, mapOf("BITRISE_DEPLOY_DIR" to File(tmp, "deploy").path), PrintStream(errors, true), Log(false))
        assertEquals(0, accept(File(tmp, "deploy/swiftshot-report.zip")))
        assertTrue(bytes(File(root, "changed-pixels/output/en-US/Pixel 9-Home.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Home.png"))))
    }

    @Test fun acceptsAZipWithOneTopLevelDirectory() {
        repoWith("changed-pixels")
        assertEquals(0, accept(zip(report("changed-pixels"), File(tmp, "report.zip"), prefix = "screenshots-report/")))
    }

    @Test fun zipSlipIsRejected() {
        repoWith("changed-pixels")
        val z = zip(report("changed-pixels"), File(tmp, "report.zip"), extra = listOf("../../evil.txt" to "x".toByteArray()))
        assertEquals(64, accept(z))
        assertFalse(File(tmp, "evil.txt").exists())
        assertContains(errors.toString(), "evil.txt")
        assertEquals("", clean())
    }

    @Test fun symlinkInZipIsRejected() {
        repoWith("changed-pixels")
        val z = zip(report("changed-pixels"), File(tmp, "report.zip"), extra = listOf("link" to "/etc/passwd".toByteArray()))
        // Mark "link" as a Unix symlink in the central directory: made by Unix, mode 0120777.
        val b = z.readBytes()
        var i = 0
        while (i < b.size - 4) {
            if (b[i] == 0x50.toByte() && b[i + 1] == 0x4b.toByte() && b[i + 2] == 0x01.toByte() && b[i + 3] == 0x02.toByte()) {
                val n = (b[i + 28].toInt() and 0xff) or ((b[i + 29].toInt() and 0xff) shl 8)
                if (String(b, i + 46, n) == "link") {
                    b[i + 5] = 3
                    val attrs = 0xA1FF shl 16
                    for (k in 0..3) b[i + 38 + k] = (attrs ushr (8 * k)).toByte()
                }
            }
            i++
        }
        z.writeBytes(b)
        assertEquals(64, accept(z))
        assertContains(errors.toString(), "link")
    }

    @Test fun theArtifactTokenGoesOnlyOverHttps() {
        repoWith("changed-pixels")
        assertEquals(64, accept(token = "secret", urls = listOf("http://example.invalid/artifact.zip")))
        assertContains(errors.toString(), "SWIFTSHOT_ARTIFACT_TOKEN is sent only over https")
        assertFalse("secret" in errors.toString())
    }

    @Test fun reportWithErrorsWarnsAndStillApplies() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        val f = File(r, "result.json")
        f.writeText(CanonicalJson.pretty(json(f).entries.associate { (k, v) -> k as String to if (k == "status") "error" else v }))
        assertEquals(0, accept(r))
        assertContains(errors.toString(), "verify had errors")
        assertTrue(bytes(File(root, "changed-pixels/output/en-US/Pixel 9-Home.png")).contentEquals(bytes(File(baseline, "en-US/Pixel 9-Home.png"))))
    }

    @Test fun downloadsAZipWithTheArtifactToken() {
        repoWith("changed-pixels")
        val data = zip(report("changed-pixels"), File(tmp, "report.zip")).readBytes()
        val seen = mutableListOf<String?>()
        val agents = mutableListOf<String?>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/artifact.zip") { ex ->
            seen += ex.requestHeaders.getFirst("Authorization")
            agents += ex.requestHeaders.getFirst("User-Agent")
            ex.sendResponseHeaders(200, data.size.toLong()); ex.responseBody.use { it.write(data) }
        }
        server.createContext("/redirect") { ex ->
            seen += ex.requestHeaders.getFirst("Authorization")
            agents += ex.requestHeaders.getFirst("User-Agent")
            // Another host (localhost, not 127.0.0.1): the token stays behind.
            ex.responseHeaders.add("Location", "http://localhost:${server.address.port}/artifact.zip")
            ex.sendResponseHeaders(302, -1); ex.close()
        }
        server.start()
        try {
            assertEquals(0, accept(token = "secret", urls = listOf("http://127.0.0.1:${server.address.port}/artifact.zip")))
            assertEquals(listOf<String?>("Bearer secret"), seen)
            git(repo, "checkout", "-q", "--", ".")
            seen.clear()
            assertEquals(0, accept(token = "secret", urls = listOf("http://127.0.0.1:${server.address.port}/redirect")))
            assertEquals(listOf<String?>("Bearer secret", null), seen)
            assertEquals(64, accept(urls = listOf("http://127.0.0.1:${server.address.port}/missing.zip")))
        } finally {
            server.stop(0)
        }
    }

    @Test fun unexpectedExceptionIsARefusal() {
        repoWith("changed-pixels")
        val log = object : Log(false) { override fun ok(s: String) = throw IllegalStateException("broken terminal") }
        assertEquals(1, Accept.run(listOf(report("changed-pixels").path), null, false, null, baseline, log, gitEnv = gitEnv))
    }

    @Test fun acceptOptions() {
        val dir = File(tmp, "project").apply { mkdirs() }
        val o = Options.parse(listOf("accept", "--project-dir", dir.path, "--from", "a", "--from", "b.zip", "--only", "x,y", "--only", "z", "--push", "--author", "A <a@b.c>"))
        assertEquals("accept", o.command)
        assertEquals(listOf("a", "b.zip"), o.from)
        assertEquals(setOf("x", "y", "z"), o.only)
        assertTrue(o.push)
        assertEquals("A <a@b.c>", o.author)
        assertEquals("pr", Options.parse(listOf("accept", "--project-dir", dir.path, "--from", "a", "--push", "--branch", "pr")).branch)
        assertFailsWith<UsageError> { Options.parse(listOf("accept", "--project-dir", dir.path, "--from", "a", "--branch", "pr")) }
        assertEquals(64, cli(listOf("accept", "--project-dir", dir.path, "--from", "a", "--branch", "pr"), Log(false)))
        assertEquals(64, cli(listOf("accept", "--project-dir", dir.path), Log(false)))
        assertFailsWith<IllegalArgumentException> { Options.parse(listOf("run", "--project-dir", dir.path, "--push")) }
    }

    private fun remote() {
        val remote = File(tmp, "remote.git")
        git(tmp, "init", "-q", "--bare", "-b", "main", remote.path)
        git(repo, "remote", "add", "origin", remote.path)
        git(repo, "push", "-q", "-u", "origin", "main")
    }

    @Test fun pushCommitsOnlyWhatAcceptWrote() {
        repoWith("changed-pixels")
        remote()
        val verified = head()
        File(baseline, "en-US/Pixel 9-Settings.png").appendBytes(byteArrayOf(1))
        File(baseline, "en-US/Pixel 9-Stray.png").writeBytes(byteArrayOf(2))
        assertEquals(0, accept(report("changed-pixels"), push = true))
        assertEquals(1, git(repo, "rev-list", "--count", "$verified..HEAD").toInt())
        assertEquals(setOf("screenshots-baseline/baseline.json", "screenshots-baseline/en-US/Pixel 9-Home.png"),
            git(repo, "-c", "core.quotePath=false", "show", "--name-only", "--format=", "HEAD").lines().toSet())
        assertEquals(setOf("M \"screenshots-baseline/en-US/Pixel 9-Settings.png\"", "?? \"screenshots-baseline/en-US/Pixel 9-Stray.png\""),
            clean().lines().map { it.trim() }.toSet())
        // Accepting it again with the baseline still dirty: nothing of accept's changed, so no commit.
        assertEquals(0, accept(report("changed-pixels", commit = verified, name = "again"), push = true))
        assertEquals(1, git(repo, "rev-list", "--count", "$verified..HEAD").toInt())
    }

    // CI checkouts

    private val ciEnv = mapOf("GITLAB_CI" to "true", "CI_COMMIT_BRANCH" to "feature/x")
    private val bare get() = File(tmp, "remote.git")

    @Test fun pushFromDetachedUsesCiBranch() {
        repoWith("changed-pixels")
        remote()
        git(repo, "checkout", "-q", "--detach")
        assertEquals(0, accept(report("changed-pixels"), push = true, env = ciEnv))
        assertEquals(head(), git(bare, "rev-parse", "feature/x"))
        assertFalse(git(bare, "rev-parse", "main") == head())
    }

    @Test fun pushFromDetachedWithoutBranchRefuses() {
        repoWith("changed-pixels")
        remote()
        git(repo, "checkout", "-q", "--detach")
        assertEquals(1, accept(report("changed-pixels"), push = true))
        assertContains(errors.toString(), "HEAD is detached and no branch is known; pass --branch <the pull request branch>")
        assertEquals("", clean())
    }

    @Test fun pushFromDetachedOnAGithubCommentRefuses() {
        repoWith("changed-pixels")
        remote()
        git(repo, "checkout", "-q", "--detach")
        // An issue_comment run's GITHUB_REF_NAME is the default branch, never the pull request's.
        val comment = mapOf("GITHUB_ACTIONS" to "true", "GITHUB_EVENT_NAME" to "issue_comment", "GITHUB_REF_NAME" to "main", "GITHUB_REF_TYPE" to "branch")
        assertEquals(1, accept(report("changed-pixels"), push = true, env = comment))
        assertContains(errors.toString(), "HEAD is detached and no branch is known; pass --branch <the pull request branch>")
        assertEquals("", clean())
    }

    @Test fun branchFlagWins() {
        repoWith("changed-pixels")
        remote()
        val verified = head()
        assertEquals(0, accept(report("changed-pixels"), push = true, branch = "pr/1", env = ciEnv))
        assertEquals(head(), git(bare, "rev-parse", "pr/1"))
        assertEquals(verified, git(bare, "rev-parse", "main"))
        assertEquals(1, accept(report("changed-pixels", commit = verified, name = "x"), push = true, branch = "pr/1", env = mapOf("GITLAB_CI" to "true", "CI_MERGE_REQUEST_SOURCE_PROJECT_ID" to "2", "CI_MERGE_REQUEST_PROJECT_ID" to "1")))
    }

    @Test fun forkRefusesPush() {
        repoWith("changed-pixels")
        remote()
        val fork = ciEnv + mapOf("CI_MERGE_REQUEST_SOURCE_PROJECT_ID" to "2", "CI_MERGE_REQUEST_PROJECT_ID" to "1")
        assertEquals(1, accept(report("changed-pixels"), push = true, env = fork))
        assertContains(errors.toString(), "This pull request comes from a fork; download the report and run swiftshot accept --from <report> in the fork")
        assertEquals("", clean())
        assertEquals(0, accept(report("changed-pixels", name = "again"), env = fork))
    }

    @Test fun pushFailureHidesToken() {
        repoWith("changed-pixels")
        val seen = mutableListOf<String?>()
        val agents = mutableListOf<String?>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { ex ->
            seen += ex.requestHeaders.getFirst("Authorization")
            agents += ex.requestHeaders.getFirst("User-Agent")
            ex.sendResponseHeaders(403, -1); ex.close()
        }
        server.start()
        try {
            git(repo, "remote", "add", "origin", "http://127.0.0.1:${server.address.port}/owner/repo.git")
            val token = "tok-s3cret"
            val b64 = java.util.Base64.getEncoder().encodeToString("x-access-token:$token".toByteArray())
            // With redaction off, git traces the request headers, extraHeader included. A GIT_CONFIG_* setting of
            // the CI's own stays in force next to the header.
            val ciConfig = mapOf("GIT_CONFIG_COUNT" to "1", "GIT_CONFIG_KEY_0" to "http.userAgent", "GIT_CONFIG_VALUE_0" to "ci-agent")
            assertEquals(1, accept(report("changed-pixels"), push = true, extraGit = mapOf("GIT_TRACE_CURL" to "1", "GIT_TRACE_REDACT" to "0") + ciConfig,
                env = mapOf("SWIFTSHOT_GIT_HOST" to "github", "SWIFTSHOT_HOST_TOKEN" to token)))
            assertTrue(seen.isNotEmpty() && seen.all { it == "Basic $b64" }, "the header reached the server: $seen")
            assertTrue(agents.isNotEmpty() && agents.all { it == "ci-agent" }, "the CI's config reached the server: $agents")
            val out = errors.toString()
            assertContains(out, "git push origin HEAD failed")
            for (secret in listOf(token, b64)) assertFalse(secret in out, "output has $secret")
            assertContains(out, "***")
            assertFalse(token in File(repo, ".git/config").readText())
        } finally {
            server.stop(0)
        }
    }

    @Test fun pushHeaderGoesInTheEnvironmentNotTheCommandLine() {
        val header = "Authorization: Basic c2VjcmV0"
        val (args, env) = Accept.pushCommand(listOf("origin", "HEAD:refs/heads/x"), header, emptyMap())
        assertEquals(listOf("push", "origin", "HEAD:refs/heads/x"), args)
        assertFalse(args.any { "c2VjcmV0" in it })
        assertEquals(mapOf("GIT_CONFIG_COUNT" to "1", "GIT_CONFIG_KEY_0" to "http.extraHeader", "GIT_CONFIG_VALUE_0" to header), env)
        // The CI's own GIT_CONFIG_* entries stay; the header goes after them.
        assertEquals(mapOf("GIT_CONFIG_COUNT" to "3", "GIT_CONFIG_KEY_2" to "http.extraHeader", "GIT_CONFIG_VALUE_2" to header),
            Accept.pushCommand(listOf("origin", "HEAD"), header, mapOf("GIT_CONFIG_COUNT" to "2")).second)
        assertEquals(listOf("push", "origin", "HEAD") to emptyMap(), Accept.pushCommand(listOf("origin", "HEAD"), null, mapOf("GIT_CONFIG_COUNT" to "2")))
    }

    @Test fun tokenWithANonHttpsRemoteWarnsAndPushesPlainly() {
        repoWith("changed-pixels")
        remote()
        val token = "tok-s3cret"
        assertEquals(0, accept(report("changed-pixels"), push = true, env = mapOf("SWIFTSHOT_GIT_HOST" to "github", "SWIFTSHOT_HOST_TOKEN" to token)))
        assertEquals(head(), git(bare, "rev-parse", "main"))
        val out = errors.toString()
        assertEquals(1, Regex("SWIFTSHOT_HOST_TOKEN is not used: origin is not an https remote").findAll(out).count(), out)
        assertFalse(token in out)
    }

    @Test fun artifactAuthHeaderPerHost() {
        fun h(url: String, token: String = "t", env: Map<String, String> = emptyMap()) = Accept.artifactHeader(java.net.URI(url), token, env).let { "${it.first}: ${it.second}" }
        val basic = { s: String -> "Basic " + java.util.Base64.getEncoder().encodeToString(s.toByteArray()) }
        assertEquals("Authorization: Bearer t", h("https://api.github.com/repos/o/r/actions/artifacts/1/zip"))
        assertEquals("Authorization: Bearer t", h("https://ghe.example.com/api/v3/x", env = mapOf("GITHUB_API_URL" to "https://ghe.example.com/api/v3")))
        assertEquals("PRIVATE-TOKEN: t", h("https://gitlab.com/api/v4/projects/1/jobs/2/artifacts"))
        assertEquals("JOB-TOKEN: t", h("https://gitlab.com/api/v4/projects/1/jobs/2/artifacts", env = mapOf("CI_JOB_TOKEN" to "t")))
        assertEquals("PRIVATE-TOKEN: t", h("https://gitlab.com/x", env = mapOf("CI_JOB_TOKEN" to "other")))
        assertEquals("JOB-TOKEN: t", h("https://git.corp/api/v4/x", env = mapOf("CI_API_V4_URL" to "https://git.corp/api/v4", "CI_JOB_TOKEN" to "t")))
        assertEquals("Circle-Token: t", h("https://circleci.com/api/v2/project/gh/o/r/1/artifacts"))
        assertEquals(basic(":t").let { "Authorization: $it" }, h("https://dev.azure.com/org/p/_apis/x"))
        assertEquals("Authorization: ${basic(":t")}", h("https://org.visualstudio.com/p/_apis/x"))
        assertEquals("Authorization: ${basic("user:apitoken")}", h("https://jenkins.corp/job/x/artifact/r.zip", token = "user:apitoken"))
        assertEquals("Authorization: Bearer t", h("https://example.com/r.zip"))
        // The host wins over a colon in the token.
        assertEquals("PRIVATE-TOKEN: a:b", h("https://gitlab.com/x", token = "a:b"))
    }

    @Test fun artifactAuthHeaderReachesTheServer() {
        repoWith("changed-pixels")
        val data = zip(report("changed-pixels"), File(tmp, "report.zip")).readBytes()
        val seen = mutableListOf<Map<String, String?>>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { ex ->
            seen += mapOf("Authorization" to ex.requestHeaders.getFirst("Authorization"), "PRIVATE-TOKEN" to ex.requestHeaders.getFirst("PRIVATE-TOKEN"), "JOB-TOKEN" to ex.requestHeaders.getFirst("JOB-TOKEN"))
            ex.sendResponseHeaders(200, data.size.toLong()); ex.responseBody.use { it.write(data) }
        }
        server.start()
        val url = listOf("http://127.0.0.1:${server.address.port}/a.zip")
        try {
            assertEquals(0, accept(token = "secret", urls = url, env = mapOf("GITHUB_API_URL" to "http://127.0.0.1:${server.address.port}")))
            assertEquals("Bearer secret", seen.last()["Authorization"])
            git(repo, "checkout", "-q", "--", ".")
            assertEquals(0, accept(token = "secret", urls = url, env = mapOf("CI_API_V4_URL" to "http://127.0.0.1:${server.address.port}/api/v4", "CI_JOB_TOKEN" to "secret")))
            assertEquals(mapOf("Authorization" to null, "PRIVATE-TOKEN" to null, "JOB-TOKEN" to "secret"), seen.last())
            git(repo, "checkout", "-q", "--", ".")
            assertEquals(0, accept(token = "secret", urls = url, env = mapOf("CI_API_V4_URL" to "http://127.0.0.1:${server.address.port}/api/v4")))
            assertEquals("secret", seen.last()["PRIVATE-TOKEN"])
        } finally {
            server.stop(0)
        }
    }

    @Test fun artifactHeaderOverride() {
        repoWith("changed-pixels")
        val data = zip(report("changed-pixels"), File(tmp, "report.zip")).readBytes()
        val seen = mutableListOf<List<String?>>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { ex ->
            seen += listOf(ex.requestHeaders.getFirst("X-Api-Key"), ex.requestHeaders.getFirst("Authorization"))
            ex.sendResponseHeaders(200, data.size.toLong()); ex.responseBody.use { it.write(data) }
        }
        server.start()
        try {
            val env = mapOf("SWIFTSHOT_ARTIFACT_HEADER" to "X-Api-Key: key-{token}", "GITHUB_API_URL" to "http://127.0.0.1:${server.address.port}")
            assertEquals(0, accept(token = "secret", urls = listOf("http://127.0.0.1:${server.address.port}/a.zip"), env = env))
            assertEquals(listOf<List<String?>>(listOf("key-secret", null)), seen)
            assertEquals(64, accept(token = "secret", urls = listOf("http://127.0.0.1:${server.address.port}/a.zip"), env = mapOf("SWIFTSHOT_ARTIFACT_HEADER" to "no colon")))
            assertFalse("secret" in errors.toString())
        } finally {
            server.stop(0)
        }
    }

    @Test fun pushWithARemovedImageGitNeverTracked() {
        repoWith("removed")
        remote()
        git(repo, "rm", "-q", "--cached", "screenshots-baseline/en-US/Pixel 9-Legacy.png")
        git(repo, "commit", "-qm", "untrack")
        git(repo, "push", "-q")
        assertEquals(0, accept(report("removed"), push = true))
        assertEquals("screenshots-baseline/baseline.json", git(repo, "show", "--name-only", "--format=", "HEAD"))
    }

    @Test fun baselineJsonIsWrittenWithoutLeftovers() {
        repoWith("changed-pixels")
        assertEquals(0, accept(report("changed-pixels")))
        assertEquals(listOf("baseline.json", "en-US"), baseline.list()!!.sorted())
    }

    @Test fun malformedBaselineJsonIsAUsageErrorNamingIt() {
        repoWith("changed-pixels")
        File(baseline, "baseline.json").writeText("""{"fingerprints": {}, "images": [], "schema": 1}""")
        git(repo, "commit", "-qam", "broken")
        assertEquals(64, accept(report("changed-pixels")))
        assertContains(errors.toString(), "baseline.json")
        assertEquals("", clean())
    }

    @Test fun malformedResultJsonIsAUsageErrorNamingIt() {
        repoWith("changed-pixels")
        val r = report("changed-pixels")
        File(r, "result.json").writeText("[1]")
        assertEquals(64, accept(r))
        assertContains(errors.toString(), "result.json")
    }

    @Test fun damagedZipsAreUsageErrors() {
        repoWith("changed-pixels")
        val good = zip(report("changed-pixels"), File(tmp, "good.zip")).readBytes()
        // Truncated: no central directory.
        assertEquals(64, accept(File(tmp, "cut.zip").apply { writeBytes(good.copyOf(good.size / 2)) }))
        // Garbage.
        assertEquals(64, accept(File(tmp, "junk.zip").apply { writeBytes("PK not really".toByteArray()) }))
        // Damaged compressed data: the first entry's bytes after its local header.
        val bad = good.copyOf()
        for (k in 60 until 120) bad[k] = (bad[k].toInt() xor 0x5a).toByte()
        assertEquals(64, accept(File(tmp, "bad.zip").apply { writeBytes(bad) }))
        // An entry name that isn't UTF-8.
        val named = zip(report("changed-pixels", name = "n"), File(tmp, "named.zip"), extra = listOf("aXb" to byteArrayOf(1))).readBytes()
        val marker = "aXb".toByteArray()
        for (k in 0..named.size - 3) if (named[k] == marker[0] && named[k + 1] == marker[1] && named[k + 2] == marker[2]) named[k + 1] = 0xff.toByte()
        assertEquals(64, accept(File(tmp, "named.zip").apply { writeBytes(named) }))
        assertFalse(errors.toString().contains("\tat "), "no stack traces")
        assertEquals("", clean())
    }

    @Test fun acceptedImagesGetTheirOwnRuntimesBuild() {
        repoWith("multi-runtime")
        val r = report("multi-runtime")
        val id = "en-US/iPhone 17 Pro-Settings-iOS26.5"
        val result = File(r, "result.json")
        @Suppress("UNCHECKED_CAST")
        val j = (Json.parse(result.readText()) as Map<String, Any?>).toMutableMap()
        @Suppress("UNCHECKED_CAST")
        j["screenshots"] = (j["screenshots"] as List<Map<String, Any?>>).map { if (it["id"] == id) it + ("status" to "changed") else it }
        result.writeText(CanonicalJson.pretty(j))
        setManifest(r) { it["ids"] = mapOf("added" to emptyList<String>(), "changed" to listOf(id), "removed" to emptyList<String>()) }
        File(root, "multi-runtime/output/$id.png").copyTo(File(r, "images/new/$id.png"))
        assertEquals(0, accept(r))
        val fps = json(File(baseline, "baseline.json"))["fingerprints"] as Map<*, *>
        val fp = fps[(images()[id] as Map<*, *>)["fingerprint"]] as Map<*, *>
        assertEquals("23F80", fp["runtime"])
        assertFalse(fp.containsKey("runtimes"))
        // The 26.0 images keep theirs.
        assertEquals("23A343", (fps[(images()["en-US/iPhone 17 Pro-Home-iOS26.0"] as Map<*, *>)["fingerprint"]] as Map<*, *>)["runtime"])
    }
}
