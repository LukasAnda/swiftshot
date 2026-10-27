package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FlutterTest {
    private val dir: File = Files.createTempDirectory("swiftshot-flutter").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    @Test fun aPubspecOnTheFlutterSdkIsAFlutterProject() {
        File(dir, "pubspec.yaml").writeText("name: app\ndependencies:\n  flutter:\n    sdk: flutter\n")
        assertTrue(Flutter.isProject(dir))
        File(dir, "pubspec.yaml").writeText("name: tool\ndependencies:\n  path: ^1.9.0\n")
        assertFalse(Flutter.isProject(dir))
    }

    @Test fun initTakesTheLanguagesFromTheArbFiles() {
        File(dir, "l10n.yaml").writeText("arb-dir: assets/l10n\ntemplate-arb-file: app_en.arb\n")
        for (n in listOf("app_en.arb", "app_de.arb", "app_pt_BR.arb", "app_ar.arb")) File(dir, "assets/l10n/$n").apply { parentFile.mkdirs(); writeText("{}") }
        val config = Init.flutter(dir)
        assertEquals(listOf("en-US", "ar", "de", "pt-BR"), config["languages"])
        assertEquals(listOf("light", "dark"), config["appearances"])
    }

    @Test fun appleDevicesByNameAndGlob() {
        assertEquals(listOf(440, 956, 62, 34), AppleDevices.matching("iphone 17 pro max").single().let { listOf(it.width, it.height, it.top, it.bottom) })
        assertEquals(2.88, AppleDevices.matching("iPhone 13 mini").single().scale)
        assertEquals(2.0, AppleDevices.matching("iPad mini (A17 Pro)").single().scale)
        assertTrue(AppleDevices.matching("iPhone 17*").size >= 3)
        assertTrue(AppleDevices.matching("Pixel 10 Pro").isEmpty())
    }

    @Test fun hostAppHasAPreviewPerFlutterPreviewWithComponentSizes() {
        val o = Options.parse(listOf("--project-dir", dir.path))
        val ios = FlutterIos(o, Log(false), dir, dir, dir, dir)
        val manifest = listOf(
            mapOf("name" to "Root", "component" to false),
            mapOf("name" to "Card \"big\"", "component" to true, "width" to 400.0, "height" to 120.0),
            mapOf("name" to "Summary", "component" to true, "width" to 400.0, "height" to null),
            mapOf("name" to "Free", "component" to true),
        )
        val swift = ios.hostMain(manifest, mapOf("Summary" to (400.0 to 212.5)), plugins = true)
        assertTrue("#Preview(\"Root\") { flutterPreview(0) }" in swift, swift)
        assertTrue("#Preview(\"Card \\\"big\\\"\", traits: .fixedLayout(width: 400, height: 120)) { flutterPreview(1) }" in swift, swift)
        assertTrue("#Preview(\"Summary\", traits: .fixedLayout(width: 400, height: 212.50)) { flutterPreview(2) }" in swift, swift)
        assertTrue("#Preview(\"Free\", traits: .sizeThatFitsLayout) { flutterPreview(3) }" in swift, swift)
        assertTrue("registerWithRegistry:" in swift)
        assertFalse("registerWithRegistry:" in ios.hostMain(manifest, emptyMap(), plugins = false))
    }

    @Test fun fontsPerLanguageAndPlatform() {
        val material = File(dir, "material_fonts").apply { mkdirs() }
        File(material, "Roboto-Regular.ttf").writeText("")
        File(material, "MaterialIcons-Regular.otf").writeText("")
        val fonts = Fonts(material, Log(false))
        val latin = fonts.forLanguage("de-DE", ios = false, android = true)
        assertEquals(listOf(File(material, "Roboto-Regular.ttf").path), latin["Roboto"])
        assertFalse("CupertinoSystemText" in latin)
        assertTrue("MaterialIcons" in latin)
        val ios = fonts.forLanguage("en-US", ios = true, android = false)
        assertTrue("CupertinoSystemText" in ios && "CupertinoSystemDisplay" in ios && "Roboto" !in ios)
    }

    @Test fun flutterIosOption() {
        assertEquals("exact", Options.parse(listOf("--project-dir", dir.path)).flutterIos)
        assertEquals("headless", Options.parse(listOf("--project-dir", dir.path, "--flutter-ios", "headless")).flutterIos)
        assertTrue(runCatching { Options.parse(listOf("--project-dir", dir.path, "--flutter-ios", "fast")) }.isFailure)
    }
}
