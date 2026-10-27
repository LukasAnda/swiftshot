@file:OptIn(InternalComposeUiApi::class, ExperimentalComposeUiApi::class)

package swiftshot.android.desktop

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Composer
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.LocalSystemTheme
import androidx.compose.ui.SystemTheme
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.IRect
import org.jetbrains.skia.Image
import swiftshot.android.shared.Json
import java.io.File
import java.lang.reflect.Method
import java.lang.reflect.Modifier
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Renders Compose Multiplatform previews for desktop with Compose's own headless scene
 * (Skia, CPU raster, no window), the way IntelliJ's desktop preview does. Same protocol as the
 * Android worker: one job (group of shots) per stdin line, one result line per shot, then `done`.
 */
fun main() {
    val out = System.out
    System.setOut(System.err)
    val encoder = Executors.newFixedThreadPool(2) { r -> Thread(r, "encoder").apply { isDaemon = true } }
    val emit = { line: String -> synchronized(out) { out.println(line); out.flush() } }
    val input = System.`in`.bufferedReader()
    while (true) {
        val line = input.readLine() ?: break
        if (line.isBlank()) continue
        val job = Json.parse(line) as Map<*, *>
        val pending = mutableListOf<Future<*>>()
        try {
            runGroup(job, emit, encoder, pending)
        } catch (t: Throwable) {
            for (shot in job.list("shots")) emit("error\t${(shot as Map<*, *>).str("out")}\t${message(t)}")
        }
        pending.forEach { it.get() }
        emit("done")
    }
}

private fun runGroup(job: Map<*, *>, emit: (String) -> Unit, encoder: java.util.concurrent.ExecutorService, pending: MutableList<Future<*>>) {
    val start = System.nanoTime()
    val device = job.map("device")
    val width = device.int("width")
    val height = device.int("height")
    val scale = device.int("density") / 160f
    val fontScale = (job["fontScale"] as Number?)?.toFloat() ?: 1f
    val dark = job["night"] == true
    val rtl = job["rtl"] == true
    // Compose resources and Locale.current read the JVM's default locale on desktop.
    job.strOrNull("locale")?.let { Locale.setDefault(Locale.forLanguageTag(it)) }
    val shrink = job.strOrNull("mode") == "shrink"
    emit("ready\t${(System.nanoTime() - start) / 1_000_000}\tdesktop")

    for (s in job.list("shots")) {
        val shot = s as Map<*, *>
        val base = shot.str("out")
        val t0 = System.nanoTime()
        try {
            val target = Target.find(shot.str("composable"))
            val values = shot.strOrNull("provider")?.let { providerValues(it).take(shot.int("providerLimit")) }
            val indices = values?.indices?.toList() ?: listOf(-1)
            for (index in indices) {
                val file = if (index < 0) base else base.removeSuffix(".png") + "_${index + 1}.png"
                val arg = if (index < 0) null else values!![index]
                val image = render(target, arg, width, height, Density(scale, fontScale), if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr, dark, shrink,
                    shot["fixedWidth"] == true, shot["fixedHeight"] == true)
                val renderMs = (System.nanoTime() - t0) / 1_000_000
                val background = shot.strOrNull("background")
                pending += encoder.submit {
                    try {
                        File(file).parentFile.mkdirs()
                        File(file).writeBytes(png(image, background ?: if (shrink) null else if (dark) "#FF000000" else "#FFFFFFFF"))
                        emit("ok\t$file\t$renderMs\t${image.width}x${image.height}")
                    } catch (t: Throwable) {
                        emit("error\t$file\t${message(t)}")
                    }
                }
            }
        } catch (t: Throwable) {
            emit("error\t$base\t${message(t)}")
        }
    }
}

private fun render(target: Target, arg: Any?, width: Int, height: Int, density: Density, direction: LayoutDirection, dark: Boolean, shrink: Boolean,
                   fixedWidth: Boolean, fixedHeight: Boolean): Image {
    val content: @Composable () -> Unit = {
        CompositionLocalProvider(LocalSystemTheme provides if (dark) SystemTheme.Dark else SystemTheme.Light) {
            Invoke(target, arg)
        }
    }
    val scene = ImageComposeScene(width, height, density, direction, content = content)
    try {
        // Two frames: the first composes and lays out, the second draws what effects changed.
        scene.render(0)
        val image = scene.render(16_000_000)
        if (!shrink) return image
        val size = scene.calculateContentSize()
        val w = if (fixedWidth) width else size.width.coerceIn(1, width)
        val h = if (fixedHeight) height else size.height.coerceIn(1, height)
        return Image.makeFromBitmap(org.jetbrains.skia.Bitmap().also { bitmap ->
            bitmap.allocN32Pixels(w, h)
            image.readPixels(bitmap, 0, 0)
        }).also { image.close() }
    } finally {
        scene.close()
    }
}

/** Calls the preview with the composer it is given: `@Composable` functions compile to `(…, Composer, Int)`. */
@Composable
private fun Invoke(target: Target, arg: Any?) {
    target.call(androidx.compose.runtime.currentComposer, arg)
}

private class Target(val method: Method) {
    fun call(composer: Composer, arg: Any?) {
        val types = method.parameterTypes
        val composerAt = types.indexOfFirst { it == Composer::class.java }
        val args = arrayOfNulls<Any>(types.size)
        if (composerAt > 0) args[0] = arg
        args[composerAt] = composer
        // After the composer: $changed words (0 = "uncertain"), then $default words (all bits:
        // use every default), as ComposableInvoker does.
        val changed = maxOf(1, Math.ceil(composerAt / 10.0).toInt())
        for (i in composerAt + 1 until types.size) args[i] = if (i - composerAt <= changed) 0 else -1
        val receiver = if (Modifier.isStatic(method.modifiers)) null else method.declaringClass.getDeclaredConstructor().apply { isAccessible = true }.newInstance()
        method.invoke(receiver, *args)
    }

    companion object {
        fun find(fqn: String): Target {
            val cls = Class.forName(fqn.substringBeforeLast('.'))
            val name = fqn.substringAfterLast('.')
            val method = cls.declaredMethods.filter { (it.name == name || it.name.startsWith("$name-")) && it.parameterTypes.contains(Composer::class.java) }
                .minByOrNull { it.parameterCount } ?: error("no composable $fqn")
            method.isAccessible = true
            return Target(method)
        }
    }
}

private fun providerValues(name: String): List<Any?> {
    val cls = Class.forName(name)
    val provider = cls.getDeclaredConstructor().apply { isAccessible = true }.newInstance()
    @Suppress("UNCHECKED_CAST")
    return (cls.getMethod("getValues").invoke(provider) as Sequence<Any?>).toList()
}

/** PNG with an opaque background under transparent pixels (the scene clears to transparent). */
private fun png(image: Image, background: String?): ByteArray {
    if (background == null) return image.encodeToData(EncodedImageFormat.PNG)!!.bytes
    val argb = java.lang.Long.parseLong(background.removePrefix("#"), 16).toInt()
    val surface = org.jetbrains.skia.Surface.makeRasterN32Premul(image.width, image.height)
    surface.canvas.clear(argb)
    surface.canvas.drawImage(image, 0f, 0f)
    val flat = surface.makeImageSnapshot(IRect.makeWH(image.width, image.height))!!
    return flat.encodeToData(EncodedImageFormat.PNG)!!.bytes.also { flat.close(); surface.close(); image.close() }
}

private fun message(t: Throwable): String {
    var root = t
    while (root.cause != null && root.cause !== root) root = root.cause!!
    if (root is java.lang.reflect.InvocationTargetException) root = root.targetException ?: root
    val first = root.stackTrace.firstOrNull { !it.className.startsWith("java.") && !it.className.startsWith("kotlin.") }
    return "${root.javaClass.simpleName}: ${root.message ?: ""}${first?.let { " at $it" } ?: ""}".replace('\t', ' ').replace('\n', ' ')
}

private fun Map<*, *>.str(k: String) = this[k] as String
private fun Map<*, *>.strOrNull(k: String) = this[k] as String?
private fun Map<*, *>.int(k: String) = (this[k] as Number).toInt()
private fun Map<*, *>.map(k: String) = this[k] as Map<*, *>
private fun Map<*, *>.list(k: String) = this[k] as List<*>? ?: emptyList<Any>()
