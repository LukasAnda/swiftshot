package com.swiftshot.demo.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.PreviewLightDark
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.R
import com.swiftshot.demo.model.DayPart
import com.swiftshot.demo.model.Habits
import com.swiftshot.demo.model.History
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.FractionBar
import com.swiftshot.demo.ui.components.IconBadge
import com.swiftshot.demo.ui.components.ProgressRing
import com.swiftshot.demo.ui.components.SegmentedColumn
import com.swiftshot.demo.ui.components.SurfaceCard
import com.swiftshot.demo.ui.components.segmentShape
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.formatNumber
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space

/** Today's progress and a short note, on a warm wash. */
@Composable
fun TodaySummary(modifier: Modifier = Modifier) {
    val done = Habits.doneCount
    val total = Habits.all.size
    val colors = MaterialTheme.colorScheme
    val wash = Brush.linearGradient(
        listOf(colors.primary.copy(alpha = 0.16f), HabitsTheme.brand.glow.copy(alpha = 0.14f), HabitsTheme.brand.card),
    )
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp), color = HabitsTheme.brand.card) {
        Row(
            Modifier.background(wash).padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.l),
        ) {
            Box(contentAlignment = Alignment.Center) {
                ProgressRing(done / total.toFloat(), size = 76.dp, strokeWidth = 9.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(formatNumber(done), style = Figures.medium)
                    Text(stringResource(R.string.of_total, total), style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                Text(stringResource(R.string.greeting), style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.summary_body), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
            }
        }
    }
}

/** The filter chips above the list (All is selected). */
@Composable
fun FilterRow(modifier: Modifier = Modifier) {
    Row(
        modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(Space.s),
    ) {
        FilterPill(stringResource(R.string.filter_all), Habits.all.size, selected = true)
        FilterPill(stringResource(R.string.filter_morning), Habits.all.count { it.dayPart == DayPart.Morning }, selected = false)
        FilterPill(stringResource(R.string.filter_evening), Habits.all.count { it.dayPart == DayPart.Evening }, selected = false)
    }
}

@Composable
private fun FilterPill(label: String, count: Int, selected: Boolean) {
    val colors = MaterialTheme.colorScheme
    FilterChip(
        selected = selected,
        onClick = {},
        label = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(label)
                Spacer(Modifier.width(6.dp))
                Text(formatNumber(count), color = if (selected) colors.onPrimary.copy(alpha = 0.8f) else colors.onSurfaceVariant)
            }
        },
        shape = CircleShape,
        colors = FilterChipDefaults.filterChipColors(
            containerColor = HabitsTheme.brand.card,
            selectedContainerColor = colors.primary,
            selectedLabelColor = colors.onPrimary,
        ),
        border = FilterChipDefaults.filterChipBorder(enabled = true, selected = selected, borderColor = colors.outlineVariant),
    )
}

/** The habits as one segmented group. */
@Composable
fun HabitList(modifier: Modifier = Modifier, showWeek: Boolean = false, selectedId: Int? = null, onSelect: ((Int) -> Unit)? = null) {
    SegmentedColumn(modifier) {
        Habits.all.forEachIndexed { i, habit ->
            HabitCard(
                habit,
                shape = segmentShape(i, Habits.all.size),
                showWeek = showWeek,
                selected = habit.id == selectedId,
                onClick = onSelect?.let { { it(habit.id) } },
            )
        }
    }
}

/** The reminders still to come today, at fixed times. */
@Composable
fun UpNextCard(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    SurfaceCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.up_next), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Icon(Icons.Rounded.NotificationsActive, null, tint = colors.onSurfaceVariant, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(Space.xs))
            Text(stringResource(R.string.reminders_on), style = MaterialTheme.typography.labelLarge, color = colors.onSurfaceVariant)
        }
        Column {
            History.upNext.forEachIndexed { i, item ->
                val habit = Habits[item.habit]
                Row(Modifier.padding(vertical = Space.m), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        formatDate(item.epochSeconds, Format.TIME),
                        style = Figures.small,
                        modifier = Modifier.widthIn(min = 76.dp),
                        maxLines = 1,
                    )
                    Box(Modifier.width(3.dp).height(36.dp).background(colors.primary, CircleShape))
                    Spacer(Modifier.width(Space.l))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(habit.title), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(stringResource(item.note), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant, maxLines = 1)
                    }
                    Icon(habit.icon, null, tint = colors.primary, modifier = Modifier.size(20.dp))
                }
                if (i < History.upNext.lastIndex) HorizontalDivider(color = colors.outlineVariant.copy(alpha = 0.6f))
            }
        }
    }
}

/** Progress towards the next round-number streak. */
@Composable
fun MilestoneCard(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val toGo = History.MILESTONE - History.CURRENT_STREAK
    SurfaceCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Flag, null, tint = colors.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.next_milestone), style = MaterialTheme.typography.labelLarge, color = colors.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text(pluralStringResource(R.plurals.days_to_go, toGo, toGo), style = MaterialTheme.typography.labelLarge, color = colors.primary)
        }
        Text(stringResource(R.string.milestone_title), style = MaterialTheme.typography.titleLarge)
        FractionBar(History.CURRENT_STREAK / History.MILESTONE.toFloat(), height = 10.dp)
    }
}

/** One observation from the history, on a soft accent wash. */
@Composable
fun InsightCard(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    SurfaceCard(modifier, color = colors.primary.copy(alpha = 0.10f).compositeOverCanvas()) {
        Row(horizontalArrangement = Arrangement.spacedBy(Space.l)) {
            IconBadge(Icons.Rounded.WbTwilight, filled = true, shape = RoundedCornerShape(14.dp))
            Column(verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                Text(stringResource(R.string.insight_title), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.insight_body), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
            }
        }
    }
}

/** A translucent accent made opaque over the canvas, so cards never show what's behind them. */
@Composable
private fun Color.compositeOverCanvas(): Color = compositeOver(MaterialTheme.colorScheme.background)

@PreviewLightDark
@Composable
fun TodaySummaryPreview() {
    HabitsTheme {
        Surface(color = MaterialTheme.colorScheme.background) {
            TodaySummary(Modifier.padding(Space.l).widthIn(max = 420.dp))
        }
    }
}

/** Space for the floating action button under the last card. */
internal val FabClearance = 88.dp
