package swiftshot.android

import swiftshot.android.shared.Json
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.file.Files
import java.util.zip.CRC32
import java.util.zip.Deflater
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * The comparison against the shared fixtures in Shared/testdata/baseline (docs/wiki/Baseline-format.md).
 * Expected values come from each case's expected/result.json; diff images from expected/images/diff.
 * `SWIFTSHOT_WRITE_FIXTURE_IMAGES=1` writes expected/images/ instead of checking it (then run make.py to cross-check).
 */
class CompareTest {
    private val root = File(System.getProperty("swiftshot.testdata") ?: error("swiftshot.testdata not set"), "baseline")
    private val write = System.getenv("SWIFTSHOT_WRITE_FIXTURE_IMAGES") == "1"
    private val tmp: File = Files.createTempDirectory("swiftshot-compare").toFile()

    @AfterTest fun cleanUp() { tmp.deleteRecursively() }

    /** Every compared id in the fixtures, with the tolerance, ignore regions (dp) and scale its config gives it. */
    private data class Shot(val case: String, val id: String, val tolerance: Tolerance = Tolerance(), val ignore: List<List<Double>> = emptyList(), val scale: Double = 2.625)

    private val shots = listOf(
        Shot("unchanged", "en-US/iPhone 17 Pro-Home-light", scale = 3.0),
        Shot("changed-pixels", "en-US/Pixel 9-Home"),
        Shot("changed-pixels", "en-US/Pixel 9-Settings"),
        Shot("changed-size", "en-US/Pixel 9-Profile", scale = 3.0),
        Shot("same-pixels-different-bytes", "en-US/iPhone 17 Pro-Home", scale = 3.0),
        Shot("png-decoding", "en-US/iPhone 17 Pro-Rgb Filters", scale = 3.0),
        Shot("png-decoding", "en-US/iPhone 17 Pro-Rgb Changed", scale = 3.0),
        Shot("tolerance", "en-US/Pixel 9-Home", Tolerance(pixels = 5, maxChannelDelta = 1)),
        Shot("tolerance", "en-US/Pixel 9-Settings", Tolerance(pixels = 5, maxChannelDelta = 1)),
        Shot("tolerance", "en-US/Pixel 9-Clock", Tolerance(maxChannelDelta = 2)),
        Shot("tolerance", "en-US/Pixel 9-Clock Large", Tolerance(maxChannelDelta = 2)),
        Shot("ignore-region", "en-US/Pixel 9-Feed-light", ignore = listOf(listOf(0.0, 0.0, 16.0, 4.0), listOf(3.2, 20.0, 2.0, 2.0))),
        Shot("ignore-region", "en-US/Pixel 9-Feed-dark", ignore = listOf(listOf(0.0, 0.0, 16.0, 4.0), listOf(3.2, 20.0, 2.0, 2.0))),
        Shot("split-run-android", "en-US/Pixel 9-Settings"),
        Shot("device-mode", "en-US/iPhone 17 Pro-Glass", Tolerance(maxChannelDelta = 1), scale = 3.0),
        Shot("device-mode", "en-US/iPhone 17 Pro-Blur", Tolerance(maxChannelDelta = 1), scale = 3.0),
    )

    private fun entry(case: String, id: String): Map<*, *> {
        val result = Json.parse(File(root, "$case/expected/result.json").readText()) as Map<*, *>
        return (result["screenshots"] as List<*>).map { it as Map<*, *> }.single { it["id"] == id }
    }

    private fun compare(s: Shot): Diff = Compare.images(
        File(root, "${s.case}/baseline/${s.id}.png"), File(root, "${s.case}/output/${s.id}.png"),
        s.tolerance, s.ignore.map { Compare.ignoreRegion(it, s.scale) },
    )

    private fun boxes(e: Map<*, *>): List<Region> =
        (e["boxes"] as List<*>? ?: emptyList<Any>()).map { b -> (b as List<*>).map { (it as Number).toInt() }.let { Region(it[0], it[1], it[2], it[3]) } }

    @Test fun everyFixtureShotMatchesResultJson() {
        for (s in shots) {
            val e = entry(s.case, s.id)
            val d = compare(s)
            val what = "${s.case} ${s.id}"
            assertEquals(e["status"], d.status, what)
            assertEquals(e["reason"], d.reason, what)
            assertEquals((e["pixels"] as Number?)?.toInt() ?: 0, d.pixels, what)
            assertEquals(boxes(e), d.boxes, what)
            assertEquals(e["baselineSize"], d.baselineSize?.map { it.toLong() }, what)
            assertEquals(e["newSize"], d.newSize?.map { it.toLong() }, what)
            if (d.status == "changed") assertNotNull(d.diffImage, what) else assertNull(d.diffImage, what)
        }
    }

    /** Every changed or compared id in every fixture is in `shots`, so no expected image goes unchecked. */
    @Test fun shotsCoverEveryComparedFixtureId() {
        val compared = root.listFiles()!!.filter { File(it, "expected/result.json").isFile }.flatMap { case ->
            val result = Json.parse(File(case, "expected/result.json").readText()) as Map<*, *>
            (result["screenshots"] as List<*>).map { it as Map<*, *> }
                .filter { it["status"] == "changed" || (it["status"] == "unchanged" && !bytesEqual(case.name, it["id"] as String)) }
                .map { case.name to it["id"] as String }
        }.toSet()
        assertEquals(compared, shots.filter { !bytesEqual(it.case, it.id) }.map { it.case to it.id }.toSet())
    }

    private fun bytesEqual(case: String, id: String): Boolean {
        val b = File(root, "$case/baseline/$id.png")
        val n = File(root, "$case/output/$id.png")
        return b.isFile && n.isFile && b.readBytes().contentEquals(n.readBytes())
    }

    /** The diff image and the baseline/new copies of every listed id, against expected/images (or written there). */
    @Test fun reportImagesMatchFixtures() {
        val expected = mutableSetOf<File>()
        for (case in root.listFiles()!!.filter { File(it, "expected/result.json").isFile }) {
            val result = Json.parse(File(case, "expected/result.json").readText()) as Map<*, *>
            for (e in (result["screenshots"] as List<*>).map { it as Map<*, *> }) {
                val id = e["id"] as String
                val images = mutableMapOf<String, ByteArray>()
                (e["baseline"] as String?)?.let { images[it] = File(case, "baseline/$id.png").readBytes() }
                (e["new"] as String?)?.let { images[it] = File(case, "output/$id.png").readBytes() }
                (e["diff"] as String?)?.let { path ->
                    val shot = shots.single { it.case == case.name && it.id == id }
                    images[path] = Png.encode(compare(shot).diffImage!!)
                }
                for ((path, bytes) in images) {
                    val file = File(case, "expected/$path")
                    expected += file
                    if (write) { file.parentFile.mkdirs(); file.writeBytes(bytes) }
                    else assertContentEquals(file.readBytes(), bytes, "${case.name} $path")
                }
            }
        }
        val present = root.walkTopDown().filter { it.isFile && it.path.contains("/expected/images/") }.toSet()
        assertEquals(expected, present, "expected/images holds exactly the report's images")
    }

    @Test fun changedPixelsDiffImage() {
        val d = compare(shots.single { it.case == "changed-pixels" && it.id == "en-US/Pixel 9-Home" })
        val img = d.diffImage!!
        assertEquals(40, img.width); assertEquals(80, img.height)
        assertEquals(0xFFFF2D55.toInt(), img.getRGB(5, 5))
        assertEquals(0xFFFF2D55.toInt(), img.getRGB(20, 40))
        // An unchanged pixel: the baseline at 30 % over white.
        val base = Png.decode(File(root, "changed-pixels/baseline/en-US/Pixel 9-Home.png").readBytes())
        val c = base.argb[0]
        fun mix(v: Int) = (3 * v + 7 * 255 + 5) / 10
        assertEquals((0xFF shl 24) or (mix(c shr 16 and 255) shl 16) or (mix(c shr 8 and 255) shl 8) or mix(c and 255), img.getRGB(0, 0))
    }

    @Test fun changedSizeUsesLargerCanvas() {
        val d = compare(shots.single { it.case == "changed-size" })
        assertEquals("size", d.reason)
        assertEquals(listOf(40, 80), d.baselineSize); assertEquals(listOf(40, 96), d.newSize)
        assertEquals(96, d.diffImage!!.height)
        assertEquals(0xFFFF2D55.toInt(), d.diffImage!!.getRGB(0, 95))
    }

    @Test fun sizeChangeIsChangedWhateverTheTolerance() {
        val s = shots.single { it.case == "changed-size" }
        assertEquals("size", compare(s.copy(tolerance = Tolerance(pixels = 100_000, maxChannelDelta = 255))).reason)
    }

    @Test fun identicalBytesAreNeverDecoded() {
        val junk = byteArrayOf(1, 2, 3)
        val a = File(tmp, "a.png").apply { writeBytes(junk) }
        val b = File(tmp, "b.png").apply { writeBytes(junk) }
        val d = Compare.images(a, b, Tolerance(), emptyList())
        assertEquals(Diff("unchanged", null, 0, emptyList(), null), d)
    }

    @Test fun ignoreRegionScalesFloorAndCeil() {
        assertEquals(Region(0, 0, 42, 11), Compare.ignoreRegion(listOf(0.0, 0.0, 16.0, 4.0), 2.625))
        assertEquals(Region(8, 52, 6, 6), Compare.ignoreRegion(listOf(3.2, 20.0, 2.0, 2.0), 2.625))
        assertEquals(Region(1, 1, 4, 4), Compare.ignoreRegion(listOf(0.5, 0.5, 1.0, 1.0), 3.0))
    }

    @Test fun unsupportedFixturePngs() {
        val dir = File(root, "comparison-errors")
        for (name in listOf("Sixteen Bit", "Corrupt")) {
            assertFailsWith<UnsupportedPngException>(name) {
                Compare.images(File(dir, "baseline/en-US/Pixel 9-$name.png"), File(dir, "output/en-US/Pixel 9-$name.png"), Tolerance(), emptyList())
            }
        }
        val palette = "en-US/Pixel 9-Palette Same.png"
        assertEquals("unchanged", Compare.images(File(dir, "baseline/$palette"), File(dir, "output/$palette"), Tolerance(), emptyList()).status)
        assertFailsWith<UnsupportedPngException> { Png.decode(File(dir, "baseline/$palette").readBytes()) }
    }

    // ---- strict decoding, on hand-built PNGs (2x1 RGBA)

    private val pixels = byteArrayOf(10, 20, 30, 40, 50, 60, 70, 80)
    private fun ihdr(w: Int = 2, h: Int = 1, depth: Int = 8, type: Int = 6, interlace: Int = 0) =
        bytes { writeInt(w); writeInt(h); writeByte(depth); writeByte(type); writeByte(0); writeByte(0); writeByte(interlace) }
    private fun raw(filter: Int = 0) = byteArrayOf(filter.toByte()) + pixels
    private fun zlib(data: ByteArray) = Deflater(6).run { setInput(data); finish(); val out = ByteArray(1024); val n = deflate(out); end(); out.copyOf(n) }
    private fun chunk(type: String, body: ByteArray, badCrc: Boolean = false) = bytes {
        writeInt(body.size); write(type.toByteArray()); write(body)
        writeInt(CRC32().apply { update(type.toByteArray()); update(body) }.value.toInt() xor (if (badCrc) 1 else 0))
    }
    private val sig = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
    private fun png(vararg chunks: ByteArray) = chunks.fold(sig) { a, c -> a + c }
    private fun bytes(f: DataOutputStream.() -> Unit) = ByteArrayOutputStream().also { DataOutputStream(it).f() }.toByteArray()
    private val iend = chunk("IEND", ByteArray(0))

    @Test fun decodesValidAndTolerated() {
        val ok = png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw())), iend)
        assertContentEquals(intArrayOf(0x280A141E, 0x50323C46), Png.decode(ok).argb)
        // Missing IEND and bytes after IEND are tolerated; unknown chunks ignored.
        Png.decode(png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()))))
        Png.decode(ok + byteArrayOf(1, 2, 3))
        Png.decode(png(chunk("IHDR", ihdr()), chunk("tEXt", "a\u0000b".toByteArray()), chunk("IDAT", zlib(raw())), iend))
        // RGB: alpha 255.
        val rgb = png(chunk("IHDR", ihdr(type = 2)), chunk("IDAT", zlib(byteArrayOf(0, 1, 2, 3, 4, 5, 6))), iend)
        assertContentEquals(intArrayOf(0xFF010203.toInt(), 0xFF040506.toInt()), Png.decode(rgb).argb)
    }

    @Test fun rejectsMalformed() {
        val cases = mapOf(
            "bad signature" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw())), iend).also { it[1] = 0 },
            "crc" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()), badCrc = true), iend),
            "IHDR not first" to png(chunk("tEXt", byteArrayOf(65, 0, 66)), chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw())), iend),
            "no IHDR" to png(iend),
            "two IHDR" to png(chunk("IHDR", ihdr()), chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw())), iend),
            "IHDR length" to png(chunk("IHDR", ihdr() + byteArrayOf(0)), chunk("IDAT", zlib(raw())), iend),
            "truncated chunk" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()))).let { it.copyOf(it.size - 2) },
            "trailing partial chunk" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()))) + byteArrayOf(0, 0, 0),
            "zlib" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()).also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() }), iend),
            "truncated zlib" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw()).let { it.copyOf(it.size - 4) }), iend),
            "no IDAT" to png(chunk("IHDR", ihdr()), iend),
            "short data" to png(chunk("IHDR", ihdr(h = 2)), chunk("IDAT", zlib(raw())), iend),
            "long data" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw() + byteArrayOf(0))), iend),
            "filter 5" to png(chunk("IHDR", ihdr()), chunk("IDAT", zlib(raw(filter = 5))), iend),
            "16-bit" to png(chunk("IHDR", ihdr(depth = 16)), chunk("IDAT", zlib(raw() + pixels)), iend),
            "palette" to png(chunk("IHDR", ihdr(type = 3)), chunk("PLTE", byteArrayOf(1, 2, 3)), chunk("IDAT", zlib(byteArrayOf(0, 0, 0))), iend),
            "grey alpha" to png(chunk("IHDR", ihdr(type = 4)), chunk("IDAT", zlib(byteArrayOf(0, 1, 2, 3, 4))), iend),
            "interlace" to png(chunk("IHDR", ihdr(interlace = 1)), chunk("IDAT", zlib(raw())), iend),
        )
        for ((name, data) in cases) assertFailsWith<UnsupportedPngException>(name) { Png.decode(data) }
    }

    @Test fun encodingIsCanonical() {
        val img = Png.decode(File(root, "changed-pixels/baseline/en-US/Pixel 9-Home.png").readBytes())
        // make.py's encode() wrote that baseline: re-encoding the decoded pixels reproduces it byte for byte.
        assertContentEquals(File(root, "changed-pixels/baseline/en-US/Pixel 9-Home.png").readBytes(), Png.encode(img.toImage()))
    }

    @Test fun boxesMergeOnlyWhenCloserThan16() {
        // Two single pixels 15 apart (gap 15 < 16) merge; 16 apart (gap 16) stay separate.
        fun boxesFor(xs: List<Int>): List<Region> {
            val w = 60
            val base = IntArray(w) { 0xFF000000.toInt() }
            val new = base.copyOf().also { n -> xs.forEach { n[it] = -1 } }
            val a = File(tmp, "a.png").apply { writeBytes(Png.encode(PngImage(w, 1, base).toImage())) }
            val b = File(tmp, "b.png").apply { writeBytes(Png.encode(PngImage(w, 1, new).toImage())) }
            return Compare.images(a, b, Tolerance(), emptyList()).boxes
        }
        assertEquals(listOf(Region(0, 0, 17, 1)), boxesFor(listOf(0, 16)))
        assertEquals(listOf(Region(0, 0, 1, 1), Region(17, 0, 1, 1)), boxesFor(listOf(0, 17)))
        // Chained merges: a-b close, b-c close, a-c far.
        assertEquals(listOf(Region(0, 0, 31, 1)), boxesFor(listOf(0, 15, 30)))
    }
}
