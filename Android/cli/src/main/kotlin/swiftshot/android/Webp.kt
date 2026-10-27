package swiftshot.android

import java.awt.image.BufferedImage
import java.io.File
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO

/**
 * Reads PNG and WebP. WebP goes through TwelveMonkeys' pure-Java reader first; for the lossless
 * files it can't decode, the system's converter: sips on macOS, ImageMagick or dwebp elsewhere.
 */
object Webp {
    fun read(file: File): BufferedImage? {
        runCatching { ImageIO.read(file) }.getOrNull()?.let { return it }
        val png = File.createTempFile("swiftshot-art", ".png").apply { deleteOnExit() }
        val commands = listOf(
            listOf("sips", "-s", "format", "png", file.path, "--out", png.path),
            listOf("magick", file.path, png.path),
            listOf("convert", file.path, png.path),
            listOf("dwebp", file.path, "-o", png.path),
        )
        for (cmd in commands) {
            val ok = runCatching {
                val p = ProcessBuilder(cmd).redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start()
                p.waitFor(60, TimeUnit.SECONDS) && p.exitValue() == 0
            }.getOrDefault(false)
            if (ok && png.length() > 0) return runCatching { ImageIO.read(png) }.getOrNull().also { png.delete() }
        }
        png.delete()
        return null
    }
}
