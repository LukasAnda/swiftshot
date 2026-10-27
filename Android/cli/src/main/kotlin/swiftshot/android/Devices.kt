package swiftshot.android

import swiftshot.android.shared.Json
import java.io.File
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.math.roundToInt

/** A screen to render on: size in px, density, and what kind of device it is. */
data class Device(
    val id: String,
    val name: String,
    /** phone, foldable, tablet, watch, tv, car, desktop, xr */
    val type: String,
    val width: Int,
    val height: Int,
    /** density bucket in dpi (420, 480, …) */
    val density: Int,
    val xdpi: Int,
    val ydpi: Int,
    /** small, normal, large, xlarge */
    val size: String,
    val round: Boolean = false,
    val diagonal: Double = 0.0,
) {
    val widthDp get() = width * 160.0 / density
    val heightDp get() = height * 160.0 / density

    /** fastlane supply's image folder for this kind of device. */
    val playFolder: String
        get() = when (type) {
            "watch" -> "wearScreenshots"
            "tv" -> "tvScreenshots"
            "tablet", "foldable", "desktop", "xr" -> if (diagonal in 0.1..9.0) "sevenInchScreenshots" else "tenInchScreenshots"
            else -> "phoneScreenshots"
        }

    fun toJson(): LinkedHashMap<String, Any?> = linkedMapOf(
        "id" to id, "name" to name, "type" to type, "width" to width, "height" to height, "density" to density,
        "xdpi" to xdpi, "ydpi" to ydpi, "size" to size, "round" to round, "diagonal" to diagonal,
    )

    fun landscape() = if (width >= height) this else copy(name = "$name (landscape)", width = height, height = width, xdpi = ydpi, ydpi = xdpi)

    companion object {
        fun fromJson(m: Map<*, *>) = Device(
            id = m["id"] as String, name = m["name"] as String, type = m["type"] as String,
            width = (m["width"] as Number).toInt(), height = (m["height"] as Number).toInt(),
            density = (m["density"] as Number).toInt(), xdpi = (m["xdpi"] as Number).toInt(), ydpi = (m["ydpi"] as Number).toInt(),
            size = m["size"] as String, round = m["round"] as Boolean? ?: false, diagonal = (m["diagonal"] as Number?)?.toDouble() ?: 0.0,
        )
    }
}

object Devices {
    /** Android Studio's device definitions, generated with `emit-devices` (see [emit]). */
    val all: List<Device> by lazy {
        val text = Devices::class.java.getResourceAsStream("/devices.json")!!.bufferedReader().readText()
        (Json.parse(text) as List<*>).map { Device.fromJson(it as Map<*, *>) }
    }

    val defaults = listOf("Pixel 10 Pro", "Pixel Tablet")
    val defaultWatch = listOf("Wear OS Large Round")

    /** Devices by name, id or `*` glob, in the order asked for. */
    fun resolve(names: List<String>): List<Device> = names.flatMap { name ->
        val matches = find(name)
        require(matches.isNotEmpty()) { "Unknown device \"$name\". `swiftshot devices` lists them." }
        matches
    }

    fun find(name: String): List<Device> {
        if (name.contains('*')) {
            val re = Regex(name.split('*').joinToString(".*") { Regex.escape(it) }, RegexOption.IGNORE_CASE)
            return all.filter { re.matches(it.name) || re.matches(it.id) }
        }
        all.firstOrNull { it.name.equals(name, true) || it.id.equals(name, true) }?.let { return listOf(it) }
        if (name.startsWith("spec:") || name.startsWith("id:") || name.startsWith("name:")) return listOfNotNull(fromPreview(name))
        return emptyList()
    }

    /**
     * A `@Preview(device = …)` value: `id:pixel_9`, `name:Nexus 10`, or
     * `spec:width=411dp,height=891dp,dpi=420,isRound=false,orientation=landscape,parent=pixel_9`.
     */
    fun fromPreview(device: String): Device? {
        val value = device.trim()
        if (value.isEmpty()) return null
        if (value.startsWith("id:")) return all.firstOrNull { it.id == value.removePrefix("id:") }
        if (value.startsWith("name:")) return all.firstOrNull { it.name == value.removePrefix("name:") }
        if (!value.startsWith("spec:")) return all.firstOrNull { it.id == value || it.name == value }
        val params = value.removePrefix("spec:").split(',').mapNotNull {
            val kv = it.split('=', limit = 2).map(String::trim)
            if (kv.size == 2) kv[0] to kv[1] else null
        }.toMap()
        val parent = params["parent"]?.let { p -> all.firstOrNull { it.id == p } }
        if (parent != null) {
            val landscape = params["orientation"] == "landscape"
            return if (landscape) parent.landscape() else parent
        }
        val dpi = params["dpi"]?.toIntOrNull() ?: 420
        fun px(v: String?): Int? {
            v ?: return null
            return when {
                v.endsWith("dp") -> (v.removeSuffix("dp").toDouble() * dpi / 160).roundToInt()
                v.endsWith("px") -> v.removeSuffix("px").toDouble().roundToInt()
                else -> (v.toDouble() * dpi / 160).roundToInt()
            }
        }
        var w = px(params["width"]) ?: return null
        var h = px(params["height"]) ?: return null
        when (params["orientation"]) {
            "landscape" -> if (h > w) { val t = w; w = h; h = t }
            "portrait" -> if (w > h) { val t = w; w = h; h = t }
        }
        val round = params["isRound"] == "true"
        val shortDp = minOf(w, h) * 160.0 / dpi
        val type = when {
            round -> "watch"
            shortDp >= 600 -> "tablet"
            else -> "phone"
        }
        val diag = Math.hypot(w.toDouble(), h.toDouble()) / dpi
        val name = when (value) {
            "spec:width=411dp,height=891dp" -> "Phone"
            "spec:width=673dp,height=841dp" -> "Foldable"
            "spec:width=1280dp,height=800dp,dpi=240" -> "Tablet"
            "spec:width=1920dp,height=1080dp,dpi=160" -> "Desktop"
            else -> "${(w * 160.0 / dpi).roundToInt()}x${(h * 160.0 / dpi).roundToInt()}dp"
        }
        return Device(
            id = value, name = name, type = type, width = w, height = h, density = dpi, xdpi = dpi, ydpi = dpi,
            size = sizeBucket(minOf(w, h) * 160.0 / dpi, maxOf(w, h) * 160.0 / dpi), round = round, diagonal = diag,
        )
    }

    private fun sizeBucket(shortDp: Double, longDp: Double) = when {
        shortDp >= 720 && longDp >= 960 -> "xlarge"
        shortDp >= 480 && longDp >= 640 -> "large"
        shortDp >= 320 && longDp >= 470 -> "normal"
        else -> "small"
    }

    /**
     * Regenerates `devices.json` from Android Studio's catalog (`plugins/android/lib/sdklib.jar`,
     * the XML files in `com/android/sdklib/devices`). Foldables also get a "(folded)" entry with the outer
     * screen. Maintainers run this when a new Android Studio ships devices.
     */
    fun emit(sdklib: File, out: File) {
        val devices = mutableListOf<Device>()
        ZipFile(sdklib).use { zip ->
            for (file in listOf("devices.xml", "nexus.xml", "wear.xml", "tv.xml", "automotive.xml", "desktop.xml", "xr.xml")) {
                val entry = zip.getEntry("com/android/sdklib/devices/$file") ?: continue
                val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
                    .newDocumentBuilder().parse(zip.getInputStream(entry))
                val nodes = doc.getElementsByTagNameNS("*", "device")
                for (i in 0 until nodes.length) {
                    val d = nodes.item(i) as org.w3c.dom.Element
                    fun text(tag: String) = d.getElementsByTagNameNS("*", tag).item(0)?.textContent?.trim()
                    val id = text("id") ?: continue
                    val name = text("name") ?: continue
                    if (text("deprecated") == "true") continue
                    val w = text("x-dimension")?.toIntOrNull() ?: continue
                    val h = text("y-dimension")?.toIntOrNull() ?: continue
                    val density = bucket(text("pixel-density") ?: "xhdpi")
                    val xdpi = text("xdpi")?.toDoubleOrNull()?.roundToInt() ?: density
                    val ydpi = text("ydpi")?.toDoubleOrNull()?.roundToInt() ?: density
                    val tag = text("tag-id") ?: ""
                    val props = (0 until d.getElementsByTagNameNS("*", "boot-prop").length).map {
                        d.getElementsByTagNameNS("*", "boot-prop").item(it).textContent
                    }
                    val round = props.any { it.contains("ro.emulator.circular") && it.contains("true") } ||
                        (tag == "android-wear" && id.contains("round"))
                    val foldedW = text("x-folded-dimension")?.toIntOrNull()
                    val foldedH = text("y-folded-dimension")?.toIntOrNull()
                    val diagonal = text("diagonal-length")?.toDoubleOrNull() ?: 0.0
                    val sizeName = text("screen-size") ?: "normal"
                    val type = when {
                        tag == "android-wear" -> "watch"
                        tag == "android-tv" || tag == "google-tv" -> "tv"
                        tag.startsWith("android-automotive") -> "car"
                        tag == "android-desktop" || file == "desktop.xml" -> "desktop"
                        tag == "android-xr" || file == "xr.xml" -> "xr"
                        foldedW != null -> "foldable"
                        sizeName == "large" || sizeName == "xlarge" -> "tablet"
                        else -> "phone"
                    }
                    devices += Device(id, name, type, w, h, density, xdpi, ydpi, sizeName, round, diagonal)
                    if (foldedW != null && foldedH != null && (foldedW != w || foldedH != h)) {
                        val outerDiag = diagonal * Math.hypot(foldedW.toDouble(), foldedH.toDouble()) / Math.hypot(w.toDouble(), h.toDouble())
                        devices += Device("$id:folded", "$name (folded)", "phone", foldedW, foldedH, density, xdpi, ydpi, "normal", false, outerDiag)
                    }
                }
            }
        }
        val unique = devices.distinctBy { it.id }.sortedWith(compareBy({ order(it.type) }, { it.name }))
        out.writeText(Json.write(unique.map { it.toJson() }, "  ") + "\n")
        println("${unique.size} devices → $out")
    }

    private fun order(type: String) = listOf("phone", "foldable", "tablet", "watch", "tv", "car", "desktop", "xr").indexOf(type)

    private fun bucket(v: String): Int = when (v) {
        "ldpi" -> 120; "mdpi" -> 160; "tvdpi" -> 213; "hdpi" -> 240; "xhdpi" -> 320; "xxhdpi" -> 480; "xxxhdpi" -> 640
        else -> v.removeSuffix("dpi").toIntOrNull() ?: 320
    }
}
