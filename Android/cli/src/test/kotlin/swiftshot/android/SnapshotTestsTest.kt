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
            listOf(SourcePreview(":app", "com.example.AllScreens.Named", "Named"), SourcePreview(":app", "com.example.Previews.InObject", "InObject"), checkout),
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
        assertEquals(listOf(SourcePreview(":feature:cart", "com.example.cart.CartKt.CartPreview", "CartPreview")), got)
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
        assertEquals(DeviceSource.FromPreview, t.device)
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
        assertEquals(listOf(DeviceSource.FromPreview, DeviceSource.FromPreview), t.map { it.device })
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
        assertEquals(listOf(Target.Uncovered("snap(CheckoutPreview())"), Target.Uncovered("snap { CheckoutPreview() }")), t.map { it.target })
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
        assertEquals(listOf(Target.Uncovered("composeTestRule.shoot { CheckoutPreview() }"), Target.Previews(listOf(checkout.fqn))), t.map { it.target })
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
}
