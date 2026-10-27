package swiftshot.android

import java.io.File

/**
 * Finds the annotated functions, static methods and constructors in Dart sources without the
 * analyzer: strings and comments are blanked out, then declarations are read with their brace
 * depth and enclosing class. Which annotations are previews is decided at run time (`is Preview`,
 * `is MultiPreview`), so custom `Preview` subclasses need no special casing here.
 */
object DartScanner {
    /** One annotated declaration: [annotations] as written (without `@`), [reference] as a tear-off. */
    data class Found(val file: File, val library: File, val line: Int, val annotations: List<String>, val reference: String, val private: Boolean)

    /** Annotations that are never previews (Dart's and `package:meta`'s, code generators'). */
    private val ignored = setOf(
        "override", "deprecated", "Deprecated", "pragma", "visibleForTesting", "visibleForOverriding", "protected", "mustCallSuper",
        "immutable", "internal", "experimental", "factory", "literal", "nonVirtual", "sealed", "useResult", "redeclare", "reopen",
        "mustBeOverridden", "doNotStore", "alwaysThrows", "optionalTypeArgs", "required", "Since", "awaitNotRequired", "mustBeConst",
        "doNotSubmit", "widgetFactory", "Native", "JsonKey", "JsonSerializable", "freezed", "Freezed", "Default",
    )

    fun scan(lib: File): List<Found> = lib.walkTopDown()
        .filter { it.isFile && it.extension == "dart" && !it.name.endsWith(".g.dart") && !it.name.endsWith(".freezed.dart") }
        .sortedBy { it.path }
        .flatMap { scanFile(it).asSequence() }
        .toList()

    fun scanFile(file: File): List<Found> {
        val src = file.readText()
        if (!src.contains('@')) return emptyList()
        return declarations(src).map { (offset, annotations, reference) ->
            val line = src.substring(0, offset).count { it == '\n' } + 1
            val private = reference.split('.').any { it.startsWith("_") } || annotations.any { Regex("""(^|[^\w$.])_\w""").containsMatchIn(mask(it)) }
            Found(file, library(file, src), line, annotations, reference, private)
        }
    }

    /** The library a file belongs to: itself, or for a `part of` file the library it names. */
    private fun library(file: File, src: String): File {
        val m = mask(src)
        val at = Regex("""\bpart\s+of\b""").find(m) ?: return file
        val end = m.indexOf(';', at.range.last)
        val uri = Regex("""['"]([^'"]+)['"]""").find(src.substring(at.range.last + 1, end))?.groupValues?.get(1) ?: return file
        return File(file.parentFile, uri).normalize()
    }

    /** (offset, annotations, tear-off) of every declaration with at least one candidate annotation. */
    fun declarations(src: String): List<Triple<Int, List<String>, String>> {
        val m = mask(src)
        val found = mutableListOf<Triple<Int, List<String>, String>>()
        val classes = HashMap<Int, String>()
        var pendingClass: String? = null
        var depth = 0
        var i = 0
        val annotations = mutableListOf<String>()
        var annotationStart = -1
        while (i < m.length) {
            val c = m[i]
            when {
                c == '{' -> { depth++; pendingClass?.let { classes[depth] = it }; pendingClass = null; annotations.clear(); i++ }
                c == '}' -> { classes.remove(depth); depth--; annotations.clear(); i++ }
                c == ';' -> { pendingClass = null; annotations.clear(); i++ }
                c == '@' && (depth == 0 || classes.containsKey(depth)) -> {
                    val end = annotationEnd(m, i + 1)
                    if (annotations.isEmpty()) annotationStart = i
                    annotations += src.substring(i + 1, end).trim()
                    i = end
                }
                c.isLetter() || c == '_' || c == '$' -> {
                    val wordEnd = identEnd(m, i)
                    val word = m.substring(i, wordEnd)
                    if (depth == 0 && word in setOf("class", "mixin", "enum", "extension")) {
                        val name = Regex("""\s*(?:type\s+)?([A-Za-z_$][\w$]*)""").find(m, wordEnd)?.groupValues?.get(1)
                        pendingClass = if (name == "on") null else name
                        annotations.clear()
                        i = wordEnd
                    } else if (annotations.isNotEmpty() && (depth == 0 || classes.containsKey(depth))) {
                        val (end, reference) = declaration(m, i, if (depth == 0) null else classes[depth])
                        val candidates = annotations.filter { name(it) !in ignored }
                        if (reference != null && candidates.isNotEmpty()) found += Triple(annotationStart, candidates.toList(), reference)
                        annotations.clear()
                        i = end
                    } else i = wordEnd
                }
                else -> i++
            }
        }
        return found
    }

    /** The annotation's type or constant name, without prefix or arguments: `p.Preview(…)` → Preview. */
    fun name(annotation: String) = annotation.substringBefore('(').substringBefore('<').trim().substringAfterLast('.')

    /** A declaration header from [start]: its end (before its body or terminator) and its tear-off, if it is a function, static method or constructor. */
    private fun declaration(m: String, start: Int, cls: String?): Pair<Int, String?> {
        var i = start
        var angle = 0
        while (i < m.length) {
            val c = m[i]
            if (c == '<') angle++ else if (c == '>') angle--
            else if (angle <= 0 && (c == '(' || c == '{' || c == ';' || c == '=')) break
            i++
        }
        val header = m.substring(start, i).trim()
        val words = Regex("""[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?""").findAll(header.replace(Regex("<[^<>]*>"), " ")).map { it.value }.toList()
        if (i >= m.length || m[i] != '(' || words.isEmpty()) return i to null
        if (words.any { it in setOf("class", "typedef", "get", "set", "operator") }) return i to null
        val last = words.last()
        if (cls == null) return i to last.takeIf { '.' !in it }
        val rest = words.filter { it !in setOf("const", "factory", "external") }
        return i to when {
            "static" in words -> "$cls.$last"
            rest.size == 1 && rest[0] == cls -> "$cls.new"
            rest.size == 1 && rest[0].startsWith("$cls.") -> rest[0]
            else -> null
        }
    }

    private fun identEnd(m: String, from: Int): Int {
        var i = from
        while (i < m.length && (m[i].isLetterOrDigit() || m[i] == '_' || m[i] == '$')) i++
        return i
    }

    /** After `@`: a (prefixed) name, type arguments, then arguments in balanced parentheses. */
    private fun annotationEnd(m: String, from: Int): Int {
        var i = from
        while (i < m.length && (m[i].isLetterOrDigit() || m[i] == '_' || m[i] == '$' || m[i] == '.')) i++
        var j = i
        while (j < m.length && m[j].isWhitespace()) j++
        if (j < m.length && m[j] == '<') { var d = 0; while (j < m.length) { if (m[j] == '<') d++ else if (m[j] == '>') { d--; if (d == 0) { j++; break } }; j++ }; i = j }
        j = i
        while (j < m.length && m[j].isWhitespace()) j++
        if (j < m.length && m[j] == '(') {
            var d = 0
            while (j < m.length) { if (m[j] == '(') d++ else if (m[j] == ')') { d--; if (d == 0) return j + 1 }; j++ }
        }
        return i
    }

    /** The import and export directives of a library (its whole text up to each `;`). */
    fun directives(src: String): List<String> {
        val m = mask(src)
        return Regex("""(?m)^\s*(import|export)\b""").findAll(m).map { r -> src.substring(r.range.first, m.indexOf(';', r.range.last) + 1).trim() }
            .filter { it.startsWith("import") }.toList()
    }

    /**
     * The generated library for one source library: its imports (relative URIs made absolute),
     * the library itself, and `swiftshotEntries()` with each annotation re-created as written.
     */
    fun library(library: File, lib: File, pkg: String, found: List<Found>, root: File): String {
        fun uri(target: File) = if (target.canonicalPath.startsWith(lib.canonicalPath + File.separator)) "package:$pkg/" + target.canonicalFile.relativeTo(lib.canonicalFile).path.replace(File.separatorChar, '/')
            else target.canonicalFile.toURI().toString()
        val imports = directives(library.readText()).map { d ->
            Regex("""(['"])([^'"]+)\1""").replace(d) { r ->
                val u = r.groupValues[2]
                if (':' in u) r.value else "'" + uri(File(library.parentFile, u)) + "'"
            }
        }
        return buildString {
            appendLine("// Generated by Swiftshot from ${library.relativeTo(root).path}: its imports, the library and its previews.")
            appendLine("// ignore_for_file: type=lint, unused_import, deprecated_member_use")
            imports.forEach { appendLine(it) }
            appendLine("import '${uri(library)}';")
            appendLine("import 'swiftshot_flutter.dart' as swiftshot__;")
            appendLine()
            appendLine("List<swiftshot__.Entry> swiftshotEntries() => [")
            for (f in found) {
                val annotations = f.annotations.joinToString(", ") { a -> if ('(' in a) "const $a" else a }
                val script = f.file.relativeTo(root).path.replace(File.separatorChar, '/')
                appendLine("  swiftshot__.Entry('$script', ${f.line}, '${f.reference}', [$annotations], ${f.reference}),")
            }
            appendLine("];")
        }
    }

    /** [src] with strings (interpolations included) and comments replaced by spaces; line breaks kept. */
    fun mask(src: String): String {
        val out = src.toCharArray()
        fun blank(a: Int, b: Int) { for (k in a until minOf(b, out.size)) if (out[k] != '\n') out[k] = ' ' }
        // Each open string: quote, triple, raw. Each interpolation: its brace depth.
        data class Str(val quote: Char, val triple: Boolean, val raw: Boolean, val start: Int)
        val strings = ArrayDeque<Str>()
        val braces = ArrayDeque<Int>()
        var i = 0
        val n = src.length
        fun inCode() = strings.size == braces.size
        while (i < n) {
            if (inCode()) {
                val c = src[i]
                when {
                    src.startsWith("//", i) -> { val e = src.indexOf('\n', i).let { if (it < 0) n else it }; blank(i, e); i = e }
                    src.startsWith("/*", i) -> {
                        var d = 0; var j = i
                        while (j < n) {
                            if (src.startsWith("/*", j)) { d++; j += 2 } else if (src.startsWith("*/", j)) { d--; j += 2; if (d == 0) break } else j++
                        }
                        blank(i, j); i = j
                    }
                    c == '\'' || c == '"' -> {
                        val raw = i > 0 && src[i - 1] == 'r' && (i < 2 || !(src[i - 2].isLetterOrDigit() || src[i - 2] == '_'))
                        val triple = src.startsWith("$c$c$c", i)
                        strings.addLast(Str(c, triple, raw, if (raw) i - 1 else i))
                        i += if (triple) 3 else 1
                    }
                    c == '{' && braces.isNotEmpty() -> { braces.addLast(braces.removeLast() + 1); i++ }
                    c == '}' && braces.isNotEmpty() -> {
                        val d = braces.removeLast()
                        if (d == 0) i++ /* back in the string */ else { braces.addLast(d - 1); i++ }
                    }
                    else -> i++
                }
            } else {
                val s = strings.last()
                val c = src[i]
                when {
                    !s.raw && c == '\\' -> i += 2
                    !s.raw && c == '$' && i + 1 < n && src[i + 1] == '{' -> { braces.addLast(0); i += 2 }
                    s.triple && src.startsWith("${s.quote}${s.quote}${s.quote}", i) -> { strings.removeLast(); i += 3; blank(s.start, i) }
                    !s.triple && c == s.quote -> { strings.removeLast(); i++; blank(s.start, i) }
                    !s.triple && c == '\n' -> { strings.removeLast(); i++ } // unterminated: recover at the line end
                    else -> i++
                }
            }
        }
        return String(out)
    }
}
