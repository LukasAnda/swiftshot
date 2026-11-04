package swiftshot.android

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class JsonOutputTest {
    private val tmp: File = Files.createTempDirectory("swiftshot-json").toFile()
    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    @Test fun listKeepsTheOrder() {
        assertEquals("""{"previews":[{"name":"Welcome"},{"name":"Settings"}]}""", CanonicalJson.compact(JsonOutput.list(listOf("Welcome", "Settings"))))
        assertEquals("""{"previews":[]}""", CanonicalJson.compact(JsonOutput.list(emptyList())))
    }

    /** Shared/testdata/json/list.json: the bytes both CLIs print for these previews. */
    @Test fun listMatchesTheSharedFixture() {
        val file = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "json/list.json")
        assertEquals(file.readText(), CanonicalJson.pretty(JsonOutput.list(listOf("Welcome", "Settings \"dark\"", "Zürich"))))
    }

    @Test fun devicesAreNumbersWithSortedKeysAndNoRuntimes() {
        val json = CanonicalJson.compact(JsonOutput.devices(listOf(
            JsonOutput.Row("Pixel 10 Pro", "android", 411.43, 914.29, 2.625),
            JsonOutput.Row("iPhone 17 Pro", "ios", 402.0, 874.0, 3.0))))
        assertEquals("""{"devices":[{"height":914.29,"name":"Pixel 10 Pro","platform":"android","scale":2.625,"width":411.43},""" +
            """{"height":874,"name":"iPhone 17 Pro","platform":"ios","scale":3,"width":402}]}""", json)
    }

    @Test fun everyListedDeviceIsInTheDocument() {
        val rows = JsonOutput.allDevices()
        assertEquals(Devices.all.size + AppleDevices.all.size, rows.size)
        assertEquals(setOf("android", "ios"), rows.map { it.platform }.toSet())
        assertTrue(rows.all { it.width > 0 && it.height > 0 && it.scale > 0 })
        val pixel = rows.first { it.name == "Pixel 10 Pro" }
        assertEquals(Devices.all.first { it.name == "Pixel 10 Pro" }.density / 160.0, pixel.scale)
    }

    @Test fun jsonIsForListDevicesAndVerify() {
        for (c in listOf("list", "devices", "verify")) assertTrue(Options.parse(listOf(c, "--json", "--project-dir", tmp.path)).json, c)
        assertTrue(Options.parse(listOf("--json", "devices")).json)
        for (c in listOf("run", "record", "init")) assertFailsWith<IllegalArgumentException>(c) { Options.parse(listOf(c, "--json", "--project-dir", tmp.path)) }
        assertFailsWith<IllegalArgumentException> { Options.parse(listOf("--json", "--project-dir", tmp.path)) }
        assertEquals(64, cli(listOf("record", "--json", "--project-dir", tmp.path), Log(false)))
        assertEquals(1, cli(listOf("run", "--json", "--project-dir", tmp.path), Log(false)))
    }

    private fun verifyArgs(report: File) = listOf("verify", "--json", "--project-dir", tmp.path, "--output", File(tmp, "out").path,
        "--baseline-directory", File(tmp, "base").path, "--report-directory", report.path)

    /** verify --json: stdout gets the bytes of the result.json the run wrote, and only that. */
    @Test fun verifyWritesItsResultToStdout() {
        val report = File(tmp, "report")
        val stdout = ByteArrayOutputStream()
        val code = cli(verifyArgs(report), Log(false), PrintStream(stdout, true)) { _, _ -> throw RuntimeException("boom") }
        assertEquals(2, code)
        assertContentEquals(File(report, "result.json").readBytes(), stdout.toByteArray())
        assertTrue(String(stdout.toByteArray()).contains("\"status\": \"error\""))
    }

    /** No result.json for the run: stdout stays empty. */
    @Test fun verifyWithoutAResultWritesNothing() {
        val out = File(tmp, "out")
        val stdout = ByteArrayOutputStream()
        val code = cli(verifyArgs(File(tmp, "report")), Log(false), PrintStream(stdout, true)) { _, _ ->
            out.mkdirs(); File(out, "swiftshot-report.json").writeText("""{"screenshots": "x"}""")
        }
        assertEquals(2, code)
        assertEquals(0, stdout.size())
    }

    /** A reader that closed early: the write fails (PrintStream swallows it) and the exit code survives. */
    @Test fun verifyKeepsItsExitCodeWhenStdoutIsClosed() {
        val broken = object : java.io.OutputStream() {
            override fun write(b: Int) = throw java.io.IOException("Broken pipe")
            override fun write(b: ByteArray, off: Int, len: Int) = throw java.io.IOException("Broken pipe")
        }
        val code = cli(verifyArgs(File(tmp, "report")), Log(false), PrintStream(broken, true)) { _, _ -> throw RuntimeException("boom") }
        assertEquals(2, code)
    }

    /** --json anywhere: usage goes to stderr and stdout stays empty. */
    @Test fun usageGoesToStderrWithJson() {
        val out = ByteArrayOutputStream(); val err = ByteArrayOutputStream()
        Options.info("usage text", json = true, out = PrintStream(out, true), err = PrintStream(err, true))
        assertEquals(0, out.size())
        assertTrue(String(err.toByteArray()).startsWith("usage text"))
        Options.info("usage text", json = false, out = PrintStream(out, true), err = PrintStream(err, true))
        assertTrue(String(out.toByteArray()).startsWith("usage text"))
    }
}
