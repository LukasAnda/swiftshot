package com.swiftshot.demo.wear

import android.icu.text.DateFormat
import android.icu.util.TimeZone
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsRun
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.TimeSource
import java.util.Date

/** The phone app's persimmon accent in its dark variant (the watch is always dark), and warm greys. */
private val WatchColors = ColorScheme(
    primary = Color(0xFFFF6F4A),
    primaryDim = Color(0xFFE4572E),
    primaryContainer = Color(0xFF7A2A12),
    onPrimary = Color(0xFF3D0E00),
    onPrimaryContainer = Color(0xFFFFDBD1),
    secondary = Color(0xFFFFB86C),
    secondaryDim = Color(0xFFE59F55),
    secondaryContainer = Color(0xFF4A342C),
    onSecondary = Color(0xFF4A2800),
    onSecondaryContainer = Color(0xFFFFDBD1),
    tertiary = Color(0xFFE7BDB1),
    tertiaryDim = Color(0xFFCBA398),
    tertiaryContainer = Color(0xFF5D4037),
    onTertiary = Color(0xFF442A21),
    onTertiaryContainer = Color(0xFFFFDBD1),
    surfaceContainerLow = Color(0xFF151416),
    surfaceContainer = Color(0xFF1F1D1F),
    surfaceContainerHigh = Color(0xFF2A2729),
    onSurface = Color(0xFFF2ECE8),
    onSurfaceVariant = Color(0xFFC3B9B3),
    outline = Color(0xFF8D837E),
    outlineVariant = Color(0xFF3B3633),
    background = Color(0xFF000000),
    onBackground = Color(0xFFF2ECE8),
)

@Composable
fun WatchTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = WatchColors, content = content)
}

@Immutable
data class WatchHabit(
    @StringRes val title: Int,
    @StringRes val detail: Int,
    val icon: ImageVector,
    val progress: Float,
    val streak: Int,
) {
    val isDone: Boolean get() = progress >= 1f
}

/** The phone app's habits (same order and numbers), so both apps tell one story. */
val watchHabits = listOf(
    WatchHabit(R.string.habit_water, R.string.detail_water, Icons.Rounded.WaterDrop, 0.375f, 12),
    WatchHabit(R.string.habit_run, R.string.detail_run, Icons.AutoMirrored.Rounded.DirectionsRun, 1f, 31),
    WatchHabit(R.string.habit_read, R.string.detail_read, Icons.AutoMirrored.Rounded.MenuBook, 0.4f, 5),
    WatchHabit(R.string.habit_meditate, R.string.detail_meditate, Icons.Rounded.SelfImprovement, 1f, 9),
    WatchHabit(R.string.habit_journal, R.string.detail_journal, Icons.Rounded.EditNote, 0f, 0),
)

/**
 * A clock that always reads 10:09 (on the fixed "today", in UTC), so watch screenshots never
 * depend on when they were taken.
 */
object FixedTimeSource : TimeSource {
    private const val TIME_EPOCH_SECONDS = 1_789_948_800L + 10 * 3_600L + 9 * 60L

    @Composable
    override fun currentTime(): String {
        val locale = LocalConfiguration.current.locales[0]
        return DateFormat.getInstanceForSkeleton("Hmm", locale).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(TIME_EPOCH_SECONDS * 1_000))
    }
}
