package com.swiftshot.demo.bench

import androidx.compose.ui.test.junit4.ComposeContentTestRule
import com.github.takahirom.roborazzi.AndroidComposePreviewTester
import com.github.takahirom.roborazzi.ComposePreviewTester
import com.github.takahirom.roborazzi.ComposePreviewTester.TestParameter.JUnit4TestParameter.AndroidPreviewJUnit4TestParameter
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.InternalRoborazziApi
import com.github.takahirom.roborazzi.RoborazziComposeSetupOption
import com.github.takahirom.roborazzi.RoborazziRecordFilePathStrategy
import com.github.takahirom.roborazzi.captureRoboImage
import com.github.takahirom.roborazzi.provideRoborazziContext
import com.github.takahirom.roborazzi.roborazziRecordFilePathStrategy
import com.github.takahirom.roborazzi.roborazziSystemPropertyOutputDirectory
import com.github.takahirom.roborazzi.toRoborazziComposeOptions
import org.junit.rules.TestRule
import java.io.File

/**
 * Roborazzi's generated Compose Preview tests (generateComposePreviewRobolectricTests) with a
 * custom ComposePreviewTester (testerQualifiedClassName), because the generated default tester
 * renders each preview once, with the @Config qualifiers, while the benchmark needs the
 * device × language × appearance matrix.
 *
 *  - testParameters(): Roborazzi's own scan (AndroidComposePreviewTester().testParameters(),
 *    the packages configured in the Gradle extension), expanded by BenchMatrix.
 *  - test(): Roborazzi's preview capture (ComposablePreview.captureRoboImage with
 *    toRoborazziComposeOptions(), from roborazzi-compose-preview-scanner-support), plus the
 *    device as a Robolectric qualifier. It launches its own activity after applying the
 *    qualifiers, so the generated test's compose rule is not applied (that would launch a
 *    second, unused activity per test before the matrix configuration is known).
 */
@OptIn(ExperimentalRoborazziApi::class, InternalRoborazziApi::class)
class BenchComposePreviewTester : ComposePreviewTester<AndroidPreviewJUnit4TestParameter> {
    override fun options(): ComposePreviewTester.Options = super.options().copy(
        testLifecycleOptions = ComposePreviewTester.Options.JUnit4TestLifecycleOptions(
            testRuleFactory = { _: ComposeContentTestRule -> TestRule { base, _ -> base } },
        ),
    )

    override fun testParameters(): List<AndroidPreviewJUnit4TestParameter> {
        val lifecycle = options().testLifecycleOptions as ComposePreviewTester.Options.JUnit4TestLifecycleOptions
        val previews = AndroidComposePreviewTester().testParameters().map { it.preview }
        return BenchMatrix.expand(previews).map { shot ->
            AndroidPreviewJUnit4TestParameter(composeTestRuleFactory = { lifecycle.composeRuleFactory() }, preview = shot)
        }
    }

    override fun test(testParameter: AndroidPreviewJUnit4TestParameter) {
        val shot = testParameter.preview as Shot
        val prefix = if (roborazziRecordFilePathStrategy() == RoborazziRecordFilePathStrategy.RelativePathFromCurrentDirectory) {
            roborazziSystemPropertyOutputDirectory() + File.separator
        } else ""
        val filePath = "$prefix${shot.name}.${provideRoborazziContext().imageExtension}"
        val composeOptions = shot.toRoborazziComposeOptions(options().renderScale).builder()
            .addOption(DeviceQualifiers(shot.device))
            .build()
        shot.captureRoboImage(filePath = filePath, roborazziComposeOptions = composeOptions)
    }
}

/**
 * The device as Robolectric qualifiers, in the form ComposablePreviewScanner's
 * RobolectricDeviceQualifierBuilder produces for a @Preview(device = …): w…dp-h…dp-size-ratio-
 * notround-orientation-…dpi. Robolectric sizes screens in whole dp, so a 1280 px wide 480 dpi
 * screen (426.67 dp) becomes 427 dp, 1281 px.
 */
@OptIn(ExperimentalRoborazziApi::class)
private data class DeviceQualifiers(val device: BenchDevice) : RoborazziComposeSetupOption {
    override fun configure(configBuilder: RoborazziComposeSetupOption.ConfigBuilder) {
        configBuilder.addRobolectricQualifier(
            listOf(
                "w${device.widthDp}dp",
                "h${device.heightDp}dp",
                device.size,
                if (device.long) "long" else "notlong",
                "notround",
                if (device.landscape) "land" else "port",
                "${device.dpi}dpi",
            ).joinToString("-")
        )
    }
}
