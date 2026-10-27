package com.swiftshot.demo.bench

import androidx.compose.runtime.Composable
import sergio.sastre.composable.preview.scanner.android.AndroidComposablePreviewScanner
import sergio.sastre.composable.preview.scanner.android.AndroidPreviewInfo
import sergio.sastre.composable.preview.scanner.core.preview.ComposablePreview

/**
 * The benchmark matrix shared by the Paparazzi and Roborazzi setups (copied into the module's
 * test sources by bench/android/setup.sh): every scanned @Preview × device × language ×
 * appearance, with the preview's own settings winning, exactly as swiftshot plans it.
 *
 *  - a preview that sets the night bits of `uiMode` (`@PreviewLightDark`) renders only that appearance
 *  - a preview that sets `locale` renders only that language
 *  - `@PreviewParameter` and multipreviews (`@PreviewFontScale`) are expanded by ComposablePreviewScanner
 *
 * The matrix comes from system properties set by the Gradle test task (bench.devices,
 * bench.languages, bench.appearances); bench.limit keeps only the first N screenshots (used by
 * the untimed warm-up run that downloads Robolectric's android-all jar).
 */
data class BenchDevice(
    val name: String,
    val width: Int,
    val height: Int,
    val dpi: Int,
    val xdpi: Int,
    val ydpi: Int,
    /** Android screen size bucket: normal, large… */
    val size: String,
) {
    val landscape get() = width > height
    /** As swiftshot (and Android) classify it: long when the aspect ratio is above 16:9. */
    val long get() = maxOf(width, height) * 9 > minOf(width, height) * 16
    val widthDp get() = Math.round(width * 160f / dpi)
    val heightDp get() = Math.round(height * 160f / dpi)
}

object BenchMatrix {
    /** The same screens as swiftshot's devices.json. */
    val knownDevices = listOf(
        BenchDevice("Pixel 10 Pro", 1280, 2856, 480, 495, 495, "normal"),
        BenchDevice("Pixel Tablet", 2560, 1600, 320, 276, 276, "large"),
    )

    val devices: List<BenchDevice> = list("bench.devices", "Pixel 10 Pro,Pixel Tablet").map { n ->
        knownDevices.firstOrNull { it.name == n } ?: error("Unknown benchmark device \"$n\"")
    }
    val languages: List<String> = list("bench.languages", "en-US,de-DE,sk,ar,ja")
    val appearances: List<String> = list("bench.appearances", "light,dark")
    private val limit = System.getProperty("bench.limit")?.toIntOrNull() ?: Int.MAX_VALUE
    private val packages = list("bench.packages", "com.swiftshot.demo")

    /** Every screenshot, in a stable order (shards in different JVMs must agree on it). */
    val shots: List<Shot> by lazy {
        expand(
            AndroidComposablePreviewScanner()
                .scanPackageTrees(*packages.toTypedArray())
                .getPreviews()
        )
    }

    fun shard(index: Int, count: Int): List<Shot> = shots.filterIndexed { i, _ -> i % count == index }

    fun expand(previews: List<ComposablePreview<AndroidPreviewInfo>>): List<Shot> {
        val sorted = previews.sortedWith(
            compareBy({ it.declaringClass }, { it.methodName }, { it.previewIndex ?: -1 }, { it.previewInfo.toString() })
        )
        val names = HashMap<String, Int>()
        val result = mutableListOf<Shot>()
        for (p in sorted) {
            val info = p.previewInfo
            val ownNight = when (info.uiMode and UI_MODE_NIGHT_MASK) {
                UI_MODE_NIGHT_YES -> true
                UI_MODE_NIGHT_NO -> false
                else -> null
            }
            val dark = ownNight?.let { listOf(it) } ?: appearances.map { it == "dark" }
            val langs = if (info.locale.isNotBlank()) listOf(bcp47(info.locale)) else languages
            // Short, readable and unique: Paparazzi puts the name into the file name twice (test
            // name and snapshot name), and long ids exceed the file system's 255 bytes.
            val id = listOfNotNull(p.methodName, info.name.ifBlank { null }, p.previewIndex?.toString()).joinToString("_")
            for (device in devices) for (lang in langs) for (d in dark) {
                var name = clean("${lang}_${device.name}_${id}" + if (ownNight == null) (if (d) "_dark" else "_light") else "")
                val n = names.merge(name, 1, Int::plus)!!
                if (n > 1) name += "_$n"
                result += Shot(p, device, lang, d, ownNight != null, name)
            }
        }
        return result.take(limit)
    }

    /** BCP 47 to Android's resource qualifier: en-US → en-rUS (as swiftshot does). */
    fun qualifier(tag: String): String {
        val parts = tag.replace('_', '-').split('-')
        return when {
            parts.size == 1 -> parts[0]
            parts.size == 2 && parts[1].length == 2 -> "${parts[0]}-r${parts[1].uppercase()}"
            else -> "b+" + parts.joinToString("+")
        }
    }

    fun bcp47(locale: String): String =
        Regex("([a-zA-Z]{2,3})-r([a-zA-Z]{2})").matchEntire(locale)?.let { "${it.groupValues[1]}-${it.groupValues[2].uppercase()}" } ?: locale

    fun rtl(tag: String) = tag.substringBefore('-') in setOf("ar", "fa", "he", "iw", "ur")

    private fun clean(s: String) = s.replace(Regex("[^A-Za-z0-9._-]+"), "_")

    private fun list(key: String, default: String) =
        (System.getProperty(key)?.takeIf { it.isNotBlank() } ?: default).split(',').map(String::trim).filter(String::isNotEmpty)

    const val UI_MODE_NIGHT_MASK = 0x30
    const val UI_MODE_NIGHT_NO = 0x10
    const val UI_MODE_NIGHT_YES = 0x20
    const val UI_MODE_TYPE_MASK = 0x0f
    const val UI_MODE_TYPE_NORMAL = 0x01
}

/**
 * One screenshot: the scanned preview with the matrix applied to its preview info (locale and
 * night mode), so each tool's own preview-to-configuration mapping sees it like any other preview.
 */
class Shot(
    val original: ComposablePreview<AndroidPreviewInfo>,
    val device: BenchDevice,
    val language: String,
    val dark: Boolean,
    val previewSetsNight: Boolean,
    val name: String,
) : ComposablePreview<AndroidPreviewInfo> by original {
    override val previewInfo: AndroidPreviewInfo = original.previewInfo.let { info ->
        val type = (info.uiMode and BenchMatrix.UI_MODE_TYPE_MASK).takeIf { it != 0 } ?: BenchMatrix.UI_MODE_TYPE_NORMAL
        val night = if (dark) BenchMatrix.UI_MODE_NIGHT_YES else BenchMatrix.UI_MODE_NIGHT_NO
        info.copy(
            locale = BenchMatrix.qualifier(language),
            uiMode = (info.uiMode and (BenchMatrix.UI_MODE_NIGHT_MASK or BenchMatrix.UI_MODE_TYPE_MASK).inv()) or type or night,
        )
    }

    @Composable
    override fun invoke() {
        original()
    }

    override fun toString() = name
}
