package com.swiftshot.demo.ui

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Insights
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import com.swiftshot.demo.R
import com.swiftshot.demo.ui.components.AdaptiveBox
import com.swiftshot.demo.ui.components.WidthClass
import com.swiftshot.demo.ui.history.HistoryScreen
import com.swiftshot.demo.ui.settings.SettingsScreen
import com.swiftshot.demo.ui.stats.StatsScreen
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.today.AddHabitSheet
import com.swiftshot.demo.ui.today.TodayScreen

enum class AppTab(@StringRes val label: Int, val icon: ImageVector, val selectedIcon: ImageVector) {
    Today(R.string.tab_today, Icons.Outlined.CheckCircle, Icons.Rounded.CheckCircle),
    Stats(R.string.tab_stats, Icons.Outlined.Insights, Icons.Rounded.Insights),
    History(R.string.tab_history, Icons.Outlined.CalendarMonth, Icons.Rounded.CalendarMonth),
    Settings(R.string.tab_settings, Icons.Outlined.Settings, Icons.Rounded.Settings),
}

/**
 * The app's four tabs. Compact widths get a short bottom navigation bar; tablets and unfolded
 * foldables a navigation rail that also carries the "New habit" action.
 *
 * The navigation type follows the width the app is given (not the device), so it is the same
 * in the running app and in every preview renderer.
 */
@Composable
fun HabitsApp(modifier: Modifier = Modifier, initialTab: AppTab = AppTab.Today) {
    var tab by rememberSaveable { mutableStateOf(initialTab) }
    var adding by rememberSaveable { mutableStateOf(false) }
    AdaptiveBox(modifier.fillMaxSize()) { width ->
        val wide = width >= WidthClass.Medium
        val type = if (wide) NavigationSuiteType.WideNavigationRailCollapsed else NavigationSuiteType.ShortNavigationBarCompact
        NavigationSuiteScaffold(
            navigationSuiteType = type,
            containerColor = MaterialTheme.colorScheme.background,
            navigationItems = {
                AppTab.entries.forEach { item ->
                    val selected = item == tab
                    NavigationSuiteItem(
                        selected = selected,
                        onClick = { tab = item },
                        icon = { Icon(if (selected) item.selectedIcon else item.icon, contentDescription = null) },
                        label = { Text(stringResource(item.label)) },
                        navigationSuiteType = type,
                    )
                }
            },
            primaryActionContent = {
                if (wide) {
                    FloatingActionButton(
                        onClick = { adding = true },
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ) {
                        Icon(Icons.Rounded.Add, stringResource(R.string.new_habit))
                    }
                }
            },
        ) {
            when (tab) {
                AppTab.Today -> TodayScreen(showFab = !wide, onAddHabit = { adding = true })
                AppTab.Stats -> StatsScreen()
                AppTab.History -> HistoryScreen()
                AppTab.Settings -> SettingsScreen()
            }
        }
    }
    if (adding) AddHabitSheet(onDismiss = { adding = false })
}

@Preview(name = "Root", showSystemUi = true)
@Composable
fun RootPreview() {
    HabitsTheme { HabitsApp() }
}

@Preview(name = "Habit list", showSystemUi = true)
@Composable
fun HabitListPreview() {
    HabitsTheme { HabitsApp(initialTab = AppTab.Today) }
}

@Preview(name = "Stats", showSystemUi = true)
@Composable
fun StatsPreview() {
    HabitsTheme { HabitsApp(initialTab = AppTab.Stats) }
}

@Preview(name = "History", showSystemUi = true)
@Composable
fun HistoryPreview() {
    HabitsTheme { HabitsApp(initialTab = AppTab.History) }
}

@Preview(name = "Settings", showSystemUi = true)
@Composable
fun SettingsPreview() {
    HabitsTheme { HabitsApp(initialTab = AppTab.Settings) }
}
