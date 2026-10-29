package com.droidcon.flavorshub.paparazzi.screenshots

import androidx.compose.foundation.lazy.rememberLazyListState
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import app.cash.paparazzi.accessibility.AccessibilityRenderExtension
import com.droidcon.flavorshub.paparazzi.screenshots.testRules.FakeImageLoaderRule
import com.droidcon.flavorshub.ui.model.BottomNavItem.HOME
import com.droidcon.flavorshub.ui.model.FavoriteState.FAVORITE
import com.droidcon.flavorshub.ui.model.FavoriteState.NOT_FAVORITE
import com.droidcon.flavorshub.ui.model.Type.FISH
import com.droidcon.flavorshub.ui.model.Type.MEAT
import com.droidcon.flavorshub.ui.screens.main.model.MainScreenRecipeItem
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreen
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreenRecipeContent.Recipes
import com.droidcon.flavorshub.ui.theme.FlavorshubTheme
import kotlinx.collections.immutable.toImmutableList
import org.junit.Rule
import org.junit.Test

/**
 * Execute the following command for this screenshot
 * Record:
 * ./gradlew :paparazzi-tests:recordPaparazziDebug --tests 'AccessibilityScreenshotTest'
 * Verify:
 * ./gradlew :paparazzi-tests:verifyPaparazziDebug --tests 'AccessibilityScreenshotTest'
 */
class AccessibilityScreenshotTest {

    @get:Rule(order = 0)
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_4,
        renderExtensions = setOf(AccessibilityRenderExtension())
    )

    @get:Rule(order = 1)
    val fakeImageLoader = FakeImageLoaderRule { paparazzi.context }

    private val recipes = listOf(
        MainScreenRecipeItem(
            id = 1,
            name = "Recipe 1",
            shortDescription = "Description 1",
            cookingTimeInMin = 30,
            type = MEAT,
            imageUrl = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd",
            isFavorite = NOT_FAVORITE
        ),
        MainScreenRecipeItem(
            id = 2,
            name = "Recipe 2",
            shortDescription = "Description 2",
            cookingTimeInMin = 30,
            type = FISH,
            imageUrl = "https://images.unsplash.com/photo-1512621776951-a57141f2eefd",
            isFavorite = FAVORITE
        )
    ).toImmutableList()

    @Test
    fun mainScreenAccessibilityScreenshot() {
        paparazzi.snapshot(name = "Main Screen Accessibility") {
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
                    selectedFilters = listOf(MEAT, FISH).toImmutableList(),
                    onBottomNavItemClick = {},
                )
            }
        }
    }
}