package com.swiftshot.demo.ui.history

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.model.History
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.all_habits_completed
import com.swiftshot.demo.resources.in_progress
import com.swiftshot.demo.resources.n_of_5_habits
import com.swiftshot.demo.resources.perfect_day
import com.swiftshot.demo.resources.tab_history
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.HabitsTopBar
import com.swiftshot.demo.ui.components.segmentShape
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.stringResource

/** A month of check-ins, one segmented group per week: taller than any screen. */
@Composable
fun HistoryScreen(modifier: Modifier = Modifier) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            HabitsTopBar(
                title = stringResource(Res.string.tab_history),
                subtitle = formatDate(History.TODAY, Format.MONTH_YEAR),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(start = Space.l, end = Space.l, bottom = Space.xxl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            History.weeks.forEachIndexed { week, days ->
                if (week > 0) item(key = "gap$week") { Spacer(Modifier.height(Space.l)) }
                itemsIndexed(days, key = { _, day -> day }) { i, day ->
                    HistoryRow(
                        daysAgo = day,
                        shape = segmentShape(i, days.size),
                        modifier = Modifier.widthIn(max = Space.readableWidth).padding(bottom = 2.dp),
                    )
                }
            }
        }
    }
}

@Composable
fun HistoryRow(daysAgo: Int, shape: Shape, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val date = History.dayAgo(daysAgo)
    val done = History.completed(daysAgo)
    val perfect = done == 5
    Surface(modifier.fillMaxWidth(), shape = shape, color = HabitsTheme.brand.card) {
        Row(
            Modifier.heightIn(min = 72.dp).padding(horizontal = Space.l, vertical = Space.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.width(48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(formatDate(date, Format.DAY), style = Figures.medium, color = if (daysAgo == 0) colors.primary else colors.onSurface)
                Text(
                    formatDate(date, Format.WEEKDAY_SHORT).uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1,
                )
            }
            Spacer(Modifier.width(Space.l))
            Column(Modifier.weight(1f)) {
                Text(
                    when {
                        perfect -> stringResource(Res.string.perfect_day)
                        daysAgo == 0 -> stringResource(Res.string.in_progress)
                        else -> stringResource(Res.string.n_of_5_habits, done)
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (perfect) FontWeight.SemiBold else FontWeight.Normal,
                )
                if (perfect) {
                    Text(stringResource(Res.string.all_habits_completed), style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
                }
            }
            Spacer(Modifier.width(Space.s))
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                repeat(5) { i ->
                    Box(Modifier.size(9.dp).background(if (i < done) colors.primary else HabitsTheme.brand.track, CircleShape))
                }
            }
        }
    }
}
