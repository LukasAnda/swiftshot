package swiftshot.android.worker

import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.RenderingHints
import java.awt.geom.Arc2D
import java.awt.geom.GeneralPath
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import java.io.File

/**
 * The status bar and gesture handle of a phone or tablet with gesture navigation. On a device both
 * are system windows above the app (and above a dialog's scrim), so they are drawn over the finished
 * frame: the clock at 9:30, full Wi-Fi, signal and battery, a handle centred in the bottom inset.
 */
object SystemUi {
    const val STATUS_DP = 24
    const val NAV_DP = 24

    private var font: Font? = null

    /**
     * A device's status bar: as tall as its camera cutout plus a little (24 dp without one), the
     * clock centred on the cutout, the content clear of the rounded corners.
     */
    data class Bars(val status: Int, val centerY: Float, val edge: Float, val cutoutLeft: Float? = null, val cutoutRight: Float? = null) {
        companion object {
            fun of(device: Map<*, *>, dp: Float): Bars {
                val cutout = (device["cutout"] as List<*>?)?.map { (it as Number).toFloat() }
                val corner = (device["corner"] as Number?)?.toFloat() ?: 0f
                val base = STATUS_DP * dp
                val status = if (cutout != null) maxOf(base, cutout[1] + cutout[3] + 4 * dp) else base
                val center = if (cutout != null) cutout[1] + cutout[3] / 2 else status / 2
                return Bars(Math.round(status), center, maxOf(16 * dp, corner * 0.65f), cutout?.get(0), cutout?.let { it[0] + it[2] })
            }
        }
    }

    fun init(runtimeRoot: String) {
        if (font != null) return
        val file = File(runtimeRoot, "data/fonts/Roboto-Regular.ttf")
        font = runCatching { Font.createFont(Font.TRUETYPE_FONT, file) }.getOrNull() ?: Font(Font.SANS_SERIF, Font.PLAIN, 12)
    }

    /** [dark] content: light icons. [rtl] mirrors the bar, as Android does. */
    fun draw(image: BufferedImage, density: Int, bars: Bars, dark: Boolean, rtl: Boolean, handle: Boolean): BufferedImage {
        val out = BufferedImage(image.width, image.height, BufferedImage.TYPE_INT_ARGB)
        val g = out.createGraphics()
        g.drawImage(image, 0, 0, null)
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON)
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE)
        val dp = density / 160f
        val ink = if (dark) Color(0xF2, 0xF2, 0xF2) else Color(0x1F, 0x1F, 0x1F)
        g.color = ink
        val mid = bars.centerY
        val edge = bars.edge

        // Clock
        g.font = font!!.deriveFont(Font.PLAIN, 14 * dp)
        val time = "9:30"
        val tw = g.fontMetrics.stringWidth(time)
        val baseline = mid + (g.fontMetrics.ascent - g.fontMetrics.descent) / 2f
        g.drawString(time, if (rtl) image.width - edge - tw else edge, baseline)

        // Wi-Fi, signal, battery from the outer edge inwards (left to right when not mirrored).
        val icon = 16 * dp
        val gap = 4 * dp
        val battery = RoundRectangle2D.Float(0f, 0f, 9 * dp, 15 * dp, 2.2f * dp, 2.2f * dp)
        // A corner camera (unfolded foldables) pushes the icons inwards, as on the device.
        val gapCam = 8 * dp
        val endEdge = when {
            !rtl && bars.cutoutLeft != null && bars.cutoutLeft > image.width / 2f -> image.width - bars.cutoutLeft + gapCam
            rtl && bars.cutoutRight != null && bars.cutoutRight < image.width / 2f -> bars.cutoutRight + gapCam
            else -> edge
        }
        var x = if (rtl) endEdge else image.width - endEdge - battery.width
        g.translate(x.toDouble(), (mid - battery.height / 2).toDouble())
        g.fill(battery)
        g.fill(RoundRectangle2D.Float(3 * dp, -1.4f * dp, 3 * dp, 2f * dp, 0.8f * dp, 0.8f * dp))
        g.translate(-x.toDouble(), -(mid - battery.height / 2).toDouble())

        x = if (rtl) x + battery.width + gap else x - gap - icon
        val signal = GeneralPath().apply {
            moveTo(x + icon, mid - 7 * dp); lineTo(x + icon, mid + 7 * dp); lineTo(x + 1.5f * dp, mid + 7 * dp); closePath()
        }
        g.fill(signal)

        x = if (rtl) x + icon + gap else x - gap - icon
        val cx = x + icon / 2
        val wifi = Arc2D.Float(cx - 8 * dp, mid - 6 * dp, 16 * dp, 16 * dp, 45f, 90f, Arc2D.PIE)
        g.fill(wifi)

        if (handle) {
            val w = 108 * dp
            val h = 4 * dp
            g.color = if (dark) Color(255, 255, 255, 230) else Color(0, 0, 0, 200)
            g.stroke = BasicStroke(0f)
            g.fill(RoundRectangle2D.Float((image.width - w) / 2, image.height - NAV_DP * dp / 2 - h / 2, w, h, h, h))
        }
        g.dispose()
        return out
    }
}
