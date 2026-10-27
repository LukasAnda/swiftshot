package com.swiftshot.demo.bench

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams.RenderingMode
import com.android.resources.Density
import com.android.resources.LayoutDirection
import com.android.resources.NightMode
import com.android.resources.ScreenOrientation
import com.android.resources.ScreenRatio
import com.android.resources.ScreenSize
import org.junit.Rule
import org.junit.Test
import kotlin.math.ceil

/**
 * Every :app @Preview with Paparazzi, following ComposablePreviewScanner's documented Paparazzi
 * integration (README "JVM Screenshot Tests > Paparazzi": a parameterized test whose rule is built
 * from the preview's AndroidPreviewInfo, PreviewBackground and SystemUiSize wrappers), with the
 * device × language × appearance matrix of BenchMatrix as extra parameters.
 *
 * Gradle runs one test class per fork, so setup.sh generates BenchMatrix shard classes
 * (PaparazziPreviewTest0…N-1) as the paparazzi-plugin of ComposablePreviewScanner does with
 * generatedTestClassCount.
 */
abstract class PaparazziPreviewTest(private val shot: Shot) {
    @get:Rule
    val paparazzi: Paparazzi = PaparazziPreviewRule.createFor(shot)

    @Test
    fun snapshot() {
        val info = shot.previewInfo
        paparazzi.snapshot(name = shot.name) {
            when (info.showSystemUi) {
                false -> PreviewBackground(info.showBackground, info.backgroundColor) { shot() }
                true -> SystemUiSize(shot.device.widthDp, shot.device.heightDp) {
                    PreviewBackground(showBackground = true, backgroundColor = info.backgroundColor) { shot() }
                }
            }
        }
    }
}

object PaparazziPreviewRule {
    fun createFor(shot: Shot): Paparazzi {
        val info = shot.previewInfo
        return Paparazzi(
            deviceConfig = DeviceConfigBuilder.build(shot),
            // The same platform theme swiftshot renders with (its default --theme, dark variant at night).
            theme = if (shot.dark) "android:Theme.Material.NoActionBar" else "android:Theme.Material.Light.NoActionBar",
            supportsRtl = true,
            showSystemUi = info.showSystemUi,
            renderingMode = when {
                info.showSystemUi -> RenderingMode.NORMAL
                info.widthDp > 0 && info.heightDp > 0 -> RenderingMode.FULL_EXPAND
                else -> RenderingMode.SHRINK
            },
            // Full device resolution, like swiftshot (Paparazzi scales images down by default).
            useDeviceResolution = true,
            maxPercentDifference = 0.0,
        )
    }
}

object DeviceConfigBuilder {
    fun build(shot: Shot): DeviceConfig {
        val d = shot.device
        val info = shot.previewInfo
        val factor = d.dpi / 160f
        return DeviceConfig(
            screenWidth = if (info.widthDp > 0) ceil(info.widthDp * factor).toInt() else d.width,
            screenHeight = if (info.heightDp > 0) ceil(info.heightDp * factor).toInt() else d.height,
            xdpi = d.xdpi,
            ydpi = d.ydpi,
            orientation = if (d.landscape) ScreenOrientation.LANDSCAPE else ScreenOrientation.PORTRAIT,
            nightMode = if (shot.dark) NightMode.NIGHT else NightMode.NOTNIGHT,
            density = Density.create(d.dpi),
            fontScale = info.fontScale,
            layoutDirection = if (BenchMatrix.rtl(shot.language)) LayoutDirection.RTL else LayoutDirection.LTR,
            locale = info.locale,
            ratio = if (d.long) ScreenRatio.LONG else ScreenRatio.NOTLONG,
            size = ScreenSize.valueOf(d.size.uppercase()),
            softButtons = true,
        )
    }
}

/** From ComposablePreviewScanner's README: what previews render with showSystemUi = true. */
@Composable
fun SystemUiSize(widthInDp: Int, heightInDp: Int, content: @Composable () -> Unit) {
    Box(Modifier.size(width = widthInDp.dp, height = heightInDp.dp).background(Color.White)) {
        content()
    }
}

/** From ComposablePreviewScanner's README: @Preview's showBackground and backgroundColor. */
@Composable
fun PreviewBackground(showBackground: Boolean, backgroundColor: Long, content: @Composable () -> Unit) {
    when (showBackground) {
        false -> content()
        true -> {
            val color = if (backgroundColor != 0L) Color(backgroundColor) else Color.White
            Box(Modifier.background(color)) { content() }
        }
    }
}
