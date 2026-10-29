package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `init` on trimmed copies of public projects (test resources `migration/<project>`, see each SOURCE.md): the
 * swiftshot.json, the report and every snapshot test with what it renders and on which device must match the
 * hand-checked expected files. On a mismatch the actual files are written to build/migration-fixtures/<project>.
 */
class MigrationFixturesTest {
    private val tmp: File = Files.createTempDirectory("swiftshot-fixtures").toFile()
    private val fixtures = File(javaClass.getResource("/migration")!!.toURI())
    private val expectedFiles = setOf("SOURCE.md", "expected-swiftshot.json", "expected-report.txt", "expected-tests.txt")

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    @Test fun nowInAndroid() = check("nowinandroid")
    @Test fun flavorshub() = check("flavorshub")
    @Test fun androidPlayground() = check("android-playground")
    @Test fun cascade() = check("cascade")

    @Test fun everyFixtureIsChecked() {
        assertEquals(setOf("nowinandroid", "flavorshub", "android-playground", "cascade"), fixtures.listFiles()!!.filter { it.isDirectory }.map { it.name }.toSet())
    }

    private fun check(name: String) {
        val src = File(fixtures, name)
        val project = File(tmp, name)
        src.walkTopDown().filter { it.isFile && !(it.parentFile == src && it.name in expectedFiles) }.forEach { f ->
            f.copyTo(File(project, f.relativeTo(src).path))
        }
        val before = files(project)
        Init.run(Options.parse(listOf("--project-dir", project.path, "init")), force = false, log = Log(false))
        assertEquals(before + setOf("swiftshot.json", "swiftshot-migration.md"), files(project), "init writes only its two files")

        val actual = mapOf(
            "expected-swiftshot.json" to File(project, "swiftshot.json").readText(),
            "expected-report.txt" to File(project, "swiftshot-migration.md").readText(),
            "expected-tests.txt" to tests(project),
        )
        val wrong = actual.filter { (file, text) -> File(src, file).readText() != text }
        if (wrong.isNotEmpty()) {
            val out = File("build/migration-fixtures/$name").apply { deleteRecursively(); mkdirs() }
            for ((file, text) in actual) File(out, file).writeText(text)
        }
        for ((file, text) in actual) assertEquals(File(src, file).readText(), text, "$name/$file (actual in build/migration-fixtures/$name)")
        assertTrue(actual.getValue("expected-tests.txt").isNotBlank())
    }

    private fun files(dir: File) = dir.walkTopDown().filter { it.isFile }.map { it.relativeTo(dir).path }.toSet()

    /** Every snapshot test the scanner reads, one per line: where, what it renders, the device and the settings. */
    private fun tests(project: File): String {
        val modules = SnapshotModules.find(project)
        val all = SnapshotModules.projects(project)
        val previews = modules.flatMap { SnapshotTests.previews(it, all) }.distinct()
        return SnapshotTests.scan(modules, previews, all).joinToString("") { t ->
            val target = when (val g = t.target) {
                is Target.Previews -> "previews ${g.fqns.joinToString(", ")}"
                is Target.AllPreviews -> "all previews" + (if (g.packages.isEmpty()) "" else " in ${g.packages.joinToString(", ")}") + (if (g.includePrivate) "" else ", public only")
                is Target.Uncovered -> "not covered: ${g.call}"
            }
            val s = t.settings
            val settings = listOfNotNull(s.locale?.let { "locale $it" }, s.night?.let { if (it) "night" else "not night" }, s.fontScale?.let { "font scale $it" },
                s.fromPreview.takeIf { it.isNotEmpty() }?.let { "from @Preview: ${it.sorted().joinToString(", ")}" })
            "${t.file.relativeTo(project).path}:${t.line}  ${t.module} ${t.sourceSet} ${t.tool.name.lowercase()}\n" +
                "  renders: $target\n  device: ${device(t.device)}\n" + (if (settings.isEmpty()) "" else "  settings: ${settings.joinToString("; ")}\n")
        }
    }

    private fun device(d: DeviceSource?): String = when (d) {
        null -> "none"
        is DeviceSource.Read -> "${d.label} = ${screen(d.screen)} → ${TestDevices.deviceName(d.screen, d.label)}"
        is DeviceSource.ToolDefault -> "tool default = ${screen(d.screen)} → ${TestDevices.deviceName(d.screen)}"
        is DeviceSource.FromPreview -> "each preview's own; without one: ${device(d.fallback)}"
        is DeviceSource.Unresolved -> "unresolved: ${d.expression}"
    }

    private fun screen(s: Screen) = "${s.widthPx}x${s.heightPx}px ${s.densityDpi}dpi" + (if (s.round) " round" else "") + (if (s.landscape) " landscape" else "")
}
