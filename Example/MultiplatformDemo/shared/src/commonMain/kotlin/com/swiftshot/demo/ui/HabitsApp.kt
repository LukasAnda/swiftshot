package com.swiftshot.demo.ui

import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.new_habit
import com.swiftshot.demo.resources.tab_history
import com.swiftshot.demo.resources.tab_settings
import com.swiftshot.demo.resources.tab_stats
import com.swiftshot.demo.resources.tab_today
import com.swiftshot.demo.ui.components.AdaptiveBox
import com.swiftshot.demo.ui.components.WidthClass
import com.swiftshot.demo.ui.history.HistoryScreen
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.settings.SettingsScreen
import com.swiftshot.demo.ui.stats.StatsScreen
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.today.AddHabitSheet
import com.swiftshot.demo.ui.today.TodayScreen
import org.jetbrains.compose.resources.StringResource
import org.jetbrains.compose.resources.stringResource

enum class AppTab(val label: StringResource, val icon: ImageVector, val selectedIcon: ImageVector) {
    Today(Res.string.tab_today, AppIcons.Outlined.CheckCircle, AppIcons.Rounded.CheckCircle),
    Stats(Res.string.tab_stats, AppIcons.Outlined.Insights, AppIcons.Rounded.Insights),
    History(Res.string.tab_history, AppIcons.Outlined.CalendarMonth, AppIcons.Rounded.CalendarMonth),
    Settings(Res.string.tab_settings, AppIcons.Outlined.Settings, AppIcons.Rounded.Settings),
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
                        Icon(AppIcons.Rounded.Add, stringResource(Res.string.new_habit))
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
