package swiftshot.android

import swiftshot.android.shared.SystemUi
import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.RenderingHints
import java.awt.geom.Arc2D
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

/**
 * The system bars over full-screen Flutter screenshots rendered headless, as a device shows them
 * above the app: Android's status bar and gesture handle (the Android renderer's own), and an
 * iPhone-style status bar where iOS can't render (no Mac): 9:41, full signal, Wi-Fi and battery.
 * Their ink follows what is under them (dark ink on light content), as both systems do.
 */
object FlutterBars {
    fun draw(file: File, device: Map<String, Any?>, rtl: Boolean, roboto: File) {
        val image = ImageIO.read(file) ?: return
        val ratio = (device["ratio"] as Number).toDouble()
        val insets = (device["insets"] as List<*>).map { (it as Number).toDouble() }
        val top = (insets[0] * ratio).toInt()
        if (top <= 0) return
        val dark = luma(image, top) < 0.5
        val out = if (device["platform"] == "android") {
            SystemUi.initFont(roboto)
            val bars = SystemUi.Bars.of(device, ratio.toFloat())
            SystemUi.draw(image, (ratio * 160).toInt(), bars, dark, rtl, handle = true)
        } else ios(image, ratio, insets[0], dark, roboto)
        ImageIO.write(out, "png", file)
    }

    /** Mean luma (0…1) of the band under the status bar. */
    private fun luma(image: BufferedImage, height: Int): Double {
        var sum = 0.0
        var n = 0
        val step = maxOf(1, image.width / 64)
        for (y in 0 until minOf(height, image.height) step maxOf(1, height / 16)) for (x in 0 until image.width step step) {
            val p = image.getRGB(x, y)
            sum += (0.2126 * (p shr 16 and 0xFF) + 0.7152 * (p shr 8 and 0xFF) + 0.0722 * (p and 0xFF)) / 255
            n++
        }
        return if (n == 0) 1.0 else sum / n
    }

    /**
     * An iPhone status bar as the iOS renderer's (measured on an iPhone 17 Pro Max, in points):
     * "09:41" centred at 82.7 with its caps from 25.3 to 39; signal, Wi-Fi and a charging battery
     * at fixed distances from the right edge, on the clock's line. Other phones keep the distances
     * and centre the line on their own inset.
     */
    private fun ios(image: BufferedImage, scale: Double, topPt: Double, dark: Boolean, roboto: File): BufferedImage {
        val out = BufferedImage(image.width, image.height, BufferedImage.TYPE_INT_ARGB)
        val g = out.createGraphics()
        g.drawImage(image, 0, 0, null)
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON)
        val s = scale.toFloat()
        val w = image.width / s
        val t = topPt.toFloat()
        // The line's offset from the measured phone's (Dynamic Island, 62 pt inset).
        val dy = when {
            t >= 59 -> 0f
            t >= 44 -> t / 2f + 1f - 32.2f
            else -> t / 2f - 32.2f
        }
        val ink = if (dark) Color.WHITE else Color.BLACK
        g.color = ink
        // Clock: Roboto Medium sized to SF's cap height there (13.7 pt).
        val font = (runCatching { Font.createFont(Font.TRUETYPE_FONT, File(roboto.parentFile, "Roboto-Medium.ttf")) }.getOrNull()
            ?: Font(Font.SANS_SERIF, Font.BOLD, 12)).deriveFont(Font.PLAIN, 19.3f * s)
        g.font = font
        val time = "09:41"
        val tw = g.fontMetrics.stringWidth(time)
        g.drawString(time, 82.7f * s - tw / 2f, (39f + dy) * s)
        fun x(fromRight: Float) = (w - fromRight) * s
        fun y(v: Float) = (v + dy) * s
        // Signal: four bars, 3.6 pt wide, rising to the clock's cap height.
        listOf(130.3f to 33.3f, 124.3f to 31f, 118f to 28f, 112f to 25.3f).forEach { (r, top) ->
            g.fill(RoundRectangle2D.Float(x(r), y(top), 3.6f * s, y(40f) - y(top), 1.2f * s, 1.2f * s))
        }
        // Wi-Fi: three 90° arcs and a dot, 20 pt wide.
        g.stroke = BasicStroke(2.6f * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
        val cx = x(90f)
        val cy = y(39f)
        for (r in listOf(13f, 8.4f, 3.8f)) {
            if (r < 4f) g.fill(Arc2D.Float(cx - r * s, cy - r * s, 2 * r * s, 2 * r * s, 45f, 90f, Arc2D.PIE))
            else g.draw(Arc2D.Float(cx - r * s, cy - r * s, 2 * r * s, 2 * r * s, 45f, 90f, Arc2D.OPEN))
        }
        // Battery: 29 × 15.4 pt, charging (green, with a bolt), and its nub.
        val body = RoundRectangle2D.Float(x(70.7f), y(24.3f), 29f * s, 15.4f * s, 4.6f * s, 4.6f * s)
        g.color = Color(0x34, 0xC7, 0x59)
        g.fill(body)
        g.fill(RoundRectangle2D.Float(x(40.3f), y(29.7f), 1.6f * s, 4.6f * s, 1.4f * s, 1.4f * s))
        g.color = Color(0x8E, 0x8E, 0x93)
        val bx = x(70.7f) + 14.5f * s
        val by = y(32f)
        val bolt = java.awt.geom.Path2D.Float().apply {
            moveTo(bx + 1.2f * s, by - 6.2f * s); lineTo(bx - 4.2f * s, by + 1f * s); lineTo(bx - 0.4f * s, by + 1f * s)
            lineTo(bx - 1.2f * s, by + 6.2f * s); lineTo(bx + 4.2f * s, by - 1f * s); lineTo(bx + 0.4f * s, by - 1f * s); closePath()
        }
        g.fill(bolt)
        g.dispose()
        return out
    }
}
