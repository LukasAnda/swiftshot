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
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.HiltTestApplication
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :roborazzi-tests:recordRoborazziDebug --tests 'SimpleMultiFrameScreenshotTest'
 * Verify:
 * ./gradlew :roborazzi-tests:verifyRoborazziDebug --tests 'SimpleMultiFrameScreenshotTest'
 */
@HiltAndroidTest
@Config(application = HiltTestApplication::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SimpleMultiFrameScreenshotTest {

    @get:Rule(order = 0)
    val fakeImageLoaderRule = FakeImageLoaderRule { getApplicationContext() }

    @get:Rule(order = 1)
    val addActivityToRobolectricRule =
        AddActivityToRobolectricRule(FlavorshubActivity::class.java)

    @get:Rule(order = 2)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 3)
    val composeTestRule = createAndroidComposeRule<FlavorshubActivity>()

    @get:Rule(order = 4)
    val roborazziRule =
        RoborazziRule(
            composeRule = composeTestRule,
            captureRoot = composeTestRule.onRoot(),
            options = Options(
                captureType = RoborazziRule.CaptureType.Gif(),
            ),
        )

    @Config(qualifiers = RobolectricDeviceQualifiers.Pixel4)
    @Test
    fun multiFrameScreenshots() {
        ScreenInteractor(composeTestRule).run {
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