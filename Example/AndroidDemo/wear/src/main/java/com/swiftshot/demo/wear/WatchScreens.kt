package com.swiftshot.demo.wear

import android.icu.text.NumberFormat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.CircularProgressIndicator
import androidx.wear.compose.material3.EdgeButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ProgressIndicatorDefaults
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeText
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import androidx.wear.compose.ui.tooling.preview.WearPreviewDevices
import androidx.wear.tooling.preview.devices.WearDevices
import kotlin.math.roundToInt

/** Today on the wrist: overall progress, then each habit with its own ring; "New habit" at the edge. */
@Composable
fun WatchHabitList() {
    val listState = rememberTransformingLazyColumnState()
    val spec = rememberTransformationSpec()
    val done = watchHabits.count { it.isDone }
    AppScaffold(timeText = { TimeText(timeSource = FixedTimeSource) }) {
        ScreenScaffold(
            scrollState = listState,
            edgeButton = {
                EdgeButton(onClick = {}) {
                    Icon(Icons.Rounded.Add, contentDescription = stringResource(R.string.new_habit))
                }
            },
        ) { contentPadding ->
            TransformingLazyColumn(state = listState, contentPadding = contentPadding) {
                item {
                    ListHeader(
                        Modifier.fillMaxWidth().transformedHeight(this, spec),
                        transformation = SurfaceTransformation(spec),
                    ) { Text(stringResource(R.string.today)) }
                }
                item {
                    Row(
                        Modifier.fillMaxWidth().transformedHeight(this, spec).padding(bottom = 6.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(
                            progress = { done / watchHabits.size.toFloat() },
                            modifier = Modifier.size(22.dp),
                            strokeWidth = 4.dp,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            stringResource(R.string.n_of_m_done, done, watchHabits.size),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                items(watchHabits) { habit ->
                    Button(
                        onClick = {},
                        modifier = Modifier.fillMaxWidth().transformedHeight(this, spec),
                        transformation = SurfaceTransformation(spec),
                        colors = ButtonDefaults.filledTonalButtonColors(),
                        icon = { HabitRing(habit) },
                        label = { Text(stringResource(habit.title), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text(stringResource(habit.detail), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    )
                }
            }
        }
    }
}

/** A habit's icon inside its progress ring; a filled check once done. */
@Composable
private fun HabitRing(habit: WatchHabit) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.size(ButtonDefaults.LargeIconSize + 6.dp), contentAlignment = Alignment.Center) {
        if (habit.isDone) {
            CircularProgressIndicator(progress = { 1f }, modifier = Modifier.fillMaxSize(), strokeWidth = 3.dp)
            Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.primary, modifier = Modifier.size(16.dp))
        } else {
            CircularProgressIndicator(
                progress = { habit.progress },
                modifier = Modifier.fillMaxSize(),
                strokeWidth = 3.dp,
                colors = ProgressIndicatorDefaults.colors(trackColor = colors.primary.copy(alpha = 0.22f)),
            )
            Icon(habit.icon, contentDescription = null, tint = colors.primary, modifier = Modifier.size(16.dp))
        }
    }
}

/** One habit: a large ring with today's amount, the streak, and "Next glass" at the edge. */
@Composable
fun WatchHabitDetail(habit: WatchHabit = watchHabits[0]) {
    val listState = rememberTransformingLazyColumnState()
    val colors = MaterialTheme.colorScheme
    // Today's glasses (3 of 8), in the locale's digits.
    val glasses = NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format((habit.progress * 8).roundToInt())
    AppScaffold(timeText = { TimeText(timeSource = FixedTimeSource) }) {
        ScreenScaffold(
            scrollState = listState,
            edgeButton = {
                EdgeButton(onClick = {}) {
                    Text(stringResource(R.string.next_glass), maxLines = 1)
                }
            },
        ) { contentPadding ->
            TransformingLazyColumn(state = listState, contentPadding = contentPadding) {
                item {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(104.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                progress = { habit.progress },
                                modifier = Modifier.fillMaxSize(),
                                strokeWidth = 10.dp,
                                colors = ProgressIndicatorDefaults.colors(trackColor = colors.primary.copy(alpha = 0.22f)),
                            )
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(glasses, style = MaterialTheme.typography.numeralMedium.copy(fontWeight = FontWeight.Bold, fontSize = 34.sp))
                                Text(stringResource(R.string.of_8), style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
                            }
                        }
                    }
                }
                item {
                    Text(
                        stringResource(habit.title),
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                    )
                }
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.LocalFireDepartment, null, tint = colors.primary, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(
                            pluralStringResource(R.plurals.day_streak, habit.streak, habit.streak),
                            style = MaterialTheme.typography.labelMedium,
                            color = colors.primary,
                        )
                    }
                }
            }
        }
    }
}

@Preview(name = "Watch list", device = WearDevices.LARGE_ROUND, showSystemUi = true)
@Composable
fun WatchListPreview() {
    WatchTheme { WatchHabitList() }
}

@Preview(name = "Watch habit", device = WearDevices.LARGE_ROUND, showSystemUi = true)
@Composable
fun WatchHabitPreview() {
    WatchTheme { WatchHabitDetail() }
}

/** The list on every Wear device class (large and small round, square). */
@WearPreviewDevices
@Composable
fun WatchListDevicesPreview() {
    WatchTheme { WatchHabitList() }
}
