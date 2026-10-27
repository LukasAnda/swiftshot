package com.swiftshot.demo.ui.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.model.Habit
import com.swiftshot.demo.model.Habits
import com.swiftshot.demo.model.History
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.add
import com.swiftshot.demo.resources.completion_rate
import com.swiftshot.demo.resources.day_streak
import com.swiftshot.demo.resources.last_30_days
import com.swiftshot.demo.resources.last_7_days
import com.swiftshot.demo.resources.new_habit
import com.swiftshot.demo.resources.remind_me
import com.swiftshot.demo.resources.tab_today
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.AdaptiveBox
import com.swiftshot.demo.ui.components.CardHeader
import com.swiftshot.demo.ui.components.FractionBar
import com.swiftshot.demo.ui.components.HabitsTopBar
import com.swiftshot.demo.ui.components.ProgressRing
import com.swiftshot.demo.ui.components.Readable
import com.swiftshot.demo.ui.components.SurfaceCard
import com.swiftshot.demo.ui.components.WidthClass
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.formatPercent
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.pluralStringResource
import org.jetbrains.compose.resources.stringResource

/**
 * Today: the day's summary, the habits and what's next. Expanded widths become list-detail:
 * the list on the leading side, the selected habit beside it.
 *
 * @param showFab false where the navigation rail already carries the "New habit" action.
 */
@Composable
fun TodayScreen(modifier: Modifier = Modifier, showFab: Boolean = true, onAddHabit: () -> Unit = {}) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    var selectedId by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            HabitsTopBar(
                title = stringResource(Res.string.tab_today),
                subtitle = formatDate(History.TODAY, Format.WEEKDAY_DAY_MONTH),
                scrollBehavior = scrollBehavior,
            )
        },
        floatingActionButton = {
            if (showFab) {
                ExtendedFloatingActionButton(
                    onClick = onAddHabit,
                    icon = { Icon(AppIcons.Rounded.Add, null) },
                    text = { Text(stringResource(Res.string.new_habit)) },
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                )
            }
        },
    ) { padding ->
        AdaptiveBox(Modifier.padding(padding).fillMaxSize()) { width ->
            if (width >= WidthClass.Expanded) {
                Row(
                    Modifier.fillMaxSize().padding(horizontal = Space.xl),
                    horizontalArrangement = Arrangement.spacedBy(Space.xl),
                ) {
                    Column(
                        Modifier.weight(1f).widthIn(max = 560.dp).verticalScroll(rememberScrollState()).padding(bottom = Space.xxl),
                        verticalArrangement = Arrangement.spacedBy(Space.l),
                    ) {
                        TodaySummary()
                        FilterRow()
                        HabitList(showWeek = true, selectedId = selectedId, onSelect = { selectedId = it })
                        UpNextCard()
                    }
                    Column(
                        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = Space.xxl),
                        verticalArrangement = Arrangement.spacedBy(Space.l),
                    ) {
                        HabitDetailPane(Habits[selectedId])
                        MilestoneCard()
                        InsightCard()
                    }
                }
            } else {
                Readable {
                    Column(
                        Modifier
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = Space.l)
                            .padding(bottom = if (showFab) FabClearance else Space.xxl),
                        verticalArrangement = Arrangement.spacedBy(Space.l),
                    ) {
                        TodaySummary()
                        FilterRow()
                        HabitList(showWeek = width >= WidthClass.Medium)
                        UpNextCard()
                        MilestoneCard()
                        InsightCard()
                    }
                }
            }
        }
    }
}

/** The detail side of list-detail: one habit's day, week and month. */
@Composable
fun HabitDetailPane(habit: Habit, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    SurfaceCard(modifier, shape = MaterialTheme.shapes.extraLarge, padding = Space.xl) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.m)) {
            Box(contentAlignment = Alignment.Center) {
                ProgressRing(habit.progress, size = 168.dp, strokeWidth = 16.dp, checkWhenDone = false)
                Icon(habit.icon, null, tint = colors.primary, modifier = Modifier.size(44.dp))
            }
            Text(stringResource(habit.title), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Text(stringResource(habit.detail), style = MaterialTheme.typography.bodyLarge, color = colors.onSurfaceVariant)
            if (habit.streak > 0) {
                Surface(shape = CircleShape, color = colors.primary.copy(alpha = 0.12f), contentColor = colors.primary) {
                    Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(AppIcons.Rounded.LocalFireDepartment, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(Space.xs))
                        Text(pluralStringResource(Res.plurals.day_streak, habit.streak, habit.streak), style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
        Spacer(Modifier.height(Space.xs))
        CardHeader(stringResource(Res.string.last_7_days))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            habit.week.forEachIndexed { i, done ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    val isToday = i == habit.week.lastIndex
                    Surface(
                        shape = CircleShape,
                        color = if (done) colors.primary else HabitsTheme.brand.track,
                        modifier = Modifier.size(32.dp),
                    ) {
                        if (done) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(AppIcons.Rounded.Check, null, tint = colors.onPrimary, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                    Text(
                        formatDate(History.dayAgo(6 - i), Format.WEEKDAY_NARROW),
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isToday) colors.primary else colors.onSurfaceVariant,
                    )
                }
            }
        }
        CardHeader(stringResource(Res.string.completion_rate), trailing = stringResource(Res.string.last_30_days))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.l)) {
            Text(formatPercent(habit.rate.toDouble()), style = Figures.large)
            FractionBar(habit.rate, Modifier.weight(1f), height = 10.dp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Space.m)) {
            FilledTonalButton(onClick = {}, modifier = Modifier.weight(1f), contentPadding = PaddingValues(vertical = 14.dp)) {
                Icon(AppIcons.Rounded.NotificationsActive, null, Modifier.size(18.dp))
                Spacer(Modifier.width(Space.s))
                Text(stringResource(Res.string.remind_me), maxLines = 1)
            }
            Button(onClick = {}, modifier = Modifier.weight(1f), contentPadding = PaddingValues(vertical = 14.dp)) {
                Icon(AppIcons.Rounded.Add, null, Modifier.size(18.dp))
                Spacer(Modifier.width(Space.s))
                Text(stringResource(Res.string.add), maxLines = 1)
            }
        }
    }
}
