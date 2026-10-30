package swiftshot.android

import java.math.BigDecimal
import java.security.MessageDigest

/**
 * The JSON of docs/wiki/Baseline-format.md (Serialization): keys sorted by UTF-8 bytes, 2-space pretty form or
 * compact, integral numbers as integers, others in the shortest round-tripping decimal without exponent.
 */
object CanonicalJson {
    /** UTF-8 byte order (= code point order; differs from [String.compareTo] above the BMP). */
    val utf8: Comparator<String> = Comparator { a, b ->
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val x = a.codePointAt(i)
            val y = b.codePointAt(j)
            if (x != y) return@Comparator x.compareTo(y)
            i += Character.charCount(x)
            j += Character.charCount(y)
        }
        when { i < a.length -> 1; j < b.length -> -1; else -> 0 }
    }

    fun pretty(v: Any?): String = StringBuilder().also { write(it, v, "  ", "") }.append('\n').toString()

    fun compact(v: Any?): String = StringBuilder().also { write(it, v, null, "") }.toString()

    fun sha256(text: String): String = MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    /** The hash of a value: SHA-256 of its compact form. */
    fun hash(v: Any?): String = sha256(compact(v))

    fun number(n: Number): String = when (n) {
        is Int, is Long, is Short, is Byte -> n.toString()
        else -> {
            val d = n.toDouble()
            require(!d.isNaN() && !d.isInfinite() && Math.abs(d) < 1e15) { "number out of range: $d" }
            if (d == Math.floor(d)) d.toLong().toString()
            else BigDecimal(if (n is Float) n.toString() else d.toString()).stripTrailingZeros().toPlainString()
        }
    }

    private fun write(out: StringBuilder, v: Any?, indent: String?, pad: String) {
        when (v) {
            null -> out.append("null")
            is String -> quote(out, v)
            is Boolean -> out.append(v.toString())
            is Number -> out.append(number(v))
            is Map<*, *> -> {
                if (v.isEmpty()) { out.append("{}"); return }
                val inner = indent?.let { pad + it }
                out.append('{')
                v.keys.map { it.toString() to it }.sortedWith(compareBy(utf8) { it.first }).forEachIndexed { n, (k, key) ->
                    if (n > 0) out.append(',')
                    if (inner != null) out.append('\n').append(inner)
                    quote(out, k)
                    out.append(if (indent != null) ": " else ":")
                    write(out, v[key], indent, inner ?: "")
                }
                if (indent != null) out.append('\n').append(pad)
                out.append('}')
            }
            is Iterable<*>, is Array<*> -> {
                val items = if (v is Array<*>) v.toList() else (v as Iterable<*>).toList()
                if (items.isEmpty()) { out.append("[]"); return }
                val inner = indent?.let { pad + it }
                out.append('[')
                items.forEachIndexed { n, item ->
                    if (n > 0) out.append(',')
                    if (inner != null) out.append('\n').append(inner)
                    write(out, item, indent, inner ?: "")
                }
                if (indent != null) out.append('\n').append(pad)
                out.append(']')
            }
            else -> quote(out, v.toString())
        }
    }

    private fun quote(out: StringBuilder, s: String) {
        out.append('"')
        for (c in s) when (c) {
            '"' -> out.append("\\\"")
            '\\' -> out.append("\\\\")
            '\n' -> out.append("\\n")
            '\r' -> out.append("\\r")
            '\t' -> out.append("\\t")
            else -> if (c < ' ') out.append(String.format("\\u%04x", c.code)) else out.append(c)
        }
        out.append('"')
    }
}
