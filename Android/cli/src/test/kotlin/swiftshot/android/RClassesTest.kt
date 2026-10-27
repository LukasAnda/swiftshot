package swiftshot.android

import java.io.File
import java.lang.reflect.Modifier
import java.net.URLClassLoader
import java.nio.file.Files
import java.util.zip.ZipFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RClassesTest {
    private val dir: File = Files.createTempDirectory("swiftshot-rclasses").toFile()
    private val loaders = mutableListOf<URLClassLoader>()

    @AfterTest fun cleanUp() {
        loaders.forEach { it.close() }
        dir.deleteRecursively()
    }

    private fun symbols(name: String, text: String) = File(dir, name).apply { writeText(text.trimIndent() + "\n") }

    /** Writes the R jar for [files] and loads it in a class loader of its own. */
    private fun load(vararg files: File, framework: Map<String, Int> = emptyMap()): ClassLoader {
        val jar = File(dir, "r.jar")
        RClasses.write(files.map(RClasses::parse), framework, jar)
        return URLClassLoader(arrayOf(jar.toURI().toURL()), null).also { loaders += it }
    }

    private fun ClassLoader.int(cls: String, field: String) = loadClass(cls).getField(field).getInt(null)
    private fun ClassLoader.ints(cls: String, field: String) = loadClass(cls).getField(field).get(null) as IntArray

    private val app = """
        com.example.app
        string app_name
        string welcome
        drawable ic_logo
        attr title
        id content
        styleable Toolbar android_text title subtitle
        styleable Empty
    """

    @Test fun parse() {
        val s = RClasses.parse(symbols("app.txt", app))
        assertEquals("com.example.app", s.pkg)
        assertEquals(
            listOf("string" to "app_name", "string" to "welcome", "drawable" to "ic_logo", "attr" to "title", "id" to "content"),
            s.entries,
        )
        assertEquals(mapOf("Toolbar" to listOf("android_text", "title", "subtitle"), "Empty" to emptyList()), s.styleables)
        assertEquals(listOf("Toolbar", "Empty"), s.styleables.keys.toList()) // in file order
    }

    @Test fun parseSkipsBlankAndShortLines() {
        val s = RClasses.parse(symbols("odd.txt", "  com.example.lib  \n\nstring a\nlonely\n   \n  color primary  \n"))
        assertEquals("com.example.lib", s.pkg)
        assertEquals(listOf("string" to "a", "color" to "primary"), s.entries)
        assertEquals(emptyMap(), s.styleables)
    }

    @Test fun packageOnly() {
        val s = RClasses.parse(symbols("empty.txt", "com.example.empty"))
        assertEquals("com.example.empty", s.pkg)
        assertEquals(emptyList(), s.entries)
    }

    @Test fun jarHasAClassPerTypeUsed() {
        load(symbols("app.txt", app))
        val names = ZipFile(File(dir, "r.jar")).use { z -> z.entries().asSequence().map { it.name }.toSet() }
        assertEquals(
            setOf("string", "drawable", "attr", "id", "styleable").map { "com/example/app/R\$$it.class" }.toSet() + "com/example/app/R.class",
            names,
        )
    }

    @Test fun fieldsAreLibraryStyle() {
        val r = load(symbols("app.txt", app))
        val string = r.loadClass("com.example.app.R\$string")
        assertEquals(setOf("app_name", "welcome"), string.declaredFields.map { it.name }.toSet())
        for (f in string.declaredFields) {
            assertEquals(Int::class.javaPrimitiveType, f.type)
            assertTrue(Modifier.isPublic(f.modifiers) && Modifier.isStatic(f.modifiers))
            assertTrue(!Modifier.isFinal(f.modifiers), "${f.name} is final") // as in a library's R: not inlined
        }
        // Inner classes are declared on R, as javac would.
        val outer = r.loadClass("com.example.app.R")
        assertEquals(setOf("string", "drawable", "attr", "id", "styleable"), outer.declaredClasses.map { it.simpleName }.toSet())
    }

    @Test fun idsArePerTypeAndUnique() {
        val r = load(symbols("app.txt", app))
        val appName = r.int("com.example.app.R\$string", "app_name")
        val welcome = r.int("com.example.app.R\$string", "welcome")
        val logo = r.int("com.example.app.R\$drawable", "ic_logo")
        val content = r.int("com.example.app.R\$id", "content")
        val title = r.int("com.example.app.R\$attr", "title")
        // 0x7f, then the type, then a counter within the type.
        for (id in listOf(appName, welcome, logo, content, title)) assertEquals(0x7f, id ushr 24)
        assertEquals(appName ushr 16, welcome ushr 16)
        assertNotEquals(appName, welcome)
        assertEquals(setOf(appName ushr 16, logo ushr 16, content ushr 16, title ushr 16).size, 4)
        assertEquals(0x7f140001, appName) // string is type 20 of the list
        assertEquals(0x7f140002, welcome)
        assertEquals(0x7f040001, title) // attr is type 4
    }

    @Test fun sameNameSameIdAcrossPackages() {
        val lib = symbols(
            "lib.txt",
            """
            com.example.lib
            string welcome
            string lib_only
            attr subtitle
            styleable Card title
            """,
        )
        val r = load(symbols("app.txt", app), lib)
        assertEquals(r.int("com.example.app.R\$string", "welcome"), r.int("com.example.lib.R\$string", "welcome"))
        assertEquals(r.int("com.example.app.R\$attr", "title"), r.ints("com.example.lib.R\$styleable", "Card")[0])
        // Each package's class only has its own names.
        assertFailsWith<NoSuchFieldException> { r.loadClass("com.example.lib.R\$string").getField("app_name") }
        assertFailsWith<NoSuchFieldException> { r.loadClass("com.example.app.R\$string").getField("lib_only") }
        assertNotEquals(r.int("com.example.app.R\$string", "app_name"), r.int("com.example.lib.R\$string", "lib_only"))
    }

    @Test fun samePackageIsMerged() {
        val more = symbols("more.txt", "com.example.app\nstring extra\nstring welcome\nstyleable Badge count")
        val r = load(symbols("app.txt", app), more)
        val string = r.loadClass("com.example.app.R\$string")
        assertEquals(setOf("app_name", "welcome", "extra"), string.declaredFields.map { it.name }.toSet())
        assertEquals(1, ZipFile(File(dir, "r.jar")).use { z -> z.entries().asSequence().count { it.name == "com/example/app/R\$string.class" } })
        val styleable = r.loadClass("com.example.app.R\$styleable")
        assertTrue(styleable.declaredFields.any { it.name == "Badge" } && styleable.declaredFields.any { it.name == "Toolbar" })
    }

    @Test fun styleables() {
        val r = load(symbols("app.txt", app), framework = mapOf("text" to 0x0101014f))
        val cls = "com.example.app.R\$styleable"
        val toolbar = r.ints(cls, "Toolbar")
        // android_ attributes get the framework's id; the others the app's attr ids (made up for
        // attributes only a styleable names).
        assertEquals(3, toolbar.size)
        assertEquals(0x0101014f, toolbar[0])
        assertEquals(r.int("com.example.app.R\$attr", "title"), toolbar[1])
        assertEquals(0x7f04, toolbar[2] ushr 16)
        assertNotEquals(toolbar[1], toolbar[2])
        assertContentEquals(IntArray(0), r.ints(cls, "Empty"))
        assertEquals(0, r.int(cls, "Toolbar_android_text"))
        assertEquals(1, r.int(cls, "Toolbar_title"))
        assertEquals(2, r.int(cls, "Toolbar_subtitle"))
        // A styleable's child attribute is no field of R.attr unless it is declared there.
        assertFailsWith<NoSuchFieldException> { r.loadClass("com.example.app.R\$attr").getField("subtitle") }
    }

    @Test fun unknownFrameworkAttrIsZero() {
        val r = load(symbols("app.txt", app))
        assertEquals(0, r.ints("com.example.app.R\$styleable", "Toolbar")[0])
    }

    @Test fun noStyleablesNoStyleableClass() {
        val r = load(symbols("plain.txt", "com.example.plain\ncolor primary"))
        assertEquals(0x7f, r.int("com.example.plain.R\$color", "primary") ushr 24)
        assertFailsWith<ClassNotFoundException> { r.loadClass("com.example.plain.R\$styleable") }
    }

    @Test fun manyFieldsSplitStaticInit() {
        // More than one 500-field chunk, and enough that a single <clinit> would pass 64 KB.
        val text = "com.example.big\n" + (0 until 12000).joinToString("\n") { "string s$it" }
        val r = load(symbols("big.txt", text))
        val first = r.int("com.example.big.R\$string", "s0")
        assertEquals(first + 11999, r.int("com.example.big.R\$string", "s11999"))
    }

    @Test fun noJarForDesktopOrApplication() {
        assertNull(RClasses.jar(Module(mapOf("module" to ":shared", "platform" to "desktop"))))
        assertNull(RClasses.jar(Module(mapOf("module" to ":app", "application" to true))))
        // No symbol files: nothing to write.
        assertNull(RClasses.jar(Module(mapOf("module" to ":lib", "symbolFiles" to listOf(File(dir, "missing.txt").path)))))
    }
}
