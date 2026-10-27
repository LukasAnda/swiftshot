package swiftshot.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DevicesTest {
    private fun named(name: String) = Devices.all.single { it.name == name }

    @Test fun catalogLoads() {
        assertTrue(Devices.all.size > 50, "only ${Devices.all.size} devices")
        for (name in listOf("Pixel 9", "Pixel 10 Pro", "Pixel Tablet", "Pixel 9 Pro Fold", "Wear OS Large Round", "Television (1080p)")) named(name)
    }

    @Test fun namesAndIdsAreUnique() {
        assertEquals(Devices.all.size, Devices.all.map { it.name.lowercase() }.toSet().size, "duplicate names")
        assertEquals(Devices.all.size, Devices.all.map { it.id.lowercase() }.toSet().size, "duplicate ids")
    }

    @Test fun everyDeviceIsSane() {
        val types = setOf("phone", "foldable", "tablet", "watch", "tv", "car", "desktop", "xr")
        for (d in Devices.all) {
            assertTrue(d.width in 200..8000 && d.height in 200..8000, "${d.name}: ${d.width}x${d.height}")
            assertTrue(d.density in 100..700, "${d.name}: ${d.density} dpi")
            assertTrue(d.xdpi > 0 && d.ydpi > 0, "${d.name}: xdpi/ydpi")
            assertTrue(d.type in types, "${d.name}: type ${d.type}")
            assertTrue(d.size in setOf("small", "normal", "large", "xlarge"), "${d.name}: size ${d.size}")
            assertTrue(d.diagonal >= 0, "${d.name}: diagonal")
            assertTrue(d.widthDp > 100 && d.heightDp > 100, "${d.name}: ${d.widthDp}x${d.heightDp} dp")
            if (d.round) assertEquals("watch", d.type, "${d.name} is round")
            assertTrue(d.name.isNotBlank() && d.id.isNotBlank())
        }
    }

    @Test fun defaultsResolve() {
        assertEquals(Devices.defaults, Devices.resolve(Devices.defaults).map { it.name })
        assertEquals(Devices.defaultWatch, Devices.resolve(Devices.defaultWatch).map { it.name })
        assertEquals("watch", Devices.resolve(Devices.defaultWatch).single().type)
    }

    @Test fun pixel9() {
        val d = named("Pixel 9")
        assertEquals("pixel_9", d.id)
        assertEquals("phone", d.type)
        assertEquals(1080 to 2424, d.width to d.height)
        assertEquals(420, d.density)
        assertEquals(411.43, d.widthDp, 0.01)
    }

    @Test fun foldablesHaveFoldedEntries() {
        val foldables = Devices.all.filter { it.type == "foldable" }
        assertTrue(foldables.isNotEmpty())
        for (f in foldables) {
            val folded = Devices.all.singleOrNull { it.id == "${f.id}:folded" }
            assertNotNull(folded, "${f.name} has no folded entry")
            assertEquals("${f.name} (folded)", folded.name)
            assertEquals("phone", folded.type)
            assertEquals(f.density, folded.density)
            assertTrue(folded.diagonal < f.diagonal, "${folded.name}: outer screen is smaller")
        }
        val fold = named("Pixel 9 Pro Fold (folded)")
        assertEquals(1080 to 2424, fold.width to fold.height)
        assertEquals("pixel_9_pro_fold:folded", fold.id)
    }

    @Test fun resolveByNameIdAndCase() {
        assertEquals("Pixel 9", Devices.resolve(listOf("Pixel 9")).single().name)
        assertEquals("Pixel 9", Devices.resolve(listOf("pixel_9")).single().name)
        assertEquals("Pixel 9", Devices.resolve(listOf("PIXEL 9")).single().name)
        assertEquals("Pixel 9", Devices.resolve(listOf("PIXEL_9")).single().name)
        assertEquals("Pixel Tablet", Devices.resolve(listOf("pixel tablet")).single().name)
    }

    @Test fun resolveKeepsTheOrderAsked() {
        assertEquals(listOf("Pixel Tablet", "Pixel 9", "Pixel 10 Pro"), Devices.resolve(listOf("Pixel Tablet", "pixel_9", "Pixel 10 Pro")).map { it.name })
    }

    @Test fun resolveGlobs() {
        val nines = Devices.resolve(listOf("Pixel 9*")).map { it.name }
        assertEquals(
            setOf("Pixel 9", "Pixel 9 Pro", "Pixel 9 Pro Fold", "Pixel 9 Pro Fold (folded)", "Pixel 9 Pro XL", "Pixel 9a"),
            nines.toSet(),
        )
        assertEquals(nines.size, nines.toSet().size)
        assertEquals(Devices.all.filter { it.type == "watch" }.map { it.name }.toSet(), Devices.resolve(listOf("wear os*")).map { it.name }.toSet())
        // Globs match ids too, and the whole name: "*Fold" does not match "Pixel 9 Pro Fold (folded)".
        assertEquals(setOf("Pixel 9 Pro Fold", "Pixel 10 Pro Fold", "Pixel Fold"), Devices.resolve(listOf("Pixel*Fold")).map { it.name }.toSet())
        assertTrue(Devices.resolve(listOf("pixel_9_*")).map { it.id }.containsAll(listOf("pixel_9_pro", "pixel_9_pro_fold", "pixel_9_pro_fold:folded")))
        // Regex characters in a glob are literal.
        assertTrue(Devices.find("Pixel.9*").isEmpty())
        assertEquals("Resizable (Experimental)", Devices.resolve(listOf("Resizable (Exp*al)")).single().name)
    }

    @Test fun resolvePreviewSpecs() {
        assertEquals("Pixel 9", Devices.resolve(listOf("id:pixel_9")).single().name)
        assertEquals("Phone", Devices.resolve(listOf("spec:width=411dp,height=891dp")).single().name)
    }

    @Test fun unknownDevicesFail() {
        val e = assertFailsWith<IllegalArgumentException> { Devices.resolve(listOf("Pixel 9", "iPhone 17")) }
        assertTrue(e.message!!.contains("iPhone 17"))
        assertFailsWith<IllegalArgumentException> { Devices.resolve(listOf("Nokia*")) }
        assertFailsWith<IllegalArgumentException> { Devices.resolve(listOf("id:nope")) }
        assertTrue(Devices.find("").isEmpty())
    }

    @Test fun fromPreviewById() {
        assertEquals(named("Pixel 9"), Devices.fromPreview("id:pixel_9"))
        assertEquals(named("Wear OS Large Round"), Devices.fromPreview("id:wearos_large_round"))
        assertNull(Devices.fromPreview("id:not_a_device"))
        // The preview's own syntax is exact, like Android Studio's.
        assertNull(Devices.fromPreview("id:PIXEL_9"))
    }

    @Test fun fromPreviewByName() {
        assertEquals(named("Pixel 9"), Devices.fromPreview("name:Pixel 9"))
        assertEquals(named("Nexus 7"), Devices.fromPreview("name:Nexus 7"))
        assertNull(Devices.fromPreview("name:Pixel 99"))
    }

    @Test fun fromPreviewBare() {
        assertEquals(named("Pixel 9"), Devices.fromPreview("pixel_9"))
        assertEquals(named("Pixel 9"), Devices.fromPreview(" Pixel 9 "))
        assertNull(Devices.fromPreview(""))
        assertNull(Devices.fromPreview("   "))
    }

    @Test fun phoneSpec() {
        // Devices.PHONE; dpi defaults to 420.
        val d = Devices.fromPreview("spec:width=411dp,height=891dp")!!
        assertEquals("Phone", d.name)
        assertEquals("phone", d.type)
        assertEquals(1079 to 2339, d.width to d.height)
        assertEquals(420, d.density)
        assertEquals(420, d.xdpi)
        assertEquals(420, d.ydpi)
        assertEquals("normal", d.size)
        assertFalse(d.round)
        assertEquals("phoneScreenshots", d.playFolder)
        assertEquals("spec:width=411dp,height=891dp", d.id)
    }

    @Test fun foldableSpec() {
        val d = Devices.fromPreview("spec:width=673dp,height=841dp")!!
        assertEquals("Foldable", d.name)
        assertEquals(1767 to 2208, d.width to d.height)
        assertEquals("tablet", d.type)
        assertEquals("large", d.size)
        assertEquals("sevenInchScreenshots", d.playFolder)
    }

    @Test fun tabletSpec() {
        val d = Devices.fromPreview("spec:width=1280dp,height=800dp,dpi=240")!!
        assertEquals("Tablet", d.name)
        assertEquals(1920 to 1200, d.width to d.height)
        assertEquals(240, d.density)
        assertEquals("tablet", d.type)
        assertEquals("xlarge", d.size)
        assertEquals("tenInchScreenshots", d.playFolder)
    }

    @Test fun desktopSpec() {
        val d = Devices.fromPreview("spec:width=1920dp,height=1080dp,dpi=160")!!
        assertEquals("Desktop", d.name)
        assertEquals(1920 to 1080, d.width to d.height)
        assertEquals(160, d.density)
        assertEquals("tablet", d.type)
        assertEquals("tenInchScreenshots", d.playFolder)
    }

    @Test fun specOrientation() {
        val land = Devices.fromPreview("spec:width=411dp,height=891dp,orientation=landscape")!!
        assertEquals(2339 to 1079, land.width to land.height)
        assertEquals("891x411dp", land.name)
        val port = Devices.fromPreview("spec:width=891dp,height=411dp,orientation=portrait")!!
        assertEquals(1079 to 2339, port.width to port.height)
        // Already the asked orientation: unchanged.
        val same = Devices.fromPreview("spec:width=891dp,height=411dp,orientation=landscape")!!
        assertEquals(2339 to 1079, same.width to same.height)
    }

    @Test fun specWithParent() {
        val pixel9 = named("Pixel 9")
        assertEquals(pixel9, Devices.fromPreview("spec:parent=pixel_9"))
        assertEquals(pixel9, Devices.fromPreview("spec:parent=pixel_9,orientation=portrait"))
        val land = Devices.fromPreview("spec:parent=pixel_9,orientation=landscape")!!
        assertEquals("Pixel 9 (landscape)", land.name)
        assertEquals(2424 to 1080, land.width to land.height)
        assertEquals(pixel9.ydpi to pixel9.xdpi, land.xdpi to land.ydpi)
        assertEquals(420, land.density)
        assertEquals("phone", land.type)
        assertEquals(land, Devices.fromPreview("spec: parent = pixel_9 , orientation = landscape "))
    }

    @Test fun specWithLandscapeParentInPortrait() {
        val tablet = named("Pixel Tablet")
        assertEquals(tablet, Devices.fromPreview("spec:parent=pixel_tablet,orientation=landscape"))
        val port = Devices.fromPreview("spec:parent=pixel_tablet,orientation=portrait")!!
        assertEquals(1600 to 2560, port.width to port.height)
        assertEquals("Pixel Tablet (portrait)", port.name)
    }

    @Test fun roundSpecIsAWatch() {
        val d = Devices.fromPreview("spec:width=227dp,height=227dp,dpi=320,isRound=true")!!
        assertEquals("watch", d.type)
        assertTrue(d.round)
        assertEquals(454 to 454, d.width to d.height)
        assertEquals("wearScreenshots", d.playFolder)
        assertEquals("small", d.size)
        assertFalse(Devices.fromPreview("spec:width=227dp,height=227dp,dpi=320,isRound=false")!!.round)
    }

    @Test fun specUnits() {
        val px = Devices.fromPreview("spec:width=1080px,height=2400px,dpi=480")!!
        assertEquals(1080 to 2400, px.width to px.height)
        assertEquals("360x800dp", px.name)
        // A number without a unit is dp.
        val bare = Devices.fromPreview("spec:width=360,height=640,dpi=320")!!
        assertEquals(720 to 1280, bare.width to bare.height)
        val fractional = Devices.fromPreview("spec:width=392.7dp,height=850.9dp,dpi=440")!!
        assertEquals(1080 to 2340, fractional.width to fractional.height)
    }

    @Test fun incompleteSpecs() {
        assertNull(Devices.fromPreview("spec:width=411dp"))
        assertNull(Devices.fromPreview("spec:height=411dp"))
        assertNull(Devices.fromPreview("spec:"))
        // An unknown parent falls back to the explicit size.
        assertEquals(1079 to 2339, Devices.fromPreview("spec:parent=nope,width=411dp,height=891dp")!!.let { it.width to it.height })
    }

    @Test fun sizeBuckets() {
        assertEquals("small", Devices.fromPreview("spec:width=300dp,height=400dp")!!.size)
        assertEquals("normal", Devices.fromPreview("spec:width=360dp,height=640dp")!!.size)
        assertEquals("large", Devices.fromPreview("spec:width=600dp,height=960dp")!!.size)
        assertEquals("xlarge", Devices.fromPreview("spec:width=800dp,height=1280dp")!!.size)
    }

    @Test fun playFolders() {
        assertEquals("phoneScreenshots", named("Pixel 10 Pro").playFolder)
        assertEquals("phoneScreenshots", named("Pixel 9 Pro Fold (folded)").playFolder)
        assertEquals("sevenInchScreenshots", named("Pixel 9 Pro Fold").playFolder)
        assertEquals("sevenInchScreenshots", named("Nexus 7").playFolder)
        assertEquals("tenInchScreenshots", named("Pixel Tablet").playFolder)
        assertEquals("tenInchScreenshots", named("Medium Desktop").playFolder)
        assertEquals("wearScreenshots", named("Wear OS Large Round").playFolder)
        assertEquals("wearScreenshots", named("Wear OS Square").playFolder)
        assertEquals("tvScreenshots", named("Television (1080p)").playFolder)
        for (d in Devices.all) assertTrue(d.playFolder.endsWith("Screenshots"))
    }

    @Test fun landscapeAndPortrait() {
        val p = named("Pixel 9")
        // Rotating drops the cutout (it is measured in portrait); everything else round-trips.
        assertEquals(p, p.landscape().portrait().copy(name = p.name, cutout = p.cutout))
        assertEquals(p, p.portrait())
        val t = named("Pixel Tablet")
        assertEquals(t, t.landscape())
    }

    @Test fun jsonRoundTrip() {
        for (d in Devices.all) assertEquals(d, Device.fromJson(d.toJson()))
        val spec = Devices.fromPreview("spec:width=227dp,height=227dp,dpi=320,isRound=true")!!
        assertEquals(spec, Device.fromJson(swiftshot.android.shared.Json.parse(swiftshot.android.shared.Json.write(spec.toJson())) as Map<*, *>))
    }
}
