package swiftshot.android

import java.io.File
import java.net.URI
import java.util.Base64

/**
 * Android Studio's device art (Apache 2.0, AOSP `tools/adt/idea/artwork/resources/device-art-resources`):
 * the frame of each Pixel, tablet and watch, with where its screen sits. Taken from an installed
 * Android Studio, else the SDK's skins folder, else downloaded from AOSP into the cache once.
 */
data class FrameArt(val back: File, val mask: File?, val canvasWidth: Int, val canvasHeight: Int, val x: Int, val y: Int, val width: Int, val height: Int) {
    fun toJson() = linkedMapOf<String, Any?>(
        "back" to back.path, "mask" to mask?.path, "canvas" to listOf(canvasWidth, canvasHeight),
        "screen" to listOf(x, y, width, height),
    )
}

object Frames {
    private const val AOSP = "https://android.googlesource.com/platform/tools/adt/idea/+/refs/heads/mirror-goog-studio-main/artwork/resources/device-art-resources"

    /** The art folder for a device: pixel_9, pixel_9_pro_fold/default, pixel_9_pro_fold/closed… */
    fun folder(device: Device): String? {
        val id = device.id.removeSuffix(":folded")
        if (device.id.startsWith("spec:") || device.id.contains(' ')) return null
        return when {
            device.id.endsWith(":folded") -> "$id/closed"
            device.type == "foldable" -> "$id/default"
            else -> id
        }
    }

    fun art(device: Device, log: Log): FrameArt? {
        val folder = folder(device) ?: return null
        val dir = local(folder) ?: download(folder, log) ?: return null
        val art = parse(dir)?.let { png(it) } ?: return null
        if (art.width != device.width || art.height != device.height) {
            log.warn("${device.name}: the frame's screen is ${art.width}×${art.height}, the device ${device.width}×${device.height}; not framed")
            return null
        }
        return art
    }

    private fun roots(): List<File> {
        val home = System.getProperty("user.home")
        val sdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT") ?: "$home/Library/Android/sdk"
        return listOf(
            "/Applications/Android Studio.app/Contents/plugins/android/resources/device-art-resources",
            "$home/Applications/Android Studio.app/Contents/plugins/android/resources/device-art-resources",
            "/opt/android-studio/plugins/android/resources/device-art-resources",
            "$sdk/skins",
        ).map(::File).filter { it.isDirectory }
    }

    private fun local(folder: String): File? = roots().map { File(it, folder) }.firstOrNull { File(it, "layout").isFile }
        ?: File(Cache.root, "device-art/$folder").takeIf { File(it, "layout").isFile }

    /** The renderer reads PNG only: WebP art is converted once, next to the cache. */
    private fun png(art: FrameArt): FrameArt? = runCatching {
        fun convert(f: File): File {
            if (f.extension.lowercase() == "png") return f
            val out = File(Cache.root, "device-art-png/${f.parentFile.name}-${f.parentFile.parentFile.name}-${f.nameWithoutExtension}-${f.length()}.png")
            if (!out.isFile) {
                out.parentFile.mkdirs()
                val image = Webp.read(f) ?: error("can't read $f")
                javax.imageio.ImageIO.write(image, "png", out)
            }
            return out
        }
        art.copy(back = convert(art.back), mask = art.mask?.let(::convert))
    }.getOrNull()

    /** Gitiles serves a file as base64 with `?format=TEXT`. */
    private fun download(folder: String, log: Log): File? {
        val dir = File(Cache.root, "device-art/$folder")
        return runCatching {
            dir.mkdirs()
            val layout = fetch("$folder/layout")
            File(dir, "layout").writeBytes(layout)
            for (name in images(String(layout))) File(dir, name).writeBytes(fetch("$folder/$name"))
            log.step("Downloaded the ${folder} frame from AOSP")
            dir
        }.getOrElse {
            dir.deleteRecursively()
            log.warn("No device art for $folder (${it.message})")
            null
        }
    }

    private fun fetch(path: String): ByteArray {
        val text = URI("$AOSP/$path?format=TEXT").toURL().openStream().use { it.readBytes() }
        return Base64.getMimeDecoder().decode(text)
    }

    private fun images(layout: String) = Regex("""\b(?:image|mask)\s+(\S+\.(?:webp|png))""").findAll(layout).map { it.groupValues[1] }.distinct().toList()

    /** The emulator-skin `layout` format: nested `name { key value … }` blocks. */
    fun parse(dir: File): FrameArt? {
        val root = block(File(dir, "layout").readText())
        val display = root.path("parts", "device", "display") ?: return null
        val portraitPart = root.path("parts", "portrait") ?: root.path("parts", "landscape") ?: return null
        val layout = root.path("layouts", "portrait") ?: root.path("layouts", "landscape") ?: return null
        val devicePart = layout.children.values.firstOrNull { it.values["name"] == "device" } ?: return null
        val back = portraitPart.path("background")?.values?.get("image") ?: return null
        val mask = portraitPart.path("foreground")?.values?.get("mask")
        return FrameArt(
            back = File(dir, back), mask = mask?.let { File(dir, it) },
            canvasWidth = layout.int("width") ?: return null, canvasHeight = layout.int("height") ?: return null,
            x = devicePart.int("x") ?: 0, y = devicePart.int("y") ?: 0,
            width = display.int("width") ?: return null, height = display.int("height") ?: return null,
        )
    }

    class Block {
        val values = LinkedHashMap<String, String>()
        val children = LinkedHashMap<String, Block>()
        fun path(vararg names: String): Block? = names.fold(this as Block?) { b, n -> b?.children?.get(n) }
        fun int(key: String) = values[key]?.toIntOrNull()
    }

    fun block(text: String): Block {
        val tokens = Regex("""\{|\}|[^\s{}]+""").findAll(text.lines().joinToString("\n") { it.substringBefore('#') }).map { it.value }.toList()
        var i = 0
        fun read(): Block {
            val b = Block()
            while (i < tokens.size) {
                val t = tokens[i++]
                if (t == "}") return b
                if (i < tokens.size && tokens[i] == "{") { i++; b.children[t] = read() }
                else if (i < tokens.size) b.values[t] = tokens[i++]
            }
            return b
        }
        return read()
    }
}
