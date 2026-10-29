package com.droidcon.flavorshub.roborazzi.screenshots.interactor

import com.droidcon.flavorshub.ui.R
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.rules.ActivityScenarioRule
import com.github.takahirom.roborazzi.DEFAULT_ROBORAZZI_OUTPUT_DIR_PATH
import com.github.takahirom.roborazzi.captureRoboImage

/**
 * Class that provides a simple interface interacting with UI elements and for capturing screenshots.
 * @param composeTestRule the test rule for the Compose UI
 * @param parameterNames the list of parameters to be used for unique screenshot naming in parameterized tests
 */
class ScreenInteractor<A : ComponentActivity>(
    val composeTestRule: AndroidComposeTestRule<ActivityScenarioRule<A>, A>,
    val parameterNames: List<Enum<*>> = emptyList<Enum<*>>()
) {
    private fun stringRes(stringRes: Int, vararg formatArgs: Any) =
        composeTestRule.activity.getString(stringRes, *formatArgs)

    fun captureScreenshot(name: String) {
        val parametersString = when (parameterNames.isEmpty()) {
            true -> ""
            false -> "[${parameterNames.joinToString(",") { it.name }}]"
        }
        val screenshotName = "$DEFAULT_ROBORAZZI_OUTPUT_DIR_PATH/$name$parametersString.png"
        composeTestRule.onRoot().captureRoboImage(screenshotName)
    }

    fun addToFavoritesButtonInRecipeAtIndex(index: Int): SemanticsNodeInteraction =
        composeTestRule.onAllNodesWithContentDescription(
            label = stringRes(R.string.add_to_favorites_icon),
            useUnmergedTree = true
        )[index]

    fun removeFromFavoritesButtonInRecipeAtIndex(index: Int): SemanticsNodeInteraction =
        composeTestRule.onAllNodesWithContentDescription(
            label = stringRes(R.string.remove_from_favorites_icon),
            useUnmergedTree = true
        )[index]

    fun bottomTabFavorites(): SemanticsNodeInteraction =
        composeTestRule.onNodeWithText(stringRes(R.string.bottom_nav_Favorites))

    fun recipeImageAtIndex(index: Int): SemanticsNodeInteraction =
        composeTestRule.onAllNodesWithContentDescription(
            label = stringRes(R.string.recipe_image_content_description, ""),
            substring = true,
            useUnmergedTree = true
        )[index]

    fun pressBack() {
        composeTestRule.activity.onBackPressedDispatcher.onBackPressed()
    }
}