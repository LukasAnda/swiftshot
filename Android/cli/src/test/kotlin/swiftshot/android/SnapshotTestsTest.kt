package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class SnapshotTestsTest {
    private val dir: File = Files.createTempDirectory("swiftshot-tests").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private fun write(path: String, text: String) = File(dir, path).apply { parentFile.mkdirs(); writeText(text.trimIndent()) }
    private fun module(path: String = ":app", tool: SnapshotTool = SnapshotTool.PAPARAZZI) =
        SnapshotModule(path, File(dir, path.removePrefix(":").replace(':', '/')), setOf(tool), listOf("imports"))
    private fun all(vararg paths: String) = paths.associateWith { File(dir, it.removePrefix(":").replace(':', '/')) }

    private val checkout = SourcePreview(":app", "com.example.UiKt.CheckoutPreview", "CheckoutPreview")
    private fun ui() = write("app/src/main/kotlin/com/example/Ui.kt", """
        package com.example
        import androidx.compose.runtime.Composable
        import androidx.compose.ui.tooling.preview.Preview
        @Preview
        @Composable
        fun CheckoutPreview(dark: Boolean = false) {}
        @Composable fun CheckoutScreen(state: Int) {}
    """)

    private fun scan(m: SnapshotModule = module()): List<SnapshotTest> =
        SnapshotTests.scan(listOf(m), SnapshotTests.previews(m, all(m.path)))
    private fun one(m: SnapshotModule = module()) = scan(m).also { assertEquals(1, it.size, it.toString()) }.single()
    private fun paparazziTest(body: String, rule: String = "Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)", imports: String = "") =
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", "package com.example\n$imports\nclass CheckoutTest {\n    @get:Rule val paparazzi = $rule\n    @Test fun checkout() {\n        $body\n    }\n}\n")

    private val pixel5 = DeviceSource.Read(TestDevices.paparazziPreset("PIXEL_5")!!, "DeviceConfig.PIXEL_5")
    private val roboPixel5 = TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel5").first

    @Test fun previewsFromSources() {
        ui()
        write("app/src/main/kotlin/com/example/Screens.kt", """
            @file:JvmName("AllScreens")
            package com.example
            @Preview(name = "x", device = "id:pixel_5") @Composable private fun Named() {}
            object Previews { @PreviewLightDark @Composable fun InObject() = Unit }
            @Composable fun NotAPreview() {}
            // @Preview @Composable fun Commented() {}
            val s = "@Preview @Composable fun InString() {}"
        """)
        assertEquals(
            listOf(
                SourcePreview(":app", "com.example.AllScreens.Named", "Named", isPrivate = true, own = listOf(PreviewOwn(device = "id:pixel_5"))),
                SourcePreview(":app", "com.example.Previews.InObject", "InObject", own = listOf(PreviewOwn(night = true))),
                checkout,
            ),
            SnapshotTests.previews(module(), all(":app")),
        )
    }

    @Test fun previewsFromDependenciesAndCustomMultipreviews() {
        write("settings.gradle.kts", "")
        write("app/build.gradle.kts", """dependencies { implementation(project(":feature:cart")); implementation(projects.core.ui) }""")
        write("core/ui/src/main/kotlin/com/example/ui/DevicePreviews.kt", """
            package com.example.ui
            @Preview(device = "id:pixel_5") @Preview(device = "id:pixel_tablet")
            annotation class DevicePreviews
        """)
        write("feature/cart/src/main/kotlin/com/example/cart/Cart.kt", """
            package com.example.cart
            import com.example.ui.DevicePreviews
            @DevicePreviews @Composable fun CartPreview() {}
        """)
        write("other/src/main/kotlin/com/example/other/Other.kt", "package com.example.other\n@Preview @Composable fun OtherPreview() {}")
        val got = SnapshotTests.previews(module(), all(":app", ":feature:cart", ":core:ui", ":other"))
        assertEquals(listOf(SourcePreview(":feature:cart", "com.example.cart.CartKt.CartPreview", "CartPreview", own = listOf(PreviewOwn(device = "id:pixel_5"), PreviewOwn(device = "id:pixel_tablet")))), got)
    }

    @Test fun previewsOwnSettings() {
        write("app/src/main/kotlin/com/example/Ui.kt", """
            package com.example
            @Preview(name = "a", device = Devices.PIXEL_TABLET, locale = "de-rDE", uiMode = Configuration.UI_MODE_NIGHT_YES or Configuration.UI_MODE_TYPE_NORMAL, fontScale = 1.5f)
            @Composable fun All() {}
            @Preview(uiMode = 0x21) @Preview(uiMode = UI_MODE_NIGHT_NO) @Composable internal fun Modes() {}
            @Preview(device = DEVICE, fontScale = SCALE) @Composable fun Unread() {}
            @PreviewFontScale @Composable fun Scales() {}
            @Composable
            @Preview
            private fun Plain() {}
        """)
        val got = SnapshotTests.previews(module(), all(":app")).associate { it.function to (it.isPrivate to it.own) }
        assertEquals(false to listOf(PreviewOwn("id:pixel_tablet", "de-rDE", true, 1.5)), got["All"])
        assertEquals(false to listOf(PreviewOwn(night = true), PreviewOwn(night = false)), got["Modes"])
        assertEquals(false to listOf(PreviewOwn(unreadable = true)), got["Unread"])
        assertEquals(listOf(0.85, 1.0, 1.15, 1.3, 1.5, 1.8, 2.0), got["Scales"]!!.second.map { it.fontScale })
        assertEquals(true to emptyList<PreviewOwn>(), got["Plain"])
    }

    @Test fun paparazziCallsPreview() {
        ui()
        paparazziTest("paparazzi.snapshot { CheckoutPreview() }")
        val t = one()
        assertEquals(Target.Previews(listOf(checkout.fqn)), t.target)
        assertEquals(pixel5, t.device)
        assertEquals(SnapshotTool.PAPARAZZI, t.tool)
        assertEquals(TestSettings(), t.settings)
        assertEquals(6, t.line)
        assertEquals("test", t.sourceSet)
        assertEquals(":app", t.module)
        assertEquals(File(dir, "app/src/test/kotlin/com/example/CheckoutTest.kt"), t.file)
    }

    @Test fun deviceConfigSettingsAndConstants() {
        ui()
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", """
            package com.example
            private val TABLET = DeviceConfig(screenWidth = 2560, screenHeight = 1600, density = Density.XHIGH, nightMode = NightMode.NIGHT, locale = "de", fontScale = 1.5f)
            class CheckoutTest {
                @get:Rule val paparazzi = Paparazzi(theme = "x", deviceConfig = TABLET)
                @Test fun checkout() { paparazzi.snapshot(name = "a") { CheckoutPreview() } }
            }
        """)
        val t = one()
        assertEquals(TestSettings(locale = "de", night = true, fontScale = 1.5), t.settings)
        assertEquals(Screen(1600, 2560, 320), assertIs<DeviceSource.Read>(t.device).screen)
    }

    @Test fun unsafeUpdateConfigIsClosest() {
        ui()
        paparazziTest("paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.NEXUS_5)\n        paparazzi.snapshot { CheckoutPreview() }")
        assertEquals(DeviceSource.Read(TestDevices.paparazziPreset("NEXUS_5")!!, "DeviceConfig.NEXUS_5"), one().device)
    }

    @Test fun wrappedCallStillCovered() {
        ui()
        paparazziTest("paparazzi.snapshot { MyTheme { Box(Modifier.padding(8.dp)) { CheckoutPreview(dark = true) } } }")
        assertEquals(Target.Previews(listOf(checkout.fqn)), one().target)
    }

    @Test fun siblingContentIsUncovered() {
        ui()
        paparazziTest("paparazzi.snapshot { Column { CheckoutPreview(); Text(\"extra\") } }")
        assertIs<Target.Uncovered>(one().target)
    }

    @Test fun samePreviewNameTwoPackages() {
        write("app/src/main/kotlin/com/a/A.kt", "package com.a\n@Preview @Composable fun CheckoutPreview() {}")
        write("app/src/main/kotlin/com/b/B.kt", "package com.b\n@Preview @Composable fun CheckoutPreview() {}")
        paparazziTest("paparazzi.snapshot { CheckoutPreview() }", imports = "import com.b.CheckoutPreview")
        assertEquals(Target.Previews(listOf("com.b.BKt.CheckoutPreview")), one().target)
    }

    @Test fun samePackageStarImportAliasAndQualifiedCalls() {
        write("app/src/main/kotlin/com/a/A.kt", "package com.a\n@Preview @Composable fun APreview() {}\nobject Gallery { @Preview @Composable fun G() {} }")
        write("app/src/main/kotlin/com/b/B.kt", "package com.b\n@Preview @Composable fun BPreview() {}")
        write("app/src/main/kotlin/com/c/C.kt", "package com.c\n@Preview @Composable fun CPreview() {}")
        write("app/src/test/kotlin/com/c/T.kt", """
            package com.c
            import com.a.*
            import com.b.BPreview as Renamed
            class T {
                @get:Rule val paparazzi = Paparazzi()
                @Test fun a() { paparazzi.snapshot { APreview() } }
                @Test fun b() { paparazzi.snapshot { Renamed() } }
                @Test fun c() { paparazzi.snapshot { CPreview() } }
                @Test fun d() { paparazzi.snapshot { com.b.BPreview() } }
                @Test fun e() { paparazzi.snapshot { Gallery.G() } }
                @Test fun f() { paparazzi.snapshot { BPreview() } }
            }
        """)
        assertEquals(
            listOf(
                Target.Previews(listOf("com.a.AKt.APreview")), Target.Previews(listOf("com.b.BKt.BPreview")),
                Target.Previews(listOf("com.c.CKt.CPreview")), Target.Previews(listOf("com.b.BKt.BPreview")),
                Target.Previews(listOf("com.a.Gallery.G")), Target.Uncovered("BPreview()"),
            ),
            scan().map { it.target },
        )
    }

    @Test fun uncoveredCall() {
        ui()
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", """
            package com.example
            /* paparazzi.snapshot { CheckoutPreview() } */
            class CheckoutTest {
                @get:Rule val paparazzi = Paparazzi()
                val label = "paparazzi.snapshot { CheckoutPreview() }"

                @Test fun checkout() {
                    val state = CheckoutState()
                    paparazzi.snapshot {
                        CheckoutScreen(state)
                    }
                }
            }
        """)
        val t = one()
        assertEquals(Target.Uncovered("CheckoutScreen(state)"), t.target)
        assertEquals(9, t.line)
    }

    @Test fun viewsAndGifsAreUncovered() {
        ui()
        paparazziTest("paparazzi.snapshot(view)\n        paparazzi.gif(view)")
        assertEquals(listOf(Target.Uncovered("paparazzi.snapshot(view)"), Target.Uncovered("paparazzi.gif(view)")), scan().map { it.target })
    }

    private fun roboTest(classAnnotations: String, methods: String, path: String = "app/src/test/kotlin/com/example/CheckoutTest.kt") = write(path,
        "package com.example\n\n@RunWith(AndroidJUnit4::class)\n@GraphicsMode(GraphicsMode.Mode.NATIVE)\n$classAnnotations\nclass CheckoutTest {\n    @get:Rule val composeTestRule = createComposeRule()\n$methods\n}\n")

    private fun roboMethod(name: String, annotation: String = "", extra: String = "") =
        "    $annotation\n    @Test fun $name() {\n        $extra\n        composeTestRule.setContent { CheckoutPreview() }\n        composeTestRule.onRoot().captureRoboImage()\n    }\n"

    @Test fun roborazziCapture() {
        ui()
        roboTest("@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)", roboMethod("light") + roboMethod("dark", "@Config(qualifiers = \"+night\")"))
        val (light, dark) = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(SnapshotTool.ROBORAZZI, light.tool)
        assertEquals(Target.Previews(listOf(checkout.fqn)), light.target)
        assertEquals(roboPixel5, light.device)
        assertEquals(TestSettings(), light.settings)
        assertEquals(roboPixel5, dark.device)
        assertEquals(TestSettings(night = true), dark.settings)
        assertEquals(Target.Previews(listOf(checkout.fqn)), dark.target)
    }

    @Test fun composedQualifiers() {
        ui()
        roboTest("", roboMethod("a", "@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5 + \"-night\")") +
            roboMethod("b", "@Config(qualifiers = \"w411dp-h891dp-xxhdpi\" + \"-de\")") +
            roboMethod("c", "@Config(qualifiers = \"+night\")") +
            roboMethod("d", "@Config(qualifiers = QUALIFIERS)"))
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(roboPixel5, t[0].device); assertEquals(TestSettings(night = true), t[0].settings)
        assertEquals(TestDevices.parseQualifiers("w411dp-h891dp-xxhdpi").first, t[1].device); assertEquals(TestSettings(locale = "de"), t[1].settings)
        assertEquals(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI), t[2].device); assertEquals(TestSettings(night = true), t[2].settings)
        assertEquals(DeviceSource.Unresolved("QUALIFIERS"), t[3].device)
    }

    @Test fun plusOverrideOnUnknownBaseIsUnresolved() {
        ui()
        roboTest("@Config(qualifiers = Devices.TABLET)", roboMethod("a", "@Config(qualifiers = \"+night\")") + roboMethod("b", "@Config(qualifiers = \"w400dp-h800dp-xhdpi\")"))
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertIs<DeviceSource.Unresolved>(t[0].device)
        assertEquals(TestDevices.parseQualifiers("w400dp-h800dp-xhdpi").first, t[1].device)
    }

    @Test fun robolectricPropertiesBase() {
        ui()
        write("app/src/test/resources/robolectric.properties", "sdk=34\nqualifiers=w411dp-h891dp-xxhdpi\n")
        roboTest("", roboMethod("a") + roboMethod("b", "@Config(qualifiers = \"+land-night\")"))
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(TestDevices.parseQualifiers("w411dp-h891dp-xxhdpi").first, t[0].device)
        assertEquals(TestDevices.parseQualifiers("w411dp-h891dp-xxhdpi-land").first, t[1].device)
        assertEquals(TestSettings(night = true), t[1].settings)
    }

    @Test fun setQualifiersInBodyIsClosest() {
        ui()
        roboTest("@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)",
            roboMethod("a", "@Config(qualifiers = \"+night\")", "RuntimeEnvironment.setQualifiers(\"+de\")\n        RuntimeEnvironment.setFontScale(2f)") +
                roboMethod("b", "", "RuntimeEnvironment.setQualifiers(\"w400dp-h800dp-xhdpi\")"))
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(roboPixel5, t[0].device)
        assertEquals(TestSettings(locale = "de", night = true, fontScale = 2.0), t[0].settings)
        assertEquals(TestDevices.parseQualifiers("w400dp-h800dp-xhdpi").first, t[1].device)
    }

    @Test fun inheritedConfig() {
        ui()
        write("app/src/test/kotlin/com/example/Base.kt", "package com.example\n@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)\nabstract class Base")
        write("app/src/test/kotlin/com/example/T.kt", """
            package com.example
            class Known : Base() {
                @Test fun a() { captureRoboImage { CheckoutPreview() } }
            }
            class Unknown : LibraryBase() {
                @Test fun a() { captureRoboImage { CheckoutPreview() } }
            }
        """)
        val t = scan(module(tool = SnapshotTool.ROBORAZZI)).sortedBy { it.line }
        assertEquals(roboPixel5, t[0].device)
        assertIs<DeviceSource.Unresolved>(t[1].device)
    }

    @Test fun roborazziRuleCaptures() {
        ui()
        write("app/src/test/kotlin/com/example/T.kt", """
            package com.example
            @Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)
            class T {
                @get:Rule val composeTestRule = createComposeRule()
                @get:Rule val roborazziRule = RoborazziRule(
                    composeRule = composeTestRule,
                    captureRoot = composeTestRule.onRoot(),
                    options = RoborazziRule.Options(captureType = RoborazziRule.CaptureType.LastImage()),
                )
                @Config(qualifiers = "+night")
                @Test fun a() { composeTestRule.setContent { CheckoutPreview() } }
                @Test fun b() { composeTestRule.setContent { CheckoutScreen(1) } }
            }
        """)
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(listOf(Target.Previews(listOf(checkout.fqn)), Target.Uncovered("CheckoutScreen(1)")), t.map { it.target })
        assertEquals(TestSettings(night = true), t[0].settings)
        assertEquals(roboPixel5, t[0].device)
    }

    @Test fun nodeCaptureIsUncovered() {
        ui()
        roboTest("", "    @Test fun a() {\n        composeTestRule.setContent { CheckoutPreview() }\n        composeTestRule.onNodeWithTag(\"x\").captureRoboImage()\n    }\n")
        assertEquals(Target.Uncovered("composeTestRule.onNodeWithTag(\"x\").captureRoboImage()"), one(module(tool = SnapshotTool.ROBORAZZI)).target)
    }

    @Test fun captureRoboImageLambda() {
        ui()
        roboTest("", "    @Test fun a() {\n        captureRoboImage(\"a.png\") { CheckoutPreview() }\n    }\n")
        val t = one(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(Target.Previews(listOf(checkout.fqn)), t.target)
        assertEquals(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI), t.device)
    }

    @Test fun generatedPreviewTests() {
        ui()
        write("app/build.gradle.kts", "plugins { id(\"io.github.takahirom.roborazzi\") }\nroborazzi {\n    generateComposePreviewRobolectricTests {\n        enable = true\n        packages = listOf(\"com.example\")\n    }\n}")
        val t = one(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(Target.AllPreviews(listOf("com.example"), includePrivate = false), t.target)
        assertEquals(DeviceSource.FromPreview(TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel4a").first), t.device)
        assertEquals(3, t.line)
        assertEquals(File(dir, "app/build.gradle.kts"), t.file)
    }

    @Test fun generatedPreviewTestsDisabled() {
        ui()
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = false } }")
        assertTrue(scan(module(tool = SnapshotTool.ROBORAZZI)).isEmpty())
    }

    @Test fun previewScanner() {
        ui()
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            @RunWith(Parameterized::class)
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object {
                    @JvmStatic @Parameterized.Parameters
                    fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews()
                }
                @get:Rule val paparazzi = Paparazzi()
                @Test fun snapshot() {
                    paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfigBuilder.build(preview.previewInfo))
                    paparazzi.snapshot { preview() }
                }
            }
        """)
        write("app/src/test/kotlin/com/example/RoboPreviewTest.kt", """
            package com.example
            @RunWith(ParameterizedRobolectricTestRunner::class)
            class RoboPreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                @Test fun snapshot() {
                    RobolectricDeviceQualifierBuilder.build(preview.previewInfo)?.run { RuntimeEnvironment.setQualifiers(this) }
                    captureRoboImage { preview() }
                }
                companion object {
                    @JvmStatic @ParameterizedRobolectricTestRunner.Parameters
                    fun values() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews()
                }
            }
        """)
        val t = scan()
        assertEquals(listOf(Target.AllPreviews(listOf("com.example"), false), Target.AllPreviews(listOf("com.example"), false)), t.map { it.target })
        // Paparazzi: no DeviceConfigBuilder in the sources, so its fallback can't be read. Roborazzi: the builder only sets
        // qualifiers for previews with a device; the rest render on the class's setup (here Robolectric's default).
        assertEquals(listOf(DeviceSource.FromPreview(null), DeviceSource.FromPreview(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI))), t.map { it.device })
        assertEquals(setOf(SnapshotTool.PAPARAZZI, SnapshotTool.ROBORAZZI), t.map { it.tool }.toSet())
    }

    @Test fun noDeviceConfig() {
        ui()
        paparazziTest("paparazzi.snapshot { CheckoutPreview() }", rule = "Paparazzi()")
        assertEquals(DeviceSource.ToolDefault(TestDevices.paparazziDefault(), SnapshotTool.PAPARAZZI), one().device)
        roboTest("", roboMethod("a"))
        assertEquals(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI), one(module(tool = SnapshotTool.ROBORAZZI)).device)
    }

    @Test fun desktopAndIosRoborazzi() {
        write("app/src/commonMain/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun CheckoutPreview() {}")
        for (ss in listOf("desktopTest", "iosTest", "androidUnitTest")) write("app/src/$ss/kotlin/com/example/T.kt", """
            package com.example
            class T {
                @Test fun a() = runComposeUiTest {
                    setContent { CheckoutPreview() }
                    onRoot().captureRoboImage()
                }
            }
        """)
        val t = scan(module(tool = SnapshotTool.ROBORAZZI)).sortedBy { it.sourceSet }
        assertEquals(listOf("androidUnitTest", "desktopTest", "iosTest"), t.map { it.sourceSet })
        assertTrue(t.all { it.target == Target.Previews(listOf("com.example.UiKt.CheckoutPreview")) }, t.toString())
        assertEquals(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI), t[0].device)
    }

    @Test fun unknownPatternIsUncovered() {
        ui()
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", """
            package com.example
            class CheckoutTest {
                @get:Rule val paparazzi = Paparazzi()
                private fun snap(content: @Composable () -> Unit) = paparazzi.snapshot { MyTheme { content() } }
                @Test fun a() { snap(CheckoutPreview()) }
                @Test fun b() {
                    snap { CheckoutPreview() }
                }
            }
        """)
        val t = scan()
        // The lambda passed for `content` is followed into the helper; a non-lambda argument can't be.
        assertEquals(listOf(Target.Uncovered("snap(CheckoutPreview())"), Target.Previews(listOf(checkout.fqn))), t.map { it.target })
        assertEquals(listOf(5, 7), t.map { it.line })
    }

    @Test fun helperWithFixedPreviewIsCovered() {
        ui()
        paparazziTest("shot()\n    }\n    private fun shot() { paparazzi.snapshot { CheckoutPreview() } }\n    @Test fun again() { shot()")
        val t = scan()
        assertEquals(listOf(6, 9), t.map { it.line })
        assertTrue(t.all { it.target == Target.Previews(listOf(checkout.fqn)) })
    }

    @Test fun extensionHelperCalledWithReceiver() {
        ui()
        write("app/src/test/kotlin/com/example/T.kt", """
            package com.example
            class T {
                @get:Rule val composeTestRule = createComposeRule()
                private fun ComposeContentTestRule.shoot(content: @Composable () -> Unit) {
                    setContent { content() }
                    onRoot().captureRoboImage()
                }
                @Test fun a() { composeTestRule.shoot { CheckoutPreview() } }
                @Test fun b() { composeTestRule.setContent { CheckoutPreview() }; composeTestRule.onRoot().captureRoboImage() }
            }
        """)
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(listOf(Target.Previews(listOf(checkout.fqn)), Target.Previews(listOf(checkout.fqn))), t.map { it.target })
        assertEquals(listOf(8, 9), t.map { it.line })
    }

    // Review fixes

    @Test fun lowercaseCallWithoutLambdaIsUncovered() {
        ui()
        write("app/src/test/kotlin/com/example/T.kt", """
            package com.example
            class T {
                @get:Rule val paparazzi = Paparazzi()
                fun shot(extra: @Composable () -> Unit) = paparazzi.snapshot { CheckoutPreview(); extra() }
                @Test fun a() { paparazzi.snapshot { MyTheme { CheckoutPreview(); content() } } }
                @Test fun b() { shot { Text("x") } }
                @Test fun c() { paparazzi.snapshot { println("x"); CheckoutPreview() } }
            }
        """)
        assertEquals(
            listOf(Target.Uncovered("MyTheme { CheckoutPreview(); content() }"), Target.Uncovered("shot { Text(\"x\") }"), Target.Previews(listOf(checkout.fqn))),
            scan().map { it.target },
        )
    }

    @Test fun lambdaArgumentOfWrapperIsUncovered() {
        ui()
        paparazziTest("paparazzi.snapshot { Scaffold(topBar = { TopBar() }) { CheckoutPreview() } }\n        paparazzi.snapshot { Box(Modifier.padding(8.dp)) { CheckoutPreview() } }")
        assertEquals(listOf(Target.Uncovered("Scaffold(topBar = { TopBar() }) { CheckoutPreview() }"), Target.Previews(listOf(checkout.fqn))), scan().map { it.target })
    }

    @Test fun scannerOnlyCoversScannedPreviewCalls() {
        ui()
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example", "com.other").includePrivatePreviews().getPreviews() }
                @get:Rule val paparazzi = Paparazzi()
                @Test fun all() { paparazzi.snapshot { MyTheme { preview() } } }
                @Test fun other() { paparazzi.snapshot { CheckoutScreen(1) } }
                @Test fun mixed() { paparazzi.snapshot { preview(); CheckoutScreen(1) } }
            }
        """)
        assertEquals(
            listOf(Target.AllPreviews(listOf("com.example", "com.other"), includePrivate = true), Target.Uncovered("CheckoutScreen(1)"), Target.Uncovered("preview(); CheckoutScreen(1)")),
            scan().map { it.target },
        )
    }

    @Test fun filteredScannerIsUncovered() {
        ui()
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").filterPreviews { it.methodName.startsWith("A") }.getPreviews() }
                @get:Rule val paparazzi = Paparazzi()
                @Test fun all() { paparazzi.snapshot { preview() } }
            }
        """)
        assertEquals(Target.Uncovered("filtered previews"), one().target)
    }

    @Test fun generatedPreviewTestsOptions() {
        ui()
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; packages = listOf(\"a\", \"b\"); includePrivatePreviews = true } }")
        assertEquals(Target.AllPreviews(listOf("a", "b"), includePrivate = true), one(module(tool = SnapshotTool.ROBORAZZI)).target)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable.set(true); packages.set(listOf(\"a\")); annotationFilter = listOf(\"x\") } }")
        assertEquals(Target.Uncovered("filtered previews"), one(module(tool = SnapshotTool.ROBORAZZI)).target)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; packages = myPackages } }")
        assertEquals(Target.Uncovered("filtered previews"), one(module(tool = SnapshotTool.ROBORAZZI)).target)
    }

    @Test fun backtickTestNames() {
        ui()
        roboTest("@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)",
            "    @Config(qualifiers = \"+night\")\n    @Test fun `renders checkout`() {\n        RuntimeEnvironment.setQualifiers(\"+de\")\n        composeTestRule.setContent { CheckoutPreview() }\n        composeTestRule.onRoot().captureRoboImage()\n    }\n" +
                "    private fun `shoot it`() { captureRoboImage { CheckoutPreview() } }\n    @Test fun `uses helper`() { `shoot it`() }\n")
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(listOf(Target.Previews(listOf(checkout.fqn)), Target.Previews(listOf(checkout.fqn))), t.map { it.target })
        assertEquals(roboPixel5, t[0].device)
        assertEquals(TestSettings(locale = "de", night = true), t[0].settings)
        assertEquals(listOf(12, 15), t.map { it.line })
    }

    @Test fun robolectricPropertiesWithoutQualifiersLooksFurtherUp() {
        ui()
        write("app/src/test/resources/com/example/robolectric.properties", "sdk=34\n")
        write("app/src/test/resources/com/robolectric.properties", "qualifiers=w411dp-h891dp-xxhdpi\n")
        roboTest("", roboMethod("a"))
        assertEquals(TestDevices.parseQualifiers("w411dp-h891dp-xxhdpi").first, one(module(tool = SnapshotTool.ROBORAZZI)).device)
    }

    @Test fun nestedHelpersKeepTheTestScope() {
        ui()
        write("app/src/test/kotlin/com/example/T.kt", """
            package com.example
            @Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)
            class T {
                private fun inner() { captureRoboImage { CheckoutPreview() } }
                @Config(qualifiers = "+notnight")
                private fun outer() { inner() }
                private fun unused() { captureRoboImage { CheckoutPreview() } }
                @Config(qualifiers = "+night")
                @Test fun a() { outer() }
                @Test fun b() { outer() }
            }
        """)
        val t = scan(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(listOf(7, 9, 10), t.map { it.line })
        assertEquals(DeviceSource.Unresolved("helper unused"), t[0].device)
        assertEquals(roboPixel5, t[1].device); assertEquals(TestSettings(night = true), t[1].settings)
        assertEquals(roboPixel5, t[2].device); assertEquals(TestSettings(), t[2].settings)
        assertTrue(t.all { it.target == Target.Previews(listOf(checkout.fqn)) })
    }

    @Test fun paparazziRenderingMode() {
        ui()
        paparazziTest("paparazzi.snapshot { CheckoutPreview() }", rule = "Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, renderingMode = SessionParams.RenderingMode.SHRINK)")
        assertEquals(DeviceSource.Unresolved("renderingMode=SHRINK"), one().device)
        paparazziTest("paparazzi.unsafeUpdateConfig(renderingMode = RenderingMode.NORMAL)\n        paparazzi.snapshot { CheckoutPreview() }",
            rule = "Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, renderingMode = SessionParams.RenderingMode.SHRINK)")
        assertEquals(pixel5, one().device)
        paparazziTest("paparazzi.unsafeUpdateConfig(renderingMode = SessionParams.RenderingMode.V_SCROLL)\n        paparazzi.snapshot { CheckoutPreview() }")
        assertEquals(DeviceSource.Unresolved("renderingMode=V_SCROLL"), one().device)
    }

    // Review round 2

    @Test fun generatedPreviewTestsFallbackDevice() {
        ui()
        val m = module(tool = SnapshotTool.ROBORAZZI)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; robolectricConfig = mapOf(\"sdk\" to \"[34]\", \"qualifiers\" to \"RobolectricDeviceQualifiers.Pixel5\") } }")
        assertEquals(DeviceSource.FromPreview(roboPixel5), one(m).device)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; robolectricConfig.set(mapOf(\"qualifiers\" to \"\\\"w400dp-h800dp-xhdpi\\\"\")) } }")
        assertEquals(DeviceSource.FromPreview(TestDevices.parseQualifiers("w400dp-h800dp-xhdpi").first), one(m).device)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; robolectricConfig = mapOf(\"sdk\" to \"[34]\") } }")
        assertEquals(DeviceSource.FromPreview(DeviceSource.ToolDefault(TestDevices.robolectricDefault(), SnapshotTool.ROBORAZZI)), one(m).device)
        write("app/build.gradle.kts", "roborazzi { generateComposePreviewRobolectricTests { enable = true; robolectricConfig = mapOf(\"qualifiers\" to \"MY_QUALIFIERS\") } }")
        assertEquals(DeviceSource.FromPreview(null), one(m).device)
    }

    @Test fun scannerFallbackFromProjectDeviceConfigBuilder() {
        ui()
        write("app/src/test/kotlin/com/example/DeviceConfigBuilder.kt", """
            package com.example
            object DeviceConfigBuilder {
                fun build(previewDevice: String): DeviceConfig {
                    val device = DevicePreviewInfoParser.parse(previewDevice) ?: return DeviceConfig.PIXEL_5
                    return DeviceConfig(screenHeight = device.dimensions.height.toInt())
                }
            }
        """)
        write("app/src/test/kotlin/com/example/PreviewTest.kt", """
            package com.example
            class PreviewTest(val preview: ComposablePreview<AndroidPreviewInfo>) {
                companion object { fun previews() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews() }
                @get:Rule val paparazzi = Paparazzi()
                @Test fun snapshot() {
                    paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfigBuilder.build(preview.previewInfo.device))
                    paparazzi.snapshot { preview() }
                }
            }
        """)
        assertEquals(DeviceSource.FromPreview(pixel5), one().device)
    }

    @Test fun roborazziPreviewCaptureFallsBackToTheClassSetup() {
        ui()
        roboTest("@Config(qualifiers = RobolectricDeviceQualifiers.Pixel5)", """
            |    @Test fun snapshot() { preview.captureRoboImage("a.png") }
            |    companion object { fun values() = AndroidComposablePreviewScanner().scanPackageTrees("com.example").getPreviews() }
            |    lateinit var preview: ComposablePreview<AndroidPreviewInfo>
        """.trimMargin())
        val t = one(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(Target.AllPreviews(listOf("com.example"), false), t.target)
        assertEquals(DeviceSource.FromPreview(roboPixel5), t.device)
    }

    @Test fun deviceConfigurationOverride() {
        ui()
        paparazziTest(listOf(
            "paparazzi.snapshot { DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(1.5f) then DeviceConfigurationOverride.DarkMode(true) then DeviceConfigurationOverride.Locales(LocaleList(\"de-DE\"))) { CheckoutPreview() } }",
            "paparazzi.snapshot { DeviceConfigurationOverride(override = DeviceConfigurationOverride.ForcedSize(DpSize(400.dp, 800.dp))) { CheckoutPreview() } }",
            "paparazzi.snapshot { DeviceConfigurationOverride(DeviceConfigurationOverride.RoundScreen(true)) { CheckoutPreview() } }",
            "paparazzi.snapshot { DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(scale)) { CheckoutPreview() } }",
            "paparazzi.snapshot { DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) { CheckoutScreen(1) } }",
        ).joinToString("\n        "))
        val t = scan()
        assertEquals(Target.Previews(listOf(checkout.fqn)), t[0].target)
        assertEquals(pixel5, t[0].device)
        assertEquals(TestSettings(locale = "de-DE", night = true, fontScale = 1.5), t[0].settings)
        assertEquals(Target.Previews(listOf(checkout.fqn)), t[1].target)
        assertEquals(DeviceSource.Unresolved("DeviceConfigurationOverride.ForcedSize"), t[1].device)
        assertEquals(Target.Uncovered("DeviceConfigurationOverride"), t[2].target)
        assertEquals(Target.Uncovered("DeviceConfigurationOverride"), t[3].target)
        assertIs<Target.Uncovered>(t[4].target)
        assertEquals(TestSettings(), t[4].settings)
    }

    /** Now in Android's layout: a shared screenshot-testing module (no plugin) with multi-device helpers. */
    private fun sharedHelpers() {
        write("settings.gradle.kts", "include(\":feature\", \":core:screenshot-testing\")")
        write("feature/build.gradle.kts", "dependencies { testImplementation(projects.core.screenshotTesting) }")
        write("feature/src/main/kotlin/com/example/Ui.kt", "package com.example\n@Preview @Composable fun CheckoutPreview() {}")
        write("core/screenshot-testing/src/main/kotlin/com/example/testing/ScreenshotHelper.kt", """
            package com.example.testing
            enum class DefaultTestDevices(val description: String, val spec: String) {
                PHONE("phone", "spec:shape=Normal,width=640,height=360,unit=dp,dpi=480"),
                FOLDABLE("foldable", "spec:shape=Normal,width=673,height=841,unit=dp,dpi=480"),
                TABLET("tablet", "spec:shape=Normal,width=1280,height=800,unit=dp,dpi=480"),
            }
            fun <A : ComponentActivity> AndroidComposeTestRule<ActivityScenarioRule<A>, A>.captureMultiDevice(
                screenshotName: String,
                body: @Composable () -> Unit,
            ) {
                DefaultTestDevices.entries.forEach {
                    this.captureForDevice(it.description, it.spec, screenshotName, body = body)
                }
            }
            fun <A : ComponentActivity> AndroidComposeTestRule<ActivityScenarioRule<A>, A>.captureForDevice(
                deviceName: String,
                deviceSpec: String,
                screenshotName: String,
                darkMode: Boolean = false,
                body: @Composable () -> Unit,
            ) {
                val (width, height, dpi) = extractSpecs(deviceSpec)
                RuntimeEnvironment.setQualifiers("w${'$'}{width}dp-h${'$'}{height}dp-${'$'}{dpi}dpi")
                this.activity.setContent {
                    CompositionLocalProvider(LocalInspectionMode provides true) {
                        NiaTheme(darkTheme = darkMode) { body() }
                    }
                }
                this.onRoot().captureRoboImage("src/test/screenshots/${'$'}{screenshotName}_${'$'}deviceName.png")
            }
        """)
    }

    @Test fun helpersInAnotherModule() {
        sharedHelpers()
        write("feature/src/test/kotlin/com/example/CheckoutScreenshotTests.kt", """
            package com.example
            import com.example.testing.captureMultiDevice
            import com.example.testing.captureForDevice
            class CheckoutScreenshotTests {
                @get:Rule val composeTestRule = createAndroidComposeRule<ComponentActivity>()
                @Test fun checkout() {
                    composeTestRule.captureMultiDevice("Checkout") { CheckoutPreview() }
                }
                @Test fun screen() {
                    composeTestRule.captureMultiDevice("Screen") { CheckoutScreen(1) }
                }
                @Test fun tablet() {
                    composeTestRule.captureForDevice("tablet", "spec:width=1280dp,height=800dp,dpi=480", "Tablet") { CheckoutPreview() }
                }
            }
        """)
        val m = SnapshotModule(":feature", File(dir, "feature"), setOf(SnapshotTool.ROBORAZZI), listOf("imports"))
        val previews = SnapshotTests.previews(m, all(":feature", ":core:screenshot-testing"))
        val t = SnapshotTests.scan(listOf(m), previews)
        assertEquals(listOf(7, 7, 7, 10, 10, 10, 13), t.map { it.line }, t.joinToString("\n"))
        val fqn = "com.example.UiKt.CheckoutPreview"
        assertEquals(List(3) { Target.Previews(listOf(fqn)) } + List(3) { Target.Uncovered("composeTestRule.captureMultiDevice(\"Screen\") { CheckoutScreen(1) }") } + Target.Previews(listOf(fqn)),
            t.map { it.target })
        // One test per device in the helper's list; the device comes from a computed qualifier string, so it's unresolved, per entry.
        val devices = t.take(3).map { assertIs<DeviceSource.Unresolved>(it.device).expression }
        assertEquals(3, devices.distinct().size)
        assertTrue(devices[0].endsWith("for PHONE(\"phone\", \"spec:shape=Normal,width=640,height=360,unit=dp,dpi=480\")"), devices[0])
        assertTrue(t.all { it.module == ":feature" && it.sourceSet == "test" && it.file.name == "CheckoutScreenshotTests.kt" })
    }

    @Test fun helperThatCantBeFollowedIsCounted() {
        ui()
        roboTest("", """
            |    @Test fun a() { composeTestRule.captureMultiTheme("x") { CheckoutPreview() } }
            |    @Test fun b() { composeTestRule.onNodeWithText("x").assertExists() }
        """.trimMargin())
        val t = one(module(tool = SnapshotTool.ROBORAZZI))
        assertEquals(Target.Uncovered("helper captureMultiTheme"), t.target)
        assertEquals(DeviceSource.Unresolved("helper captureMultiTheme"), t.device)
        assertEquals(8, t.line)
    }

    @Test fun paparazziHelperInAnotherFileUsesTheTestsRule() {
        ui()
        write("app/src/test/kotlin/com/example/util/Snap.kt", """
            package com.example.util
            import app.cash.paparazzi.Paparazzi
            fun snapIt(paparazzi: Paparazzi, content: @Composable () -> Unit) {
                paparazzi.snapshot { MyTheme { content() } }
            }
        """)
        paparazziTest("snapIt(paparazzi) { CheckoutPreview() }", imports = "import com.example.util.snapIt")
        val t = one()
        assertEquals(Target.Previews(listOf(checkout.fqn)), t.target)
        assertEquals(pixel5, t.device)
        assertEquals(6, t.line)
        assertEquals("CheckoutTest.kt", t.file.name)
    }

    @Test fun loopsOverDevicesInATest() {
        ui()
        paparazziTest("listOf(DeviceConfig.PIXEL_5, DeviceConfig.NEXUS_5).forEach {\n            paparazzi.unsafeUpdateConfig(deviceConfig = it)\n            paparazzi.snapshot { CheckoutPreview() }\n        }\n" +
            "        devices().forEach { paparazzi.snapshot { CheckoutPreview() } }")
        val t = scan()
        assertEquals(listOf(DeviceSource.Unresolved("it for DeviceConfig.PIXEL_5"), DeviceSource.Unresolved("it for DeviceConfig.NEXUS_5")), t.take(2).map { it.device })
        assertEquals(Target.Uncovered("loop over devices()"), t[2].target)
        assertEquals(3, t.size)
    }

    // Review round 3

    @Test fun paparazziParameterHelpers() {
        ui()
        write("app/src/test/kotlin/com/example/Helpers.kt", """
            package com.example
            fun shotWith(rule: Paparazzi, content: @Composable () -> Unit) { rule.snapshot { content() } }
        """)
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", """
            package com.example
            class CheckoutTest {
                @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)
                private fun shot(rule: Paparazzi) { rule.snapshot { CheckoutPreview() } }
                @Test fun a() { shot(paparazzi) }
                @Test fun b() { shotWith(paparazzi) { CheckoutPreview() } }
                @Test fun c() { shotWith(paparazzi) { CheckoutScreen(1) } }
            }
        """)
        val t = scan()
        assertEquals(listOf(5, 6, 7), t.map { it.line })
        assertEquals(listOf(Target.Previews(listOf(checkout.fqn)), Target.Previews(listOf(checkout.fqn)), Target.Uncovered("shotWith(paparazzi) { CheckoutScreen(1) }")), t.map { it.target })
        assertTrue(t.all { it.device == pixel5 && it.file.name == "CheckoutTest.kt" }, t.toString())
    }

    @Test fun paparazziExtensionHelpers() {
        ui()
        write("app/src/test/kotlin/com/example/util/Snap.kt", """
            package com.example.util
            import com.example.CheckoutPreview
            fun Paparazzi.snapAll(content: @Composable () -> Unit) = snapshot { MyTheme { content() } }
            fun app.cash.paparazzi.Paparazzi.snapThis() { this.snapshot { CheckoutPreview() } }
            fun Paparazzi.unused() { snapshot { CheckoutPreview() } }
        """)
        paparazziTest("paparazzi.snapAll { CheckoutPreview() }\n        paparazzi.snapThis()", imports = "import com.example.util.*\nimport com.example.CheckoutPreview")
        val t = scan()
        val inTest = t.filter { it.file.name == "CheckoutTest.kt" }
        assertEquals(listOf(7, 8), inTest.map { it.line })
        assertTrue(inTest.all { it.target == Target.Previews(listOf(checkout.fqn)) && it.device == pixel5 }, inTest.toString())
        // The helper no test calls still counts once, its device unknown.
        val unused = t.single { it.file.name == "Snap.kt" }
        assertEquals(DeviceSource.Unresolved("helper unused"), unused.device)
        assertEquals(3, t.size)
    }

    @Test fun unreadableSnapshotHelperIsCountedNotDropped() {
        ui()
        write("app/src/test/kotlin/com/example/CheckoutTest.kt", """
            package com.example
            class CheckoutTest {
                @get:Rule val rule = MySnapshotRule()
                private fun shoot(r: MySnapshotRule) { r.snapshot { CheckoutPreview() } }
                @Test fun a() { shoot(rule) }
                @Test fun b() { assertEquals(1, 1) }
            }
        """)
        val t = one()
        assertEquals(Target.Uncovered("helper shoot"), t.target)
        assertEquals(DeviceSource.Unresolved("helper shoot"), t.device)
        assertEquals(5, t.line)
    }
}
