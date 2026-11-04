package swiftshot.android

import java.util.Locale

/** The documents `list --json` and `devices --json` print (docs/wiki/Command-line.md). The Mac CLI builds the same shapes. */
object JsonOutput {
    /** `{"previews": [{"name": ...}]}`, in the order given. */
    fun list(previews: List<String>): Map<String, Any?> = mapOf("previews" to previews.map { mapOf("name" to it) })

    /** One device: width and height in dp (Android) or points (iOS). */
    data class Row(val name: String, val platform: String, val width: Double, val height: Double, val scale: Double)

    /** `{"devices": [{name, platform, width, height, scale}]}`; there is no `runtimes` key (the Mac CLI has installed iOS runtimes to report, this one has none). */
    fun devices(rows: List<Row>): Map<String, Any?> = mapOf("devices" to rows.map {
        mapOf("name" to it.name, "platform" to it.platform, "width" to it.width, "height" to it.height, "scale" to it.scale)
    })

    private fun round2(d: Double) = Math.round(d * 100) / 100.0

    /** Every device `devices` lists: Android Studio's definitions (dp at density/160), then the iPhones and iPads of Flutter projects (points). */
    fun allDevices(): List<Row> =
        Devices.all.map { Row(it.name, "android", round2(it.widthDp), round2(it.heightDp), it.density / 160.0) } +
            AppleDevices.all.map { Row(it.name, "ios", it.width.toDouble(), it.height.toDouble(), it.scale) }

    fun print(document: Map<String, Any?>, out: java.io.PrintStream = System.out) {
        out.write(CanonicalJson.pretty(document).toByteArray(Charsets.UTF_8))
        out.flush()
    }
}
