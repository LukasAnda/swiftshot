package swiftshot.android

import swiftshot.android.shared.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TestDevicesTest {
    private val json = Json.parse(TestDevicesTest::class.java.getResourceAsStream("/paparazzi-devices.json")!!.bufferedReader().readText()) as Map<*, *>
    private val presets = (json["paparazzi"] as Map<*, *>)["presets"] as Map<*, *>
    private val constants = (json["robolectricDeviceQualifiers"] as Map<*, *>)["constants"] as Map<*, *>

    private fun recorded(name: String): Screen {
        val p = presets[name] as Map<*, *>
        val w = (p["width"] as Number).toInt(); val h = (p["height"] as Number).toInt()
        val land = p["orientation"] == "landscape"
        return Screen(if (land) maxOf(w, h) else minOf(w, h), if (land) minOf(w, h) else maxOf(w, h), (p["density"] as Number).toInt(), p["round"] as Boolean, land)
    }

    private fun exact(s: Screen) = Devices.all.firstOrNull { it.width == s.widthPx && it.height == s.heightPx && it.density == s.densityDpi && it.round == s.round }

    private fun spec(s: Screen): String {
        fun dp(px: Int): String {
            if (px * 160 % s.densityDpi == 0) return "${px * 160 / s.densityDpi}dp"
            val one = "%.1f".format(java.util.Locale.ROOT, px * 160.0 / s.densityDpi)
            return if (Math.round(one.toDouble() * s.densityDpi / 160).toInt() == px) "${one}dp" else "${px}px"
        }
        return "spec:width=${dp(s.widthPx)},height=${dp(s.heightPx)},dpi=${s.densityDpi}" + (if (s.round) ",isRound=true" else "") + (if (s.landscape) ",orientation=landscape" else "")
    }

    private fun read(source: DeviceSource): Screen = assertIs<DeviceSource.Read>(source).screen

    @Test fun presetMapsToSpecWhenDensityDiffers() {
        val pixel5 = recorded("PIXEL_5")
        assertEquals(pixel5, TestDevices.paparazziPreset("PIXEL_5"))
        val catalog = Devices.all.single { it.name == "Pixel 5" }
        val expected = if (catalog.width == pixel5.widthPx && catalog.height == pixel5.heightPx && catalog.density == pixel5.densityDpi) "Pixel 5" else spec(pixel5)
        assertEquals(expected, TestDevices.deviceName(pixel5, "PIXEL_5"))
        // The catalog's Wear OS Square is not what Paparazzi's WEAR_OS_SQUARE renders.
        val square = recorded("WEAR_OS_SQUARE")
        assertNull(exact(square))
        assertEquals(spec(square), TestDevices.deviceName(square))
        // Paparazzi renders PIXEL_FOLD portrait; the catalog's Pixel Fold is landscape.
        assertEquals(spec(recorded("PIXEL_FOLD")), TestDevices.deviceName(recorded("PIXEL_FOLD"), "PIXEL_FOLD"))
        for (name in presets.keys) assertEquals(recorded(name as String), TestDevices.paparazziPreset(name), name)
        assertNull(TestDevices.paparazziPreset("PIXEL_99"))
    }

    @Test fun exactCatalogMatchUsesName() {
        val d = Devices.all.first { it.name == "Pixel 9" }
        assertEquals("Pixel 9", TestDevices.deviceName(Screen(d.width, d.height, d.density, d.round), "Pixel 9"))
        assertEquals(exact(Screen(d.width, d.height, d.density))!!.name, TestDevices.deviceName(Screen(d.width, d.height, d.density)))
    }

    @Test fun defaults() {
        assertEquals(recorded("NEXUS_5"), TestDevices.paparazziDefault())
        assertEquals("Nexus 5", TestDevices.deviceName(TestDevices.paparazziDefault(), "NEXUS_5"))
        assertEquals(Screen(320, 470, 160), TestDevices.robolectricDefault())
        assertEquals(DeviceSource.ToolDefault(Screen(320, 470, 160), SnapshotTool.ROBORAZZI) to TestSettings(), TestDevices.parseQualifiers(""))
        assertEquals(DeviceSource.ToolDefault(Screen(320, 470, 160), SnapshotTool.ROBORAZZI) to TestSettings(night = true), TestDevices.parseQualifiers("+night"))
    }

    @Test fun presetExpression() {
        assertEquals(DeviceSource.Read(recorded("PIXEL_5"), "DeviceConfig.PIXEL_5") to TestSettings(), TestDevices.parseDeviceConfig("DeviceConfig.PIXEL_5"))
        assertEquals(DeviceSource.Unresolved("DeviceConfig.PIXEL_99"), TestDevices.parseDeviceConfig("DeviceConfig.PIXEL_99").first)
        val land = TestDevices.parseDeviceConfig("DeviceConfig.PIXEL_5.copy(orientation = ScreenOrientation.LANDSCAPE)").first
        assertEquals(Screen(2340, 1080, 440, landscape = true), read(land))
    }

    @Test fun customDeviceConfig() {
        val (source, settings) = TestDevices.parseDeviceConfig(
            """
            DeviceConfig(
                screenWidth = 1440,
                screenHeight = 3120,
                xdpi = 512,
                ydpi = 512,
                density = Density.XXXHIGH,
                ratio = ScreenRatio.LONG,
            )
            """.trimIndent(),
        )
        assertEquals(Screen(1440, 3120, 640), read(source))
        assertEquals("spec:width=360dp,height=780dp,dpi=640", TestDevices.deviceName(read(source)))
        assertEquals(TestSettings(), settings)
        assertEquals(Screen(1080, 1920, 420), read(TestDevices.parseDeviceConfig("DeviceConfig(screenWidth = 1080, screenHeight = 1920, density = Density.create(420))").first))
        assertEquals(Screen(454, 454, 320, round = true), read(TestDevices.parseDeviceConfig("DeviceConfig(screenWidth = 454, screenHeight = 454, screenRound = ScreenRound.ROUND)").first))
    }

    @Test fun copyCarriesSettings() {
        val (source, settings) = TestDevices.parseDeviceConfig("""DeviceConfig.PIXEL_5.copy(nightMode = NightMode.NIGHT, locale = "de-rDE", fontScale = 1.3f)""")
        assertEquals(DeviceSource.Read(recorded("PIXEL_5"), "DeviceConfig.PIXEL_5"), source)
        assertEquals(TestSettings(locale = "de-DE", night = true, fontScale = 1.3), settings)
        assertEquals(TestSettings(locale = "sr-Latn"), TestDevices.parseDeviceConfig("""DeviceConfig.PIXEL_5.copy(locale = "b+sr+Latn")""").second)
    }

    @Test fun qualifiers() {
        val (source, settings) = TestDevices.parseQualifiers("w411dp-h891dp-xxhdpi-night-de")
        assertEquals(DeviceSource.Read(Screen(1233, 2673, 480), "w411dp-h891dp-xxhdpi"), source)
        assertEquals(TestSettings(locale = "de", night = true), settings)
        assertEquals(Screen(454, 454, 320, round = true), read(TestDevices.parseQualifiers("w227dp-h227dp-small-long-round-watch-xhdpi").first))
        assertEquals(Screen(2673, 1233, 480, landscape = true), read(TestDevices.parseQualifiers("w411dp-h891dp-land-xxhdpi").first))
        assertEquals(TestSettings(locale = "de-DE"), TestDevices.parseQualifiers("de-rDE-w411dp-h891dp-xxhdpi").second)
        // Robolectric truncates dp × density: 411 × 2.625 = 1078.875 → 1078.
        assertEquals(Screen(1078, 2399, 420), read(TestDevices.parseQualifiers("w411dp-h914dp-420dpi").first))
        val pixel5 = TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel5").first
        assertEquals(DeviceSource.Read(Screen(1080, 2340, 440), "RobolectricDeviceQualifiers.Pixel5"), pixel5)
        assertEquals("Pixel 5", TestDevices.deviceName(read(pixel5), "Pixel5"))
    }

    @Test fun unresolvable() {
        val expr = "DeviceConfig(screenWidth = width, screenHeight = 2400)"
        assertEquals(DeviceSource.Unresolved(expr), TestDevices.parseDeviceConfig(expr).first)
        assertIs<DeviceSource.Unresolved>(TestDevices.parseDeviceConfig("deviceConfigFor(phone)").first)
        assertIs<DeviceSource.Unresolved>(TestDevices.parseDeviceConfig("DeviceConfig.PIXEL_5.copy(locale = lang)").first)
        assertIs<DeviceSource.Unresolved>(TestDevices.parseQualifiers("RobolectricDeviceQualifiers.Pixel99").first)
        assertIs<DeviceSource.Unresolved>(TestDevices.parseQualifiers("w\${width}dp").first)
        assertIs<DeviceSource.Unresolved>(TestDevices.parseQualifiers("w411dp-bogus").first)
    }

    @Test fun pixelSizeOnlyWithDensityAndNothingElseOnScreen() {
        assertEquals(Screen(1080, 2340, 440), read(TestDevices.parseQualifiers("1080x2340-440dpi").first))
        for (q in listOf("1080x2340", "w411dp-1080x2340-440dpi", "1080x2340-land-440dpi", "1080x2340-port-440dpi", "large-1080x2340-440dpi", "long-1080x2340-440dpi"))
            assertIs<DeviceSource.Unresolved>(TestDevices.parseQualifiers(q).first, q)
    }

    @Test fun roundTripThroughDevices() {
        val screens = presets.keys.map { recorded(it as String) } + constants.values.map { read(TestDevices.parseQualifiers(it as String).first) } +
            listOf(TestDevices.robolectricDefault(), Screen(1081, 2401, 420), Screen(2340, 1080, 440, landscape = true), Screen(384, 384, 320, round = true))
        for (s in screens) {
            val name = TestDevices.deviceName(s)
            val d = if (name.startsWith("spec:")) Devices.fromPreview(name)!! else Devices.all.single { it.name == name }
            assertEquals(listOf(s.widthPx, s.heightPx, s.densityDpi), listOf(d.width, d.height, d.density), "$s → $name")
            assertEquals(s.round, d.round, "$s → $name")
        }
        assertTrue(screens.any { TestDevices.deviceName(it).contains("px") || TestDevices.deviceName(it).contains(".") })
    }
}
