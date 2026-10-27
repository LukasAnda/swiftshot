package com.swiftshot.demo.ui.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsRun
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.R
import com.swiftshot.demo.model.Habits
import com.swiftshot.demo.model.History
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.AdaptiveBox
import com.swiftshot.demo.ui.components.CardHeader
import com.swiftshot.demo.ui.components.FractionBar
import com.swiftshot.demo.ui.components.HabitsTopBar
import com.swiftshot.demo.ui.components.IconBadge
import com.swiftshot.demo.ui.components.SurfaceCard
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.formatNumber
import com.swiftshot.demo.ui.formatPercent
import com.swiftshot.demo.ui.today.InsightCard
import com.swiftshot.demo.ui.today.MilestoneCard
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space

/**
 * Statistics: the completion rate, the last week, a heat map and each habit's month. Wide
 * screens arrange the cards in two columns.
 *
 * @param extended adds the highlights and the Today cards, for a screen well taller than any device.
 */
@Composable
fun StatsScreen(modifier: Modifier = Modifier, extended: Boolean = false) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            HabitsTopBar(
                title = stringResource(R.string.statistics),
                subtitle = formatDate(History.TODAY, Format.WEEKDAY_DAY_MONTH_YEAR),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        AdaptiveBox(Modifier.padding(padding).fillMaxSize()) { width ->
            val wide = width >= 700.dp
            Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
                Column(
                    Modifier
                        .widthIn(max = 1100.dp)
                        .padding(horizontal = if (wide) Space.xl else Space.l)
                        .padding(bottom = Space.xxl),
                    verticalArrangement = Arrangement.spacedBy(Space.l),
                ) {
                    RangePicker(Modifier.then(if (wide) Modifier.widthIn(max = 360.dp) else Modifier.fillMaxWidth()))
                    if (wide) {
                        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Space.l)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.l)) {
                                CompletionHero()
                                MetricGrid()
                            }
                            WeekChart(Modifier.weight(1f).fillMaxHeight())
                        }
                        ConsistencyGrid(weeks = 26)
                        Row(horizontalArrangement = Arrangement.spacedBy(Space.l)) {
                            HabitBreakdown(Modifier.weight(1f))
                            Highlights(Modifier.weight(1f))
                        }
                    } else {
                        CompletionHero()
                        WeekChart()
                        ConsistencyGrid()
                        MetricGrid()
                        HabitBreakdown()
                        if (extended) {
                            Highlights()
                            MilestoneCard()
                            InsightCard()
                        }
                    }
                }
            }
        }
    }
}

/** Week / Month / Year as a connected button group. */
@Composable
private fun RangePicker(modifier: Modifier = Modifier) {
    var range by rememberSaveable { mutableIntStateOf(0) }
    val labels = listOf(R.string.range_week, R.string.range_month, R.string.range_year)
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
        labels.forEachIndexed { i, label ->
            ToggleButton(
                checked = range == i,
                onCheckedChange = { range = i },
                modifier = Modifier.weight(1f).semantics { role = Role.RadioButton },
                shapes = when (i) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    labels.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
            ) { Text(stringResource(label), maxLines = 1) }
        }
    }
}

/** The headline number. */
@Composable
fun CompletionHero(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    SurfaceCard(modifier, shape = RoundedCornerShape(28.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.completion_rate), style = MaterialTheme.typography.titleSmall, color = colors.onSurfaceVariant)
                Text(formatPercent(History.COMPLETION_RATE), style = Figures.hero, maxLines = 1)
            }
            Surface(shape = CircleShape, color = colors.primary.copy(alpha = 0.12f), contentColor = colors.primary) {
                Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.AutoMirrored.Rounded.TrendingUp, null, Modifier.size(16.dp))
                    Spacer(Modifier.width(Space.xs))
                    Text(
                        stringResource(R.string.vs_last_week, "+" + formatPercent(History.COMPLETION_DELTA)),
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** Completion of each of the last seven days; today in full accent. */
@Composable
fun WeekChart(modifier: Modifier = Modifier, barHeight: Dp = 150.dp) {
    val colors = MaterialTheme.colorScheme
    SurfaceCard(modifier) {
        CardHeader(
            stringResource(R.string.last_7_days),
            trailing = pluralStringResource(R.plurals.n_check_ins, History.weekCheckIns, History.weekCheckIns),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(Space.m), verticalAlignment = Alignment.Bottom) {
            History.week.forEachIndexed { i, value ->
                val isToday = i == History.week.lastIndex
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.s)) {
                    Box(
                        Modifier.fillMaxWidth().height(barHeight).background(HabitsTheme.brand.track, RoundedCornerShape(12.dp)),
                        contentAlignment = Alignment.BottomCenter,
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(barHeight * value)
                                .background(if (isToday) colors.primary else colors.primary.copy(alpha = 0.45f), RoundedCornerShape(12.dp))
                        )
                    }
                    Text(
                        formatDate(History.dayAgo(6 - i), Format.WEEKDAY_NARROW),
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isToday) colors.primary else colors.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Weeks of check-ins as a heat map (fixed data). Columns are weeks, oldest first. */
@Composable
fun ConsistencyGrid(modifier: Modifier = Modifier, weeks: Int = 12) {
    val colors = MaterialTheme.colorScheme
    val track = HabitsTheme.brand.track
    fun color(level: Int) = when {
        level < 0 -> null
        level == 0 -> track
        else -> colors.primary.copy(alpha = 0.2f + 0.2f * level)
    }
    SurfaceCard(modifier) {
        CardHeader(stringResource(R.string.consistency), trailing = pluralStringResource(R.plurals.last_n_weeks, weeks, weeks))
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            repeat(weeks) { week ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    repeat(7) { day ->
                        val c = color(History.level(week, day, weeks))
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .aspectRatio(1f)
                                .then(if (c != null) Modifier.background(c, RoundedCornerShape(4.dp)) else Modifier)
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.less), style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
            for (level in 0..4) {
                Box(Modifier.size(11.dp).background(color(level)!!, RoundedCornerShape(3.dp)))
            }
            Text(stringResource(R.string.more), style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
        }
    }
}

@Composable
fun MetricGrid(modifier: Modifier = Modifier) {
    Row(modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Space.m)) {
        MetricTile(
            Icons.Rounded.LocalFireDepartment,
            pluralStringResource(R.plurals.days, History.CURRENT_STREAK, History.CURRENT_STREAK),
            stringResource(R.string.current_streak),
            Modifier.weight(1f).fillMaxHeight(),
        )
        MetricTile(
            Icons.Rounded.EmojiEvents,
            pluralStringResource(R.plurals.days, History.BEST_STREAK, History.BEST_STREAK),
            stringResource(R.string.best_streak),
            Modifier.weight(1f).fillMaxHeight(),
        )
        MetricTile(
            Icons.Rounded.Verified,
            formatNumber(History.TOTAL_CHECK_INS),
            stringResource(R.string.check_ins),
            Modifier.weight(1f).fillMaxHeight(),
        )
    }
}

@Composable
private fun MetricTile(icon: ImageVector, value: String, title: String, modifier: Modifier = Modifier) {
    SurfaceCard(modifier, shape = RoundedCornerShape(20.dp), padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s)) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
            Text(value, style = Figures.medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(title, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, minLines = 2, maxLines = 2)
        }
    }
}

/** Each habit's completion over the last 30 days. */
@Composable
fun HabitBreakdown(modifier: Modifier = Modifier) {
    SurfaceCard(modifier) {
        CardHeader(stringResource(R.string.by_habit), trailing = stringResource(R.string.last_30_days))
        Habits.all.forEach { habit ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(habit.icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(Space.s))
                    Text(stringResource(habit.title), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                    Text(formatPercent(habit.rate.toDouble()), style = Figures.small)
                }
                FractionBar(habit.rate, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f + 0.65f * habit.rate))
            }
        }
    }
}

/** A few notable facts, as a short list. */
@Composable
fun Highlights(modifier: Modifier = Modifier) {
    SurfaceCard(modifier) {
        Text(stringResource(R.string.highlights), style = MaterialTheme.typography.titleMedium)
        HighlightRow(Icons.Rounded.CalendarMonth, R.string.best_day, R.string.best_day_value)
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        HighlightRow(Icons.Rounded.WbTwilight, R.string.best_time, R.string.best_time_value)
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        HighlightRow(Icons.AutoMirrored.Rounded.DirectionsRun, R.string.most_consistent, R.string.habit_run)
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        HighlightRow(Icons.Rounded.EditNote, R.string.needs_attention, R.string.needs_attention_value)
    }
}

@Composable
private fun HighlightRow(icon: ImageVector, title: Int, value: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.m)) {
        IconBadge(icon, size = 36.dp)
        Text(stringResource(title), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(stringResource(value), style = MaterialTheme.typography.titleSmall)
    }
}

@Preview(name = "Stats long", showSystemUi = true)
@Composable
fun StatsLongPreview() {
    HabitsTheme {
        StatsScreen(extended = true)
    }
}
