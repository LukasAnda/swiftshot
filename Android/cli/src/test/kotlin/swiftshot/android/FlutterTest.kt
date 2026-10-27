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
}
