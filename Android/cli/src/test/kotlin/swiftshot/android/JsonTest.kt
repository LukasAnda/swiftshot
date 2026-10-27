package swiftshot.android

import swiftshot.android.shared.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class JsonTest {
    @Test fun parsesLiterals() {
        assertEquals(true, Json.parse("true"))
        assertEquals(false, Json.parse(" false "))
        assertNull(Json.parse("null"))
        assertEquals("", Json.parse("\"\""))
    }

    @Test fun integersAreLongsAndFractionsDoubles() {
        assertEquals(42L, assertIs<Long>(Json.parse("42")))
        assertEquals(-7L, assertIs<Long>(Json.parse("-7")))
        assertEquals(0L, assertIs<Long>(Json.parse("0")))
        assertEquals(9007199254740993L, Json.parse("9007199254740993"))
        assertEquals(Long.MAX_VALUE, Json.parse(Long.MAX_VALUE.toString()))
        assertEquals(1.5, assertIs<Double>(Json.parse("1.5")))
        assertEquals(-0.25, Json.parse("-0.25"))
        assertEquals(1000.0, assertIs<Double>(Json.parse("1e3")))
        assertEquals(1.5e-3, Json.parse("1.5E-3"))
        assertEquals(2.0e10, Json.parse("2e+10"))
    }

    @Test fun writesNumbers() {
        assertEquals("1", Json.write(1))
        assertEquals("-9223372036854775808", Json.write(Long.MIN_VALUE))
        assertEquals("1", Json.write(1.0))
        assertEquals("3", Json.write(3f))
        assertEquals("1.5", Json.write(1.5))
        assertEquals("0.1", Json.write(0.1))
        assertEquals("-2.75", Json.write(-2.75))
        assertEquals("1.0E15", Json.write(1e15))
        // Whole doubles come back as longs: the value is kept, the type is not.
        assertEquals(2L, Json.parse(Json.write(2.0)))
    }

    @Test fun parsesNestedStructures() {
        val v = Json.parse("""{"a": [1, 2.5, {"b": null}], "c": {"d": [], "e": {}}, "f": "g"}""")
        assertEquals(
            mapOf("a" to listOf(1L, 2.5, mapOf("b" to null)), "c" to mapOf("d" to emptyList<Any>(), "e" to emptyMap<String, Any>()), "f" to "g"),
            v,
        )
    }

    @Test fun keepsKeyOrder() {
        val m = Json.parse("""{"z":1,"a":2,"m":3}""") as Map<*, *>
        assertEquals(listOf("z", "a", "m"), m.keys.toList())
        assertEquals("""{"z":1,"a":2,"m":3}""", Json.write(m))
    }

    @Test fun roundTripsCompactAndIndented() {
        val value = linkedMapOf(
            "name" to "Pixel 9", "width" to 1080L, "ratio" to 2.25, "round" to false, "none" to null,
            "list" to listOf(1L, listOf("x", mapOf("deep" to listOf(true))), emptyList<Any>()),
            "empty" to emptyMap<String, Any>(),
        )
        assertEquals(value, Json.parse(Json.write(value)))
        assertEquals(value, Json.parse(Json.write(value, "  ")))
        assertEquals(value, Json.parse(Json.write(value, "\t")))
    }

    @Test fun indentsLikeAPrettyPrinter() {
        val text = Json.write(linkedMapOf("a" to listOf(1, 2), "b" to emptyList<Any>(), "c" to emptyMap<String, Any>(), "d" to mapOf("e" to "f")), "  ")
        assertEquals(
            """
            {
              "a": [
                1,
                2
              ],
              "b": [],
              "c": {},
              "d": {
                "e": "f"
              }
            }
            """.trimIndent(),
            text,
        )
    }

    @Test fun writesEscapes() {
        assertEquals("\"a\\\"b\\\\c\\nd\\re\\tf\"", Json.write("a\"b\\c\nd\re\tf"))
        assertEquals("\"\\u0001\\u001f\"", Json.write("\u0001\u001f"))
        assertEquals("\"/\"", Json.write("/"))
    }

    @Test fun parsesEscapes() {
        assertEquals("a\"b\\c/d\ne\tf\rg\bh\u000ci", Json.parse(""""a\"b\\c\/d\ne\tf\rg\bh\fi""""))
        assertEquals("é", Json.parse("\"\\u00e9\""))
        assertEquals("é", Json.parse("\"\\u00E9\""))
    }

    @Test fun unicode() {
        val s = "žluťoučký kůň · 日本語 · العربية · 😀"
        assertEquals("\"$s\"", Json.write(s))
        assertEquals(s, Json.parse(Json.write(s)))
        assertEquals("😀", Json.parse("\"\\ud83d\\ude00\""))
        assertEquals(mapOf("ключ" to "значение"), Json.parse("""{"ключ":"значение"}"""))
    }

    @Test fun controlCharactersRoundTrip() {
        val s = (0 until 32).map { it.toChar() }.joinToString("")
        assertEquals(s, Json.parse(Json.write(s)))
    }

    @Test fun writesOtherValuesAsStrings() {
        assertEquals("\"x/y\"", Json.write(java.io.File("x/y")))
        assertEquals("[\"a\",\"b\"]", Json.write(setOf("a", "b")))
        assertEquals("{\"1\":true}", Json.write(mapOf(1 to true)))
    }

    @Test fun toleratesWhitespace() {
        assertEquals(mapOf("a" to listOf(1L)), Json.parse(" \n\t{ \"a\" :\r\n [ 1 ] } \n"))
    }

    @Test fun rejectsBadInputWithReadableErrors() {
        val bad = listOf(
            "", "   ", "{", "[", "[1,", "[1 2]", "{\"a\" 1}", "{\"a\":1,}", "[1,]", "{a:1}", "tru", "nul", "\"abc",
            "\"\\u12", "\"\\uzzzz\"", "1 2", "{} x", "-", "1.2.3", "'a'", "{\"a\":1", "[\"a\"", "@",
        )
        for (text in bad) {
            try {
                Json.parse(text)
                fail("parsed bad JSON: $text")
            } catch (e: Exception) {
                // Main reports these two as a one-line error; anything else would be a stack trace.
                assertTrue(e is IllegalArgumentException || e is IllegalStateException, "\"$text\" threw ${e::class.simpleName}")
            }
        }
    }

    @Test fun reportsTrailingData() {
        val e = assertFailsWith<IllegalArgumentException> { Json.parse("[1] [2]") }
        assertTrue(e.message!!.contains("trailing"))
    }
}
