package swiftshot.android.worker

import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

/**
 * A screenshot inside its device: Android Studio's device art (chassis with a see-through screen,
 * plus a mask for the rounded corners and the camera hole), converted to PNG by the CLI.
 */
object Frame {
    private val cache = HashMap<String, BufferedImage>()

    fun compose(shot: BufferedImage, art: Map<*, *>): BufferedImage {
        val canvas = (art["canvas"] as List<*>).map { (it as Number).toInt() }
        val screen = (art["screen"] as List<*>).map { (it as Number).toInt() }
        require(shot.width == screen[2] && shot.height == screen[3]) { "${shot.width}×${shot.height} isn't the device's screen" }
        val out = BufferedImage(canvas[0], canvas[1], BufferedImage.TYPE_INT_ARGB)
        val g = out.createGraphics()
        g.drawImage(shot, screen[0], screen[1], screen[2], screen[3], null)
        (art["mask"] as String?)?.let { g.drawImage(image(it), screen[0], screen[1], screen[2], screen[3], null) }
        g.drawImage(image(art["back"] as String), 0, 0, canvas[0], canvas[1], null)
        g.dispose()
        return out
    }

    private fun image(path: String): BufferedImage = cache.getOrPut(path) { ImageIO.read(File(path)) ?: error("can't read $path") }
}
