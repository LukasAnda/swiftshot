package swiftshot.android

import java.awt.image.BufferedImage
import java.io.File
import kotlin.math.ceil
import kotlin.math.floor

/** `tolerance` of the comparison config: up to [pixels] differing pixels pass; a channel differs by more than [maxChannelDelta]. */
data class Tolerance(val pixels: Int = 0, val maxChannelDelta: Int = 0)

/** A rectangle in pixels. */
data class Region(val x: Int, val y: Int, val width: Int, val height: Int)

/**
 * One comparison. [status] `unchanged` or `changed`; [reason] `tolerance` (unchanged, [pixels] > 0), `pixels` or `size`
 * (changed), else null. [boxes], [diffImage] and the sizes (`[w, h]`, size changes only) are set for changed only.
 */
data class Diff(
    val status: String,
    val reason: String?,
    val pixels: Int,
    val boxes: List<Region>,
    val diffImage: BufferedImage?,
    val baselineSize: List<Int>? = null,
    val newSize: List<Int>? = null,
)

/** The pixel comparison of docs/wiki/Baseline-format.md (Comparison, Boxes, Diff image). */
object Compare {
    /** Boxes closer than this (in pixels, along the larger axis gap) are merged. */
    const val MERGE_DISTANCE = 16
    private const val DIFF_COLOR = 0xFFFF2D55.toInt()

    /**
     * Compares two PNG files. Equal bytes are `unchanged` without decoding; otherwise both are decoded
     * (throws [UnsupportedPngException]). [ignore] pixels never differ (see [ignoreRegion]); they are clipped to the canvas.
     */
    fun images(baseline: File, new: File, tolerance: Tolerance, ignore: List<Region>): Diff {
        val a = baseline.readBytes()
        val b = new.readBytes()
        if (a.contentEquals(b)) return Diff("unchanged", null, 0, emptyList(), null)
        return images(Png.decode(a), Png.decode(b), tolerance, ignore)
    }

    fun images(base: PngImage, new: PngImage, tolerance: Tolerance, ignore: List<Region>): Diff {
        val cw = maxOf(base.width, new.width)
        val ch = maxOf(base.height, new.height)
        val mask = BooleanArray(cw * ch)
        val d = tolerance.maxChannelDelta
        var count = 0
        for (y in 0 until ch) {
            for (x in 0 until cw) {
                val differs = if (x >= base.width || y >= base.height || x >= new.width || y >= new.height) true else {
                    val p = base.argb[y * base.width + x]
                    val q = new.argb[y * new.width + x]
                    p != q && (channel(p, q, 24) > d || channel(p, q, 16) > d || channel(p, q, 8) > d || channel(p, q, 0) > d)
                }
                if (differs) mask[y * cw + x] = true
            }
        }
        for (r in ignore) {
            val x0 = r.x.coerceIn(0, cw); val y0 = r.y.coerceIn(0, ch)
            val x1 = (r.x.toLong() + r.width).coerceIn(0, cw.toLong()).toInt(); val y1 = (r.y.toLong() + r.height).coerceIn(0, ch.toLong()).toInt()
            if (x1 <= x0) continue
            for (y in y0 until y1) java.util.Arrays.fill(mask, y * cw + x0, y * cw + x1, false)
        }
        for (m in mask) if (m) count++
        val sized = base.width != new.width || base.height != new.height
        if (!sized && count <= tolerance.pixels) return Diff("unchanged", if (count > 0) "tolerance" else null, count, emptyList(), null)
        return Diff(
            "changed", if (sized) "size" else "pixels", count, boxes(mask, cw, ch), diffImage(base, mask, cw, ch),
            if (sized) listOf(base.width, base.height) else null, if (sized) listOf(new.width, new.height) else null,
        )
    }

    /**
     * An `ignore_regions` entry `[x, y, w, h]` in points/dp at [scale] pixels per point, in pixels:
     * `floor(x·s)`, `floor(y·s)` to `ceil((x+w)·s)`, `ceil((y+h)·s)`, not yet clipped to the canvas.
     */
    fun ignoreRegion(rect: List<Double>, scale: Double): Region {
        require(rect.size == 4) { "ignore region must be [x, y, w, h]" }
        val (x, y, w, h) = rect
        val x0 = floor(x * scale).toInt()
        val y0 = floor(y * scale).toInt()
        val x1 = ceil((x + w) * scale).toInt()
        val y1 = ceil((y + h) * scale).toInt()
        return Region(x0, y0, x1 - x0, y1 - y0)
    }

    private fun channel(p: Int, q: Int, shift: Int) = Math.abs((p ushr shift and 255) - (q ushr shift and 255))

    /** Bounding boxes of the 8-connected components, merged while any two are closer than [MERGE_DISTANCE]; sorted by y, x, w, h. */
    internal fun boxes(mask: BooleanArray, w: Int, h: Int): List<Region> {
        val seen = BooleanArray(mask.size)
        val stack = IntArray(mask.size)
        val comps = ArrayList<IntArray>()   // x0, y0, x1, y1 (half-open)
        for (start in mask.indices) {
            if (!mask[start] || seen[start]) continue
            var top = 0
            stack[top++] = start
            seen[start] = true
            var x0 = Int.MAX_VALUE; var y0 = Int.MAX_VALUE; var x1 = Int.MIN_VALUE; var y1 = Int.MIN_VALUE
            while (top > 0) {
                val p = stack[--top]
                val x = p % w; val y = p / w
                if (x < x0) x0 = x; if (y < y0) y0 = y; if (x + 1 > x1) x1 = x + 1; if (y + 1 > y1) y1 = y + 1
                for (dy in -1..1) for (dx in -1..1) {
                    val nx = x + dx; val ny = y + dy
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue
                    val q = ny * w + nx
                    if (mask[q] && !seen[q]) { seen[q] = true; stack[top++] = q }
                }
            }
            comps += intArrayOf(x0, y0, x1, y1)
        }
        // Union close pairs until none is close. Unions only grow, so the fixpoint is the same in any order.
        var merged = true
        while (merged) {
            merged = false
            var i = 0
            while (i < comps.size) {
                var j = i + 1
                while (j < comps.size) {
                    val a = comps[i]; val b = comps[j]
                    if (gap(a, b) < MERGE_DISTANCE) {
                        comps[i] = intArrayOf(minOf(a[0], b[0]), minOf(a[1], b[1]), maxOf(a[2], b[2]), maxOf(a[3], b[3]))
                        comps.removeAt(j)
                        merged = true
                        j = i + 1   // the union may now be close to boxes already passed
                    } else j++
                }
                i++
            }
        }
        return comps.map { Region(it[0], it[1], it[2] - it[0], it[3] - it[1]) }
            .sortedWith(compareBy<Region>({ it.y }, { it.x }, { it.width }, { it.height }))
    }

    private fun gap(a: IntArray, b: IntArray) = maxOf(0, b[0] - a[2], a[0] - b[2], b[1] - a[3], a[1] - b[3])

    /** Canvas-sized, opaque: differing pixels `#FF2D55`, other baseline pixels at 30 % over white, the rest white. */
    private fun diffImage(base: PngImage, mask: BooleanArray, cw: Int, ch: Int): BufferedImage {
        val out = IntArray(cw * ch)
        for (y in 0 until ch) for (x in 0 until cw) {
            val i = y * cw + x
            out[i] = when {
                mask[i] -> DIFF_COLOR
                x < base.width && y < base.height -> {
                    val p = base.argb[y * base.width + x]
                    val a = p ushr 24
                    fun mix(c: Int): Int { val c1 = (c * a + 255 * (255 - a) + 127) / 255; return (3 * c1 + 7 * 255 + 5) / 10 }
                    (0xFF shl 24) or (mix(p shr 16 and 255) shl 16) or (mix(p shr 8 and 255) shl 8) or mix(p and 255)
                }
                else -> -1
            }
        }
        return PngImage(cw, ch, out).toImage()
    }
}
