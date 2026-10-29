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
 * ./gradlew :paparazzi-tests:recordPaparazziDebug --tests 'ParameterizedRecipeCardScreenshotTest'
 * Verify:
 * ./gradlew :paparazzi-tests:verifyPaparazziDebug --tests 'ParameterizedRecipeCardScreenshotTest'
 */
@RunWith(TestParameterInjector::class)
class ParameterizedRecipeCardScreenshotTest(
    @TestParameter val device: Device,
    @TestParameter val uiMode: UiMode,
    @TestParameter val fontSize: FontSize,
    @TestParameter val recipeInLocale: RecipeInLocale,
) {

    enum class Device(val deviceConfig: DeviceConfig){
        TABLET(DeviceConfig.PIXEL_C),
        PHONE(DeviceConfig.PIXEL_4),
    }

    enum class UiMode(val nightMode: NightMode) {
        LIGHT(NightMode.NOTNIGHT),
        DARK(NightMode.NIGHT)
    }

    enum class FontSize(val scale: Float) {
        NORMAL(1.0f),
        LARGE(1.25f)
    }

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

    @get:Rule(order = 0)
    val paparazzi = Paparazzi(
        deviceConfig = device.deviceConfig.copy(
            fontScale = fontSize.scale,
            nightMode = uiMode.nightMode,
            locale = recipeInLocale.localeAsString
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
                    recipe = recipeInLocale.mainScreenRecipeItem,
                    onFavouriteClick = { id -> },
                    onClick = { }
                )
            }
        }
    }
}