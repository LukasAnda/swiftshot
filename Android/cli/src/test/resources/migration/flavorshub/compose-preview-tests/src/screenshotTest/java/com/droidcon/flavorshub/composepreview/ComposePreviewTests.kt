package com.droidcon.flavorshub.composepreview

import android.content.res.Configuration
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.tooling.preview.Preview
import coil3.ColorImage
import coil3.annotation.ExperimentalCoilApi
import coil3.compose.AsyncImagePreviewHandler
import coil3.compose.LocalAsyncImagePreviewHandler
import com.droidcon.flavorshub.ui.model.BottomNavItem.HOME
import com.droidcon.flavorshub.ui.model.FavoriteState.FAVORITE
import com.droidcon.flavorshub.ui.model.FavoriteState.NOT_FAVORITE
import com.droidcon.flavorshub.ui.model.Type.FISH
import com.droidcon.flavorshub.ui.model.Type.MEAT
import com.droidcon.flavorshub.ui.screens.main.model.MainScreenRecipeItem
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreen
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreenRecipeContent.NoRecipes
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreenRecipeContent.Recipes
import com.droidcon.flavorshub.ui.screens.recipedetails.model.RecipeDetailsItem
import com.droidcon.flavorshub.ui.screens.recipedetails.ui.RecipeDetailsScreen
import com.droidcon.flavorshub.ui.theme.FlavorshubTheme
import kotlinx.collections.immutable.toImmutableList

/**
 * To execute these tests and generate screenshots, run the command
 * Record:
 * ./gradlew :compose-preview-tests:updateDebugScreenshotTest
 * Verify:
 * ./gradlew :compose-preview-tests:validateDebugScreenshotTest
 *
 * WARNING: The commands above work although Android Studio might show errors
 */
class ComposePreviewTests {
    @OptIn(ExperimentalCoilApi::class)
    @Preview(fontScale = 1.3f)
    @Preview(uiMode = Configuration.UI_MODE_NIGHT_YES)
    @Preview(locale = "ar")
    @Composable
    fun ContentMainScreenPreview() {
        val recipes = listOf(
            MainScreenRecipeItem(
                id = 1,
                name = "Recipe 1",
                shortDescription = "Description 1",
                cookingTimeInMin = 30,
                type = MEAT,
                imageUrl = "https://example.com/recipe1.jpg",
                isFavorite = NOT_FAVORITE
            ),
            MainScreenRecipeItem(
                id = 2,
                name = "Recipe 2",
                shortDescription = "Description 2",
                cookingTimeInMin = 30,
                type = FISH,
                imageUrl = "https://example.com/recipe1.jpg",
                isFavorite = FAVORITE
            )
        ).toImmutableList()

        val previewHandler = AsyncImagePreviewHandler {
            ColorImage(Color.Red.toArgb())
        }
        CompositionLocalProvider(LocalAsyncImagePreviewHandler provides previewHandler) {
            FlavorshubTheme {
                MainScreen(
                    content = Recipes(
                        scrollState = rememberLazyListState(),
                        recipes = recipes,
                        onToggleFavorite = {},
                        onRecipeClick = {}
                    ),
                    selectedBottomNavItem = HOME,
                    onToggleFilter = {},
                    selectedFilters = listOf(MEAT).toImmutableList(),
                    onBottomNavItemClick = {},
                )
            }
        }
    }

    @OptIn(ExperimentalCoilApi::class)
    @Preview(fontScale = 1.3f)
    @Preview(uiMode = Configuration.UI_MODE_NIGHT_YES)
    @Preview(locale = "ar")
    @Composable
    fun EmptyMainScreenPreview() {
        FlavorshubTheme {
            MainScreen(
                selectedBottomNavItem = HOME,
                onToggleFilter = {},
                selectedFilters = listOf(MEAT).toImmutableList(),
                onBottomNavItemClick = {},
                content = NoRecipes
            )
        }

    }

    @OptIn(ExperimentalCoilApi::class)
    @Preview(fontScale = 1.3f)
    @Preview(uiMode = Configuration.UI_MODE_NIGHT_YES)
    @Preview(locale = "ar")
    @Composable
    fun RecipeDetailsPreview() {
        val previewHandler = AsyncImagePreviewHandler {
            ColorImage(Color.Companion.Red.toArgb())
        }
        CompositionLocalProvider(LocalAsyncImagePreviewHandler provides previewHandler) {
            FlavorshubTheme {
                RecipeDetailsScreen(
                    scrollState = rememberScrollState(),
                    recipe = RecipeDetailsItem(
                        id = 1,
                        name = "Test Recipe",
                        cookingTimeInMin = 15,
                        type = MEAT,
                        imageUrl = "",
                        ingredients = listOf(
                            "1 cup quinoa, rinsed",
                            "1 sweet potato, diced",
                            "1 cup broccoli florets",
                            "1 red bell pepper, sliced",
                            "1 cup chickpeas, drained and rinsed",
                            "2 tbsp olive oil",
                            "1 avocado, sliced",
                            "2 tbsp tahini",
                            "1 tbsp lemon juice",
                            "1 tsp maple syrup",
                            "Salt and pepper to taste"
                        ),
                        instructions = listOf(
                            "1. Preheat oven to 425°F (220°C)",
                            "2. Cook quinoa according to package instructions",
                            "3. Toss sweet potato, broccoli and bell pepper with olive oil, salt and pepper",
                            "4. Roast vegetables for 20-25 minutes until tender",
                            "5. Mix tahini, lemon juice, maple syrup and 2-3 tbsp water to make dressing",
                            "6. Assemble bowl with quinoa, roasted vegetables, chickpeas and avocado",
                            "7. Drizzle with tahini dressing and serve"
                        )
                    ),
                    onBackPressed = {}
                )
            }
        }
    }
}