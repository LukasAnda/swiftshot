package com.droidcon.flavorshub.paparazzi.screenshots

import androidx.compose.ui.Modifier
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import com.android.resources.NightMode
import com.droidcon.flavorshub.paparazzi.screenshots.testRules.FakeImageLoaderRule
import com.droidcon.flavorshub.ui.model.FavoriteState
import com.droidcon.flavorshub.ui.model.Type
import com.droidcon.flavorshub.ui.screens.main.model.MainScreenRecipeItem
import com.droidcon.flavorshub.ui.screens.main.ui.RecipeCard
import com.droidcon.flavorshub.ui.theme.FlavorshubTheme
import com.google.testing.junit.testparameterinjector.TestParameter
import com.google.testing.junit.testparameterinjector.TestParameterInjector
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :paparazzi-tests:recordPaparazziDebug --tests 'NoOvertestingRecipeCardScreenshotTest'
 * Verify:
 * ./gradlew :paparazzi-tests:verifyPaparazziDebug --tests 'NoOvertestingRecipeCardScreenshotTest'
 */
@RunWith(TestParameterInjector::class)
class NoOvertestingRecipeCardScreenshotTest(
    @TestParameter val testCase: TestCase,
) {

    enum class RecipeInLocale(
        val localeAsString: String,
        val mainScreenRecipeItem: MainScreenRecipeItem
    ) {
        ENGLISH(
            localeAsString = "en",
            mainScreenRecipeItem = MainScreenRecipeItem(
                id = 1,
                name = "Recipe Title",
                shortDescription = "Recipe Description",
                type = Type.MEAT,
                cookingTimeInMin = 30,
                isFavorite = FavoriteState.FAVORITE,
                imageUrl = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd"
            )
        ),
        ARABIC(
            localeAsString = "ar",
            mainScreenRecipeItem = MainScreenRecipeItem(
                id = 2,
                name = "عنوان الوصفة",
                shortDescription = "وصف الوصفة",
                type = Type.VEGAN,
                cookingTimeInMin = 30,
                isFavorite = FavoriteState.NOT_FAVORITE,
                imageUrl = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd"
            )
        )
    }

    enum class TestCase(
        val device: DeviceConfig,
        val fontSize: Float,
        val recipeInLocale: RecipeInLocale,
        val uiMode: NightMode
    ) {
        HAPPY_PATH_LARGE(
            device = DeviceConfig.PIXEL_4,
            fontSize = 1.25f,
            recipeInLocale = RecipeInLocale.ENGLISH,
            uiMode = NightMode.NOTNIGHT,
        ),
        UNHAPPY_PATH(
            device = DeviceConfig.PIXEL_C,
            fontSize = 1.0f,
            recipeInLocale = RecipeInLocale.ARABIC,
            uiMode = NightMode.NIGHT
        )
    }

    @get:Rule(order = 0)
    val paparazzi = Paparazzi(
        deviceConfig = testCase.device.copy(
            fontScale = testCase.fontSize,
            nightMode = testCase.uiMode,
            locale = testCase.recipeInLocale.localeAsString
        ),
        supportsRtl = true,
        renderingMode = SessionParams.RenderingMode.SHRINK
    )

    @get:Rule(order = 1)
    val fakeImageLoader = FakeImageLoaderRule { paparazzi.context }

    @Test
    fun recipeCardScreenshot() {
        paparazzi.snapshot(name = "RecipeCard") {
            FlavorshubTheme {
                RecipeCard(
                    modifier = Modifier.Companion,
                    recipe = testCase.recipeInLocale.mainScreenRecipeItem,
                    onFavouriteClick = { id -> },
                    onClick = { }
                )
            }
        }
    }
}