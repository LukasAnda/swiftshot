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

class RunnerPlanTest {
    private val dir: File = Files.createTempDirectory("swiftshot-plan").toFile()
    private val out = File(dir, "out")

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    /** What the init script would report for a module. */
    private fun module(path: String = ":app", wear: Boolean = false) = Module(
        mapOf(
            "module" to path, "packageName" to "com.example", "wear" to wear,
            "classDirs" to listOf("$dir/classes"), "classpath" to emptyList<String>(), "components" to emptyList<String>(),
            "layoutlibRuntime" to "$dir/runtime.jar", "layoutlibResources" to "$dir/resources.jar", "compileSdk" to 36L,
        ),
    )

    private fun runner(vararg args: String) = Runner(Options.parse(listOf("--project-dir", dir.path, "--output", out.path) + args), Log(false))

    private fun preview(name: String, function: String = name.substringBefore(" - "), composable: String = "com.example.UiKt.$function") =
        Preview(composable = composable, function = function, name = name)

    private fun plan(previews: List<Preview>, vararg args: String, module: Module = module()) = runner(*args).plan(module, previews)

    private fun List<Shot>.files() = map { it.file.relativeTo(out).path }

    @Test fun defaultMatrix() {
        val m = module()
        val shots = plan(listOf(preview("Welcome")), module = m)
        assertEquals(listOf("en-US/Pixel 10 Pro-Welcome.png", "en-US/Pixel Tablet-Welcome.png"), shots.files())
        for (s in shots) {
            assertEquals(m, s.module)
            assertEquals("en-US", s.language)
            assertFalse(s.dark)
            assertEquals(1.0, s.fontScale)
            assertEquals("shrink", s.mode)
            assertFalse(s.systemUi)
            assertEquals(0L, s.delayMs)
            assertTrue(s.file.isAbsolute)
        }
        assertEquals(listOf("Pixel 10 Pro", "Pixel Tablet"), shots.map { it.device.name })
    }

    @Test fun fullMatrix() {
        val shots = plan(
            listOf(preview("Welcome"), preview("Stats")),
            "--devices", "Pixel 9,Pixel Tablet", "--languages", "en-US,de-DE", "--appearances", "light,dark", "--font-scales", "1,1.5",
        )
        assertEquals(2 * 2 * 2 * 2 * 2, shots.size)
        assertEquals(shots.size, shots.map { it.file }.toSet().size)
        assertEquals(
            listOf(
                "en-US/Pixel 9-Welcome-light-1x.png", "en-US/Pixel 9-Welcome-light-1.5x.png",
                "en-US/Pixel 9-Welcome-dark-1x.png", "en-US/Pixel 9-Welcome-dark-1.5x.png",
                "de-DE/Pixel 9-Welcome-light-1x.png", "de-DE/Pixel 9-Welcome-light-1.5x.png",
                "de-DE/Pixel 9-Welcome-dark-1x.png", "de-DE/Pixel 9-Welcome-dark-1.5x.png",
            ),
            shots.take(8).files(),
        )
        val s = shots.first { it.file.name == "Pixel Tablet-Stats-dark-1.5x.png" && it.language == "de-DE" }
        assertTrue(s.dark)
        assertEquals(1.5, s.fontScale)
        assertEquals("Pixel Tablet", s.device.name)
    }

    @Test fun matrixDevicesMayBeGlobsAndIds() {
        val shots = plan(listOf(preview("Welcome")), "--devices", "pixel_9,Pixel 9 Pro Fold*")
        assertEquals(listOf("Pixel 9", "Pixel 9 Pro Fold (folded)", "Pixel 9 Pro Fold"), shots.map { it.device.name })
    }

    @Test fun darkOnlyGetsASuffix() {
        assertEquals(listOf("en-US/Pixel 9-Welcome-dark.png"), plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--appearances", "dark").files())
    }

    @Test fun singleNonDefaultScaleGetsASuffix() {
        assertEquals(listOf("en-US/Pixel 9-Welcome-1.3x.png"), plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--font-scales", "1.3").files())
        assertEquals(listOf("en-US/Pixel 9-Welcome-2x.png"), plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--font-scales", "2").files())
    }

    @Test fun previewSettingsBeatTheMatrix() {
        val p = preview("Welcome").copy(device = "id:pixel_9", locale = "ja", uiMode = 0x21, fontScale = 1.3)
        val shots = plan(
            listOf(p), "--devices", "Pixel Tablet,Pixel 10 Pro", "--languages", "en-US,de-DE", "--appearances", "light,dark", "--font-scales", "1,2",
        )
        val s = shots.single()
        assertEquals("Pixel 9", s.device.name)
        assertEquals("ja", s.language)
        assertTrue(s.dark)
        assertEquals(1.3, s.fontScale)
        // The preview chose these, so the names carry no appearance or scale.
        assertEquals("ja/Pixel 9-Welcome.png", s.file.relativeTo(out).path)
    }

    @Test fun previewLightModeBeatsTheMatrix() {
        val shots = plan(listOf(preview("Welcome").copy(uiMode = 0x11)), "--devices", "Pixel 9", "--appearances", "light,dark")
        assertEquals(listOf(false), shots.map { it.dark })
        assertEquals(listOf("en-US/Pixel 9-Welcome.png"), shots.files())
    }

    @Test fun previewDeviceSpecs() {
        val spec = plan(listOf(preview("Welcome").copy(device = "spec:width=411dp,height=891dp")))
        assertEquals(listOf("en-US/Phone-Welcome.png"), spec.files())
        assertEquals(1079, spec.single().device.width)
        val land = plan(listOf(preview("Welcome").copy(device = "spec:parent=pixel_9,orientation=landscape")))
        assertEquals("Pixel 9 (landscape)", land.single().device.name)
        val named = plan(listOf(preview("Welcome").copy(device = "name:Pixel Tablet")))
        assertEquals("Pixel Tablet", named.single().device.name)
    }

    @Test fun previewDeviceBeatsARule() {
        val shots = plan(listOf(preview("Welcome").copy(device = "id:pixel_9")), "--screen", "Welcome: devices=pixel_tablet")
        assertEquals("Pixel 9", shots.single().device.name)
    }

    @Test fun unknownPreviewDevice() {
        val e = assertFailsWith<CliError> { plan(listOf(preview("Welcome").copy(device = "id:nokia_3310"))) }
        assertTrue(e.message!!.contains("Welcome") && e.message!!.contains("nokia_3310"))
    }

    @Test fun unknownMatrixDevice() {
        assertFailsWith<IllegalArgumentException> { plan(listOf(preview("Welcome")), "--devices", "iPhone 17") }
    }

    @Test fun previewSize() {
        val shots = plan(listOf(preview("Welcome").copy(widthDp = 300)), "--devices", "Pixel 10 Pro")
        assertEquals(900 to 2856, shots.single().device.width to shots.single().device.height)
        val both = plan(listOf(preview("Welcome").copy(widthDp = 320, heightDp = 640, device = "id:pixel_9")))
        assertEquals(840 to 1680, both.single().device.width to both.single().device.height)
    }

    @Test fun previewLocales() {
        fun lang(locale: String) = plan(listOf(preview("Welcome").copy(locale = locale)), "--devices", "Pixel 9").single().language
        assertEquals("de", lang("de"))
        assertEquals("de-DE", lang("de-DE"))
        assertEquals("pt-BR", lang("pt_BR"))
        // Android Studio writes resource qualifiers.
        assertEquals("fr-FR", lang("fr-rFR"))
        assertEquals("sr-Latn", lang("b+sr+Latn"))
        assertEquals("zh-Hans-CN", lang("b+zh+Hans+CN"))
    }

    @Test fun screenRules() {
        val shots = plan(
            listOf(preview("Welcome"), preview("Stats"), preview("Debug")),
            "--devices", "Pixel 9",
            "--screen", "Stats: languages=de-DE,ja devices=pixel_tablet,pixel_10_pro appearances=dark font_scales=2 full_length=true delay=0.25",
            "--screen", "Debug: skip=true",
        )
        val welcome = shots.filter { it.preview.name == "Welcome" }
        assertEquals(listOf("en-US/Pixel 9-Welcome.png"), welcome.files())
        assertEquals("shrink", welcome.single().mode)
        assertEquals(0L, welcome.single().delayMs)
        val stats = shots.filter { it.preview.name == "Stats" }
        assertEquals(
            listOf(
                "de-DE/Pixel Tablet-Stats-dark-2x.png", "ja/Pixel Tablet-Stats-dark-2x.png",
                "de-DE/Pixel 10 Pro-Stats-dark-2x.png", "ja/Pixel 10 Pro-Stats-dark-2x.png",
            ),
            stats.files(),
        )
        assertTrue(stats.all { it.mode == "vscroll" && it.delayMs == 250L && it.dark && it.fontScale == 2.0 })
        assertTrue(shots.none { it.preview.name == "Debug" })
    }

    @Test fun ruleGlobs() {
        val shots = plan(listOf(preview("Stats - Light"), preview("Stats - Dark"), preview("Welcome")), "--devices", "Pixel 9", "--screen", "stats*: skip=true")
        assertEquals(listOf("Welcome"), shots.map { it.preview.name })
    }

    @Test fun ruleFullLengthOverridesTheFlag() {
        val shots = plan(listOf(preview("Welcome"), preview("Stats")), "--devices", "Pixel 9", "--full-length", "--screen", "Stats: full_length=false")
        assertEquals(mapOf("Welcome" to "vscroll", "Stats" to "shrink"), shots.associate { it.preview.name to it.mode })
    }

    @Test fun previewsFilter() {
        val all = listOf(preview("Welcome"), preview("Welcome - Dark"), preview("Stats"), preview("Settings"), preview("Statistics"))
        val shots = plan(all, "--devices", "Pixel 9", "--previews", "Welcome*,stats")
        assertEquals(listOf("Welcome", "Welcome - Dark", "Stats"), shots.map { it.preview.name })
        assertTrue(plan(all, "--previews", "Nope").isEmpty())
    }

    @Test fun watchModule() {
        val shots = plan(listOf(preview("Tile")), "--appearances", "light,dark", "--devices", "Pixel 9", module = module(":wear", wear = true))
        val s = shots.single()
        assertEquals("Wear OS Large Round", s.device.name)
        assertTrue(s.dark)
        assertEquals("en-US/Wear OS Large Round-Tile.png", s.file.relativeTo(out).path)
    }

    @Test fun watchDevicesFlag() {
        val shots = plan(listOf(preview("Tile")), "--watch-devices", "Wear OS Small Round,wearos_square", module = module(":wear", wear = true))
        assertEquals(listOf("Wear OS Small Round", "Wear OS Square"), shots.map { it.device.name })
        assertTrue(shots.all { it.dark })
    }

    @Test fun watchPreviewDeviceInAPhoneModule() {
        val shots = plan(listOf(preview("Tile").copy(device = "id:wearos_small_round")), "--appearances", "light,dark")
        assertEquals(listOf("en-US/Wear OS Small Round-Tile.png"), shots.files())
        assertTrue(shots.single().dark)
        val round = plan(listOf(preview("Tile").copy(device = "spec:width=227dp,height=227dp,dpi=320,isRound=true")), "--appearances", "light,dark")
        assertEquals(listOf(true), round.map { it.dark })
        assertEquals("watch", round.single().device.type)
    }

    @Test fun watchStillScalesFonts() {
        val shots = plan(listOf(preview("Tile")), "--font-scales", "1,2", module = module(":wear", wear = true))
        assertEquals(listOf("en-US/Wear OS Large Round-Tile-1x.png", "en-US/Wear OS Large Round-Tile-2x.png"), shots.files())
    }

    @Test fun fastlaneLayout() {
        val shots = plan(listOf(preview("Welcome")), "--layout", "fastlane", "--devices", "Pixel 10 Pro,Pixel 9 Pro Fold,Pixel 9 Pro Fold (folded),Nexus 7,Pixel Tablet")
        assertEquals(
            listOf(
                "en-US/images/phoneScreenshots/Pixel 10 Pro-Welcome.png",
                "en-US/images/sevenInchScreenshots/Pixel 9 Pro Fold-Welcome.png",
                "en-US/images/phoneScreenshots/Pixel 9 Pro Fold (folded)-Welcome.png",
                "en-US/images/sevenInchScreenshots/Nexus 7-Welcome.png",
                "en-US/images/tenInchScreenshots/Pixel Tablet-Welcome.png",
            ),
            shots.files(),
        )
        val wear = plan(listOf(preview("Tile")), "--layout", "fastlane", "--languages", "de-DE", module = module(":wear", wear = true))
        assertEquals(listOf("de-DE/images/wearScreenshots/Wear OS Large Round-Tile.png"), wear.files())
    }

    @Test fun duplicateNamesGetANumber() {
        val shots = plan(
            listOf(preview("Welcome", composable = "a.AKt.Welcome"), preview("Welcome", composable = "b.BKt.Welcome"), preview("Welcome", composable = "c.CKt.Welcome")),
            "--devices", "Pixel 9", "--appearances", "light,dark",
        )
        assertEquals(
            listOf(
                "en-US/Pixel 9-Welcome-light.png", "en-US/Pixel 9-Welcome-dark.png",
                "en-US/Pixel 9-Welcome-light 2.png", "en-US/Pixel 9-Welcome-dark 2.png",
                "en-US/Pixel 9-Welcome-light 3.png", "en-US/Pixel 9-Welcome-dark 3.png",
            ),
            shots.files(),
        )
        assertEquals(listOf("a.AKt.Welcome", "a.AKt.Welcome", "b.BKt.Welcome", "b.BKt.Welcome", "c.CKt.Welcome", "c.CKt.Welcome"), shots.map { it.preview.composable })
    }

    @Test fun samePreviewOnTwoModulesDoesNotClashWithinAPlan() {
        // Numbering is per plan (one module), so separate modules each start clean.
        val r = runner("--devices", "Pixel 9")
        assertEquals(listOf("en-US/Pixel 9-Welcome.png"), r.plan(module(":a"), listOf(preview("Welcome"))).files())
        assertEquals(listOf("en-US/Pixel 9-Welcome.png"), r.plan(module(":b"), listOf(preview("Welcome"))).files())
    }

    @Test fun pathCharactersAreCleaned() {
        assertEquals(listOf("en-US/Pixel 9-Login-Signup- step 1.png"), plan(listOf(preview("Login/Signup: step 1")), "--devices", "Pixel 9").files())
    }

    @Test fun fontScaleSuffixOnlyForMatrixScales() {
        val shots = plan(
            listOf(preview("Welcome"), preview("Large").copy(fontScale = 2.0)),
            "--devices", "Pixel 9", "--font-scales", "1,1.3",
        )
        assertEquals(
            listOf("en-US/Pixel 9-Welcome-1x.png", "en-US/Pixel 9-Welcome-1.3x.png", "en-US/Pixel 9-Large.png"),
            shots.files(),
        )
        assertEquals(listOf(1.0, 1.3, 2.0), shots.map { it.fontScale })
    }

    @Test fun modes() {
        fun mode(p: Preview, vararg args: String) = plan(listOf(p), "--devices", "Pixel 9", *args).single().let { it.mode to it.systemUi }
        val plain = preview("Welcome")
        val withUi = plain.copy(showSystemUi = true)
        assertEquals("shrink" to false, mode(plain))
        assertEquals("normal" to true, mode(withUi))
        assertEquals("normal" to true, mode(plain, "--system-ui", "always"))
        assertEquals("shrink" to false, mode(withUi, "--system-ui", "never"))
        assertEquals("normal" to true, mode(withUi, "--system-ui", "preview"))
        assertEquals("vscroll" to false, mode(plain, "--full-length"))
        assertEquals("vscroll" to true, mode(withUi, "--full-length"))
        assertEquals("vscroll" to false, mode(plain, "--screen", "Welcome: full_length=true"))
    }

    @Test fun delays() {
        assertEquals(500L, plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--delay", "0.5").single().delayMs)
        assertEquals(1500L, plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--delay", "0.5", "--screen", "Welcome: delay=1.5").single().delayMs)
    }

    @Test fun ruleAppearancesAndScales() {
        val shots = plan(listOf(preview("Welcome")), "--devices", "Pixel 9", "--screen", "Welcome: appearances=light,dark font_scales=1")
        assertEquals(listOf("en-US/Pixel 9-Welcome-light.png", "en-US/Pixel 9-Welcome-dark.png"), shots.files())
    }

    @Test fun emptyPreviewList() {
        assertTrue(plan(emptyList()).isEmpty())
    }

    @Test fun qualifiers() {
        val r = runner()
        assertEquals("en-rUS", r.qualifier("en-US"))
        assertEquals("pt-rBR", r.qualifier("pt_BR"))
        assertEquals("de-rDE", r.qualifier("de-de"))
        assertEquals("sk", r.qualifier("sk"))
        assertEquals("b+zh+Hans+CN", r.qualifier("zh-Hans-CN"))
        assertEquals("b+sr+Latn", r.qualifier("sr-Latn"))
        assertEquals("b+es+419", r.qualifier("es-419"))
    }

    @Test fun bcp47() {
        val r = runner()
        assertEquals("en-US", r.bcp47("en-rUS"))
        assertEquals("en-US", r.bcp47("en-US"))
        assertEquals("en-US", r.bcp47("en_US"))
        assertEquals("de", r.bcp47("de"))
        assertEquals("zh-Hans-CN", r.bcp47("b+zh+Hans+CN"))
        assertEquals("es-419", r.bcp47("es-419"))
        for (tag in listOf("en-US", "sk", "zh-Hans-CN", "sr-Latn", "pt-BR")) assertEquals(tag, r.bcp47(r.qualifier(tag)))
    }

    @Test fun rightToLeft() {
        val r = runner()
        for (tag in listOf("ar", "ar-EG", "he", "he-IL", "iw", "fa-IR", "ur", "ps", "sd", "ug", "yi", "dv", "ckb", "ar_SA")) assertTrue(r.rtl(tag), tag)
        for (tag in listOf("en-US", "de", "ja", "zh-Hans-CN", "sk", "arn", "hea")) assertFalse(r.rtl(tag), tag)
    }
}

class ModuleThemeTest {
    private fun module(manifest: String?): Module {
        val dir = kotlin.io.path.createTempDirectory("swiftshot-theme").toFile()
        if (manifest != null) File(dir, "src/main").apply { mkdirs() }.resolve("AndroidManifest.xml").writeText(manifest)
        return Module(mapOf(
            "module" to ":app", "projectDir" to dir.path, "packageName" to "a", "wear" to false,
            "classDirs" to emptyList<String>(), "classpath" to emptyList<String>(),
            "layoutlibRuntime" to "", "layoutlibResources" to "", "components" to emptyList<String>(),
        ))
    }

    @Test fun projectTheme() = assertEquals("Theme.Habits", module("""<manifest><application android:label="x"
        android:theme="@style/Theme.Habits"><activity android:theme="@style/Other"/></application></manifest>""").theme)

    @Test fun frameworkTheme() = assertEquals("android:Theme.DeviceDefault",
        module("""<manifest><application android:theme="@android:style/Theme.DeviceDefault"/></manifest>""").theme)

    @Test fun noTheme() {
        assertNull(module("""<manifest><application android:label="x"/></manifest>""").theme)
        assertNull(module(null).theme)
    }
}
