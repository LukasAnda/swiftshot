package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DartScannerTest {
    private val dir: File = Files.createTempDirectory("swiftshot-dart").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private fun decls(src: String) = DartScanner.declarations(src).map { it.third to it.second }

    @Test fun topLevelFunctionsWithTheirAnnotationsAsWritten() {
        val src = """
            import 'package:flutter/widget_previews.dart';

            @Preview(name: 'Home', size: Size(400, 120))
            Widget homePreview() => const Home();

            @Preview(name: 'A') @Preview(name: 'B', brightness: Brightness.dark)
            Widget twice() => const Home();

            @LightDarkPreview(name: 'Card')
            WidgetBuilder builderPreview() => (context) => const Card();
        """.trimIndent()
        assertEquals(listOf(
            "homePreview" to listOf("Preview(name: 'Home', size: Size(400, 120))"),
            "twice" to listOf("Preview(name: 'A')", "Preview(name: 'B', brightness: Brightness.dark)"),
            "builderPreview" to listOf("LightDarkPreview(name: 'Card')"),
        ), decls(src))
    }

    @Test fun staticMethodsAndConstructorsInClasses() {
        val src = """
            class Card extends StatelessWidget {
              @Preview(name: 'Default')
              const Card({super.key});

              @Preview(name: 'Named')
              const Card.compact({super.key}) : this();

              @Preview(name: 'Factory')
              factory Card.big() => const Card();

              @Preview(name: 'Static')
              static Widget preview() => const Card();

              @override
              Widget build(BuildContext context) => const SizedBox();
            }
        """.trimIndent()
        assertEquals(listOf("Card.new", "Card.compact", "Card.big", "Card.preview"), decls(src).map { it.first })
    }

    @Test fun stringsAndCommentsDoNotConfuseTheScanner() {
        val src = """
            // @Preview(name: 'commented out')
            /* @Preview(name: 'block') /* nested */ still a comment */
            const text = 'class Fake { @Preview() Widget no() }';
            const raw = r'@Preview(name: "raw")';
            const multi = '''
            @Preview(name: 'in a string')
            ''';
            final i = 'a ${'$'}{"@Preview()"} b';

            @Preview(name: 'Paren ) in a string', group: "a{b")
            Widget real() => const SizedBox();
        """.trimIndent()
        assertEquals(listOf("real" to listOf("Preview(name: 'Paren ) in a string', group: \"a{b\")")), decls(src))
    }

    @Test fun otherAnnotationsAreLeftOut() {
        val src = """
            @visibleForTesting
            Widget helper() => const SizedBox();

            @Deprecated('old') @Preview(name: 'Kept')
            Widget kept() => const SizedBox();

            @override
            Widget build() => const SizedBox();
        """.trimIndent()
        assertEquals(listOf("kept" to listOf("Preview(name: 'Kept')")), decls(src))
    }

    @Test fun gettersVariablesAndInstanceMethodsAreNotPreviews() {
        val src = """
            @Preview() Widget get notAFunction => const SizedBox();
            @Preview() final variable = 1;
            class A { @Preview() Widget instance() => const SizedBox(); }
            @Preview() class B {}
        """.trimIndent()
        assertEquals(emptyList(), decls(src))
    }

    @Test fun privatePreviewsAndPrivateArgumentsAreFlagged() {
        val file = File(dir, "lib/a.dart").apply { parentFile.mkdirs() }
        file.writeText("""
            @Preview(name: 'P') Widget _hidden() => const SizedBox();
            @Preview(wrapper: _wrap) Widget wrapped() => const SizedBox();
            @Preview(name: 'Ok', wrapper: wrap) Widget ok() => const SizedBox();
        """.trimIndent())
        val found = DartScanner.scanFile(file)
        assertEquals(listOf(true, true, false), found.map { it.private })
        assertEquals(listOf(1, 2, 3), found.map { it.line })
    }

    @Test fun partFilesUseTheirLibrary() {
        val lib = File(dir, "lib").apply { mkdirs() }
        File(lib, "screens.dart").writeText("import 'package:flutter/material.dart';\npart 'screens/home.dart';\n")
        val part = File(lib, "screens/home.dart").apply { parentFile.mkdirs(); writeText("part of '../screens.dart';\n@Preview() Widget home() => const SizedBox();\n") }
        assertEquals(File(lib, "screens.dart").canonicalFile, DartScanner.scanFile(part).single().library.canonicalFile)
    }

    @Test fun generatedLibraryHasTheImportsMadeAbsolute() {
        val lib = File(dir, "lib").apply { mkdirs() }
        File(lib, "theme.dart").writeText("Widget wrap(Widget w) => w;")
        val file = File(lib, "ui/home.dart").apply { parentFile.mkdirs() }
        file.writeText("""
            import 'package:flutter/widget_previews.dart';
            import '../theme.dart' as t show wrap;

            @Preview(name: 'Home', wrapper: t.wrap)
            Widget homePreview() => const SizedBox();
        """.trimIndent())
        val text = DartScanner.library(file, lib, "habits", DartScanner.scanFile(file), dir)
        assertTrue("import 'package:flutter/widget_previews.dart';" in text, text)
        assertTrue("import 'package:habits/theme.dart' as t show wrap;" in text, text)
        assertTrue("import 'package:habits/ui/home.dart';" in text, text)
        assertTrue("swiftshot__.Entry('lib/ui/home.dart', 4, 'homePreview', [const Preview(name: 'Home', wrapper: t.wrap)], homePreview)," in text, text)
    }

    @Test fun maskKeepsLengthAndLines() {
        val src = "a // c\n'str' \"x\" r'y' '''m\nn''' /* b */ z"
        val m = DartScanner.mask(src)
        assertEquals(src.length, m.length)
        assertEquals(src.count { it == '\n' }, m.count { it == '\n' })
        assertFalse(m.contains("str") || m.contains("c") && m.indexOf('c') < 7)
        assertTrue(m.trimEnd().endsWith("z"))
    }
}
