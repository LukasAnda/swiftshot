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

    /** Pair checks and grid entries of the last [boxes] call (tests keep it bounded). */
    @Volatile internal var lastBoxWork = 0L

    /**
     * Bounding boxes of the 8-connected components, merged while any two are closer than [MERGE_DISTANCE]; sorted by
     * y, x, w, h. The merged result doesn't depend on the order of merges, and every merge of a close pair is forced, so
     * this starts from coarser groups that would merge anyway: all differing pixels of one 16×16 cell are at most 15 px
     * apart, so their components are close. It then unions close boxes (found through a 16 px grid) until none is close.
     */
    internal fun boxes(mask: BooleanArray, w: Int, h: Int): List<Region> {
        val c = MERGE_DISTANCE
        val gw = (w + c - 1) / c
        val gh = (h + c - 1) / c
        var work = 0L
        // One box per non-empty cell.
        val cells = IntArray(gw * gh * 4)
        val used = BooleanArray(gw * gh)
        for (y in 0 until h) {
            val row = y * w
            val cy = y / c
            for (x in 0 until w) {
                if (!mask[row + x]) continue
                val k = cy * gw + x / c
                val o = k * 4
                if (!used[k]) { used[k] = true; cells[o] = x; cells[o + 1] = y; cells[o + 2] = x + 1; cells[o + 3] = y + 1 }
                else {
                    if (x < cells[o]) cells[o] = x
                    if (x + 1 > cells[o + 2]) cells[o + 2] = x + 1
                    cells[o + 3] = y + 1
                }
            }
        }
        var boxes = ArrayList<IntArray>()
        for (k in used.indices) if (used[k]) boxes += cells.copyOfRange(k * 4, k * 4 + 4)
        // Union every close pair (union-find), replace each group by its union, repeat until a pass merges nothing.
        while (true) {
            val n = boxes.size
            // Grid buckets (CSR): box i is listed in every cell it covers.
            val count = IntArray(gw * gh + 1)
            for (b in boxes) for (cy in b[1] / c..(b[3] - 1) / c) for (cx in b[0] / c..(b[2] - 1) / c) count[cy * gw + cx + 1]++
            for (k in 1 until count.size) count[k] += count[k - 1]
            val fillAt = count.copyOf()
            val members = IntArray(count[count.size - 1])
            for ((i, b) in boxes.withIndex()) for (cy in b[1] / c..(b[3] - 1) / c) for (cx in b[0] / c..(b[2] - 1) / c) members[fillAt[cy * gw + cx]++] = i
            work += members.size
            val parent = IntArray(n) { it }
            fun find(i: Int): Int { var r = i; while (parent[r] != r) r = parent[r]; var j = i; while (parent[j] != r) { val nx = parent[j]; parent[j] = r; j = nx }; return r }
            val stamp = IntArray(n) { -1 }
            var merged = false
            for (i in 0 until n) {
                val a = boxes[i]
                // gap < c: a close box starts at most c px past this one's last pixel (b.x0 - a.x1 <= c - 1), and ends at most c before its first.
                val cx0 = maxOf(0, a[0] - c) / c; val cx1 = minOf(w - 1, a[2] - 1 + c) / c
                val cy0 = maxOf(0, a[1] - c) / c; val cy1 = minOf(h - 1, a[3] - 1 + c) / c
                for (cy in cy0..cy1) for (cx in cx0..cx1) {
                    val k = cy * gw + cx
                    for (m in count[k] until count[k + 1]) {
                        val j = members[m]
                        if (j <= i || stamp[j] == i) continue
                        stamp[j] = i
                        work++
                        if (gap(a, boxes[j]) < c) {
                            val ri = find(i); val rj = find(j)
                            if (ri != rj) { parent[rj] = ri; merged = true }
                        }
                    }
                }
            }
            if (!merged) break
            val groups = LinkedHashMap<Int, IntArray>()
            for (i in 0 until n) {
                val b = boxes[i]
                val g = groups.getOrPut(find(i)) { b.copyOf() }
                g[0] = minOf(g[0], b[0]); g[1] = minOf(g[1], b[1]); g[2] = maxOf(g[2], b[2]); g[3] = maxOf(g[3], b[3])
            }
            boxes = ArrayList(groups.values)
        }
        lastBoxWork = work
        return boxes.map { Region(it[0], it[1], it[2] - it[0], it[3] - it[1]) }
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
