package swiftshot.android

import org.objectweb.asm.AnnotationVisitor
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes.ACC_ABSTRACT
import org.objectweb.asm.Opcodes.ACC_ANNOTATION
import org.objectweb.asm.Opcodes.ACC_BRIDGE
import org.objectweb.asm.Opcodes.ACC_FINAL
import org.objectweb.asm.Opcodes.ACC_INTERFACE
import org.objectweb.asm.Opcodes.ACC_PRIVATE
import org.objectweb.asm.Opcodes.ACC_PUBLIC
import org.objectweb.asm.Opcodes.ACC_STATIC
import org.objectweb.asm.Opcodes.ACC_SUPER
import org.objectweb.asm.Opcodes.ACC_SYNTHETIC
import org.objectweb.asm.Opcodes.RETURN
import org.objectweb.asm.Opcodes.V17
import org.objectweb.asm.Type
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Class files shaped like the Kotlin compiler's output for `@Preview` composables, written with
 * ASM: `@Preview` has binary retention, so it is a RuntimeInvisibleAnnotation on a static method
 * of the file class, and a repeated one is wrapped in `Preview.Container`.
 */
class PreviewScannerTest {
    private val tmp: File = Files.createTempDirectory("swiftshot-scan").toFile()

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    // --- class file builders --------------------------------------------------------------------

    /** An annotation: descriptor, values (String, Int, Float, Long, Boolean, Type, [A], List), visibility. */
    data class A(val desc: String, val values: Map<String, Any?> = emptyMap(), val visible: Boolean = false)

    data class M(
        val name: String,
        val desc: String = COMPOSABLE,
        val access: Int = ACC_PUBLIC or ACC_STATIC or ACC_FINAL,
        val anns: List<A> = emptyList(),
        val paramAnns: Map<Int, A> = emptyMap(),
    )

    companion object {
        const val COMPOSABLE = "(Landroidx/compose/runtime/Composer;I)V"
        const val PREVIEW = "Landroidx/compose/ui/tooling/preview/Preview;"
        const val CONTAINER = "Landroidx/compose/ui/tooling/preview/Preview\$Container;"
        const val PARAMETER = "Landroidx/compose/ui/tooling/preview/PreviewParameter;"
        const val COMPOSABLE_ANN = "Landroidx/compose/runtime/Composable;"

        fun preview(vararg values: Pair<String, Any?>) = A(PREVIEW, mapOf(*values))
        fun container(vararg previews: A) = A(CONTAINER, mapOf("value" to previews.toList()))
        fun desc(internal: String) = "L$internal;"
    }

    private fun AnnotationVisitor.fill(values: Map<String, Any?>) {
        for ((k, v) in values) when (v) {
            is A -> visitAnnotation(k, v.desc).fill(v.values)
            is List<*> -> visitArray(k).apply {
                for (item in v) if (item is A) visitAnnotation(null, item.desc).fill(item.values) else visit(null, item)
                visitEnd()
            }
            else -> visit(k, v)
        }
        visitEnd()
    }

    /** A file class (`FooKt`) with composable methods. */
    private fun fileClass(internal: String, vararg methods: M): Pair<String, ByteArray> {
        val cw = ClassWriter(ClassWriter.COMPUTE_MAXS)
        cw.visit(V17, ACC_PUBLIC or ACC_FINAL or ACC_SUPER, internal, null, "java/lang/Object", null)
        for (m in methods) {
            val params = Type.getArgumentTypes(m.desc).size
            val mv = cw.visitMethod(m.access, m.name, m.desc, null, null)
            for (a in m.anns) mv.visitAnnotation(a.desc, a.visible).fill(a.values)
            if (m.paramAnns.isNotEmpty()) {
                val visible = m.paramAnns.values.first().visible
                mv.visitAnnotableParameterCount(params, visible)
                for ((i, a) in m.paramAnns) mv.visitParameterAnnotation(i, a.desc, a.visible).fill(a.values)
            }
            mv.visitCode()
            mv.visitInsn(RETURN)
            mv.visitMaxs(0, 0)
            mv.visitEnd()
        }
        cw.visitEnd()
        return "$internal.class" to cw.toByteArray()
    }

    /** An annotation class (a multipreview when it carries `@Preview`s or other multipreviews). */
    private fun annotationClass(internal: String, vararg anns: A): Pair<String, ByteArray> {
        val cw = ClassWriter(0)
        cw.visit(V17, ACC_PUBLIC or ACC_ANNOTATION or ACC_INTERFACE or ACC_ABSTRACT, internal, null, "java/lang/Object", arrayOf("java/lang/annotation/Annotation"))
        cw.visitAnnotation("Lkotlin/annotation/Retention;", true).fill(emptyMap())
        for (a in anns) cw.visitAnnotation(a.desc, a.visible).fill(a.values)
        cw.visitEnd()
        return "$internal.class" to cw.toByteArray()
    }

    private fun dir(name: String, vararg classes: Pair<String, ByteArray>) = File(tmp, name).apply {
        for ((path, bytes) in classes) File(this, path).apply { parentFile.mkdirs(); writeBytes(bytes) }
    }

    private fun jar(name: String, vararg classes: Pair<String, ByteArray>) = File(tmp, name).apply {
        ZipOutputStream(outputStream()).use { z ->
            z.putNextEntry(ZipEntry("META-INF/MANIFEST.MF")); z.write("Manifest-Version: 1.0\n".toByteArray()); z.closeEntry()
            for ((path, bytes) in classes) { z.putNextEntry(ZipEntry(path)); z.write(bytes); z.closeEntry() }
        }
    }

    // --- fixtures -------------------------------------------------------------------------------

    private val themePreviews = "com/example/ui/ThemePreviews"
    private val allPreviews = "com/example/ui/AllPreviews"
    private val libraryPreviews = "com/lib/preview/WearPreviews"
    private val namesProvider = "com/example/NamesProvider"

    /** The library: a multipreview annotation and a preview of its own that must not be scanned. */
    private fun library() = jar(
        "library.jar",
        annotationClass(
            libraryPreviews,
            container(
                preview("device" to "id:wearos_large_round", "showSystemUi" to true),
                preview("device" to "id:wearos_small_round", "showSystemUi" to true),
            ),
        ),
        fileClass("com/lib/LibraryKt", M("LibraryPreview", anns = listOf(preview()))),
    )

    private fun appClasses() = arrayOf(
        annotationClass(
            themePreviews,
            preview("name" to "Light", "uiMode" to 0x11),
            preview("name" to "Dark", "uiMode" to 0x21),
        ),
        // A multipreview of a multipreview, plus a preview of its own.
        annotationClass(allPreviews, A(desc(themePreviews)), preview("name" to "Tablet", "device" to "id:pixel_tablet")),
        fileClass(
            "com/example/WelcomeKt",
            M(
                "Welcome",
                anns = listOf(
                    A(COMPOSABLE_ANN, visible = true),
                    preview(
                        "name" to "Welcome screen", "group" to "Onboarding", "device" to "id:pixel_9", "locale" to "de",
                        "fontScale" to 1.3f, "uiMode" to 0x21, "showSystemUi" to true, "showBackground" to true,
                        "backgroundColor" to 0xFF112233L, "widthDp" to 400, "heightDp" to 800, "apiLevel" to 34,
                    ),
                ),
            ),
            M("Plain", anns = listOf(preview())),
            M("Repeated", anns = listOf(container(preview("name" to "Small", "fontScale" to 0.85f), preview("name" to "Large", "fontScale" to 2f)))),
            M("LightDark", access = ACC_PRIVATE or ACC_STATIC or ACC_FINAL, anns = listOf(A(desc(themePreviews)))),
            M("Nested", anns = listOf(A(desc(allPreviews)))),
            M("Mixed", anns = listOf(preview("name" to "Own"), A(desc(themePreviews)))),
            M("FromLibrary", anns = listOf(A(desc(libraryPreviews)))),
            M(
                "WithParams", desc = "(Lcom/example/User;Landroidx/compose/runtime/Composer;I)V",
                anns = listOf(preview("name" to "Users")),
                paramAnns = mapOf(0 to A(PARAMETER, mapOf("provider" to Type.getType(desc(namesProvider)), "limit" to 3), visible = true)),
            ),
            M(
                "AllUsers", desc = "(Lcom/example/User;Landroidx/compose/runtime/Composer;I)V",
                anns = listOf(preview()),
                paramAnns = mapOf(0 to A(PARAMETER, mapOf("provider" to Type.getType(desc(namesProvider))), visible = true)),
            ),
            M("Duplicated", anns = listOf(container(preview("name" to "Same"), preview("name" to "Same")))),
            // Not previews: compiler-generated, not composable, or only other annotations.
            M("Welcome\$lambda\$0", access = ACC_PRIVATE or ACC_STATIC or ACC_SYNTHETIC, anns = listOf(preview())),
            M("Bridge", access = ACC_PUBLIC or ACC_BRIDGE, anns = listOf(preview())),
            M("helper", desc = "()V", anns = listOf(preview())),
            M("NotAPreview", anns = listOf(A(COMPOSABLE_ANN, visible = true), A("Lkotlin/Deprecated;", mapOf("message" to "x"), visible = true))),
            M("UnknownAnnotation", anns = listOf(A("Lcom/missing/Gone;"))),
        ),
        fileClass("com/example/settings/SettingsKt", M("Settings", anns = listOf(preview("name" to "Settings")))),
    )

    private fun scanApp(): List<Preview> {
        val app = dir("classes", *appClasses())
        return PreviewScanner(listOf(app, library())).scan(listOf(app))
    }

    private fun List<Preview>.named(name: String) = filter { it.name == name }.also { assertTrue(it.isNotEmpty(), "no preview \"$name\" in ${map { p -> p.name }}") }

    // --- tests ----------------------------------------------------------------------------------

    @Test fun findsEveryPreviewAndNothingElse() {
        val names = scanApp().map { "${it.function}: ${it.name}" }
        assertEquals(
            listOf(
                "AllUsers: AllUsers",
                "Duplicated: Same",
                "FromLibrary: FromLibrary",
                "FromLibrary: FromLibrary",
                "LightDark: LightDark - Dark",
                "LightDark: LightDark - Light",
                "Mixed: Mixed - Dark",
                "Mixed: Mixed - Light",
                "Mixed: Own",
                "Nested: Nested - Dark",
                "Nested: Nested - Light",
                "Nested: Nested - Tablet",
                "Plain: Plain",
                "Repeated: Large",
                "Repeated: Small",
                "Welcome: Welcome screen",
                "WithParams: Users",
                "Settings: Settings",
            ),
            names,
        )
    }

    @Test fun readsEveryParameter() {
        val p = scanApp().named("Welcome screen").single()
        assertEquals("com.example.WelcomeKt.Welcome", p.composable)
        assertEquals("Welcome", p.function)
        assertEquals("Onboarding", p.group)
        assertEquals("id:pixel_9", p.device)
        assertEquals("de", p.locale)
        assertEquals(1.3, p.fontScale)
        assertEquals(0x21, p.uiMode)
        assertEquals(true, p.night)
        assertTrue(p.showSystemUi)
        assertTrue(p.showBackground)
        assertEquals(0xFF112233L, p.backgroundColor)
        assertEquals(400, p.widthDp)
        assertEquals(800, p.heightDp)
        assertEquals(34, p.apiLevel)
        assertNull(p.provider)
        assertEquals(Int.MAX_VALUE, p.providerLimit)
    }

    @Test fun defaultsWhenUnset() {
        val p = scanApp().named("Plain").single()
        assertEquals(Preview("com.example.WelcomeKt.Plain", "Plain", "Plain"), p)
        assertNull(p.night)
        assertTrue(!p.isWatchDevice)
    }

    @Test fun repeatedPreviews() {
        val ps = scanApp().filter { it.function == "Repeated" }
        assertEquals(listOf("Large" to 2.0, "Small" to 0.85), ps.map { it.name to it.fontScale })
    }

    @Test fun identicalPreviewsCollapse() {
        assertEquals(1, scanApp().count { it.function == "Duplicated" })
    }

    @Test fun multipreviewNamesAreQualifiedByFunction() {
        val ps = scanApp()
        val light = ps.named("LightDark - Light").single()
        assertEquals(0x11, light.uiMode)
        assertEquals(false, light.night)
        assertEquals("com.example.WelcomeKt.LightDark", light.composable)
        assertEquals(true, ps.named("LightDark - Dark").single().night)
        // A direct @Preview keeps its own name next to a multipreview's.
        assertEquals(0, ps.named("Own").single().uiMode)
    }

    @Test fun nestedMultipreviews() {
        val ps = scanApp().filter { it.function == "Nested" }
        assertEquals(mapOf("Nested - Dark" to "", "Nested - Light" to "", "Nested - Tablet" to "id:pixel_tablet"), ps.associate { it.name to it.device })
    }

    @Test fun multipreviewFromALibraryJar() {
        val ps = scanApp().filter { it.function == "FromLibrary" }
        assertEquals(setOf("id:wearos_large_round", "id:wearos_small_round"), ps.map { it.device }.toSet())
        assertTrue(ps.all { it.name == "FromLibrary" && it.showSystemUi && it.isWatchDevice })
    }

    @Test fun libraryPreviewsAreNotScanned() {
        assertTrue(scanApp().none { it.composable.startsWith("com.lib") })
    }

    @Test fun previewParameter() {
        val ps = scanApp()
        val users = ps.named("Users").single()
        assertEquals("com.example.NamesProvider", users.provider)
        assertEquals(3, users.providerLimit)
        assertEquals("com.example.WelcomeKt.WithParams", users.composable)
        val all = ps.named("AllUsers").single()
        assertEquals("com.example.NamesProvider", all.provider)
        assertEquals(Int.MAX_VALUE, all.providerLimit)
    }

    @Test fun invisibleParameterAnnotation() {
        val app = dir(
            "invisible",
            fileClass(
                "p/AKt",
                M(
                    "P", desc = "(Ljava/lang/String;Landroidx/compose/runtime/Composer;I)V", anns = listOf(preview()),
                    paramAnns = mapOf(0 to A(PARAMETER, mapOf("provider" to Type.getType("Lp/Strings;"), "limit" to 1))),
                ),
            ),
        )
        val p = PreviewScanner(listOf(app)).scan(listOf(app)).single()
        assertEquals("p.Strings" to 1, p.provider to p.providerLimit)
    }

    @Test fun jarRootsScanLikeDirectories() {
        val classes = appClasses()
        val dirResult = scanApp()
        val appJar = jar("app.jar", *classes)
        assertEquals(dirResult, PreviewScanner(listOf(appJar, library())).scan(listOf(appJar)))
    }

    @Test fun multipreviewMissingFromTheClasspath() {
        val app = dir("classes", *appClasses())
        // Without the library the library multipreview finds nothing; everything else still does.
        val ps = PreviewScanner(listOf(app)).scan(listOf(app))
        assertTrue(ps.none { it.function == "FromLibrary" })
        assertEquals(scanApp().size - 2, ps.size)
    }

    @Test fun cyclicMultipreviewsTerminate() {
        val app = dir(
            "cycle",
            annotationClass("c/A", A(desc("c/B")), preview("name" to "FromA")),
            annotationClass("c/B", A(desc("c/A")), preview("name" to "FromB")),
            fileClass("c/CKt", M("Loop", anns = listOf(A(desc("c/A"))))),
        )
        val names = PreviewScanner(listOf(app)).scan(listOf(app)).map { it.name }.toSet()
        assertEquals(setOf("Loop - FromA", "Loop - FromB"), names)
    }

    @Test fun nothingToFind() {
        val app = dir("empty", fileClass("e/EKt", M("helper", desc = "()V")))
        assertEquals(emptyList(), PreviewScanner(listOf(app)).scan(listOf(app)))
        assertEquals(emptyList(), PreviewScanner(emptyList()).scan(listOf(File(tmp, "missing"))))
    }

    @Test fun watchDetection() {
        assertTrue(Preview("a", "a", "a", device = "id:wearos_small_round").isWatchDevice)
        assertTrue(Preview("a", "a", "a", device = "spec:width=192dp,height=192dp,isRound=true").isWatchDevice)
        assertTrue(!Preview("a", "a", "a", device = "id:pixel_9").isWatchDevice)
    }

    @Test fun nightFromUiMode() {
        assertEquals(true, Preview("a", "a", "a", uiMode = 0x21).night)
        assertEquals(false, Preview("a", "a", "a", uiMode = 0x11).night)
        assertNull(Preview("a", "a", "a", uiMode = 0x01).night)
        assertNull(Preview("a", "a", "a").night)
    }
}
