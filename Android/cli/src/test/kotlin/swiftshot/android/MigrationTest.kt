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
                ScreenRule("com.example.UiKt.Q", devices = listOf("Pixel 5"), languages = listOf("en-US")),
                ScreenRule("*", skip = true),
            ),
            options().screens,
        )
        assertEquals(listOf("en-US"), options().languages)
        val r = lines()
        assertTrue(r.contains("  languages: en-US, de (from tests; en-US where a test sets none)"), r.joinToString("\n"))
        // P's two tests take 2 of the 8 combinations its rule renders.
        val extra = r.single { it.startsWith("  com.example.UiKt.P: also renders ") }
        assertEquals(6, extra.removePrefix("  com.example.UiKt.P: also renders ").removeSuffix(" (no test takes them)").split("; ").size, extra)
        assertTrue(extra.contains("Pixel 5 / de / light / 1x"), extra)
        assertFalse(r.any { it.startsWith("  com.example.UiKt.Q: also") })
    }

    @Test fun noLocaleOrNightInTests() {
        settings(":app")
        paparazzi()
        strings("app", "-de")
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}")
        paparazziTest("PTest", "DeviceConfig.PIXEL_5", "P()")
        val c = init()
        assertEquals(listOf(ScreenRule("com.example.UiKt.P", devices = listOf("Pixel 5")), ScreenRule("*", skip = true)), options().screens)
        // The locale the tests render; the app's other languages are listed. Light only, what the tests render.
        assertEquals(listOf("en-US"), c["languages"])
        assertEquals(listOf("light"), options().appearances)
        val r = lines()
        assertTrue(r.contains("  languages: en-US (no test sets a locale)"), r.joinToString("\n"))
        assertTrue(r.contains("  string resources also have de: add them to languages to render them"), r.joinToString("\n"))
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
        // Only desktop and iOS tests: Android isn't rendered.
        assertEquals(listOf("desktop", "ios"), c["platforms"])
        assertTrue(lines().contains("  desktop, ios (from tests; the project also has android)"), lines().joinToString("\n"))
        // An Android test on another preview: every platform, and Home is listed as rendering on more than its tests.
        write("shared/src/commonMain/kotlin/com/example/Other.kt", "package com.example\n@Preview @Composable fun Other() {}")
        write("shared/src/androidUnitTest/kotlin/com/example/A.kt", """
            package com.example
            class A {
                @Test fun a() = runComposeUiTest {
                    setContent { Other() }
                    onRoot().captureRoboImage()
                }
            }
        """)
        assertNull(init()["platforms"])
        val r = lines()
        assertTrue(r.contains("  com.example.UiKt.Home: tested on desktop, ios; also renders on android"), r.joinToString("\n"))
        assertTrue(r.contains("  com.example.OtherKt.Other: tested on android; also renders on desktop, ios"), r.joinToString("\n"))
    }

    @Test fun scannerOnAFixedDeviceOverridesPreviews() {
        settings(":app")
        paparazzi()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview(device = \"id:pixel_9\", uiMode = Configuration.UI_MODE_NIGHT_YES) @Composable fun A() {}\n@Preview @Composable fun B() {}")
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews() }
                @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)
                @Test fun snapshot() { paparazzi.snapshot { preview() } }
            }
        """)
        init()
        assertEquals(
            listOf(
                ScreenRule("com.example.UiKt.A", devices = listOf("Pixel 5"), appearances = listOf("light"), fontScales = listOf(1.0), overridePreview = true),
                ScreenRule("com.example.*", devices = listOf("Pixel 5")),
                ScreenRule("*", skip = true),
            ),
            options().screens,
        )
        val shots = plan(preview("com.example.UiKt.A", "id:pixel_9", 0x21), preview("com.example.UiKt.B"))
        assertEquals(listOf("A" to "Pixel 5", "B" to "Pixel 5"), shots.map { it.preview.function to it.device.name })
        assertEquals(listOf(false, false), shots.map { it.dark })
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
            "  languages: en-US (no test sets a locale)",
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

    /** Previews with their own uiMode, locale and font scale; a Roborazzi scanner test and a Paparazzi one on the same previews. */
    private fun ownSettingsPreviews(paparazziMode: String = "") {
        settings(":app", ":robo", ":papa")
        write("app/build.gradle.kts", """plugins { id("com.android.library") }""")
        strings("app", "-ar")
        write("app/src/main/kotlin/com/example/Ui.kt", """
            package com.example
            @Preview(fontScale = 1.3f) @Preview(uiMode = Configuration.UI_MODE_NIGHT_YES) @Preview(locale = "ar") @Composable fun Screen() {}
        """)
        roborazzi("robo", "dependencies { testImplementation(project(\":app\")) }")
        write("robo/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews() }
                @Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)
                @Test fun snapshot() {
                    captureRoboImage(roborazziComposeOptions = RoborazziComposeOptions {
                        uiMode(preview.previewInfo.uiMode); fontScale(preview.previewInfo.fontScale); locale(preview.previewInfo.locale)
                    }) { preview() }
                }
            }
        """)
        if (paparazziMode.isEmpty()) return
        paparazzi("papa")
        write("papa/build.gradle.kts", "plugins { id(\"com.android.library\"); id(\"app.cash.paparazzi\") }\ndependencies { implementation(project(\":app\")) }")
        write("papa/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PaparazziPreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews() }
                @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_4, renderingMode = SessionParams.RenderingMode.$paparazziMode)
                @Test fun snapshot() { paparazzi.snapshot { preview() } }
            }
        """)
    }

    // flavorshub: the test takes each preview's own uiMode, font scale and locale, so the rule leaves them to the preview.
    @Test fun settingsFromEachPreview() {
        ownSettingsPreviews()
        val c = init()
        val pixel5 = TestDevices.deviceName((TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel5").first as DeviceSource.Read).screen, "Pixel5")
        assertEquals(listOf(ScreenRule("com.example.*", devices = listOf(pixel5)), ScreenRule("*", skip = true)), options().screens)
        assertNull(c["appearances"])
        val r = lines()
        assertTrue(r.contains("  each preview's own locale, uiMode, fontScale (from @Preview, as the tests apply previewInfo)"), r.joinToString("\n"))
        assertFalse(r.any { it.contains("override_preview") || it.contains("Extra combinations") }, r.joinToString("\n"))
        // Renders what the test renders: one shot per @Preview, each with its own setting.
        val shots = Runner(options(), Log(false)).plan(module(), listOf(
            Preview(composable = "com.example.UiKt.Screen", function = "Screen", name = "Screen", fontScale = 1.3),
            Preview(composable = "com.example.UiKt.Screen", function = "Screen", name = "Screen", uiMode = 0x21),
            Preview(composable = "com.example.UiKt.Screen", function = "Screen", name = "Screen", locale = "ar"),
        ))
        assertEquals(listOf(Triple("en-US", false, 1.3), Triple("en-US", true, 1.0), Triple("ar", false, 1.0)), shots.map { Triple(it.language, it.dark, it.fontScale) })
        assertEquals(setOf(pixel5), shots.map { it.device.name }.toSet())
    }

    // flavorshub: a second test on the same previews whose device can't be read renders on the first test's device.
    @Test fun unresolvedTestWhosePreviewsGetAnotherTestsDevice() {
        ownSettingsPreviews(paparazziMode = "SHRINK")
        init()
        val r = lines()
        assertTrue(r.any { it.contains("renderingMode=SHRINK → unresolved") && it.endsWith("its previews render on the devices other tests give them") }, r.joinToString("\n"))
        // What it renders is unknown, so it adds no extra combinations.
        assertFalse(r.any { it.contains("Extra combinations") }, r.joinToString("\n"))
    }

    @Test fun nothingCovered() {
        settings(":app")
        roborazzi()
        strings()
        write("app/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun P() {}")
        write("app/src/test/kotlin/com/example/ScreenTest.kt", """
            package com.example
            class ScreenTest {
                @Test fun a() { composeTestRule.setContent { Screen(1) }; composeTestRule.onRoot().captureRoboImage() }
            }
        """)
        init()
        val r = lines()
        assertTrue(r.containsAll(listOf("Devices:", "  none (no test renders a preview)")), r.joinToString("\n"))
        assertFalse(r.any { it.contains("string resources also have") }, r.joinToString("\n"))
    }
}

