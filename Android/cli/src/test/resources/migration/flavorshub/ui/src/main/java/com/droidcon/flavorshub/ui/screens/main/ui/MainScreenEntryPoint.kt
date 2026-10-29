package com.droidcon.flavorshub.ui.screens.main.ui

import android.content.res.Configuration
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.Icons.Default
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil3.ColorImage
import coil3.annotation.ExperimentalCoilApi
import coil3.compose.AsyncImagePreviewHandler
import coil3.compose.LocalAsyncImagePreviewHandler
import com.droidcon.flavorshub.ui.R
import com.droidcon.flavorshub.ui.model.BottomNavItem
import com.droidcon.flavorshub.ui.model.BottomNavItem.FAVOURITES
import com.droidcon.flavorshub.ui.model.BottomNavItem.HOME
import com.droidcon.flavorshub.ui.model.FavoriteState.FAVORITE
import com.droidcon.flavorshub.ui.model.FavoriteState.NOT_FAVORITE
import com.droidcon.flavorshub.ui.model.Type
import com.droidcon.flavorshub.ui.model.Type.FISH
import com.droidcon.flavorshub.ui.model.Type.MEAT
import com.droidcon.flavorshub.ui.model.Type.VEGAN
import com.droidcon.flavorshub.ui.screens.main.model.MainScreenRecipeItem
import com.droidcon.flavorshub.ui.screens.main.ui.MainScreenRecipeContent.Recipes
import com.droidcon.flavorshub.ui.theme.FlavorshubTheme
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.toImmutableList

@OptIn(ExperimentalMaterial3Api::class, ExperimentalAnimationApi::class)
@Composable
fun MainScreen(
    selectedBottomNavItem: BottomNavItem,
    selectedFilters: ImmutableList<Type>,
    onBottomNavItemClick: (BottomNavItem) -> Unit,
    onToggleFilter: (Type) -> Unit,
    content: MainScreenRecipeContent,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                colors = TopAppBarDefaults.topAppBarColors(),
                modifier = Modifier,
            )
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    icon = { Icon(Default.Home, stringResource(R.string.bottom_nav_home)) },
                    label = { Text(stringResource(R.string.bottom_nav_home)) },
                    selected = selectedBottomNavItem == HOME,
                    onClick = { onBottomNavItemClick(HOME) }
                )

                NavigationBarItem(
                    icon = {
                        Icon(
                            Default.Favorite,
                            stringResource(R.string.bottom_nav_Favorites)
                        )
                    },
                    label = { Text(stringResource(R.string.bottom_nav_Favorites)) },
                    selected = selectedBottomNavItem == FAVOURITES,
                    onClick = { onBottomNavItemClick(FAVOURITES) }
                )
            }
        },
        content = { padding ->
            Column(
                modifier = Modifier.padding(padding)
            ) {
                LazyRow(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item(key = VEGAN.name) {
                        FoodFilterChip(
                            text = stringResource(R.string.filter_vegan),
                            isSelected = selectedFilters.contains(VEGAN),
                            onClick = { onToggleFilter(VEGAN) }
                        )
                    }
                    item(key = FISH.name) {
                        FoodFilterChip(
                            text = stringResource(R.string.filter_fish),
                            isSelected = selectedFilters.contains(FISH),
                            onClick = { onToggleFilter(FISH) }
                        )
                    }
                    item(key = MEAT.name) {
                        FoodFilterChip(
                            text = stringResource(R.string.filter_meat),
                            isSelected = selectedFilters.contains(MEAT),
                            onClick = { onToggleFilter(MEAT) }
                        )
                    }
                }
                content.Display()
            }
        }
    )
}

@Composable
fun EmptyContent() {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Image(
            painter = painterResource(id = R.drawable.empty_recipes),
            contentDescription = stringResource(R.string.no_recipes_illustration_content_description),
            contentScale = ContentScale.FillBounds,
            modifier = Modifier.size(200.dp)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(stringResource(R.string.no_recipes_found))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RecipesContent(
    scrollState: LazyListState,
    recipes: ImmutableList<MainScreenRecipeItem>,
    onRecipeClick: (Int) -> Unit,
    onToggleFavorite: (Int) -> Unit
) {

    LazyColumn(
        state = scrollState,
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .padding(top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        items(recipes.size) { index ->
            val recipeUi = recipes[index]
            RecipeCard(
                modifier = Modifier.animateItem(
                    fadeInSpec = null, fadeOutSpec = null, placementSpec = tween(
                        durationMillis = 300,
                        easing = FastOutSlowInEasing
                    )
                ),
                recipe = recipeUi,
                onFavouriteClick = { onToggleFavorite(recipeUi.id) },
                onClick = { onRecipeClick(recipeUi.id) }
            )
        }

        item { Spacer(modifier = Modifier.height(8.dp)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FoodFilterChip(
    modifier: Modifier = Modifier,
    text: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    FilterChip(
        modifier = modifier,
        selected = isSelected,
        onClick = onClick,
        label = { Text(text) },
        leadingIcon = {
            AnimatedVisibility(visible = isSelected) {
                Icon(
                    modifier = Modifier.size(18.dp),
                    imageVector = Icons.Outlined.Check,
                    contentDescription = stringResource(R.string.selected_icon_filter_chip_content_description),
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalCoilApi::class)
@Preview(fontScale = 1.3f)
@Preview(uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(locale = "ar")
@Composable
fun ContentScreenPreview() {
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
fun EmptyScreenPreview() {
    FlavorshubTheme {
        MainScreen(
            selectedBottomNavItem = HOME,
            onToggleFilter = {},
            selectedFilters = listOf(MEAT).toImmutableList(),
            onBottomNavItemClick = {},
            content = MainScreenRecipeContent.NoRecipes
        )
    }
}