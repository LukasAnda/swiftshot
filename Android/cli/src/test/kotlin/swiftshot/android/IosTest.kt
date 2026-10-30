package swiftshot.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class IosTest {
    private fun preview(
        function: String, file: String = "Ui.kt", pkg: String = "com.example", name: String = function,
        private: Boolean = false, provider: String? = null, limit: Int = Int.MAX_VALUE,
    ) = Preview(
        composable = "$pkg.${file.removeSuffix(".kt")}Kt.$function", function = function, name = name,
        isPrivate = private, sourceFile = file, provider = provider, providerLimit = limit,
    )

    // Private previews: made internal, renamed apart when they clash

    @Test fun namesAreTheFunctionsUnlessPrivateOnesClash() {
        val public = preview("Welcome")
        val alone = preview("Stats", private = true)
        val names = Ios.callNames(listOf(public, alone))
        assertEquals(mapOf(public to "Welcome", alone to "Stats"), names)
    }

    @Test fun privateClashesInOnePackageAreRenamed() {
        val a = preview("CardPreview", file = "A.kt", private = true)
        val b = preview("CardPreview", file = "B.kt", private = true)
        val other = preview("CardPreview", file = "C.kt", pkg = "com.other", private = true)
        val names = Ios.callNames(listOf(a, b, other))
        assertTrue(names[a]!!.matches(Regex("CardPreview__swiftshot[0-9a-f]{6}")), names[a])
        assertTrue(names[b]!!.matches(Regex("CardPreview__swiftshot[0-9a-f]{6}")), names[b])
        assertNotEquals(names[a], names[b])
        // Another package has its own namespace.
        assertEquals("CardPreview", names[other])
        // Stable from run to run (incremental compilation).
        assertEquals(names, Ios.callNames(listOf(a, b, other)))
    }

    @Test fun publicAndPrivateWithOneNameDoNotClash() {
        // Only private previews are copied into internal ones; a public one is called as it is.
        val pub = preview("Card", file = "A.kt")
        val priv = preview("Card", file = "B.kt", private = true)
        assertEquals(mapOf(pub to "Card", priv to "Card"), Ios.callNames(listOf(pub, priv)))
    }

    @Test fun privateWithoutSourceFileIsLeftAlone() {
        val a = preview("Card", file = "A.kt", private = true)
        val b = preview("Card", file = "B.kt", private = true).copy(sourceFile = null)
        assertEquals(mapOf(a to "Card", b to "Card"), Ios.callNames(listOf(a, b)))
    }

    @Test fun rewriteMakesPrivatePreviewsInternal() {
        val p = preview("WelcomePreview", private = true)
        val source = """
            package com.example

            @Preview
            @Composable
            private fun WelcomePreview() { Welcome() }

            private fun WelcomePreviewHelper() = 1
            private val WelcomePreview2 = 2
        """.trimIndent()
        val out = Ios.rewrite(source, listOf(p), Ios.callNames(listOf(p)))
        assertEquals(source.replace("private fun WelcomePreview()", "internal fun WelcomePreview()"), out)
    }

    @Test fun rewriteKeepsWhitespaceAndModifiers() {
        val p = preview("Dark", private = true)
        val source = "package com.example\n\n@Preview\nprivate  fun\tDark() {}\n"
        assertEquals("package com.example\n\n@Preview\ninternal  fun\tDark() {}\n", Ios.rewrite(source, listOf(p), mapOf(p to "Dark")))
    }

    @Test fun rewriteRenamesClashesAndTheirCalls() {
        val a = preview("CardPreview", file = "A.kt", private = true)
        val b = preview("CardPreview", file = "B.kt", private = true)
        val names = Ios.callNames(listOf(a, b))
        val source = """
            package com.example

            @Preview @Composable private fun CardPreview() { Card() }
            @Preview @Composable private fun CardPreviewDark() { CardPreview () }
        """.trimIndent()
        val n = names[a]!!
        assertEquals(
            """
            package com.example

            @Preview @Composable internal fun $n() { Card() }
            @Preview @Composable private fun CardPreviewDark() { $n() }
            """.trimIndent(),
            Ios.rewrite(source, listOf(a), names),
        )
    }

    @Test fun rewriteSkipsPreviewsOfAnotherPackage() {
        // A file named like the preview's, in another package (another source set).
        val p = preview("WelcomePreview", pkg = "com.example.ui", private = true)
        val source = "package com.example.other\n\nprivate fun WelcomePreview() {}\n"
        assertEquals(source, Ios.rewrite(source, listOf(p), Ios.callNames(listOf(p))))
        // Without a package statement, only previews in the root package would match.
        val bare = "private fun WelcomePreview() {}\n"
        assertEquals(bare, Ios.rewrite(bare, listOf(p), Ios.callNames(listOf(p))))
    }

    @Test fun rewriteLeavesPublicFunctionsAlone() {
        val p = preview("Welcome", private = true)
        val source = "package com.example\n\nfun Welcome() {}\ninternal fun Other() {}\n"
        assertEquals(source, Ios.rewrite(source, listOf(p), mapOf(p to "Welcome")))
    }

    // SwiftshotPreviews.kt

    @Test fun registryHasComposeHooks() {
        val text = Ios.registry(emptyList(), emptyMap())
        val lines = text.lines()
        assertTrue("package swiftshot.generated" in lines)
        assertTrue("@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)" in lines)
        assertTrue("import androidx.compose.ui.window.ComposeUIViewController" in lines)
        assertTrue("import platform.UIKit.UIViewController" in lines)
        assertTrue("fun swiftshotComposeMark() { swiftshotEarlier = androidx.compose.runtime.Recomposer.runningRecomposers.value.toSet() }" in lines)
        assertTrue(
            "fun swiftshotComposeBusy(): Boolean = androidx.compose.runtime.Recomposer.runningRecomposers.value.any { it !in swiftshotEarlier && it.hasPendingWork }" in lines,
        )
        assertFalse(text.contains("fun swiftshotPreview"))
    }

    @Test fun registryWrapsEachPreview() {
        val welcome = preview("WelcomePreview")
        val names = preview("Greeting", file = "Names.kt", pkg = "com.example.ui", private = true, provider = "com.example.ui.NamesProvider")
        val stats = preview("Stats", file = "Stats.kt")
        val previews = listOf(welcome, names, stats)
        val text = Ios.registry(previews, Ios.callNames(previews))
        val config = "configure = { enforceStrictPlistSanityCheck = false; parallelRendering = false }"
        val wrappers = text.lines().dropWhile { !it.startsWith("fun swiftshotPreview") }.filter { it.isNotEmpty() }
        assertEquals(
            listOf(
                "fun swiftshotPreview0(): UIViewController = ComposeUIViewController($config) { com.example.WelcomePreview() }",
                "fun swiftshotPreview1(index: Int): UIViewController = ComposeUIViewController($config) {",
                "    com.example.ui.Greeting(com.example.ui.NamesProvider().values.elementAt(index))",
                "}",
                "fun swiftshotPreview2(): UIViewController = ComposeUIViewController($config) { com.example.Stats() }",
            ),
            wrappers,
        )
        assertTrue(text.endsWith("}\n"))
    }

    @Test fun registryCallsRenamedPreviews() {
        val a = preview("CardPreview", file = "A.kt", private = true)
        val b = preview("CardPreview", file = "B.kt", private = true)
        val names = Ios.callNames(listOf(a, b))
        val text = Ios.registry(listOf(a, b), names)
        assertTrue(text.contains("{ com.example.${names[a]}() }"))
        assertTrue(text.contains("{ com.example.${names[b]}() }"))
    }

    // The host app's main.swift

    private fun previewLines(swift: String) = swift.lines().filter { it.startsWith("#Preview") }

    @Test fun hostMainHasOnePreviewEach() {
        val swift = Ios.hostMain(listOf(preview("Welcome"), preview("Stats", name = "Stats - dark")), emptyMap(), emptyMap())
        assertEquals(
            listOf(
                "#Preview(\"Welcome\") { SwiftshotPreviewsKt.swiftshotPreview0() }",
                "#Preview(\"Stats - dark\") { SwiftshotPreviewsKt.swiftshotPreview1() }",
            ),
            previewLines(swift),
        )
        val lines = swift.lines()
        assertEquals("import SwiftUI", lines.first())
        assertTrue("import SwiftshotHost" in lines)
        assertTrue("@_cdecl(\"swiftshot_host_main\") public func swiftshotHostMain() {}" in lines)
        assertTrue("@_cdecl(\"swiftshot_compose_busy\") public func swiftshotComposeBusy() -> Int32 { SwiftshotPreviewsKt.swiftshotComposeBusy() ? 1 : 0 }" in lines)
        assertTrue("@_cdecl(\"swiftshot_compose_mark\") public func swiftshotComposeMark() { SwiftshotPreviewsKt.swiftshotComposeMark() }" in lines)
        assertEquals("SwiftshotHostApp.main()", lines.last { it.isNotEmpty() })
        // The agent starts before the app's main runs.
        assertTrue(swift.indexOf("SwiftshotAgentStartNow") < swift.indexOf("SwiftshotHostApp.main()"))
    }

    @Test fun hostMainFixedLayoutFromMeasuredSizes() {
        val button = preview("ButtonPreview", name = "Button")
        val screen = preview("ScreenPreview", name = "Screen")
        val swift = Ios.hostMain(listOf(button, screen), emptyMap(), mapOf("${button.composable}|Button" to (120 to 48)))
        assertEquals(
            listOf(
                "#Preview(\"Button\", traits: .fixedLayout(width: 120, height: 48)) { SwiftshotPreviewsKt.swiftshotPreview0() }",
                "#Preview(\"Screen\") { SwiftshotPreviewsKt.swiftshotPreview1() }",
            ),
            previewLines(swift),
        )
    }

    @Test fun hostMainExpandsProviders() {
        val names = preview("Greeting", name = "Greeting", provider = "com.example.NamesProvider")
        val key = "${names.composable}|Greeting"
        assertEquals(
            listOf(
                "#Preview(\"Greeting_1\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 0) }",
                "#Preview(\"Greeting_2\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 1) }",
                "#Preview(\"Greeting_3\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 2) }",
            ),
            previewLines(Ios.hostMain(listOf(names), mapOf(key to 3), emptyMap())),
        )
        // The provider's limit caps the values; with no count from the JVM there is one.
        assertEquals(2, previewLines(Ios.hostMain(listOf(names.copy(providerLimit = 2)), mapOf(key to 3), emptyMap())).size)
        assertEquals(
            listOf("#Preview(\"Greeting_1\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 0) }"),
            previewLines(Ios.hostMain(listOf(names), emptyMap(), emptyMap())),
        )
        // Each value gets the size the preview measured.
        assertEquals(
            listOf(
                "#Preview(\"Greeting_1\", traits: .fixedLayout(width: 200, height: 40)) { SwiftshotPreviewsKt.swiftshotPreview0(index: 0) }",
                "#Preview(\"Greeting_2\", traits: .fixedLayout(width: 200, height: 40)) { SwiftshotPreviewsKt.swiftshotPreview0(index: 1) }",
            ),
            previewLines(Ios.hostMain(listOf(names), mapOf(key to 2), mapOf(key to (200 to 40)))),
        )
    }

    @Test fun hostMainCountsAreKeyedByComposableAndName() {
        val a = preview("Greeting", name = "Greeting", provider = "P")
        val b = preview("Greeting", file = "Other.kt", name = "Greeting", provider = "P")
        val swift = Ios.hostMain(listOf(a, b), mapOf("${a.composable}|Greeting" to 2, "${b.composable}|Greeting" to 1), emptyMap())
        assertEquals(
            listOf(
                "#Preview(\"Greeting_1\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 0) }",
                "#Preview(\"Greeting_2\") { SwiftshotPreviewsKt.swiftshotPreview0(index: 1) }",
                "#Preview(\"Greeting_1\") { SwiftshotPreviewsKt.swiftshotPreview1(index: 0) }",
            ),
            previewLines(swift),
        )
    }

    @Test fun hostMainEscapesNames() {
        val p = preview("Quote", name = "Say \"hi\" \\ bye")
        assertEquals(
            listOf("#Preview(\"Say \\\"hi\\\" \\\\ bye\") { SwiftshotPreviewsKt.swiftshotPreview0() }"),
            previewLines(Ios.hostMain(listOf(p), emptyMap(), emptyMap())),
        )
    }

    // The iOS renderer's report (the Swift binary): its error ids and its own fingerprint

    @Test fun iosPartReadsTheRenderersErrorIdsAndFingerprint() {
        val report = swiftshot.android.shared.Json.parse(
            """{"errors": [{"id": "en-US/iPhone 17 Pro-Home", "message": "no image from the render server"}, {"message": "iOS 26.0 · launch failed"}],
               "fingerprint": {"ios": {"host": "macos-x64", "mode": "no-boot", "platform": "ios", "runtimes": {"26.0": "23A343"}, "swiftshot": "1.0.0", "xcode": "17A400"}},
               "screenshots": []}""",
        ) as Map<*, *>
        // A second iOS module's run, on another runtime too.
        val second = mapOf("fingerprint" to mapOf("ios" to mapOf("host" to "macos-x64", "mode" to "no-boot", "platform" to "ios",
            "runtimes" to mapOf("26.5" to "23F77"), "swiftshot" to "1.0.0", "xcode" to "17A400")))
        val part = Runner.IosPart(emptyList(), listOf(report, second))
        assertEquals(
            listOf(mapOf<String, Any?>("id" to "en-US/iPhone 17 Pro-Home", "message" to "no image from the render server"), mapOf<String, Any?>("message" to "iOS 26.0 · launch failed")),
            part.errors(),
        )
        val fp = part.fingerprint()!!
        assertEquals(mapOf("platform" to "ios", "mode" to "no-boot", "runtimes" to mapOf("26.0" to "23A343", "26.5" to "23F77"), "swiftshot" to "1.0.0", "xcode" to "17A400", "host" to Fingerprints.host), fp)
        // Nothing reported (no iOS run rendered): no iOS fingerprint, rather than one that lacks Xcode and the runtime.
        assertNull(Runner.IosPart(emptyList(), listOf(mapOf("screenshots" to emptyList<Any>()))).fingerprint())
    }
}
