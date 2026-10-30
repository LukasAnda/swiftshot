package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FingerprintsTest {
    private val dir: File = Files.createTempDirectory("swiftshot-fp").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private val gradleCache = "/home/u/.gradle/caches/modules-2/files-2.1"

    @Test fun versionsFromGradleCachePathsAndFileNames() {
        val cp = listOf(
            File("$gradleCache/org.jetbrains.skiko/skiko-awt/0.9.4.2/abc/skiko-awt-0.9.4.2.jar"),
            File("$gradleCache/org.jetbrains.skiko/skiko-awt-runtime-macos-arm64/0.9.4.2/abc/skiko-awt-runtime-macos-arm64-0.9.4.2.jar"),
            File("$gradleCache/org.jetbrains.compose.ui/ui-desktop/1.8.2/def/ui-desktop-1.8.2.jar"),
            File("/libs/ui-graphics-desktop-1.8.2.jar"),
        )
        assertEquals("0.9.4.2", Fingerprints.versionIn(cp, "org.jetbrains.skiko", "skiko-awt"))
        assertEquals("1.8.2", Fingerprints.versionIn(cp, "org.jetbrains.compose.ui", "ui-desktop", "ui"))
        assertEquals("2.0.1", Fingerprints.versionIn(listOf(File("/x/skiko-awt-2.0.1.jar")), "org.jetbrains.skiko", "skiko-awt"))
        assertNull(Fingerprints.versionIn(cp, "androidx.compose.ui", "ui"))
    }

    @Test fun androidFingerprint() {
        val runtime = File("$gradleCache/com.android.tools.layoutlib/layoutlib-runtime/16.2.3/aa/layoutlib-runtime-16.2.3-mac-arm.jar")
        val m = Module(mapOf("module" to ":app", "layoutlibRuntime" to runtime.path, "layoutlibResources" to "/r.jar",
            "components" to listOf("project :app", "androidx.compose.ui:ui-android:1.9.1", "androidx.compose.ui:ui:1.9.1")))
        val home = File(dir, "jdk").apply { mkdirs(); File(this, "release").writeText("IMPLEMENTOR=\"JetBrains\"\nJAVA_VERSION=\"21.0.8\"\n") }
        val fp = Fingerprints.android(listOf(m), File(home, "bin/java"), "linux-x64")
        assertEquals(
            mapOf("compose" to "1.9.1", "host" to "linux-x64", "jdk" to "21.0.8", "layoutlib" to "16.2.3", "mode" to "headless",
                "platform" to "android", "swiftshot" to Fingerprints.version()),
            fp,
        )
        assertEquals("16.2.3", Fingerprints.layoutlib(File("/cache/layoutlib-runtime-16.2.3-linux.jar")))
    }

    @Test fun hostNames() {
        assertEquals("macos-arm64", Fingerprints.hostOf("Mac OS X", "aarch64"))
        assertEquals("macos-x64", Fingerprints.hostOf("Mac OS X", "x86_64"))
        assertEquals("linux-x64", Fingerprints.hostOf("Linux", "amd64"))
        assertEquals("linux-arm64", Fingerprints.hostOf("Linux", "aarch64"))
    }

    @Test fun flutterVersionFromSdk() {
        File(dir, "bin/cache").mkdirs()
        File(dir, "bin/cache/flutter.version.json").writeText("""{"frameworkVersion": "3.38.0", "channel": "stable"}""")
        assertEquals("3.38.0", Fingerprints.flutterVersion(dir))
        val fp = Fingerprints.flutter(dir, "skia", listOf("/a/Roboto-Regular.ttf", "/b/MaterialIcons-Regular.otf", "/a/Roboto-Regular.ttf"), "linux-x64")
        assertEquals(listOf("MaterialIcons-Regular.otf", "Roboto-Regular.ttf"), fp["fonts"])
        assertEquals("headless", fp["mode"])
        assertEquals("exact-ios", Fingerprints.flutter(dir, "exact-ios", emptyList(), "macos-arm64")["mode"])
    }

    @Test fun canonicalJson() {
        val v = mapOf("b" to listOf(1.0, 2.625, 1.3, 1e-5), "a" to mapOf<String, Any>(), "é" to "x\u0001\"/", "Z" to emptyList<Any>(), "n" to null)
        assertEquals(
            "{\n  \"Z\": [],\n  \"a\": {},\n  \"b\": [\n    1,\n    2.625,\n    1.3,\n    0.00001\n  ],\n  \"n\": null,\n  \"é\": \"x\\u0001\\\"/\"\n}\n",
            CanonicalJson.pretty(v),
        )
        assertEquals("{\"Z\":[],\"a\":{},\"b\":[1,2.625,1.3,0.00001],\"n\":null,\"é\":\"x\\u0001\\\"/\"}", CanonicalJson.compact(v))
        // UTF-8 byte order, not UTF-16: U+FF5E sorts before U+1F600.
        assertEquals(listOf("～", "😀"), listOf("😀", "～").sortedWith(CanonicalJson.utf8))
    }
}
