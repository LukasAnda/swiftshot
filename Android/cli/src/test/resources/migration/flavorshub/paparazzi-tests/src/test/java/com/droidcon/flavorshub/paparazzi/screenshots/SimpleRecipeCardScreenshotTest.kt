package com.droidcon.flavorshub.paparazzi.screenshots

import androidx.compose.ui.Modifier
import app.cash.paparazzi.Paparazzi
import com.android.ide.common.rendering.api.SessionParams
import com.droidcon.flavorshub.paparazzi.screenshots.testRules.FakeImageLoaderRule
import com.droidcon.flavorshub.ui.model.FavoriteState
import com.droidcon.flavorshub.ui.model.Type
import com.droidcon.flavorshub.ui.screens.main.model.MainScreenRecipeItem
import com.droidcon.flavorshub.ui.screens.main.ui.RecipeCard
import com.droidcon.flavorshub.ui.theme.FlavorshubTheme
import org.junit.Rule
import org.junit.Test

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :paparazzi-tests:recordPaparazziDebug --tests 'SimpleRecipeCardScreenshotTest'
 * Verify:
 * ./gradlew :paparazzi-tests:verifyPaparazziDebug --tests 'SimpleRecipeCardScreenshotTest'
 */
class SimpleRecipeCardScreenshotTest {

    @get:Rule(order = 0)
    val paparazzi = Paparazzi(
        maxPercentDifference = 0.0,
        renderingMode = SessionParams.RenderingMode.SHRINK
    )

    @get:Rule(order = 1)
    val fakeImageLoader = FakeImageLoaderRule { paparazzi.context }

    @Test
    fun recipeCardScreenshot() {
        paparazzi.snapshot(name = "Recipe Card screenshot") {
            FlavorshubTheme {
                RecipeCard(
                    modifier = Modifier.Companion,
                    recipe = MainScreenRecipeItem(
                        id = 1,
                        name = "Recipe Title",
                        shortDescription = "Recipe Description",
                        type = Type.VEGAN,
                        cookingTimeInMin = 30,
                        isFavorite = FavoriteState.FAVORITE,
                        imageUrl = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd"
                    ),
                    onFavouriteClick = { id -> },
                    onClick = { }
                )
            }
        }
    }
}