package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class InitTest {
    private val dir: File = Files.createTempDirectory("swiftshot-init").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private fun write(path: String, text: String) = File(dir, path).apply { parentFile.mkdirs(); writeText(text) }

    private fun init(): Map<*, *> {
        val o = Options.parse(listOf("--project-dir", dir.path, "init"))
        Init.run(o, force = true, log = Log(false))
        return Json.parse(File(dir, "swiftshot.json").readText()) as Map<*, *>
    }

    @Test fun multiplatformModuleWithDesktopAndIos() {
        write("settings.gradle.kts", """include(":shared", ":androidApp")""")
        write("shared/build.gradle.kts", """plugins { kotlin("multiplatform") }
            kotlin { jvm("desktop"); iosSimulatorArm64(); androidLibrary { } }""")
        write("shared/src/commonMain/kotlin/Screens.kt", "@Preview @Composable fun Home() {}")
        write("shared/src/commonMain/composeResources/values/strings.xml", "<resources/>")
        write("shared/src/commonMain/composeResources/values-de/strings.xml", "<resources/>")
        write("androidApp/build.gradle.kts", """plugins { id("com.android.application") }""")
        write("androidApp/src/main/kotlin/Main.kt", "class MainActivity")
        val c = init()
        // The app module only hosts the shared one: no previews, not listed.
        assertEquals(listOf(":shared"), c["modules"])
        assertEquals(Devices.defaultDesktop, c["desktop_devices"])
        assertEquals(Ios.defaultDevices, c["ios_devices"])
        assertEquals(listOf("en-US", "de"), c["languages"])
    }

    @Test fun androidOnlyHasNoMultiplatformDevices() {
        write("settings.gradle.kts", """include(":app")""")
        write("app/build.gradle.kts", """plugins { id("com.android.application") }""")
        write("app/src/main/kotlin/Ui.kt", "@Preview @Composable fun Home() {}")
        write("app/src/main/res/values/strings.xml", "<resources/>")
        val c = init()
        assertEquals(listOf(":app"), c["modules"])
        assertNull(c["desktop_devices"])
        assertNull(c["ios_devices"])
    }

    @Test fun noPreviewsAnywhereKeepsEveryModule() {
        write("settings.gradle.kts", """include(":a", ":b")""")
        write("a/build.gradle.kts", """plugins { id("com.android.library") }""")
        write("b/build.gradle.kts", """plugins { id("com.android.library") }""")
        assertEquals(listOf(":a", ":b"), init()["modules"])
    }
}
