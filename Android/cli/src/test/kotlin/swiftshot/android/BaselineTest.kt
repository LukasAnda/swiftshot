package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * `verify` and `record` against the shared fixtures in Shared/testdata/baseline (docs/wiki/Baseline-format.md):
 * every case gives exactly the expected result.json, junit.xml, manifest.json, images and exit code.
 */
class BaselineTest {
    private val root = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "baseline")
    private val tmp: File = Files.createTempDirectory("swiftshot-baseline").toFile()
    private val env = BaselineEnv(GitInfo("0123456789abcdef0123456789abcdef01234567", "feature/x"), "1.0.0-test", ci = false)

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    private fun cases() = root.listFiles()!!.filter { File(it, "expected/result.json").isFile }.sortedBy { it.name }
    private fun case(name: String) = File(root, name)

    private fun config(case: File) = CompareConfig.from(Options.parse(listOf("--project-dir", tmp.path, "--config", File(case, "config.json").path)))

    private fun verify(case: File, report: File = File(tmp, case.name)): Verification =
        Baseline.evaluate(File(case, "output"), File(case, "baseline"), report, config(case), env)

    private fun files(dir: File): Map<String, File> =
        if (!dir.isDirectory) emptyMap() else dir.walkTopDown().filter { it.isFile }.associateBy { it.relativeTo(dir).invariantSeparatorsPath }

    private fun result(dir: File) = Json.parse(File(dir, "result.json").readText()) as Map<*, *>
    private fun ids(dir: File) = (result(dir)["screenshots"] as List<*>).map { (it as Map<*, *>)["id"] as String }

    @Test fun everyFixtureCaseMatchesByteForByte() {
        val all = cases()
        assertEquals(22, all.size, "fixture cases")
        val problems = mutableListOf<String>()
        for (case in all) {
            val report = File(tmp, case.name)
            val v = verify(case, report)
            for (name in listOf("result.json", "junit.xml", "manifest.json")) {
                val want = File(case, "expected/$name").readText()
                val got = File(report, name).takeIf { it.isFile }?.readText()
                if (got != want) problems += "${case.name}/$name differs:\n--- want\n$want--- got\n$got"
            }
            val wantImages = files(File(case, "expected/images"))
            val gotImages = files(File(report, "images"))
            if (wantImages.keys != gotImages.keys) problems += "${case.name}: images ${wantImages.keys} != ${gotImages.keys}"
            for ((k, f) in wantImages) if (gotImages[k]?.readBytes()?.contentEquals(f.readBytes()) == false) problems += "${case.name}: image $k bytes differ"
            val status = result(File(case, "expected"))["status"]
            val code = mapOf("passed" to 0, "failed" to 1, "error" to 2)[status]
            if (v.exitCode != code) problems += "${case.name}: exit ${v.exitCode}, want $code"
        }
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
    }

    @Test fun outOfScopeBaselineImagesAreNotRemoved() {
        val v = verify(case("out-of-scope"))
        assertEquals(0, v.counts["removed"])
        assertEquals(listOf("en-US/iPhone 17 Pro-Home One"), ids(File(tmp, "out-of-scope")))
    }

    @Test fun splitRunVerifiesOnlyItsOwnPlatform() {
        verify(case("split-run-android"))
        assertTrue(ids(File(tmp, "split-run-android")).all { "Pixel 9" in it })
        // The iOS job: its Settings is removed, the Android images aren't looked at.
        verify(case("split-run-ios"))
        assertEquals(listOf("en-US/iPhone 17 Pro-Home", "en-US/iPhone 17 Pro-Settings"), ids(File(tmp, "split-run-ios")))
    }

    @Test fun fingerprintMismatchIsSaidFirst() {
        val v = verify(case("fingerprint-mismatch"))
        assertEquals(0, v.exitCode)
        val lines = BaselineReport.summary(v, File(tmp, "fingerprint-mismatch"))
        assertTrue(lines.first().second.contains("android host: baseline linux-x64, this run macos-arm64"), lines.toString())
        assertEquals("warn", lines.first().first)
    }

    @Test fun localBaselineWarnsAndPasses() {
        val v = verify(case("local-baseline"))
        assertEquals(0, v.exitCode)
        assertTrue(v.localBaseline)
        assertTrue(BaselineReport.summary(v, File(tmp, "local-baseline")).any { it.first == "warn" && "outside CI" in it.second })
    }

    @Test fun staleReportFilesAreReplaced() {
        val report = File(tmp, "reuse")
        verify(case("changed-pixels"), report)
        assertTrue(File(report, "images/diff/en-US/Pixel 9-Home.png").isFile)
        verify(case("unchanged"), report)
        assertFalse(File(report, "images").exists())
    }

    /** A run's output dir: the fixture's output, copied (record writes into the baseline only). */
    private fun output(name: String) = File(tmp, "out-$name").also { case(name).resolve("output").copyRecursively(it) }

    private fun baselineJson(dir: File) = Json.parse(File(dir, "baseline.json").readText()) as Map<*, *>

    @Test fun recordWritesBaselineWithFingerprintsAndLocal() {
        val out = output("fingerprint-mismatch")
        val base = File(tmp, "base")
        assertEquals(0, Baseline.record(out, base, ci = false, log = Log(false)))
        val json = baselineJson(base)
        assertEquals(1L, json["schema"])
        val images = json["images"] as Map<*, *>
        assertEquals(setOf("en-US/iPhone 17 Pro-Home", "en-US/Pixel 9-Home"), images.keys)
        val fps = json["fingerprints"] as Map<*, *>
        assertEquals(2, fps.size)
        for ((id, fp) in fps) assertEquals(id, Fingerprints.id(fp as Map<*, *>))
        val ios = images["en-US/iPhone 17 Pro-Home"] as Map<*, *>
        assertEquals(true, ios["local"])
        assertEquals("default", ios["textSize"])
        assertEquals("26.0", ios["runtime"])
        assertEquals("ios", (fps[ios["fingerprint"]] as Map<*, *>)["platform"])
        // The image fingerprint: its own runtime's build, not the run's runtimes.
        assertEquals("23A343", (fps[ios["fingerprint"]] as Map<*, *>)["runtime"])
        assertFalse((fps[ios["fingerprint"]] as Map<*, *>).containsKey("runtimes"))
        val android = images["en-US/Pixel 9-Home"] as Map<*, *>
        assertEquals(":app", android["module"])
        assertEquals(1L, android["fontScale"])
        assertTrue(File(base, "en-US/Pixel 9-Home.png").readBytes().contentEquals(File(out, "en-US/Pixel 9-Home.png").readBytes()))
        // The written file is canonical.
        assertEquals(CanonicalJson.pretty(json), File(base, "baseline.json").readText())

        // On CI: local false; a verify against it passes.
        assertEquals(0, Baseline.record(out, base, ci = true, log = Log(false)))
        assertEquals(false, ((baselineJson(base)["images"] as Map<*, *>)["en-US/Pixel 9-Home"] as Map<*, *>)["local"])
        val v = Baseline.evaluate(out, base, File(tmp, "after-record"), CompareConfig(null, emptyList()), env)
        assertEquals(0, v.exitCode)
        assertTrue(v.mismatches.isEmpty())
        assertFalse(v.localBaseline)
    }

    @Test fun recordReplacesInScopeImagesAndKeepsOthers() {
        // The removed case: Legacy is in scope and not rendered, so record drops it.
        val base = File(tmp, "base-removed").also { case("removed").resolve("baseline").copyRecursively(it) }
        Baseline.record(output("removed"), base, ci = true, log = Log(false))
        assertEquals(setOf("en-US/Pixel 9-Home"), (baselineJson(base)["images"] as Map<*, *>).keys)
        assertFalse(File(base, "en-US/Pixel 9-Legacy.png").exists())
        // A split run: the iOS job's record keeps the Android images.
        val shared = File(tmp, "base-split").also { case("split-run-ios").resolve("baseline").copyRecursively(it) }
        Baseline.record(output("split-run-ios"), shared, ci = true, log = Log(false))
        val images = (baselineJson(shared)["images"] as Map<*, *>).keys
        assertEquals(setOf("en-US/Pixel 9-Home", "en-US/Pixel 9-Settings", "en-US/iPhone 17 Pro-Home"), images)
        assertTrue(File(shared, "en-US/Pixel 9-Settings.png").isFile)
        assertFalse(File(shared, "en-US/iPhone 17 Pro-Settings.png").exists())
    }

    @Test fun recordWithRenderErrorsKeepsTheirImagesAndExits2() {
        val base = File(tmp, "base-error").also { case("render-error").resolve("baseline").copyRecursively(it) }
        assertEquals(2, Baseline.record(output("render-error"), base, ci = true, log = Log(false)))
        assertTrue(File(base, "en-US/Pixel 9-Broken.png").isFile)
        assertTrue("en-US/Pixel 9-Broken" in (baselineJson(base)["images"] as Map<*, *>))
    }

    @Test fun configHashIsTheNormalizedConfigs() {
        val c = config(case("tolerance"))
        val normalized = """{"screens":[{"preview":"clock*","tolerance":{"max_channel_delta":2,"pixels":0}}],"tolerance":{"max_channel_delta":1,"pixels":5}}"""
        assertEquals(CanonicalJson.sha256(normalized), c.hash())
    }

    @Test fun deviceModeDefaultsToChannelDeltaOne() {
        val c = CompareConfig(null, emptyList())
        assertEquals(Tolerance(0, 1), c.forShot("Glass", "device", 3.0).first)
        assertEquals(Tolerance(0, 0), c.forShot("Glass", "no-boot", 3.0).first)
        assertEquals(Tolerance(2, 0), CompareConfig(Tolerance(2, 0), emptyList()).forShot("Glass", "device", 3.0).first)
    }

    @Test fun globIsAsciiCaseInsensitive() {
        assertTrue(Baseline.glob("clock*", "Clock Large"))
        assertTrue(Baseline.glob("*a*b*", "xAyBz"))
        assertFalse(Baseline.glob("über", "ÜBER"))
        assertFalse(Baseline.glob("ab*ba", "aba"))
        assertTrue(Baseline.glob("Feed", "feed"))
    }

    /** A run's output: the given ids as copies of one fixture PNG, and its report with [errors]. */
    private fun runOutput(dir: File, ids: List<String>, errors: List<Map<String, Any?>>) {
        val png = case("unchanged").resolve("output/en-US/iPhone 17 Pro-Über.png")
        val shots = ids.map { id ->
            png.copyTo(File(dir, "$id.png"), overwrite = true)
            mapOf("id" to id, "file" to "$id.png", "platform" to "android", "module" to ":app", "device" to "Pixel 9", "language" to "en-US",
                "appearance" to "light", "preview" to id.substringAfter("Pixel 9-").substringBefore('_'), "fontScale" to 1.0, "scale" to 2.625)
        }
        val scope = ScopeBuilder(emptyList()).apply { shots.forEach(::shot); previews += "Cards" }.toJson()
        RunReport.write(dir, "android", 1.0, shots, errors, scope, mapOf("android" to Fingerprints.android(emptyList(), null, "linux-x64")))
    }

    @Test fun providerPreviewThatFailedWithoutIndexRemovesNothing() {
        val base = File(tmp, "base-provider")
        val first = File(tmp, "first")
        runOutput(first, listOf("en-US/Pixel 9-Cards_1", "en-US/Pixel 9-Cards_2", "en-US/Pixel 9-Home"), emptyList())
        assertEquals(0, Baseline.record(first, base, ci = true, log = Log(false)))

        // The provider couldn't be counted: the worker reports the preview's base file, without _N.
        val out = File(tmp, "second").apply { mkdirs() }
        val runner = Runner(Options.parse(listOf("--project-dir", tmp.path, "--output", out.path)), Log(false))
        val module = Module(mapOf("module" to ":app", "layoutlibRuntime" to "/r.jar", "layoutlibResources" to "/s.jar"))
        val cards = Preview(composable = "com.example.UiKt.Cards", function = "Cards", name = "Cards", provider = "com.example.CardsProvider")
        val device = Devices.resolve(listOf("Pixel 9")).first()
        val shot = Shot(module, cards, device, "en-US", false, 1.0, "shrink", false, 0, File(out, "en-US/Pixel 9-Cards.png"))
        val errors = runner.errors(listOf(shot to Result(File(out, "en-US/Pixel 9-Cards.png").path, false, error = "NoSuchMethodException: CardsProvider")))
        assertEquals(listOf(mapOf<String, Any?>("message" to "Cards · Pixel 9 · en-US: NoSuchMethodException: CardsProvider")), errors)
        // A failed value with its index keeps its id.
        val indexed = runner.errors(listOf(shot to Result(File(out, "en-US/Pixel 9-Cards_2.png").path, false, error = "boom")))
        assertEquals(listOf(mapOf<String, Any?>("id" to "en-US/Pixel 9-Cards_2", "message" to "boom")), indexed)

        runOutput(out, listOf("en-US/Pixel 9-Home"), errors)
        val v = Baseline.evaluate(out, base, File(tmp, "provider-report"), CompareConfig(null, emptyList()), env)
        assertEquals(0, v.counts["removed"])
        assertEquals(2, v.exitCode)
        assertEquals(emptyList<Any?>(), (Json.parse(File(tmp, "provider-report/manifest.json").readText()) as Map<*, *>).let { (it["ids"] as Map<*, *>)["removed"] })
        assertEquals(2, Baseline.record(out, base, ci = true, log = Log(false)))
        assertTrue(File(base, "en-US/Pixel 9-Cards_1.png").isFile)
        assertTrue(File(base, "en-US/Pixel 9-Cards_2.png").isFile)
        assertEquals(setOf("en-US/Pixel 9-Cards_1", "en-US/Pixel 9-Cards_2", "en-US/Pixel 9-Home"), (baselineJson(base)["images"] as Map<*, *>).keys)
    }

    @Test fun flutterIosRendererErrorsAreIdLess() {
        val withErrors = Ios.Rendered(1, emptyList(), mapOf("errors" to listOf("Home · iPhone 17 Pro: timed out", mapOf("id" to "en-US/iPhone 17 Pro-Feed @1.3x", "message" to "crashed"))))
        assertEquals(
            listOf(mapOf<String, Any?>("message" to "iOS: Home · iPhone 17 Pro: timed out"), mapOf<String, Any?>("message" to "iOS: en-US/iPhone 17 Pro-Feed @1.3x: crashed")),
            FlutterIos.errorsOf(withErrors),
        )
        assertEquals(listOf(mapOf<String, Any?>("message" to "iOS: the iOS renderer exited with status 3")), FlutterIos.errorsOf(Ios.Rendered(3, emptyList(), mapOf("errors" to emptyList<Any>()))))
        assertEquals(emptyList<Map<String, Any?>>(), FlutterIos.errorsOf(Ios.Rendered(0, emptyList(), emptyMap<String, Any?>())))
    }

    @Test fun multiRuntimeMismatchIsOnlyForTheChangedRuntime() {
        val v = verify(case("multi-runtime"))
        assertEquals(listOf("ios runtime: baseline 23F77, this run 23F80"), v.mismatches)
        // Recording that run gives each image its own runtime's build.
        val base = File(tmp, "base-multi")
        Baseline.record(output("multi-runtime"), base, ci = true, log = Log(false))
        val json = baselineJson(base)
        val fps = json["fingerprints"] as Map<*, *>
        val images = json["images"] as Map<*, *>
        fun build(id: String) = (fps[(images[id] as Map<*, *>)["fingerprint"]] as Map<*, *>)["runtime"]
        assertEquals("23A343", build("en-US/iPhone 17 Pro-Home-iOS26.0"))
        assertEquals("23F80", build("en-US/iPhone 17 Pro-Settings-iOS26.5"))
    }

    @Test fun imageFingerprintTakesTheImagesRuntime() {
        val run = mapOf("platform" to "ios", "mode" to "no-boot", "runtimes" to mapOf("26.0" to "23A343", "watchOS 11.0" to "22R349"))
        assertEquals(mapOf("platform" to "ios", "mode" to "no-boot", "runtime" to "22R349"), Fingerprints.forImage(run, mapOf("runtime" to "watchOS 11.0")))
        assertEquals(mapOf("platform" to "ios", "mode" to "no-boot"), Fingerprints.forImage(run, mapOf("runtime" to "18.0")))
        val android = mapOf("platform" to "android", "jdk" to "21")
        assertEquals(android, Fingerprints.forImage(android, mapOf("runtime" to "26.0")))
    }
}
