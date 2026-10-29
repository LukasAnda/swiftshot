package com.droidcon.flavorshub.paparazzi.screenshots

import android.content.res.Configuration.UI_MODE_NIGHT_MASK
import android.content.res.Configuration.UI_MODE_NIGHT_YES
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import com.android.resources.NightMode
import com.droidcon.flavorshub.paparazzi.screenshots.testRules.FakeImageLoaderRule
import com.google.testing.junit.testparameterinjector.TestParameter
import com.google.testing.junit.testparameterinjector.TestParameterInjector
import com.google.testing.junit.testparameterinjector.TestParameterValuesProvider
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import sergio.sastre.composable.preview.scanner.android.AndroidComposablePreviewScanner
import sergio.sastre.composable.preview.scanner.android.AndroidPreviewInfo
import sergio.sastre.composable.preview.scanner.android.screenshotid.AndroidPreviewScreenshotIdBuilder
import sergio.sastre.composable.preview.scanner.core.preview.ComposablePreview

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :paparazzi-tests:recordPaparazziDebug --tests 'CustomComposePreviewTest'
 * Verify:
 * ./gradlew :paparazzi-tests:verifyPaparazziDebug --tests 'CustomComposePreviewTest'
 */
class ComposablePreviewProvider : TestParameterValuesProvider() {
    private val cachedPreviews: List<ComposablePreview<AndroidPreviewInfo>> by lazy {
        AndroidComposablePreviewScanner()
            .scanPackageTrees("com.droidcon.flavorshub")
            .getPreviews()
    }

    override fun provideValues(
        context: Context
    ): List<ComposablePreview<AndroidPreviewInfo>> = cachedPreviews
}

@RunWith(TestParameterInjector::class)
class CustomComposePreviewTest(
    @TestParameter(valuesProvider = ComposablePreviewProvider::class)
    val preview: ComposablePreview<AndroidPreviewInfo>
) {

    @get:Rule(order = 0)
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_4.copy(
            nightMode =
                when (preview.previewInfo.uiMode and UI_MODE_NIGHT_MASK == UI_MODE_NIGHT_YES) {
                    true -> NightMode.NIGHT
                    false -> NightMode.NOTNIGHT
                },
            fontScale = preview.previewInfo.fontScale,
            locale = preview.previewInfo.locale.ifBlank { "en" }
        ),
        supportsRtl = true, // for Arabic
        renderingMode = SessionParams.RenderingMode.SHRINK,
    )

    @get:Rule(order = 1)
    val fakeImageLoaderRule = FakeImageLoaderRule { paparazzi.context }

    @Test
    fun snapshotPreview() {
        paparazzi.snapshot(
            name =
                AndroidPreviewScreenshotIdBuilder(preview)
                    .ignoreClassName()
                    .ignoreMethodName()
                    .build()
        ) {
            preview()
        }
    }
}