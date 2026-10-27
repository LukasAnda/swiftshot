package swiftshot.android

import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.FieldVisitor
import org.objectweb.asm.Opcodes
import java.io.File
import java.security.MessageDigest
import java.util.jar.JarEntry
import java.util.jar.JarOutputStream
import java.util.zip.ZipFile

/**
 * The R classes of every package a library module uses, as an app's R.jar has them. AGP gives a
 * library only its own compile-time R class, but AndroidX and Compose code read their R ids at run
 * time (view tags, styleables), and layoutlib maps ids back to resources through these classes.
 * Built from the package-aware symbol lists, one id per resource name across all packages (as in
 * a non-namespaced app), framework attributes with their real ids.
 */
object RClasses {
    private val types = listOf("anim", "animator", "array", "attr", "bool", "color", "dimen", "drawable", "font", "fraction",
        "id", "integer", "interpolator", "layout", "menu", "mipmap", "navigation", "plurals", "raw", "string", "style",
        "styleable", "transition", "xml")

    fun jar(m: Module): File? {
        if (m.desktop || m.json["application"] == true) return null
        val files = ((m.json["ownSymbolFiles"] as List<*>? ?: emptyList<Any>()) + (m.json["symbolFiles"] as List<*>? ?: emptyList<Any>()))
            .map { File(it as String) }.filter { it.isFile }
        if (files.isEmpty()) return null
        val digest = MessageDigest.getInstance("SHA-1")
        for (f in files) digest.update(f.readBytes())
        val hash = digest.digest().joinToString("") { "%02x".format(it) }.take(16)
        val out = File(Cache.root, "rclasses/$hash.jar")
        if (out.isFile) return out
        out.parentFile.mkdirs()
        write(files.map(::parse), frameworkAttrs(m.classpath), File(out.path + ".part"))
        File(out.path + ".part").renameTo(out)
        return out
    }

    class Symbols(val pkg: String, val entries: List<Pair<String, String>>, val styleables: Map<String, List<String>>)

    fun parse(file: File): Symbols {
        val lines = file.readLines().filter { it.isNotBlank() }
        val entries = mutableListOf<Pair<String, String>>()
        val styleables = LinkedHashMap<String, List<String>>()
        for (line in lines.drop(1)) {
            val parts = line.trim().split(' ')
            if (parts.size < 2) continue
            if (parts[0] == "styleable") styleables[parts[1]] = parts.drop(2) else entries += parts[0] to parts[1]
        }
        return Symbols(lines.first().trim(), entries, styleables)
    }

    /** android.R.attr from layoutlib's framework classes (compile-time constants). */
    private fun frameworkAttrs(classpath: List<File>): Map<String, Int> {
        val result = HashMap<String, Int>()
        for (jar in classpath.filter { it.name.startsWith("layoutlib-") && it.name.endsWith(".jar") }) {
            ZipFile(jar).use { z ->
                val e = z.getEntry("android/R\$attr.class") ?: return@use
                ClassReader(z.getInputStream(e).readBytes()).accept(object : ClassVisitor(Opcodes.ASM9) {
                    override fun visitField(access: Int, name: String, descriptor: String, signature: String?, value: Any?): FieldVisitor? {
                        if (value is Int) result[name] = value
                        return null
                    }
                }, ClassReader.SKIP_CODE)
            }
            if (result.isNotEmpty()) break
        }
        return result
    }

    private fun write(all: List<Symbols>, framework: Map<String, Int>, out: File) {
        // One id per (type, name), shared by every package's R class.
        val ids = HashMap<String, Int>()
        val counters = IntArray(types.size)
        fun id(type: String, name: String): Int = ids.getOrPut("$type/$name") {
            val t = types.indexOf(type).let { if (it < 0) types.size - 1 else it }
            0x7f000000 or ((t + 1) shl 16) or (++counters[t])
        }
        for (s in all) {
            for ((type, name) in s.entries) if (type != "styleable") id(type, name)
            for (children in s.styleables.values) for (c in children) if (!c.startsWith("android_")) id("attr", c)
        }
        JarOutputStream(out.outputStream()).use { jar ->
            for (s in all.distinctBy { it.pkg }) {
                val merged = all.filter { it.pkg == s.pkg }
                val base = s.pkg.replace('.', '/') + "/R"
                val byType = LinkedHashMap<String, MutableSet<String>>()
                for (x in merged) for ((type, name) in x.entries) if (type != "styleable") byType.getOrPut(type) { linkedSetOf() } += name
                val styleables = LinkedHashMap<String, List<String>>()
                for (x in merged) styleables.putAll(x.styleables)
                val inner = (byType.keys + if (styleables.isNotEmpty()) listOf("styleable") else emptyList()).distinct()
                jar.putNextEntry(JarEntry("$base.class")); jar.write(outer(base, inner)); jar.closeEntry()
                for (type in inner) {
                    val fields = if (type == "styleable") emptyMap() else byType[type]!!.associateWith { id(type, it) }
                    val arrays = if (type == "styleable") styleables.mapValues { (_, c) -> c.map { a -> if (a.startsWith("android_")) framework[a.removePrefix("android_")] ?: 0 else id("attr", a) } } else emptyMap()
                    val indexes = if (type == "styleable") styleables.flatMap { (n, c) -> c.mapIndexed { i, a -> "${n}_$a" to i } }.toMap() else emptyMap()
                    jar.putNextEntry(JarEntry("$base\$$type.class")); jar.write(innerClass(base, type, fields + indexes, arrays)); jar.closeEntry()
                }
            }
        }
    }

    private fun outer(name: String, inner: List<String>): ByteArray {
        val cw = ClassWriter(0)
        cw.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC or Opcodes.ACC_FINAL or Opcodes.ACC_SUPER, name, null, "java/lang/Object", null)
        for (t in inner) cw.visitInnerClass("$name\$$t", name, t, Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC or Opcodes.ACC_FINAL)
        cw.visitEnd()
        return cw.toByteArray()
    }

    /** Non-final static ints (as in a library's R), set in <clinit>; int[] for styleables. */
    private fun innerClass(outer: String, type: String, ints: Map<String, Int>, arrays: Map<String, List<Int>>): ByteArray {
        val name = "$outer\$$type"
        val cw = ClassWriter(ClassWriter.COMPUTE_MAXS)
        cw.visit(Opcodes.V1_8, Opcodes.ACC_PUBLIC or Opcodes.ACC_FINAL or Opcodes.ACC_SUPER, name, null, "java/lang/Object", null)
        cw.visitInnerClass(name, outer, type, Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC or Opcodes.ACC_FINAL)
        for (f in ints.keys) cw.visitField(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, f, "I", null, null).visitEnd()
        for (f in arrays.keys) cw.visitField(Opcodes.ACC_PUBLIC or Opcodes.ACC_STATIC, f, "[I", null, null).visitEnd()
        // Static initialisers are split into helper methods: a single method may not exceed 64 KB.
        val chunks = (ints.entries.map { it.key to it.value as Any } + arrays.entries.map { it.key to it.value as Any }).chunked(500)
        chunks.forEachIndexed { i, chunk ->
            val mv = cw.visitMethod(Opcodes.ACC_PRIVATE or Opcodes.ACC_STATIC, "init$i", "()V", null, null)
            mv.visitCode()
            for ((field, value) in chunk) {
                if (value is Int) {
                    mv.visitLdcInsn(value)
                    mv.visitFieldInsn(Opcodes.PUTSTATIC, name, field, "I")
                } else {
                    @Suppress("UNCHECKED_CAST") val list = value as List<Int>
                    mv.visitLdcInsn(list.size)
                    mv.visitIntInsn(Opcodes.NEWARRAY, Opcodes.T_INT)
                    list.forEachIndexed { j, v -> mv.visitInsn(Opcodes.DUP); mv.visitLdcInsn(j); mv.visitLdcInsn(v); mv.visitInsn(Opcodes.IASTORE) }
                    mv.visitFieldInsn(Opcodes.PUTSTATIC, name, field, "[I")
                }
            }
            mv.visitInsn(Opcodes.RETURN)
            mv.visitMaxs(0, 0)
            mv.visitEnd()
        }
        val clinit = cw.visitMethod(Opcodes.ACC_STATIC, "<clinit>", "()V", null, null)
        clinit.visitCode()
        for (i in chunks.indices) clinit.visitMethodInsn(Opcodes.INVOKESTATIC, name, "init$i", "()V", false)
        clinit.visitInsn(Opcodes.RETURN)
        clinit.visitMaxs(0, 0)
        clinit.visitEnd()
        cw.visitEnd()
        return cw.toByteArray()
    }
}
