package swiftshot.android.worker

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Environment
import app.cash.paparazzi.PaparazziSdk
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import com.android.ide.common.rendering.api.ResourceNamespace
import com.android.ide.common.rendering.api.SessionParams.RenderingMode
import com.android.layoutlib.bridge.android.BridgeContext
import com.android.layoutlib.bridge.android.BridgeXmlBlockParser
import com.android.layoutlib.bridge.android.RenderParamsFlags
import com.android.resources.Density
import com.android.resources.LayoutDirection
import com.android.resources.NightMode
import com.android.resources.ScreenOrientation
import com.android.resources.ScreenRatio
import com.android.resources.ScreenRound
import com.android.resources.ScreenSize
import com.android.resources.UiMode
import org.kxml2.io.KXmlParser
import swiftshot.android.shared.Json
import org.xmlpull.v1.XmlPullParser
import java.awt.Color
import java.awt.image.BufferedImage
import java.io.File
import java.io.StringReader
import javax.imageio.ImageIO

/**
 * Renders previews inside the app's own classpath. Reads one job per line on stdin (a group of
 * shots that share a device, locale, appearance, font scale and rendering mode), writes one line per
 * shot on stdout, then `done`. Layoutlib is initialised once and reused for every job.
 */
fun main() {
    val out = System.out
    // Layoutlib and the app print freely; keep stdout for the protocol.
    System.setOut(System.err)
    var env: Environment? = null
    val input = System.`in`.bufferedReader()
    while (true) {
        val line = input.readLine() ?: break
        if (line.isBlank()) continue
        val job = Json.parse(line) as Map<*, *>
        if (env == null) {
            System.setProperty("paparazzi.layoutlib.runtime.root", job.str("layoutlibRuntime"))
            System.setProperty("paparazzi.layoutlib.resources.root", job.str("layoutlibResources"))
            env = environment(job.map("environment"))
        }
        val emit = { line: String -> synchronized(out) { out.println(line); out.flush() } }
        try {
            runGroup(env, job, emit)
        } catch (t: Throwable) {
            for (shot in job.list("shots")) emit("error\t${(shot as Map<*, *>).str("out")}\t${message(t)}")
        }
        out.println("done"); out.flush()
    }
}

private fun environment(e: Map<*, *>) = Environment(
    appTestDir = e.str("appTestDir"),
    packageName = e.str("packageName"),
    compileSdkVersion = e.int("compileSdk"),
    resourcePackageNames = e.strings("resourcePackageNames"),
    localResourceDirs = e.strings("localResourceDirs"),
    moduleResourceDirs = e.strings("moduleResourceDirs"),
    libraryResourceDirs = e.strings("libraryResourceDirs"),
    allModuleAssetDirs = e.strings("assetDirs"),
    libraryAssetDirs = e.strings("libraryAssetDirs"),
)

private fun runGroup(env: Environment, job: Map<*, *>, emit: (String) -> Unit) {
    val device = deviceConfig(job.map("device"), job)
    // Full length: rendered at the device size, then on a taller screen until nothing scrolls.
    val fullLength = job.str("mode") == "vscroll"
    val mode = when (job.str("mode")) {
        "shrink" -> RenderingMode.SHRINK
        else -> RenderingMode.NORMAL
    }
    val round = device.screenRound == ScreenRound.ROUND
    val targetSdk = (job.map("environment")["targetSdk"] as Number?)?.toInt() ?: 0
    val type = job.map("device").strOrNull("type")
    // Apps that target 35+ are edge-to-edge: rendered full screen with the device's insets, and
    // the system bars drawn on top afterwards (see SystemUi). Older apps keep layoutlib's decor.
    val ownBars = job.bool("systemUi") && targetSdk >= 35 && type !in setOf("watch", "tv", "car")
    val dp = device.density.dpiValue / 160f
    val bars = SystemUi.Bars.of(job.map("device"), dp)
    Insets.synthetic = if (ownBars) intArrayOf(device.screenWidth, device.screenHeight, bars.status, Math.round(SystemUi.NAV_DP * dp)) else null
    SystemUi.init(job.str("layoutlibRuntime"))
    var frame: BufferedImage? = null
    var remaining = 0
    val pending = mutableListOf<java.util.concurrent.Future<*>>()
    val sdk = PaparazziSdk(
        environment = env,
        deviceConfig = device,
        theme = job.str("theme"),
        renderingMode = mode,
        supportsRtl = true,
        showSystemUi = job.bool("systemUi") && !ownBars && type != "watch",
        useDeviceResolution = true,
        onNewFrame = { frame = it; Debug.frame(); if (fullLength) remaining = Debug.view?.let { v -> Scroll.remaining(v.rootView) } ?: 0 },
    )
    val start = System.nanoTime()
    val flags = linkedMapOf<Any, Any>(
        RenderParamsFlags.FLAG_KEY_USE_GESTURE_NAV to job.bool("gestureNav"),
        // Android 15 enforces edge-to-edge for apps that target it; Android Studio renders them so.
        RenderParamsFlags.FLAG_KEY_EDGE_TO_EDGE to (targetSdk >= 35),
    )
    val trace = System.getenv("SWIFTSHOT_TRACE") != null
    fun mark(what: String) { if (trace) System.err.println("TRACE ${what} ${(System.nanoTime() - start) / 1_000_000} ms (jvm up ${java.lang.management.ManagementFactory.getRuntimeMXBean().uptime} ms)") }
    try {
        mark("begin")
        sdk.setup()
        mark("setup")
        Insets.install()
        val injected = SessionFlags.add(flags, targetSdk)
        sdk.prepare()
        mark("prepare")
        // The very first session is built before Paparazzi's builder exists: rebuild it with the flags.
        if (!injected && SessionFlags.add(flags, targetSdk)) sdk.unsafeUpdateConfig(theme = job.str("theme"))
    } catch (t: Throwable) {
        for (shot in job.list("shots")) emit("error\t${(shot as Map<*, *>).str("out")}\t${message(t)}")
        return
    }
    BuildInfo.fill(job.map("device").str("name"), type == "watch")
    emit("ready\t${(System.nanoTime() - start) / 1_000_000}")
    for (s in job.list("shots")) {
        val shot = s as Map<*, *>
        val base = shot.str("out")
        // A @PreviewParameter preview is one screenshot per provided value: name_1.png, name_2.png…
        val indices = shot.strOrNull("provider")?.let { name ->
            val count = runCatching { providerCount(name) }.getOrElse { emit("error\t$base\t${message(it)}"); continue }
            (0 until minOf(count, shot.int("providerLimit"))).toList()
        } ?: listOf(-1)
        for (index in indices) {
            val target = if (index < 0) base else base.removeSuffix(".png") + "_${index + 1}.png"
            val t0 = System.nanoTime()
            try {
                frame = null
                var extra = 0
                for (pass in 0 until if (fullLength) 8 else 1) {
                    remaining = 0
                    val view = previewView(sdk, shot, mode, index, ownBars)
                    Debug.view = view
                    sdk.snapshot(view, shot.long("offsetMs"))
                    if (!fullLength || remaining <= 0 || extra + remaining > 30_000) break
                    extra += remaining
                    val taller = device.copy(screenHeight = device.screenHeight + extra)
                    Insets.synthetic = Insets.synthetic?.let { intArrayOf(it[0], taller.screenHeight, it[2], it[3]) }
                    sdk.unsafeUpdateConfig(deviceConfig = taller)
                }
                if (extra > 0) {
                    Insets.synthetic = Insets.synthetic?.let { intArrayOf(it[0], device.screenHeight, it[2], it[3]) }
                    sdk.unsafeUpdateConfig(deviceConfig = device)
                }
                var image = frame ?: error("no frame rendered")
                if (ownBars) image = SystemUi.draw(image, device.density.dpiValue, bars, job.bool("night"), job.bool("rtl"), handle = true)
                File(target).parentFile.mkdirs()
                val renderMs = (System.nanoTime() - t0) / 1_000_000
                val size = "${image.width}x${image.height}"
                val rendered = image
                // PNG encoding (and framing) runs beside the next render instead of before it.
                pending += Encoder.pool.submit {
                    try {
                        val final = opaque(rendered, round, job.str("roundCorners"))
                        ImageIO.write(final, "png", File(target))
                        shot.strOrNull("framed")?.let { framed ->
                            val f = File(if (index < 0) framed else framed.removeSuffix("_framed.png") + "_${index + 1}_framed.png")
                            runCatching {
                                f.parentFile.mkdirs()
                                ImageIO.write(Frame.compose(final, job.map("frame")), "png", f)
                            }.onFailure { System.err.println("swiftshot: no frame for $target: ${message(it)}") }
                        }
                        emit("ok\t$target\t$renderMs\t$size")
                    } catch (t: Throwable) {
                        emit("error\t$target\t${message(t)}")
                    }
                }
            } catch (t: Throwable) {
                emit("error\t$target\t${message(t)}")
            }
        }
    }
    pending.forEach { it.get() }
    try {
        sdk.teardown()
    } catch (_: Throwable) {
        // Layoutlib logs missing optional resources as errors; the shots are already written.
    }
}

/**
 * The preview inside Compose's own `ComposeViewAdapter`, inflated from a one-element layout the way
 * Android Studio does it, so `@PreviewParameter`, inspection mode and the preview wrappers behave
 * as in the IDE.
 */
private fun previewView(sdk: PaparazziSdk, shot: Map<*, *>, mode: RenderingMode, index: Int, edgeToEdge: Boolean): View {
    val full = mode != RenderingMode.SHRINK
    val width = shot.intOrNull("widthDp")?.let { "${it}dp" } ?: if (full) "match_parent" else "wrap_content"
    val height = shot.intOrNull("heightDp")?.let { "${it}dp" }
        ?: if (full && mode == RenderingMode.NORMAL) "match_parent" else "wrap_content"
    val attrs = buildString {
        append(""" android:layout_width="$width" android:layout_height="$height"""")
        append(""" tools:composableName="${xml(shot.str("composable"))}"""")
        shot.strOrNull("provider")?.let {
            append(""" tools:parameterProviderClass="${xml(it)}" tools:parameterProviderIndex="$index"""")
        }
        shot.strOrNull("background")?.let { append(""" android:background="$it"""") }
    }
    val layout = """<androidx.compose.ui.tooling.ComposeViewAdapter
        xmlns:android="http://schemas.android.com/apk/res/android"
        xmlns:tools="http://schemas.android.com/tools"$attrs />"""
    val parser = KXmlParser().apply {
        setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        setInput(StringReader(layout))
    }
    val context = sdk.context as BridgeContext
    val block = BridgeXmlBlockParser(parser, context, ResourceNamespace.RES_AUTO)
    val root = android.widget.FrameLayout(context)
    val view = sdk.layoutInflater.inflate(block, root, false)
    view.layoutParams = view.layoutParams ?: ViewGroup.LayoutParams(-1, -1)
    if (edgeToEdge) view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        // Apps that target 35+ are edge-to-edge: the window doesn't fit the system bars, the
        // content gets the insets. Layoutlib's window fits them, like an app from before 35.
        override fun onViewAttachedToWindow(v: View) {
            val decor = v.rootView
            // The decor passes the insets on instead of turning them into margins and padding,
            // and its bar backgrounds are transparent, as Android 15 makes them for these apps.
            decor.setOnApplyWindowInsetsListener { _, insets -> insets }
            val window = generateSequence<Class<*>>(decor.javaClass) { it.superclass }
                .firstNotNullOfOrNull { c -> runCatching { c.getDeclaredField("mWindow") }.getOrNull() }
                ?.apply { isAccessible = true }?.get(decor) as? android.view.Window
            window?.run {
                @Suppress("DEPRECATION") statusBarColor = android.graphics.Color.TRANSPARENT
                @Suppress("DEPRECATION") navigationBarColor = android.graphics.Color.TRANSPARENT
                isNavigationBarContrastEnforced = false
                isStatusBarContrastEnforced = false
            }
            var p = v.parent
            while (p is ViewGroup && p !== decor) {
                if (p.fitsSystemWindows) {
                    p.fitsSystemWindows = false
                    p.setPadding(0, 0, 0, 0)
                    (p.layoutParams as? ViewGroup.MarginLayoutParams)?.setMargins(0, 0, 0, 0)
                }
                p = p.parent
            }
            decor.requestApplyInsets()
        }
        override fun onViewDetachedFromWindow(v: View) = Unit
    })
    return view
}

/**
 * Paparazzi keeps one SessionParams builder for the process; layoutlib flags it doesn't expose
 * (gesture navigation, edge-to-edge) are added to it before each session is built.
 */
private object SessionFlags {
    private val field by lazy { PaparazziSdk::class.java.getDeclaredField("sessionParamsBuilder").apply { isAccessible = true } }

    fun add(flags: Map<Any, Any>, targetSdk: Int): Boolean {
        val builder = runCatching { field.get(null) }.getOrNull() ?: return false
        val plus = builder.javaClass.methods.first { it.name == "plusFlag" }
        var b: Any = builder
        for ((k, v) in flags) b = plus.invoke(b, k, v)
        // Paparazzi renders as if the app targeted API 22; the framework decides edge-to-edge
        // (enforced from 35) and other behaviour from the real target.
        if (targetSdk > 0) b.javaClass.getDeclaredField("targetSdk").apply { isAccessible = true }.setInt(b, targetSdk)
        field.set(null, b)
        return true
    }
}

object Debug {
    var view: View? = null
    fun frame() {
        if (System.getenv("SWIFTSHOT_DEBUG_INSETS") == null) return
        val v = view ?: return
        System.err.println("INSETS attached=${v.isAttachedToWindow} root=${v.rootView.javaClass.name} rootInsets=${v.rootWindowInsets}")
        var p: Any? = v.parent; var depth = 0
        while (p != null && depth < 12) {
            val pv = p as? View
            System.err.println("  parent ${p.javaClass.name}" + (pv?.let { " y=${it.top} h=${it.height} pad=${it.paddingTop}/${it.paddingBottom} fits=${it.fitsSystemWindows} lp=${(it.layoutParams as? WindowManager.LayoutParams)?.let { l -> "fit=${l.fitInsetsTypes}" } ?: it.layoutParams?.javaClass?.simpleName}" } ?: ""))
            p = (p as? android.view.ViewParent)?.parent; depth++
        }
        System.err.println("  view y=${v.top} h=${v.height}")
    }
}

object Encoder {
    val pool: java.util.concurrent.ExecutorService = java.util.concurrent.Executors.newFixedThreadPool(2) { r -> Thread(r, "encoder").apply { isDaemon = true } }
}

/** How many values a PreviewParameterProvider gives (its `count`, as Android Studio uses). */
private fun providerCount(name: String): Int {
    val cls = Class.forName(name, true, Thread.currentThread().contextClassLoader ?: ClassLoader.getSystemClassLoader())
    val ctor = cls.getDeclaredConstructor().apply { isAccessible = true }
    val provider = ctor.newInstance()
    return cls.getMethod("getCount").invoke(provider) as Int
}

/** Play rejects screenshots with transparency: round watch screens get black corners. */
private fun opaque(image: BufferedImage, round: Boolean, corners: String): BufferedImage {
    if (!round && image.colorModel.hasAlpha().not()) return image
    if (round && corners == "transparent") return image
    val result = BufferedImage(image.width, image.height, BufferedImage.TYPE_INT_RGB)
    val g = result.createGraphics()
    g.color = if (round) Color.BLACK else Color.WHITE
    g.fillRect(0, 0, image.width, image.height)
    g.drawImage(image, 0, 0, null)
    g.dispose()
    return result
}

private fun deviceConfig(d: Map<*, *>, job: Map<*, *>): DeviceConfig {
    val width = d.int("width")
    val height = d.int("height")
    val dpi = d.int("density")
    val rtl = job.bool("rtl")
    return DeviceConfig(
        screenWidth = width,
        screenHeight = height,
        xdpi = d.intOrNull("xdpi") ?: dpi,
        ydpi = d.intOrNull("ydpi") ?: dpi,
        orientation = if (width > height) ScreenOrientation.LANDSCAPE else ScreenOrientation.PORTRAIT,
        uiMode = when (d.strOrNull("type")) {
            "watch" -> UiMode.WATCH
            "tv" -> UiMode.TELEVISION
            "car" -> UiMode.CAR
            else -> UiMode.NORMAL
        },
        nightMode = if (job.bool("night")) NightMode.NIGHT else NightMode.NOTNIGHT,
        density = Density.create(d.int("density")),
        fontScale = job.double("fontScale").toFloat(),
        layoutDirection = if (rtl) LayoutDirection.RTL else LayoutDirection.LTR,
        locale = job.strOrNull("locale"),
        ratio = if (maxOf(width, height) * 9 > minOf(width, height) * 16) ScreenRatio.LONG else ScreenRatio.NOTLONG,
        size = when (d.strOrNull("size")) {
            "small" -> ScreenSize.SMALL
            "large" -> ScreenSize.LARGE
            "xlarge" -> ScreenSize.XLARGE
            else -> ScreenSize.NORMAL
        },
        softButtons = d.strOrNull("type") != "watch",
        screenRound = if (d.bool("round")) ScreenRound.ROUND else null,
    )
}

private fun message(t: Throwable): String {
    var root = t
    while (root.cause != null && root.cause !== root) root = root.cause!!
    val first = root.stackTrace.firstOrNull { !it.className.startsWith("java.") && !it.className.startsWith("kotlin.") }
    return "${root.javaClass.simpleName}: ${root.message ?: ""}${first?.let { " at $it" } ?: ""}".replace('\t', ' ').replace('\n', ' ')
}

private fun xml(s: String) = s.replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;")

private fun Map<*, *>.str(k: String) = this[k] as String
private fun Map<*, *>.strOrNull(k: String) = this[k] as String?
private fun Map<*, *>.int(k: String) = (this[k] as Number).toInt()
private fun Map<*, *>.intOrNull(k: String) = (this[k] as Number?)?.toInt()
private fun Map<*, *>.long(k: String) = (this[k] as Number?)?.toLong() ?: 0L
private fun Map<*, *>.double(k: String) = (this[k] as Number?)?.toDouble() ?: 1.0
private fun Map<*, *>.bool(k: String) = this[k] as Boolean? ?: false
private fun Map<*, *>.map(k: String) = this[k] as Map<*, *>
private fun Map<*, *>.list(k: String) = this[k] as List<*>? ?: emptyList<Any>()
private fun Map<*, *>.strings(k: String) = list(k).map { it as String }
