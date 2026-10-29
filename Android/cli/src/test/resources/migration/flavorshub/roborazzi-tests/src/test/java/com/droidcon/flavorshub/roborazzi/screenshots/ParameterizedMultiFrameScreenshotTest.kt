package com.droidcon.flavorshub.roborazzi.screenshots

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider.getApplicationContext
import com.droidcon.flavorshub.FlavorshubActivity
import com.droidcon.flavorshub.roborazzi.screenshots.interactor.ScreenInteractor
import com.droidcon.flavorshub.roborazzi.screenshots.testrules.AddActivityToRobolectricRule
import com.droidcon.flavorshub.roborazzi.screenshots.testrules.FakeImageLoaderRule
import com.github.takahirom.roborazzi.RobolectricDeviceQualifiers
import com.github.takahirom.roborazzi.RoborazziRule
import com.github.takahirom.roborazzi.RoborazziRule.Options
import com.google.testing.junit.testparameterinjector.TestParameter
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.HiltTestApplication
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestParameterInjector
import org.robolectric.RuntimeEnvironment.setFontScale
import org.robolectric.RuntimeEnvironment.setQualifiers
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :roborazzi-tests:recordRoborazziDebug --tests 'ParameterizedMultiFrameScreenshotTest'
 * Verify:
 * ./gradlew :roborazzi-tests:verifyRoborazziDebug --tests 'ParameterizedMultiFrameScreenshotTest'
 */
@HiltAndroidTest
@Config(application = HiltTestApplication::class)
@RunWith(RobolectricTestParameterInjector::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ParameterizedMultiFrameScreenshotTest(
    @TestParameter val device: Device,
    @TestParameter val uiMode: UiMode,
    @TestParameter val locale: Locale,
    @TestParameter val fontSize: FontSize
) {

    enum class Device(val qualifier: String) {
        TABLET(RobolectricDeviceQualifiers.PixelC),
        PHONE(RobolectricDeviceQualifiers.Pixel4)
    }

    enum class UiMode(val cumulativeQualifier: String) {
        LIGHT("+notnight"),
        DARK("+night")
    }

    enum class FontSize(val scale: Float) {
        NORMAL(1.0f),
        LARGE(1.3f)
    }

    enum class Locale(val cumulativeQualifier: String) {
        ENGLISH("+en"),
        ARABIC("+ar")
    }

    @get:Rule(order = 0)
    val fakeImageLoaderRule = FakeImageLoaderRule { getApplicationContext() }

    @get:Rule(order = 1)
    val addActivityToRobolectricRule =
        AddActivityToRobolectricRule(FlavorshubActivity::class.java)

    @get:Rule(order = 2)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 3)
    val robolectricQualifiersRule = object : TestWatcher() {
        override fun starting(description: Description) {
            setQualifiers(device.qualifier)
            setQualifiers(uiMode.cumulativeQualifier)
            setQualifiers(locale.cumulativeQualifier)
            setFontScale(fontSize.scale)
        }
    }

    @get:Rule(order = 4)
    val composeTestRule = createAndroidComposeRule<FlavorshubActivity>()

    @get:Rule(order = 5)
    val roborazziRule =
        RoborazziRule(
            composeRule = composeTestRule,
            captureRoot = composeTestRule.onRoot(),
            options = Options(
                captureType = RoborazziRule.CaptureType.Gif()
            )
        )

    @Test
    fun multiFrameScreenshots() {
        ScreenInteractor(
            composeTestRule = composeTestRule,
            parameterNames = listOf(device, uiMode, locale, fontSize)
        ).run {
            captureScreenshot("1. Show Home")

            addToFavoritesButtonInRecipeAtIndex(0).performClick()
            captureScreenshot("2. Added 1st recipe to favorites")

            bottomTabFavorites().performClick()
            captureScreenshot("3. Show Favorites")

            recipeImageAtIndex(0).performClick()
            captureScreenshot("4. Show Details Screen of favorited Recipe")

            pressBack()
            captureScreenshot("5. Back in Favorites")

            removeFromFavoritesButtonInRecipeAtIndex(0).performClick()
            captureScreenshot("6. Removed favorited Recipe")
        }
    }
}