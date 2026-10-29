package swiftshot.android

import java.io.File

internal class Ann(val name: String, val open: Int?)

/**
 * A `fun` or class-like declaration; [body] is its `{ … }` (or expression body) range, [params] a function's
 * parameter names in order, [isEnum] for `enum class`.
 */
internal class Decl(
    val name: String, val keyword: Int, val body: IntRange?, val annotations: List<Ann>,
    val superclass: String? = null, val params: List<String> = emptyList(), val isEnum: Boolean = false,
)

/** A call in composable content: [args] is inside its parentheses; [argLambda] when they hold a lambda that calls something. */
internal class Node(
    val name: String, val called: Boolean, val args: IntRange?, val lambda: IntRange?, val assigned: Boolean,
    val argLambda: Boolean, val children: List<Node>,
)

/** A call by name: [start] is where its receiver chain begins, [end] just past its parentheses or trailing lambda. */
internal class Call(val name: String, val nameAt: Int, val start: Int, val end: Int, val open: Int?, val lambda: IntRange?)

/** A loop around a position: `X.forEach { }`, `X.forEachIndexed { }` or `for (x in X)`, with [over] the range of X. */
internal class Loop(val over: IntRange, val body: IntRange)

/**
 * A Kotlin (or Java) source file read as text: [code] has comments blanked, [mask] string contents too, with the
 * same offsets. Brackets are matched once; declarations, imports, annotations and calls are read from [mask].
 */
internal class KotlinSource(val file: File) {
    val code: String
    val mask: String
    private val closeAt: IntArray
    private val openAt: IntArray
    private val lineStarts: List<Int>

    init {
        val text = file.readText()
        code = SnapshotModules.strip(text)
        mask = SnapshotModules.strip(text, strings = true)
        closeAt = IntArray(mask.length) { -1 }; openAt = IntArray(mask.length) { -1 }
        val stack = ArrayDeque<Int>()
        for ((i, c) in mask.withIndex()) when (c) {
            '(', '[', '{' -> stack.addLast(i)
            ')', ']', '}' -> stack.removeLastOrNull()?.let { closeAt[it] = i; openAt[i] = it }
        }
        lineStarts = listOf(0) + mask.indices.filter { mask[it] == '\n' }.map { it + 1 }
    }

    val java = file.extension == "java"

    fun close(open: Int) = closeAt[open].let { if (it < 0) mask.length - 1 else it }
    fun line(pos: Int) = lineStarts.binarySearch(pos).let { if (it >= 0) it + 1 else -it - 1 }
    fun skipWs(from: Int): Int { var i = from; while (i < mask.length && mask[i].isWhitespace()) i++; return i }
    private fun skipWsBack(from: Int): Int { var i = from; while (i >= 0 && mask[i].isWhitespace()) i--; return i }
    fun text(range: IntRange) = code.substring(range.first, minOf(range.last + 1, code.length))

    val pkg = Regex("""(?m)^\s*package\s+([\w.]+)""").find(mask)?.groupValues?.get(1) ?: ""
    private val importLines = Regex("""(?m)^\s*import\s+(?:static\s+)?([\w.]+?)(\.\*)?(?:\s+as\s+(\w+))?\s*;?\s*$""").findAll(mask).toList()
    val imports: Map<String, String> = importLines.filter { it.groupValues[2].isEmpty() }.associate { m -> m.groupValues[3].ifEmpty { m.groupValues[1].substringAfterLast('.') } to m.groupValues[1] }
    val stars: List<String> = importLines.filter { it.groupValues[2].isNotEmpty() }.map { it.groupValues[1] }

    /** The Kotlin file facade class: `@file:JvmName`, else `<FileName>Kt`. */
    val facade: String = Regex("""@file\s*:\s*JvmName\s*\(\s*"([^"]+)"""").find(code)?.groupValues?.get(1)
        ?: (file.nameWithoutExtension.replaceFirstChar(Char::uppercaseChar).replace(Regex("[^A-Za-z0-9_]"), "_") + "Kt")

    val funs: List<Decl> = Regex("""\bfun\s+(?:<[^>]*>\s*)?(?:[\w<>?,* ]+\.)*(\w+|`[^`\n]+`)\s*\(""").findAll(mask).map { m ->
        val params = args(m.range.last).mapNotNull { (_, r) ->
            Regex("""^\s*(?:(?:vararg|noinline|crossinline)\s+)*(?:@[\w.:]+(?:\s*\([^)]*\))?\s+)*(\w+)\s*:""").find(mask.substring(r.first, r.last + 1))?.groupValues?.get(1)
        }
        var i = skipWs(close(m.range.last) + 1)
        if (i < mask.length && mask[i] == ':') { i++; while (i < mask.length && mask[i] !in "{=\n;}") i = if (mask[i] in "([") close(i) + 1 else i + 1 }
        i = skipWs(i)
        val body = when {
            i < mask.length && mask[i] == '{' -> i..close(i)
            i < mask.length && mask[i] == '=' -> i..exprEnd(skipWs(i + 1))
            else -> null
        }
        Decl(m.groupValues[1].removeSurrounding("`"), m.range.first, body, annotationsBefore(m.range.first), params = params)
    }.toList()

    val classes: List<Decl> = Regex("""\b(?:(companion)\s+)?(class|object|interface)\b(?:\s+(\w+))?""").findAll(mask).mapNotNull { m ->
        if (m.range.first > 0 && mask[m.range.first - 1] in ":.") return@mapNotNull null
        val name = m.groups[3]?.value ?: if (m.groups[1] != null) "Companion" else return@mapNotNull null
        if (name in keywords) return@mapNotNull null
        var i = m.range.last + 1
        var delegation = -1
        var body: IntRange? = null
        while (i < mask.length) {
            val c = mask[i]
            when {
                c == '{' -> { body = i..close(i); break }
                c == '(' -> i = close(i) + 1
                c == '<' -> { var d = 0; while (i < mask.length) { if (mask[i] == '<') d++; if (mask[i] == '>') d--; i++; if (d == 0) break } }
                c in ";})=" -> break
                c == '\n' -> {
                    val next = skipWs(i); val prev = skipWsBack(i)
                    if (next < mask.length && mask[next] in ":,{(" || prev >= 0 && mask[prev] in ":,") i = next else break
                }
                else -> { if (c == ':' && delegation < 0) delegation = i; i++ }
            }
        }
        val superclass = if (delegation < 0) null
            else Regex("""([\w.]+)\s*(?:<[^>]*>)?\s*\(""").find(mask.substring(delegation, body?.first ?: i))?.groupValues?.get(1)?.substringAfterLast('.')
        val isEnum = m.groups[2]?.value == "class" && Regex("""\benum\s+$""").containsMatchIn(mask.substring(maxOf(0, m.range.first - 12), m.range.first))
        Decl(name, m.range.first, body, annotationsBefore(m.range.first), superclass, isEnum = isEnum)
    }.toList()

    fun fnAt(pos: Int) = funs.filter { it.body != null && pos in it.body }.maxByOrNull { it.body!!.first }
    fun classAt(pos: Int) = classes.filter { it.body != null && pos in it.body }.maxByOrNull { it.body!!.first }

    fun exprEndAt(from: Int) = exprEnd(from)

    /** End of an expression: a newline that doesn't continue it, or the enclosing block's end. */
    private fun exprEnd(from: Int): Int {
        var i = from
        while (i < mask.length) {
            val c = mask[i]
            when {
                c in "([{" -> i = close(i) + 1
                c in ")]};" -> return i - 1
                c == '\n' -> { val n = skipWs(i); if (n < mask.length && mask[n] in ".?:+-*/|&") i = n else return i - 1 }
                else -> i++
            }
        }
        return mask.length - 1
    }

    /** The calls chained after [from] (`.scanPackageTrees("a").getPreviews()`): (name, inside of its parentheses). */
    fun calledOn(from: Int): List<Pair<String, IntRange?>> {
        val out = mutableListOf<Pair<String, IntRange?>>()
        var k = from
        while (true) {
            var d = skipWs(k)
            if (d < mask.length && mask[d] in "?!") d++
            if (d >= mask.length || mask[d] != '.') return out
            val s = skipWs(d + 1)
            var e = s
            while (e < mask.length && (mask[e].isLetterOrDigit() || mask[e] == '_')) e++
            if (e == s) return out
            val name = mask.substring(s, e)
            var args: IntRange? = null
            var n = skipWs(e)
            if (n < mask.length && mask[n] == '(') { args = n + 1 until close(n); n = close(n) + 1 }
            val l = skipWs(n)
            if (l < mask.length && mask[l] == '{') n = close(l) + 1
            out += name to args
            k = n
        }
    }

    /** Annotations (and modifiers, skipped) written right before a declaration keyword at [pos]. */
    fun annotationsBefore(pos: Int): List<Ann> {
        val out = mutableListOf<Ann>()
        var i = pos
        while (true) {
            var j = skipWsBack(i - 1)
            if (j < 0) break
            var open: Int? = null
            if (mask[j] == ')') { open = openAt[j].takeIf { it >= 0 } ?: break; j = skipWsBack(open - 1) }
            var k = j
            while (k >= 0 && (mask[k].isLetterOrDigit() || mask[k] in "_.:")) k--
            val word = mask.substring(k + 1, j + 1)
            if (k >= 0 && mask[k] == '@' && word.isNotEmpty()) { out += Ann(word.substringAfter(':').substringAfterLast('.'), open); i = k; continue }
            if (open == null && word in modifiers) { i = k + 1; continue }
            break
        }
        return out.reversed()
    }

    /** Start of the receiver chain ending at [pos] (`composeTestRule.onRoot().` before `captureRoboImage`). */
    fun chainStart(pos: Int): Int {
        var s = pos
        while (true) {
            var j = skipWsBack(s - 1)
            if (j < 0 || mask[j] != '.') return s
            j = skipWsBack(j - 1)
            while (j >= 0 && mask[j] in "?!") j--
            if (j >= 0 && mask[j] == ')') j = skipWsBack(openAt[j] - 1)
            var k = j
            while (k >= 0 && (mask[k].isLetterOrDigit() || mask[k] == '_')) k--
            if (k == j) return s
            s = k + 1
        }
    }

    /** After a call name at [from]: (end of the call, opening parenthesis, inside of its trailing lambda). */
    fun callAt(from: Int): Triple<Int, Int?, IntRange?> {
        var i = skipWs(from)
        var open: Int? = null
        if (i < mask.length && mask[i] == '(') { open = i; i = close(i) + 1 } else i = from
        val k = skipWs(i)
        if (k < mask.length && mask[k] == '{') return Triple(close(k) + 1, open, k + 1 until close(k))
        return Triple(i, open, null)
    }

    /** Calls of any name followed by `(` or `{` in [range], leaving out declarations (`fun name(`). */
    fun calls(range: IntRange): List<Call> = Regex("""(?<![\w`])(\w+|`[^`\n]+`)\s*(?=[({])""").findAll(mask.substring(range.first, minOf(range.last + 1, mask.length))).mapNotNull { m ->
        val at = range.first + m.range.first
        val name = m.groupValues[1].removeSurrounding("`")
        if (name in keywords || isDeclaration(at)) return@mapNotNull null
        val (end, open, lambda) = callAt(range.first + m.range.last + 1)
        Call(name, at, chainStart(at), end, open, lambda)
    }.toList()

    fun isDeclaration(at: Int) = Regex("""\bfun\s+(?:<[^>]*>\s*)?(?:[\w<>?,* ]+\.)?$""").containsMatchIn(mask.substring(maxOf(0, at - 80), at))

    /** Arguments inside the parentheses opening at [open]: (name or null, value range). */
    fun args(open: Int): List<Pair<String?, IntRange>> {
        val end = close(open)
        val out = mutableListOf<Pair<String?, IntRange>>()
        var start = open + 1
        var i = start
        fun add(e: Int) {
            val part = mask.substring(start, e)
            if (part.isBlank()) return
            val named = Regex("""^\s*(\w+)\s*=(?!=)""").find(part)
            out += if (named != null) named.groupValues[1] to (start + named.range.last + 1 until e) else null to (start until e)
        }
        while (i < end) {
            when (mask[i]) { '(', '[', '{' -> { i = close(i) + 1; continue }; ',' -> { add(i); start = i + 1 } }
            i++
        }
        add(end)
        return out
    }

    /** [range] split where [separator] (`+`, or a word like `then`) appears outside brackets. */
    fun split(range: IntRange, separator: String): List<IntRange> {
        val parts = mutableListOf<IntRange>()
        val word = separator.first().isLetter()
        var start = range.first
        var i = range.first
        while (i <= range.last) {
            val c = mask[i]
            when {
                c in "([{" -> { i = close(i) + 1; continue }
                mask.startsWith(separator, i) && (!word || ((i == 0 || !mask[i - 1].isLetterOrDigit()) && mask.getOrNull(i + separator.length)?.isLetterOrDigit() != true)) -> {
                    parts += start until i; start = i + separator.length; i += separator.length; continue
                }
            }
            i++
        }
        parts += start..range.last
        return parts
    }

    /** The initializer of a `val`/`const val` named by [expr] (`DEVICE`, `Companion.DEVICE`), if declared once in this file. */
    fun constant(expr: String): IntRange? {
        val name = Regex("""^(?:\w+\.)*(\w+)$""").matchEntire(expr.trim())?.groupValues?.get(1) ?: return null
        val decls = Regex("""\b(?:val|var)\s+${Regex.escape(name)}\s*(?::[^=\n]+)?=(?!=)""").findAll(mask).toList()
        val d = decls.singleOrNull() ?: return null
        val start = skipWs(d.range.last + 1)
        return start..exprEnd(start)
    }

    /** The string literals of a list expression (`listOf("a", "b")`, `["a"]`, `"a"`); null when anything else is in it. */
    fun literals(range: IntRange): List<String>? {
        val text = text(range)
        val values = Regex(""""([^"$\\]*)"""").findAll(text).map { it.groupValues[1] }.toList()
        val rest = Regex(""""[^"$\\]*"""").replace(text, "").replace(Regex("""\b(?:listOf|arrayOf|setOf|mutableListOf)\b|\.set\b|\.addAll\b|[\s(),\[\]]"""), "")
        return if (rest.isEmpty()) values else null
    }

    /** The loops in [body] whose bodies contain [pos], outermost first. */
    fun loops(body: IntRange, pos: Int): List<Loop> {
        val out = mutableListOf<Loop>()
        for (m in Regex("""\.\s*(?:forEach|forEachIndexed)\s*\{""").findAll(mask.substring(body.first, minOf(body.last + 1, mask.length)))) {
            val open = body.first + m.range.last
            if (pos <= open || pos >= close(open)) continue
            val dot = body.first + m.range.first
            out += Loop(chainStart(skipWs(dot + 1)) until dot, open..close(open))
        }
        for (m in Regex("""\bfor\s*\(""").findAll(mask.substring(body.first, minOf(body.last + 1, mask.length)))) {
            val open = body.first + m.range.last
            val head = mask.substring(open + 1, close(open))
            val inAt = Regex("""\bin\b""").find(head) ?: continue
            val b = skipWs(close(open) + 1)
            val range = if (b < mask.length && mask[b] == '{') b..close(b) else b..exprEnd(b)
            if (pos !in range) continue
            out += Loop(open + 1 + inAt.range.last + 1 until close(open), range)
        }
        return out.sortedBy { it.body.first }
    }

    /** The calls written in a composable lambda, nested by their trailing lambdas; argument lists aren't entered. */
    fun nodes(from: Int, to: Int): List<Node> {
        val out = mutableListOf<Node>()
        var i = from
        while (i < to) {
            val c = mask[i]
            when {
                c == '{' -> { out += nodes(i + 1, close(i)); i = close(i) + 1 }
                c == '(' || c == '[' -> i = close(i) + 1
                c.isLetter() || c == '_' -> {
                    val start = i
                    val name = StringBuilder()
                    var j = i
                    while (true) {
                        val s = j
                        while (j < to && (mask[j].isLetterOrDigit() || mask[j] == '_')) j++
                        name.append(mask, s, j)
                        val d = skipWs(j)
                        if (d < to && mask[d] == '.' && skipWs(d + 1).let { it < to && (mask[it].isLetter() || mask[it] == '_') }) { name.append('.'); j = skipWs(d + 1) } else break
                    }
                    if (name.toString() in keywords) { i = j; continue }
                    var k = skipWs(j)
                    var args: IntRange? = null
                    var argLambda = false
                    if (k < to && mask[k] == '(') {
                        argLambda = Regex("""\{[^{}]*?[A-Za-z_]\w*\s*[({]""").containsMatchIn(mask.substring(k, close(k)))
                        args = k + 1 until close(k)
                        k = close(k) + 1
                    }
                    var lambda: IntRange? = null
                    val l = skipWs(k)
                    if (l < to && mask[l] == '{') { lambda = l + 1 until close(l); k = close(l) + 1 }
                    if (args == null && lambda == null) { i = j; continue }
                    // Calls chained on the result (`.also { }`) belong to this one.
                    while (true) {
                        var d = skipWs(k)
                        if (d < to && mask[d] in "?!") d++
                        if (d >= to || mask[d] != '.') break
                        var e = skipWs(d + 1)
                        while (e < to && (mask[e].isLetterOrDigit() || mask[e] == '_')) e++
                        e = skipWs(e)
                        if (e < to && mask[e] == '(') e = skipWs(close(e) + 1)
                        if (e < to && mask[e] == '{') e = close(e) + 1
                        k = e
                    }
                    val prev = skipWsBack(start - 1)
                    val assigned = prev >= 0 && mask[prev] == '=' && (prev == 0 || mask[prev - 1] !in "=!<>")
                    out += Node(name.toString(), args != null, args, lambda, assigned, argLambda, lambda?.let { nodes(it.first, it.last + 1) } ?: emptyList())
                    i = k
                }
                else -> i++
            }
        }
        return out
    }

    companion object {
        val keywords = setOf(
            "if", "else", "when", "try", "catch", "finally", "for", "while", "do", "return", "val", "var", "fun", "is", "in", "as",
            "null", "true", "false", "this", "super", "throw", "object", "class",
        )
        private val modifiers = setOf(
            "private", "public", "internal", "protected", "open", "abstract", "override", "final", "suspend", "inline", "data", "enum",
            "annotation", "sealed", "inner", "value", "companion", "operator", "infix", "tailrec", "external", "expect", "actual", "static", "fun",
        )
    }
}
