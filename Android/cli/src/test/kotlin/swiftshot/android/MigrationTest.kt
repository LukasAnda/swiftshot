package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MigrationTest {
    private val dir: File = Files.createTempDirectory("swiftshot-migration").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private fun write(path: String, text: String) = File(dir, path).apply { parentFile.mkdirs(); writeText(text.trimIndent() + "\n") }

    private fun init(): Map<*, *> {
        Init.run(Options.parse(listOf("--project-dir", dir.path, "init")), force = true, log = Log(false))
        return Json.parse(File(dir, "swiftshot.json").readText()) as Map<*, *>
    }

    private fun options() = Options.parse(listOf("--project-dir", dir.path))
    private fun report() = File(dir, "swiftshot-migration.md").readText()
    private fun lines() = Migration.run(dir)!!.report

    private fun settings(vararg modules: String) = write("settings.gradle.kts", modules.joinToString(", ", "include(", ")") { "\"$it\"" })
    private fun paparazzi(module: String = "app") = write("$module/build.gradle.kts", """plugins { id("com.android.library"); id("app.cash.paparazzi") }""")
    private fun roborazzi(module: String = "app", extra: String = "") = write("$module/build.gradle.kts", "plugins { id(\"com.android.library\"); id(\"io.github.takahirom.roborazzi\") }\n$extra")
    private fun strings(module: String = "app", vararg qualifiers: String) =
        (listOf("") + qualifiers).forEach { write("$module/src/main/res/values$it/strings.xml", "<resources/>") }

    private fun paparazziTest(name: String, config: String, body: String, module: String = "app", pkg: String = "com.example") =
        write("$module/src/test/kotlin/${pkg.replace('.', '/')}/$name.kt", """
            package $pkg
            class $name {
                @get:Rule val paparazzi = Paparazzi(deviceConfig = $config)
                @Test fun shot() { paparazzi.snapshot { $body } }
            }
        """)

    /** What the init script would report for a module. */
    private fun module(path: String = ":app", wear: Boolean = false) = Module(
        mapOf(
            "module" to path, "packageName" to "com.example", "wear" to wear,
            "classDirs" to listOf("$dir/classes"), "classpath" to emptyList<String>(), "components" to emptyList<String>(),
            "layoutlibRuntime" to "$dir/runtime.jar", "layoutlibResources" to "$dir/resources.jar", "compileSdk" to 36L,
        ),
    )

    private fun preview(fqn: String, device: String = "", uiMode: Int = 0) =
        Preview(composable = fqn, function = fqn.substringAfterLast('.'), name = fqn.substringAfterLast('.'), device = device, uiMode = uiMode)

    private fun plan(vararg previews: Preview) = Runner(options(), Log(false)).plan(module(), previews.toList())

    private val tablet = TestDevices.deviceName(Screen(1600, 2560, 480))

    /** Two tested previews, one declaring a device its test replaces, and one no test calls. */
    private fun twoPreviews() {
        settings(":app")
        paparazzi()
        strings()
        write("app/src/main/kotlin/com/example/Ui.kt", """
            package com.example
            @Preview(device = "id:pixel_5") @Composable fun PhonePreview() {}
            @Preview(device = "id:pixel_9", uiMode = Configuration.UI_MODE_NIGHT_YES) @Composable fun TabletPreview() {}
            @Preview @Composable fun Untested() {}
        """)
        paparazziTest("PhoneTest", "DeviceConfig.PIXEL_5", "PhonePreview()")
        paparazziTest("TabletTest", "DeviceConfig(screenWidth = 2560, screenHeight = 1600, density = Density.XXHIGH, nightMode = NightMode.NIGHT)", "TabletPreview()")
    }

    @Test fun perPreviewRules() {
        twoPreviews()
        val c = init()
        assertEquals(listOf(":app"), c["modules"])
        assertNull(c["devices"])
        assertNull(c["appearances"])
        assertEquals(listOf("en-US"), c["languages"])
        assertEquals(
            listOf(
                ScreenRule("com.example.UiKt.PhonePreview", devices = listOf("Pixel 5")),
                ScreenRule("com.example.UiKt.TabletPreview", devices = listOf(tablet), appearances = listOf("dark"), fontScales = listOf(1.0), overridePreview = true),
                ScreenRule("*", skip = true),
            ),
            options().screens,
        )
        // Renders what the tests render: the phone preview on Pixel 5 light, the tablet one on the test's tablet, dark.
        val shots = plan(preview("com.example.UiKt.PhonePreview", "id:pixel_5"), preview("com.example.UiKt.TabletPreview", "id:pixel_9", 0x21), preview("com.example.UiKt.Untested"))
        assertEquals(listOf("PhonePreview" to "Pixel 5", "TabletPreview" to "533x853dp"), shots.map { it.preview.function to it.device.name })
        assertEquals(listOf(false, true), shots.map { it.dark })
        assertEquals(listOf(1600, 2560), shots[1].device.let { listOf(it.width, it.height) })
    }

    @Test fun allPreviewsTest() {
        settings(":app")
        paparazzi()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview(device = \"id:pixel_9\") @Composable fun A() {}\n@Preview @Composable private fun B() {}")
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanAllPackages().includePrivatePreviews().getPreviews() }
                @get:Rule val paparazzi = Paparazzi()
                @Test fun snapshot() {
                    paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfigBuilder.build(preview.previewInfo))
                    paparazzi.snapshot { preview() }
                }
            }
        """)
        val c = init()
        assertEquals(listOf(ScreenRule("*")), options().screens)
        // Previews without a device: the test's fallback can't be read, so Swiftshot's defaults.
        assertEquals(Migration.defaultDevices, c["devices"])
        assertTrue(lines().any { it.contains("@Preview device") && it.contains("from @Preview") }, lines().joinToString("\n"))
    }

    @Test fun generatedTestsByPackageWithFallbackDevice() {
        settings(":app")
        roborazzi(extra = "roborazzi { generateComposePreviewRobolectricTests { enable = true; packages = listOf(\"com.example\") } }")
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview(device = \"id:pixel_9\") @Composable fun A() {}\n@Preview @Composable fun B() {}\n@Preview @Composable private fun Hidden() {}")
        write("app/src/main/kotlin/org/other/Other.kt", "package org.other\n@Preview @Composable fun Elsewhere() {}")
        val c = init()
        val pixel4a = TestDevices.deviceName((TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel4a").first as DeviceSource.Read).screen, "Pixel4a")
        assertEquals(
            listOf(ScreenRule("com.example.UiKt.Hidden", skip = true), ScreenRule("com.example.*", devices = listOf(pixel4a)), ScreenRule("*", skip = true)),
            options().screens,
        )
        assertNull(c["devices"])
        // Previews with their own device keep it; the rest render on the generated tests' device.
        val shots = plan(preview("com.example.UiKt.A", "id:pixel_9"), preview("com.example.UiKt.B"), preview("com.example.UiKt.Hidden"), preview("org.other.OtherKt.Elsewhere"))
        assertEquals(listOf("A" to "Pixel 9", "B" to pixel4a), shots.map { it.preview.function to it.device.name })
        assertTrue(report().contains("com.example.UiKt.Hidden"))
        assertTrue(report().contains("org.other.OtherKt.Elsewhere"))
    }

    @Test fun untestedPreviewsSkippedAndListed() {
        twoPreviews()
        init()
        assertTrue(plan(preview("com.example.UiKt.Untested")).isEmpty())
        val r = lines()
        val at = r.indexOf("Not tested, skipped:")
        assertTrue(at >= 0, r.joinToString("\n"))
        assertEquals("  com.example.UiKt.Untested (:app)", r[at + 1])
        assertFalse(r.drop(at + 1).takeWhile { it.startsWith("  ") }.any { it.contains("PhonePreview") })
    }

    @Test fun bothTools() {
        settings(":a", ":b")
        paparazzi("a")
        roborazzi("b")
        write("a/src/main/kotlin/com/a/Ui.kt", "package com.a\n@Preview @Composable fun APreview() {}")
        write("b/src/main/kotlin/com/b/Ui.kt", "package com.b\n@Preview @Composable fun BPreview() {}")
        paparazziTest("ATest", "DeviceConfig.PIXEL_5", "APreview()", module = "a", pkg = "com.a")
        write("b/src/test/kotlin/com/b/BTest.kt", """
            package com.b
            @RunWith(AndroidJUnit4::class)
            @Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)
            class BTest {
                @get:Rule val composeTestRule = createComposeRule()
                @Test fun b() {
                    composeTestRule.setContent { BPreview() }
                    composeTestRule.onRoot().captureRoboImage()
                }
            }
        """)
        val c = init()
        assertEquals(listOf(":a", ":b"), c["modules"])
        val robo = TestDevices.deviceName((TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel5").first as DeviceSource.Read).screen, "Pixel5")
        assertEquals(
            listOf(ScreenRule("com.a.UiKt.APreview", devices = listOf("Pixel 5")), ScreenRule("com.b.UiKt.BPreview", devices = listOf(robo)), ScreenRule("*", skip = true)),
            options().screens,
        )
    }

    @Test fun moduleWithoutPreviews() {
        settings(":a", ":c")
        paparazzi("a")
        paparazzi("c")
        write("a/src/main/kotlin/com/a/Ui.kt", "package com.a\n@Preview @Composable fun APreview() {}")
        paparazziTest("ATest", "DeviceConfig.PIXEL_5", "APreview()", module = "a", pkg = "com.a")
        write("c/src/main/kotlin/com/c/Screen.kt", "package com.c\n@Composable fun CheckoutScreen(state: Int) {}")
        paparazziTest("CTest", "DeviceConfig.PIXEL_5", "CheckoutScreen(1)", module = "c", pkg = "com.c")
        assertEquals(listOf(":a"), init()["modules"])
        val r = lines()
        assertTrue(r.any { it.startsWith("  :c ") && it.contains("not rendered") }, r.joinToString("\n"))
        assertTrue(r.contains("  c/src/test/kotlin/com/c/CTest.kt:4  CheckoutScreen(1) has no @Preview — add a @Preview with the same arguments to include it"), r.joinToString("\n"))
    }

    @Test fun languagesAppearancesScales() {
        settings(":app")
        paparazzi()
        strings("app", "-de", "-night")
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}\n@Preview @Composable fun Q() {}")
        paparazziTest("PTest", "DeviceConfig.PIXEL_5.copy(locale = \"de\", nightMode = NightMode.NIGHT, fontScale = 1.5f)", "P()")
        paparazziTest("PPlainTest", "DeviceConfig.PIXEL_5", "P()")
        paparazziTest("QTest", "DeviceConfig.PIXEL_5", "Q()")
        init()
        assertEquals(
            listOf(
                ScreenRule("com.example.UiKt.P", devices = listOf("Pixel 5"), languages = listOf("en-US", "de"), appearances = listOf("light", "dark"), fontScales = listOf(1.0, 1.5)),
                ScreenRule("com.example.UiKt.Q", devices = listOf("Pixel 5")),
                ScreenRule("*", skip = true),
            ),
            options().screens,
        )
        assertEquals(listOf("en-US", "de"), options().languages)
    }

    @Test fun noLocaleOrNightInTests() {
        settings(":app")
        paparazzi()
        strings("app", "-de")
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}")
        paparazziTest("PTest", "DeviceConfig.PIXEL_5", "P()")
        val c = init()
        assertEquals(listOf(ScreenRule("com.example.UiKt.P", devices = listOf("Pixel 5")), ScreenRule("*", skip = true)), options().screens)
        // Languages from string resources, as without the tools; light only, what the tests render.
        assertEquals(listOf("en-US", "de"), c["languages"])
        assertEquals(listOf("light"), options().appearances)
        val r = lines()
        assertTrue(r.any { it.contains("languages: en-US, de") && it.contains("string resources") }, r.joinToString("\n"))
        assertTrue(r.any { it.contains("appearances: light") && it.contains("no test uses night mode") }, r.joinToString("\n"))
    }

    @Test fun roundDevice() {
        settings(":app")
        paparazzi()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun Tile() {}")
        paparazziTest("TileTest", "DeviceConfig(screenWidth = 400, screenHeight = 400, density = Density.XHIGH, screenRound = ScreenRound.ROUND)", "Tile()")
        val c = init()
        val round = TestDevices.deviceName(Screen(400, 400, 320, round = true))
        assertTrue(round.startsWith("spec:") && round.contains("isRound=true"), round)
        assertEquals(ScreenRule("com.example.UiKt.Tile", devices = listOf(round)), options().screens.first())
        assertEquals(listOf(round), c["watch_devices"])
        val s = plan(preview("com.example.UiKt.Tile")).single()
        assertTrue(s.dark)
        assertEquals("watch", s.device.type)
        assertEquals("200x200dp-Tile.png", s.file.name)
    }

    @Test fun desktopIos() {
        settings(":shared")
        write("shared/build.gradle.kts", """plugins { kotlin("multiplatform"); id("io.github.takahirom.roborazzi") }
            kotlin { jvm("desktop"); iosSimulatorArm64(); androidLibrary { } }""")
        write("shared/src/commonMain/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun Home() {}")
        for (ss in listOf("desktopTest", "iosTest")) write("shared/src/$ss/kotlin/com/example/T.kt", """
            package com.example
            class T {
                @Test fun a() = runComposeUiTest {
                    setContent { Home() }
                    onRoot().captureRoboImage()
                }
            }
        """)
        val c = init()
        assertEquals(listOf(":shared"), c["modules"])
        assertEquals(Devices.defaultDesktop, c["desktop_devices"])
        assertEquals(Ios.defaultDevices, c["ios_devices"])
        assertFalse(lines().any { it.contains("unresolved") }, lines().joinToString("\n"))
    }

    @Test fun reportLines() {
        settings(":app")
        paparazzi()
        strings()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}\n@Composable fun CheckoutScreen(state: Int) {}")
        paparazziTest("PTest", "DeviceConfig.PIXEL_5", "P()")
        write("app/src/test/kotlin/com/example/DefaultTest.kt", """
            package com.example
            class DefaultTest {
                @get:Rule val paparazzi = Paparazzi()
                @Test fun shot() { paparazzi.snapshot { P() } }
                @Test fun checkout() { paparazzi.snapshot { CheckoutScreen(state) } }
            }
        """)
        val r = lines()
        val text = r.joinToString("\n")
        val nexus5 = TestDevices.deviceName(TestDevices.paparazziDefault())
        val expected = listOf(
            "Modules:",
            "  :app  Paparazzi (plugin app.cash.paparazzi)",
            "Devices:",
            "  DeviceConfig.PIXEL_5 → Pixel 5",
            "  Paparazzi default → $nexus5 (tool default)",
            "Settings:",
            "  languages: en-US (string resources; no test sets a locale)",
            "  appearances: light (no test uses night mode)",
            "  font scales: 1 (no test sets one)",
            "Not covered:",
            "  app/src/test/kotlin/com/example/DefaultTest.kt:5  CheckoutScreen(state) has no @Preview — add a @Preview with the same arguments to include it",
            "2 of 3 snapshot tests are covered by previews; 1 isn't (listed above)",
        )
        assertEquals(expected, r, text)
        val m = Migration.run(dir)!!
        assertEquals(2, m.covered)
        assertEquals(3, m.total)
    }

    @Test fun markdownWritten() {
        twoPreviews()
        paparazziTest("CTest", "DeviceConfig.PIXEL_5", "CheckoutScreen(1)")
        init()
        val md = report()
        for (s in listOf("# Swiftshot migration", "## Modules", "## Devices", "## Settings", "## Not covered", "## Not tested, skipped")) assertTrue(md.contains(s), md)
        assertTrue(md.contains("- app/src/test/kotlin/com/example/CTest.kt:4  CheckoutScreen(1) has no @Preview"), md)
        assertTrue(md.contains("2 of 3 snapshot tests are covered by previews; 1 isn't (listed above)"), md)
        File(dir, "app/src/test/kotlin/com/example/CTest.kt").delete()
        init()
        assertTrue(report().contains("2 of 2 snapshot tests are covered by previews"), report())
        assertFalse(report().contains("CheckoutScreen"))
    }

    @Test fun forceStillRequired() {
        twoPreviews()
        init()
        val e = runCatching { Init.run(Options.parse(listOf("--project-dir", dir.path, "init")), force = false, log = Log(false)) }.exceptionOrNull()
        assertTrue(e is CliError, e.toString())
    }

    @Test fun noToolsUnchanged() {
        settings(":app")
        write("app/build.gradle.kts", """plugins { id("com.android.application") }""")
        write("app/src/main/kotlin/Ui.kt", "@Preview @Composable fun Home() {}")
        init()
        assertFalse(File(dir, "swiftshot-migration.md").exists())
        assertNull(Migration.run(dir))
    }

    @Test fun unresolvedDeviceFallsBack() {
        settings(":app")
        paparazzi()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}\n@Preview @Composable fun Q() {}")
        paparazziTest("PTest", "deviceFor(\"phone\")", "P()")
        val c = init()
        assertEquals(Migration.defaultDevices, c["devices"])
        assertEquals(listOf(ScreenRule("com.example.UiKt.P"), ScreenRule("*", skip = true)), options().screens)
        val r = lines()
        assertTrue(r.any { it.contains("deviceFor(\"phone\") → unresolved") && it.contains("PTest.kt:4") }, r.joinToString("\n"))
        assertTrue(r.any { it.contains("Swiftshot's default devices") }, r.joinToString("\n"))
        // With one device read, unresolved tests render on the devices that were read.
        paparazziTest("QTest", "DeviceConfig.PIXEL_5", "Q()")
        assertEquals(listOf("Pixel 5"), init()["devices"])
        assertFalse(lines().any { it.contains("Swiftshot's default devices") })
    }
}
