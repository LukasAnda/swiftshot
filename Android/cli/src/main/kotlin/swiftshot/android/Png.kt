package swiftshot.android

import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.DataFormatException
import java.util.zip.Deflater
import java.util.zip.Inflater

/** Not a PNG the comparison reads (docs/wiki/Baseline-format.md, Decoding). */
class UnsupportedPngException : Exception("unsupported PNG")

/** Decoded pixels as packed ARGB, samples as stored. */
class PngImage(val width: Int, val height: Int, val argb: IntArray) {
    fun toImage(): BufferedImage = BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB).also {
        if (width > 0 && height > 0) it.setRGB(0, 0, width, height, argb, 0, width)
    }
}

/**
 * The PNG subset of the baseline format: a strict decoder for 8-bit RGB/RGBA and the canonical encoder
 * (RGBA, filter 0, one IDAT written by zlib level 6, IHDR/IDAT/IEND only). ImageIO is laxer and its
 * encoder's bytes aren't specified, so neither is used here.
 */
object Png {
    private val SIGNATURE = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)

    fun decode(data: ByteArray): PngImage {
        fun fail(): Nothing = throw UnsupportedPngException()
        fun u32(at: Int): Long = ((data[at].toLong() and 255) shl 24) or ((data[at + 1].toLong() and 255) shl 16) or
            ((data[at + 2].toLong() and 255) shl 8) or (data[at + 3].toLong() and 255)
        if (data.size < 8 || !data.copyOf(8).contentEquals(SIGNATURE)) fail()
        var i = 8
        var ihdr: ByteArray? = null
        val idat = ByteArrayOutputStream()
        while (i < data.size) {
            if (i + 12 > data.size) fail()
            val n = u32(i)
            if (i + 12 + n > data.size) fail()
            val len = n.toInt()
            val type = String(data, i + 4, 4, Charsets.ISO_8859_1)
            val crc = CRC32().apply { update(data, i + 4, 4 + len) }.value
            if (crc != u32(i + 8 + len)) fail()
            val body = i + 8
            i += 12 + len
            if ((ihdr == null) != (type == "IHDR")) fail()
            when (type) {
                "IHDR" -> { if (len != 13) fail(); ihdr = data.copyOfRange(body, body + 13) }
                "IDAT" -> idat.write(data, body, len)
                "IEND" -> break
            }
        }
        val h = ihdr ?: fail()
        fun hu32(at: Int) = ((h[at].toLong() and 255) shl 24) or ((h[at + 1].toLong() and 255) shl 16) or ((h[at + 2].toLong() and 255) shl 8) or (h[at + 3].toLong() and 255)
        val width = hu32(0)
        val height = hu32(4)
        val depth = h[8].toInt() and 255
        val colorType = h[9].toInt() and 255
        val interlace = h[12].toInt() and 255
        if (depth != 8 || (colorType != 2 && colorType != 6) || interlace != 0) fail()
        val bpp = if (colorType == 6) 4 else 3
        // Larger than an array can hold: no such image can be compared (its zlib data would be the wrong length or huge).
        if (width > Int.MAX_VALUE || height > Int.MAX_VALUE) fail()
        val limit = (Int.MAX_VALUE - 8).toLong()
        val stride = width * bpp                       // < 2^34: no overflow
        val expected = try { Math.multiplyExact(height, 1 + stride) } catch (_: ArithmeticException) { fail() }
        if (expected > limit || width * height > limit) fail()   // width·height < 2^62
        val raw = inflate(idat.toByteArray(), expected.toInt())
        val w = width.toInt()
        val s = stride.toInt()
        val out = IntArray(w * height.toInt())
        var prev = ByteArray(s)
        var row = ByteArray(s)
        var o = 0
        for (y in 0 until height.toInt()) {
            val f = raw[o].toInt() and 255
            if (f > 4) fail()
            System.arraycopy(raw, o + 1, row, 0, s)
            o += 1 + s
            for (x in 0 until s) {
                val a = if (x >= bpp) row[x - bpp].toInt() and 255 else 0
                val b = prev[x].toInt() and 255
                val c = if (x >= bpp) prev[x - bpp].toInt() and 255 else 0
                val pred = when (f) {
                    0 -> 0
                    1 -> a
                    2 -> b
                    3 -> (a + b) / 2
                    else -> {
                        val pa = Math.abs(b - c); val pb = Math.abs(a - c); val pc = Math.abs(a + b - 2 * c)
                        if (pa <= pb && pa <= pc) a else if (pb <= pc) b else c
                    }
                }
                row[x] = (row[x] + pred).toByte()
            }
            for (x in 0 until w) {
                val p = x * bpp
                val alpha = if (bpp == 4) row[p + 3].toInt() and 255 else 255
                out[y * w + x] = (alpha shl 24) or ((row[p].toInt() and 255) shl 16) or ((row[p + 1].toInt() and 255) shl 8) or (row[p + 2].toInt() and 255)
            }
            val t = prev; prev = row; row = t
        }
        return PngImage(w, height.toInt(), out)
    }

    /** One complete zlib stream (data after its end is ignored) of exactly [size] bytes. */
    private fun inflate(z: ByteArray, size: Int): ByteArray {
        val inflater = Inflater()
        try {
            inflater.setInput(z)
            val out = ByteArray(size)
            var n = 0
            while (n < size && !inflater.finished()) {
                val k = inflater.inflate(out, n, size - n)
                if (k == 0 && (inflater.needsInput() || inflater.needsDictionary())) throw UnsupportedPngException()
                n += k
            }
            if (!inflater.finished()) {
                // Filled the buffer: the stream must end here, with nothing more to inflate.
                val extra = ByteArray(1)
                while (!inflater.finished()) {
                    if (inflater.inflate(extra) > 0) throw UnsupportedPngException()
                    if (inflater.needsInput() || inflater.needsDictionary()) throw UnsupportedPngException()
                }
            }
            if (n != size) throw UnsupportedPngException()
            return out
        } catch (_: DataFormatException) {
            throw UnsupportedPngException()
        } finally {
            inflater.end()
        }
    }

    /** The canonical encoding of an image as opaque-or-not 8-bit RGBA. */
    fun encode(image: BufferedImage): ByteArray {
        val w = image.width
        val h = image.height
        val argb = image.getRGB(0, 0, w, h, null, 0, w)
        val raw = ByteArray(h * (1 + w * 4))
        var o = 0
        for (y in 0 until h) {
            raw[o++] = 0
            for (x in 0 until w) {
                val p = argb[y * w + x]
                raw[o++] = (p shr 16).toByte(); raw[o++] = (p shr 8).toByte(); raw[o++] = p.toByte(); raw[o++] = (p ushr 24).toByte()
            }
        }
        val deflater = Deflater(6)
        val z = ByteArrayOutputStream()
        try {
            deflater.setInput(raw)
            deflater.finish()
            val buf = ByteArray(64 * 1024)
            while (!deflater.finished()) z.write(buf, 0, deflater.deflate(buf))
        } finally {
            deflater.end()
        }
        val out = ByteArrayOutputStream()
        out.write(SIGNATURE)
        val ihdr = ByteArrayOutputStream().apply { int(w); int(h); write(8); write(6); write(0); write(0); write(0) }.toByteArray()
        out.chunk("IHDR", ihdr)
        out.chunk("IDAT", z.toByteArray())
        out.chunk("IEND", ByteArray(0))
        return out.toByteArray()
    }

    private fun ByteArrayOutputStream.int(v: Int) { write(v ushr 24); write(v ushr 16 and 255); write(v ushr 8 and 255); write(v and 255) }

    private fun ByteArrayOutputStream.chunk(type: String, body: ByteArray) {
        val t = type.toByteArray(Charsets.ISO_8859_1)
        int(body.size); write(t); write(body)
        int(CRC32().apply { update(t); update(body) }.value.toInt())
    }
}
