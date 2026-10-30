package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OptionsTest {
    private val dir: File = Files.createTempDirectory("swiftshot-options").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    /** Parses in an empty project directory, so no stray swiftshot.json is picked up. */
    private fun parse(vararg args: String) = Options.parse(listOf("--project-dir", dir.path) + args)

    private fun config(text: String, file: File = File(dir, "swiftshot.json")) = file.apply { parentFile.mkdirs(); writeText(text) }

    @Test fun defaults() {
        val o = parse()
        assertEquals("run", o.command)
        assertEquals(emptyList(), o.commandArgs)
        assertEquals(dir.path, o.projectDir)
        assertEquals(emptyList(), o.modules)
        assertEquals("debug", o.variant)
        assertEquals(emptyList(), o.devices)
        assertEquals(emptyList(), o.watchDevices)
        assertEquals(listOf("en-US"), o.languages)
        assertEquals(listOf("light"), o.appearances)
        assertEquals(listOf(1.0), o.fontScales)
        assertEquals(emptyList(), o.previews)
        assertEquals("screenshots", o.output)
        assertFalse(o.clear)
        assertTrue(o.html)
        assertEquals("swiftshot", o.layout)
        assertFalse(o.fullLength)
        assertEquals(0.0, o.delay)
        assertEquals("preview", o.systemUi)
        assertNull(o.theme) // each module's application theme unless android_theme is set
        assertEquals("black", o.roundCorners)
        assertEquals(0, o.parallel)
        assertEquals(emptyList(), o.gradleArgs)
        assertNull(o.javaHome)
        assertEquals(emptyList(), o.screens)
        assertFalse(o.verbose)
        assertNull(o.config)
    }

    @Test fun projectDirDefaultsToHere() {
        // Only when the working directory has no config of its own.
        if (!File("swiftshot.json").exists()) assertEquals(".", Options.parse(emptyList()).projectDir)
    }

    @Test fun everyFlag() {
        val o = parse(
            "--modules", ":app, :wear",
            "--variant", "release",
            "--devices", "Pixel 9,Pixel Tablet",
            "--watch-devices", "Wear OS Small Round",
            "--languages", "en-US,de-DE,ja",
            "--appearances", "light,dark",
            "--font-scales", "1,1.3,2",
            "--previews", "Welcome,Stats*",
            "--output", "out/shots",
            "--layout", "fastlane",
            "--clear",
            "--no-html",
            "--full-length",
            "--delay", "0.5",
            "--system-ui", "never",
            "--round-corners", "transparent",
            "--parallel", "3",
            "--gradle-arg", "--offline",
            "--gradle-arg", "-Pfoo=bar",
            "--java-home", "/opt/jdk",
            "--theme", "android:Theme.Material",
            "--screen", "Stats: languages=de-DE",
            "-v",
        )
        assertEquals(listOf(":app", ":wear"), o.modules)
        assertEquals("release", o.variant)
        assertEquals(listOf("Pixel 9", "Pixel Tablet"), o.devices)
        assertEquals(listOf("Wear OS Small Round"), o.watchDevices)
        assertEquals(listOf("en-US", "de-DE", "ja"), o.languages)
        assertEquals(listOf("light", "dark"), o.appearances)
        assertEquals(listOf(1.0, 1.3, 2.0), o.fontScales)
        assertEquals(listOf("Welcome", "Stats*"), o.previews)
        assertEquals("out/shots", o.output)
        assertEquals("fastlane", o.layout)
        assertTrue(o.clear)
        assertFalse(o.html)
        assertTrue(o.fullLength)
        assertEquals(0.5, o.delay)
        assertEquals("never", o.systemUi)
        assertEquals("transparent", o.roundCorners)
        assertEquals(3, o.parallel)
        assertEquals(listOf("--offline", "-Pfoo=bar"), o.gradleArgs)
        assertEquals("/opt/jdk", o.javaHome)
        assertEquals("android:Theme.Material", o.theme)
        assertEquals(listOf(ScreenRule("Stats", languages = listOf("de-DE"))), o.screens)
        assertTrue(o.verbose)
    }

    @Test fun inlineValues() {
        val o = parse("--devices=Pixel 9", "--languages=de-DE,fr", "--delay=1.25", "--verbose")
        assertEquals(listOf("Pixel 9"), o.devices)
        assertEquals(listOf("de-DE", "fr"), o.languages)
        assertEquals(1.25, o.delay)
        assertTrue(o.verbose)
    }

    @Test fun listsDropBlanks() {
        assertEquals(listOf("a", "b"), parse("--languages", " a, ,b ,").languages)
    }

    @Test fun lastValueWins() {
        assertEquals("release", parse("--variant", "debug", "--variant", "release").variant)
    }

    @Test fun commands() {
        assertEquals("list", parse("list").command)
        assertEquals("devices", parse("devices", "-v").command)
        val emit = parse("emit-devices", "sdklib.jar", "out.json")
        assertEquals("emit-devices", emit.command)
        assertEquals(listOf("sdklib.jar", "out.json"), emit.commandArgs)
        assertEquals("list", parse("--languages", "de", "list").command)
        val e = assertFailsWith<IllegalArgumentException> { parse("shoot") }
        assertTrue(e.message!!.contains("shoot"))
    }

    @Test fun unknownFlag() {
        val e = assertFailsWith<IllegalStateException> { parse("--colour", "red") }
        assertTrue(e.message!!.contains("--colour"))
    }

    @Test fun missingValue() {
        val e = assertFailsWith<IllegalStateException> { parse("--devices") }
        assertTrue(e.message!!.contains("--devices"))
    }

    @Test fun badNumbers() {
        assertFailsWith<NumberFormatException> { parse("--font-scales", "big") }
        assertFailsWith<NumberFormatException> { parse("--parallel", "many") }
        assertFailsWith<NumberFormatException> { parse("--delay", "soon") }
    }

    @Test fun validation() {
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("--appearances", "light,sepia") }.message!!.contains("sepia"))
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("--layout", "play") }.message!!.contains("layout"))
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("--system-ui", "sometimes") }.message!!.contains("system_ui"))
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("--round-corners", "white") }.message!!.contains("round_corners"))
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("--font-scales", "1,3.5") }.message!!.contains("3.5"))
        assertFailsWith<IllegalArgumentException> { parse("--font-scales", "0.4") }
        assertEquals(listOf(0.5, 3.0), parse("--font-scales", "0.5,3").fontScales)
        assertEquals(listOf("dark"), parse("--appearances", "dark").appearances)
        for (s in listOf("preview", "always", "never")) assertEquals(s, parse("--system-ui", s).systemUi)
    }

    @Test fun screenFlag() {
        val r = Options.screenFlag("Stats: languages=de-DE,ja devices=Pixel* skip=true")
        assertEquals(ScreenRule("Stats", languages = listOf("de-DE", "ja"), devices = listOf("Pixel*"), skip = true), r)
    }

    @Test fun overridePreviewKey() {
        assertTrue(Options.screenFlag("X: override_preview=true").overridePreview)
        assertTrue(Options.rule("X", mapOf("override_preview" to true)).overridePreview)
        assertFalse(Options.rule("X", emptyMap()).overridePreview)
        assertFailsWith<IllegalArgumentException> { Options.rule("X", mapOf("bogus" to 1)) }
    }

    @Test fun screenFlagAllKeys() {
        val r = Options.screenFlag("  Welcome*  :   appearances=dark   font_scales=1,1.5 full_length=true delay=0.25 skip=false ")
        assertEquals("Welcome*", r.preview)
        assertEquals(listOf("dark"), r.appearances)
        assertEquals(listOf(1.0, 1.5), r.fontScales)
        assertEquals(true, r.fullLength)
        assertEquals(0.25, r.delay)
        assertFalse(r.skip)
        assertNull(r.languages)
        assertNull(r.devices)
        assertEquals(ScreenRule("Empty"), Options.screenFlag("Empty:"))
    }

    @Test fun screenFlagErrors() {
        assertFailsWith<IllegalArgumentException> { Options.screenFlag("no colon here") }
        assertFailsWith<IllegalArgumentException> { Options.screenFlag(": languages=de") }
        assertTrue(assertFailsWith<IllegalArgumentException> { Options.screenFlag("Stats: languages") }.message!!.contains("languages"))
        assertTrue(assertFailsWith<IllegalArgumentException> { Options.screenFlag("Stats: colour=red") }.message!!.contains("colour"))
    }

    @Test fun rulesMatchByGlobFirstWins() {
        val o = parse("--screen", "Stats*: languages=de", "--screen", "*: languages=fr", "--screen", "Stats: languages=ja")
        assertEquals(listOf("de"), o.rule("Stats")!!.languages)
        assertEquals(listOf("de"), o.rule("stats - dark")!!.languages)
        assertEquals(listOf("fr"), o.rule("Welcome")!!.languages)
        assertNull(parse("--screen", "Stats: skip=true").rule("Welcome"))
    }

    @Test fun screenRuleMatchesTheFunctionOnlyWithADot() {
        val card = Preview(composable = "com.example.SettingsScreenKt.ProfileCard", function = "ProfileCard", name = "Profile card")
        assertFalse(ScreenRule("*Settings*", skip = true).matches(card))
        assertTrue(ScreenRule("*Profile*").matches(card))
        assertTrue(ScreenRule("com.example.SettingsScreenKt.*").matches(card))
        assertTrue(ScreenRule("*.ProfileCard").matches(card))
    }

    @Test fun globs() {
        assertTrue(glob("Pixel*").matches("pixel 9"))
        assertTrue(glob("*Fold*").matches("Pixel 9 Pro Fold (folded)"))
        assertTrue(glob("a*b*c").matches("aXXbYYc"))
        assertFalse(glob("Stats").matches("Stats 2"))
        assertFalse(glob("St.ts").matches("Stats"))
        assertTrue(glob("(x)[y]").matches("(x)[y]"))
        assertTrue(ScreenRule("Wel*").matches("Welcome - Dark"))
    }

    @Test fun configFile() {
        config(
            """
            {
              "project_dir": "android",
              "modules": [":app"],
              "variant": "staging",
              "devices": ["Pixel 9", "Pixel Tablet"],
              "watch_devices": ["Wear OS Square"],
              "languages": ["en-US", "sk"],
              "appearances": ["light", "dark"],
              "font_scales": [1, 1.5],
              "previews": ["Welcome*"],
              "output_directory": "fastlane/metadata/android",
              "clear_previous_screenshots": true,
              "html": false,
              "layout": "fastlane",
              "full_length": true,
              "delay": 2,
              "system_ui": "always",
              "android_theme": "android:Theme.DeviceDefault",
              "round_corners": "transparent",
              "parallel": 2,
              "gradle_args": ["--offline"],
              "java_home": "/opt/jdk21",
              "screens": [
                {"preview": "Stats", "languages": ["de-DE"], "devices": ["Pixel*"], "font_scales": [2], "full_length": false, "delay": 0.5},
                {"preview": "Debug*", "skip": true},
                {"preview": "Dark", "appearances": ["dark"]}
              ],
              "platform": "android",
              "android": {"anything": 1}
            }
            """.trimIndent(),
        )
        val o = parse()
        assertEquals(File(dir, "android").path, o.projectDir)
        assertEquals(listOf(":app"), o.modules)
        assertEquals("staging", o.variant)
        assertEquals(listOf("Pixel 9", "Pixel Tablet"), o.devices)
        assertEquals(listOf("Wear OS Square"), o.watchDevices)
        assertEquals(listOf("en-US", "sk"), o.languages)
        assertEquals(listOf("light", "dark"), o.appearances)
        assertEquals(listOf(1.0, 1.5), o.fontScales)
        assertEquals(listOf("Welcome*"), o.previews)
        assertEquals(File(dir, "fastlane/metadata/android").path, o.output)
        assertTrue(o.clear)
        assertFalse(o.html)
        assertEquals("fastlane", o.layout)
        assertTrue(o.fullLength)
        assertEquals(2.0, o.delay)
        assertEquals("always", o.systemUi)
        assertEquals("android:Theme.DeviceDefault", o.theme)
        assertEquals("transparent", o.roundCorners)
        assertEquals(2, o.parallel)
        assertEquals(listOf("--offline"), o.gradleArgs)
        assertEquals("/opt/jdk21", o.javaHome)
        assertEquals(
            listOf(
                ScreenRule("Stats", languages = listOf("de-DE"), devices = listOf("Pixel*"), fontScales = listOf(2.0), fullLength = false, delay = 0.5),
                ScreenRule("Debug*", skip = true),
                ScreenRule("Dark", appearances = listOf("dark")),
            ),
            o.screens,
        )
    }

    @Test fun multiplatformDefaults() {
        val o = parse()
        assertEquals(emptyList(), o.desktopDevices)
        assertEquals(emptyList(), o.iosDevices)
        assertEquals(emptyList(), o.iosVersions)
        assertEquals(emptyList(), o.platforms) // every platform the project has
    }

    @Test fun multiplatformFlags() {
        val o = parse(
            "--desktop-devices", "Desktop 1440×900 @2x, Desktop 1366×768",
            "--ios-devices", "iPhone 17 Pro Max,iPad Pro 13-inch (M5)",
            "--ios", "26.0, 27.0",
            "--platforms", "android,desktop,ios",
        )
        assertEquals(listOf("Desktop 1440×900 @2x", "Desktop 1366×768"), o.desktopDevices)
        assertEquals(listOf("iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"), o.iosDevices)
        assertEquals(listOf("26.0", "27.0"), o.iosVersions)
        assertEquals(listOf("android", "desktop", "ios"), o.platforms)
        assertEquals(listOf("desktop"), parse("--platforms=desktop").platforms)
        assertEquals(listOf("27.0"), parse("--ios=27.0").iosVersions)
    }

    @Test fun multiplatformConfig() {
        config(
            """
            {"desktop_devices": ["Desktop 1920×1080"], "ios_devices": ["iPhone 17"], "ios_versions": ["26.1"], "platforms": ["desktop", "ios"]}
            """.trimIndent(),
        )
        val o = parse()
        assertEquals(listOf("Desktop 1920×1080"), o.desktopDevices)
        assertEquals(listOf("iPhone 17"), o.iosDevices)
        assertEquals(listOf("26.1"), o.iosVersions)
        assertEquals(listOf("desktop", "ios"), o.platforms)
        // Flags win over the config.
        val f = parse("--platforms", "android", "--ios-devices", "iPad mini (A17 Pro)", "--desktop-devices", "Desktop 1280×800", "--ios", "27.0")
        assertEquals(listOf("android"), f.platforms)
        assertEquals(listOf("iPad mini (A17 Pro)"), f.iosDevices)
        assertEquals(listOf("Desktop 1280×800"), f.desktopDevices)
        assertEquals(listOf("27.0"), f.iosVersions)
    }

    @Test fun platformsAreValidated() {
        val e = assertFailsWith<IllegalArgumentException> { parse("--platforms", "android,web") }
        assertTrue(e.message!!.contains("web"))
        assertTrue(e.message!!.contains("platforms"))
        config("""{"platforms": ["macos"]}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse() }.message!!.contains("macos"))
    }

    @Test fun multiplatformFlagsNeedValues() {
        for (flag in listOf("--desktop-devices", "--ios-devices", "--ios", "--platforms")) {
            assertTrue(assertFailsWith<IllegalStateException> { parse(flag) }.message!!.contains(flag))
        }
    }

    @Test fun iosConfigWithoutGradleProjectSaysIosNeedsTheMacTool() {
        config("""{"project": "App.xcodeproj", "scheme": "App"}""")
        assertTrue(assertFailsWith<CliError> { parse() }.message!!.contains("iOS"))
    }

    @Test fun iosKeysInAGradleProjectAreIgnoredWithANote() {
        File(dir, "gradlew").writeText("")
        config("""{"ios_versions": ["27.0"], "scheme": "App", "frame": "appstore", "languages": ["de-DE"]}""")
        val o = parse()
        assertEquals(listOf("de-DE"), o.languages)
        assertEquals("plain", o.frame)
        assertTrue(o.notes.any { "scheme" in it }, o.notes.toString())
        assertTrue(o.notes.any { "App Store frames" in it }, o.notes.toString())
    }

    @Test fun unknownKeysStillRejected() {
        config("""{"langauges": ["de-DE"]}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse() }.message!!.contains("langauges"))
    }

    @Test fun platformFlagAsOnTheMac() {
        assertEquals("list", parse("--platform", "android", "list").command)
        assertTrue(assertFailsWith<CliError> { parse("--platform", "ios", "list") }.message!!.contains("iOS"))
        assertFailsWith<CliError> { parse("--platform", "web") }
    }

    @Test fun macOnlyCommandsSaySo() {
        for (c in listOf("frame", "calibrate", "emit-table"))
            assertTrue(assertFailsWith<CliError> { parse(c) }.message!!.contains("Mac"), c)
    }

    @Test fun explicitConfigPath() {
        val file = config("""{"languages": ["ja"], "output_directory": "shots"}""", File(dir, "conf/my.json"))
        val o = Options.parse(listOf("--config", file.path))
        assertEquals(file.path, o.config)
        assertEquals(listOf("ja"), o.languages)
        // Paths in a config are relative to the config file.
        assertEquals(File(dir, "conf/shots").path, o.output)
    }

    @Test fun missingExplicitConfig() {
        val e = assertFailsWith<IllegalArgumentException> { parse("--config", File(dir, "nope.json").path) }
        assertTrue(e.message!!.contains("nope.json"))
    }

    @Test fun unknownConfigKey() {
        config("""{"languages": ["de"], "langauges": ["fr"]}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse() }.message!!.contains("langauges"))
    }

    @Test fun unknownScreenKey() {
        config("""{"screens": [{"preview": "Stats", "language": ["de"]}]}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse() }.message!!.contains("language"))
    }

    @Test fun malformedConfig() {
        config("""{"languages": ["de",""")
        assertFailsWith<IllegalArgumentException> { parse() }
    }

    @Test fun configIsValidated() {
        config("""{"appearances": ["sepia"]}""")
        assertFailsWith<IllegalArgumentException> { parse() }
        config("""{"font_scales": [4]}""")
        assertFailsWith<IllegalArgumentException> { parse() }
        config("""{"layout": "play"}""")
        assertFailsWith<IllegalArgumentException> { parse() }
        config("""{"round_corners": "white"}""")
        assertFailsWith<IllegalArgumentException> { parse() }
        config("""{"system_ui": "yes"}""")
        assertFailsWith<IllegalArgumentException> { parse() }
    }

    @Test fun flagsOverrideConfig() {
        config(
            """
            {"devices": ["Pixel 9"], "languages": ["de"], "layout": "fastlane", "html": true, "delay": 3, "parallel": 4,
             "output_directory": "cfg", "gradle_args": ["--offline"],
             "screens": [{"preview": "Stats", "languages": ["fr"]}, {"preview": "*", "skip": true}]}
            """.trimIndent(),
        )
        val o = parse(
            "--devices", "Pixel Tablet", "--languages", "ja", "--layout", "swiftshot", "--no-html", "--delay", "0",
            "--parallel", "1", "--output", "flag", "--gradle-arg", "-q", "--screen", "Stats: languages=sk",
        )
        assertEquals(listOf("Pixel Tablet"), o.devices)
        assertEquals(listOf("ja"), o.languages)
        assertEquals("swiftshot", o.layout)
        assertFalse(o.html)
        assertEquals(0.0, o.delay)
        assertEquals(1, o.parallel)
        assertEquals("flag", o.output)
        assertEquals(listOf("--offline", "-q"), o.gradleArgs)
        // --screen rules come first, so they win over the config's.
        assertEquals(listOf("sk"), o.rule("Stats")!!.languages)
        assertEquals(3, o.screens.size)
        assertTrue(o.rule("Welcome")!!.skip)
    }

    @Test fun projectDirFlagBeatsAnExplicitConfig() {
        val file = config("""{"project_dir": "from-config"}""", File(dir, "conf/swiftshot.json"))
        assertEquals(File(dir, "conf/from-config").path, Options.parse(listOf("--config", file.path)).projectDir)
        assertEquals("/elsewhere", Options.parse(listOf("--config", file.path, "--project-dir", "/elsewhere")).projectDir)
    }

    @Test fun configInProjectDirIsFound() {
        val project = File(dir, "proj").apply { mkdirs() }
        config("""{"languages": ["cs"]}""", File(project, "swiftshot.json"))
        assertEquals(listOf("cs"), Options.parse(listOf("--project-dir", project.path)).languages)
        assertEquals(listOf("en-US"), parse().languages)
    }

    @Test fun baselineDefaultsAndKeys() {
        val o = parse("verify")
        assertEquals("verify", o.command)
        assertEquals(File("screenshots-baseline").absoluteFile, o.baselineDir(flutter = false))
        assertEquals(File("screenshots-report").absoluteFile, o.reportDir(flutter = false))
        assertEquals(File(dir, "screenshots-baseline"), o.baselineDir(flutter = true))
        config("""{"baseline_directory": "golden", "report_directory": "out/report", "output_directory": "shots",
            "tolerance": {"pixels": 5, "max_channel_delta": 1},
            "screens": [{"preview": "Clock*", "tolerance": {"max_channel_delta": 2}}, {"preview": "Feed", "ignore_regions": [[0, 0, 16, 4.5]]}]}""")
        val c = parse("record")
        assertEquals(File(dir, "golden"), c.baselineDir(flutter = false))
        assertEquals(File(dir, "out/report"), c.reportDir(flutter = false))
        assertEquals(Tolerance(5, 1), c.tolerance)
        assertEquals(Tolerance(0, 2), c.screens[0].tolerance)
        assertEquals(listOf(listOf(0.0, 0.0, 16.0, 4.5)), c.screens[1].ignoreRegions)
        assertNull(c.screens[1].tolerance)
        val flags = parse("verify", "--baseline-directory", "b", "--report-directory", "r")
        assertEquals(File("b").absoluteFile, flags.baselineDir(flutter = false))
        assertEquals(File("r").absoluteFile, flags.reportDir(flutter = false))
        // The report defaults next to the output.
        config("""{"output_directory": "shots"}""")
        assertEquals(File(dir, "shots-report"), parse("verify").reportDir(flutter = false))
    }

    @Test fun toleranceIsValidated() {
        config("""{"tolerance": {"pixel": 5}}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("verify") }.message!!.contains("pixel"))
        config("""{"tolerance": {"pixels": -1}}""")
        assertFailsWith<IllegalArgumentException> { parse("verify") }
        config("""{"tolerance": {"max_channel_delta": 1.5}}""")
        assertFailsWith<IllegalArgumentException> { parse("verify") }
        config("""{"screens": [{"preview": "X", "tolerance": {"delta": 1}}]}""")
        assertTrue(assertFailsWith<IllegalArgumentException> { parse("verify") }.message!!.contains("delta"))
        config("""{"screens": [{"preview": "X", "ignore_regions": [[0, 0, 16]]}]}""")
        assertFailsWith<IllegalArgumentException> { parse("verify") }
    }

    @Test fun verifyAndRecordRejectJpegAndFrames() {
        for (command in listOf("verify", "record")) {
            val e = assertFailsWith<UsageError> { parse(command, "--format", "jpeg") }
            assertTrue(e.message!!.contains("PNG"), e.message)
            assertFailsWith<UsageError> { parse(command, "--frame", "plain") }
            assertEquals(64, cli(listOf(command, "--project-dir", dir.path, "--format", "jpeg"), Log(false)))
            assertEquals(64, cli(listOf(command, "--project-dir", dir.path, "--no-such-flag"), Log(false)))
        }
        assertEquals("png", parse("verify", "--format", "png").format)
        // A config's frame is skipped, not an error.
        config("""{"frame": "plain"}""")
        assertEquals("none", parse("verify").frame)
        assertEquals("plain", parse("run").frame)
    }
}
