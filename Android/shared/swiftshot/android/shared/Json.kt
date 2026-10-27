package swiftshot.android.shared

/** A small JSON reader and writer: objects become maps, arrays lists, numbers Long or Double. */
object Json {
    fun parse(text: String): Any? = Parser(text).run { val v = value(); ws(); require(i == s.length) { "trailing data at $i" }; v }

    fun write(value: Any?, indent: String? = null): String = StringBuilder().also { write(it, value, indent, "") }.toString()

    private fun write(out: StringBuilder, v: Any?, indent: String?, pad: String) {
        when (v) {
            null -> out.append("null")
            is String -> quote(out, v)
            is Boolean, is Int, is Long -> out.append(v.toString())
            is Float, is Double -> {
                val d = (v as Number).toDouble()
                if (d == Math.floor(d) && !d.isInfinite() && Math.abs(d) < 1e15) out.append(d.toLong()) else out.append(d)
            }
            is Map<*, *> -> {
                if (v.isEmpty()) { out.append("{}"); return }
                val inner = indent?.let { pad + it }
                out.append('{')
                v.entries.forEachIndexed { n, (k, value) ->
                    if (n > 0) out.append(',')
                    if (inner != null) out.append('\n').append(inner)
                    quote(out, k.toString()); out.append(if (indent != null) ": " else ":")
                    write(out, value, indent, inner ?: "")
                }
                if (indent != null) out.append('\n').append(pad)
                out.append('}')
            }
            is Iterable<*> -> {
                val items = v.toList()
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

    private class Parser(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun value(): Any? {
            ws()
            require(i < s.length) { "unexpected end" }
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c.isDigit()) num() else error("unexpected '$c' at $i")
            }
        }
        fun lit(word: String, v: Any?): Any? { require(s.startsWith(word, i)) { "bad literal at $i" }; i += word.length; return v }
        fun obj(): Map<String, Any?> {
            val m = LinkedHashMap<String, Any?>(); i++; ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                ws(); val k = str(); ws(); require(s[i] == ':') { "expected : at $i" }; i++
                m[k] = value(); ws()
                when (s[i++]) { ',' -> continue; '}' -> return m; else -> error("expected , or } at ${i - 1}") }
            }
        }
        fun arr(): List<Any?> {
            val l = ArrayList<Any?>(); i++; ws()
            if (s[i] == ']') { i++; return l }
            while (true) {
                l.add(value()); ws()
                when (s[i++]) { ',' -> continue; ']' -> return l; else -> error("expected , or ] at ${i - 1}") }
            }
        }
        fun str(): String {
            require(s[i] == '"') { "expected string at $i" }; i++
            val b = StringBuilder()
            while (true) {
                val c = s[i++]
                when (c) {
                    '"' -> return b.toString()
                    '\\' -> when (val e = s[i++]) {
                        'n' -> b.append('\n'); 't' -> b.append('\t'); 'r' -> b.append('\r'); 'b' -> b.append('\b'); 'f' -> b.append('\u000c')
                        'u' -> { b.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                        else -> b.append(e)
                    }
                    else -> b.append(c)
                }
            }
        }
        fun num(): Number {
            val start = i
            if (s[i] == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] in ".eE+-")) i++
            val t = s.substring(start, i)
            return if (t.any { it in ".eE" }) t.toDouble() else t.toLong()
        }
    }
}
