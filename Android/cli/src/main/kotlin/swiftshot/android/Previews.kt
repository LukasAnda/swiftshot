package swiftshot.android

import org.objectweb.asm.AnnotationVisitor
import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type
import java.io.File
import java.util.zip.ZipFile

/** One `@Preview` of a composable, with every parameter Android Studio reads. */
data class Preview(
    /** e.g. `com.example.WelcomeKt.WelcomePreview` */
    val composable: String,
    val function: String,
    val name: String,
    val group: String = "",
    val device: String = "",
    val widthDp: Int = -1,
    val heightDp: Int = -1,
    val locale: String = "",
    val fontScale: Double = 1.0,
    val showSystemUi: Boolean = false,
    val showBackground: Boolean = false,
    val backgroundColor: Long = 0,
    val uiMode: Int = 0,
    val apiLevel: Int = -1,
    val provider: String? = null,
    val providerLimit: Int = Int.MAX_VALUE,
    /** Private in source: callable only from its own file (iOS wrappers make it internal). */
    val isPrivate: Boolean = false,
    /** The Kotlin file it is declared in (the class file's SourceFile), e.g. `HabitsApp.kt`. */
    val sourceFile: String? = null,
) {
    val night: Boolean? get() = when (uiMode and 0x30) { 0x20 -> true; 0x10 -> false; else -> null }
    val isWatchDevice get() = device.contains("wearos") || device.contains("isRound=true")
}

/**
 * Finds previews by reading class files: `@Preview` has binary retention, so reflection can't see
 * it. Handles repeated previews (`Preview.Container`), multipreview annotations from the project
 * or any library (`@PreviewLightDark`, `@PreviewScreenSizes`, `@WearPreviewDevices`…, nested to
 * any depth) and `@PreviewParameter`.
 */
class PreviewScanner(private val classpath: List<File>) {
    private val previewDesc = "Landroidx/compose/ui/tooling/preview/Preview;"
    private val containerDesc = "Landroidx/compose/ui/tooling/preview/Preview\$Container;"
    private val parameterDesc = "Landroidx/compose/ui/tooling/preview/PreviewParameter;"

    /** Annotation descriptor → the previews it stands for (empty if it isn't a multipreview). */
    private val multipreviews = HashMap<String, List<Map<String, Any?>>>()
    private val jarIndex: Map<String, File> by lazy {
        val index = HashMap<String, File>()
        for (f in classpath) if (f.isFile && f.name.endsWith(".jar")) runCatching {
            ZipFile(f).use { z -> z.entries().asSequence().forEach { e -> if (e.name.endsWith(".class")) index.putIfAbsent(e.name, f) } }
        }
        index
    }
    private val classDirs = classpath.filter { it.isDirectory }

    fun scan(roots: List<File>): List<Preview> {
        val result = mutableListOf<Preview>()
        for (root in roots) forEachClass(root) { bytes -> result += previewsIn(bytes) }
        return result.sortedWith(compareBy({ it.composable }, { it.name }))
    }

    private fun forEachClass(root: File, block: (ByteArray) -> Unit) {
        when {
            root.isDirectory -> root.walkTopDown().filter { it.isFile && it.name.endsWith(".class") }.forEach { block(it.readBytes()) }
            root.isFile && root.name.endsWith(".jar") -> ZipFile(root).use { z ->
                z.entries().asSequence().filter { it.name.endsWith(".class") && !it.name.startsWith("META-INF") }
                    .forEach { e -> block(z.getInputStream(e).readBytes()) }
            }
        }
    }

    private class Ann(val desc: String) { val values = LinkedHashMap<String, Any?>() }

    private fun collector(ann: Ann): AnnotationVisitor = object : AnnotationVisitor(Opcodes.ASM9) {
        override fun visit(name: String?, value: Any?) { ann.values[name ?: "value"] = value }
        override fun visitEnum(name: String?, descriptor: String?, value: String?) { ann.values[name ?: "value"] = value }
        override fun visitAnnotation(name: String?, descriptor: String): AnnotationVisitor {
            val nested = Ann(descriptor); ann.values[name ?: "value"] = nested; return collector(nested)
        }
        override fun visitArray(name: String?): AnnotationVisitor {
            val list = mutableListOf<Any?>(); ann.values[name ?: "value"] = list
            return object : AnnotationVisitor(Opcodes.ASM9) {
                override fun visit(n: String?, value: Any?) { list += value }
                override fun visitEnum(n: String?, d: String?, value: String?) { list += value }
                override fun visitAnnotation(n: String?, descriptor: String): AnnotationVisitor { val a = Ann(descriptor); list += a; return collector(a) }
            }
        }
    }

    private fun previewsIn(bytes: ByteArray): List<Preview> {
        val reader = ClassReader(bytes)
        if (reader.access and Opcodes.ACC_ANNOTATION != 0) return emptyList()
        val owner = reader.className.replace('/', '.')
        val found = mutableListOf<Preview>()
        var source: String? = null
        reader.accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visitSource(file: String?, debug: String?) { source = file }
            override fun visitMethod(access: Int, name: String, descriptor: String, signature: String?, exceptions: Array<out String>?): MethodVisitor? {
                // Composables take a Composer; synthetic and bridge methods are never previews.
                if (access and (Opcodes.ACC_SYNTHETIC or Opcodes.ACC_BRIDGE) != 0) return null
                if (!descriptor.contains("Landroidx/compose/runtime/Composer;")) return null
                val anns = mutableListOf<Ann>()
                var provider: Ann? = null
                return object : MethodVisitor(Opcodes.ASM9) {
                    override fun visitAnnotation(desc: String, visible: Boolean): AnnotationVisitor = Ann(desc).also { anns += it }.let(::collector)
                    override fun visitParameterAnnotation(parameter: Int, desc: String, visible: Boolean): AnnotationVisitor? {
                        if (desc != parameterDesc) return null
                        return Ann(desc).also { provider = it }.let(::collector)
                    }
                    override fun visitEnd() {
                        val entries = anns.flatMap { expand(it, null) }
                        if (entries.isEmpty()) return
                        val function = name
                        val p = provider
                        for ((values, via) in entries) {
                            val explicit = values["name"] as String? ?: ""
                            val display = when {
                                via != null && explicit.isNotEmpty() -> "$function - $explicit"
                                explicit.isNotEmpty() -> explicit
                                else -> function
                            }
                            found += Preview(
                                composable = "$owner.$function",
                                function = function,
                                name = display,
                                group = values["group"] as String? ?: "",
                                device = values["device"] as String? ?: "",
                                widthDp = (values["widthDp"] as Int?) ?: -1,
                                heightDp = (values["heightDp"] as Int?) ?: -1,
                                locale = values["locale"] as String? ?: "",
                                fontScale = (values["fontScale"] as Float?)?.let { Math.round(it * 100) / 100.0 } ?: 1.0,
                                showSystemUi = values["showSystemUi"] as Boolean? ?: false,
                                showBackground = values["showBackground"] as Boolean? ?: false,
                                backgroundColor = (values["backgroundColor"] as Long?) ?: 0L,
                                uiMode = (values["uiMode"] as Int?) ?: 0,
                                apiLevel = (values["apiLevel"] as Int?) ?: -1,
                                provider = (p?.values?.get("provider") as Type?)?.className,
                                providerLimit = (p?.values?.get("limit") as Int?) ?: Int.MAX_VALUE,
                                isPrivate = access and Opcodes.ACC_PRIVATE != 0,
                                sourceFile = source,
                            )
                        }
                    }
                }
            }
        }, ClassReader.SKIP_CODE or ClassReader.SKIP_FRAMES)
        return found.distinct()
    }

    /** The preview parameter sets an annotation stands for, with the multipreview it came through. */
    private fun expand(ann: Ann, via: String?): List<Pair<Map<String, Any?>, String?>> = when (ann.desc) {
        previewDesc -> listOf(ann.values to via)
        containerDesc -> (ann.values["value"] as List<*>).flatMap { expand(it as Ann, via) }
        else -> multipreview(ann.desc).map { it to (via ?: ann.desc) }
    }

    private fun multipreview(desc: String, seen: Set<String> = emptySet()): List<Map<String, Any?>> {
        multipreviews[desc]?.let { return it }
        if (desc in seen || desc.startsWith("Lkotlin/") || desc.startsWith("Ljava/")) return emptyList()
        val bytes = classBytes(Type.getType(desc).internalName + ".class") ?: return emptyList<Map<String, Any?>>().also { multipreviews[desc] = it }
        val anns = mutableListOf<Ann>()
        ClassReader(bytes).accept(object : ClassVisitor(Opcodes.ASM9) {
            override fun visitAnnotation(d: String, visible: Boolean): AnnotationVisitor = Ann(d).also { anns += it }.let(::collector)
        }, ClassReader.SKIP_CODE or ClassReader.SKIP_DEBUG or ClassReader.SKIP_FRAMES)
        val result = anns.flatMap { a ->
            when (a.desc) {
                previewDesc -> listOf(a.values)
                containerDesc -> (a.values["value"] as List<*>).map { (it as Ann).values }
                else -> multipreview(a.desc, seen + desc)
            }
        }
        multipreviews[desc] = result
        return result
    }

    private fun classBytes(entry: String): ByteArray? {
        for (dir in classDirs) File(dir, entry).takeIf { it.isFile }?.let { return it.readBytes() }
        val jar = jarIndex[entry] ?: return null
        return ZipFile(jar).use { z -> z.getEntry(entry)?.let { z.getInputStream(it).readBytes() } }
    }
}
