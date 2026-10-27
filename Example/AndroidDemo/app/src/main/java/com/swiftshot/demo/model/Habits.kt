package com.swiftshot.demo.model

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsRun
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.vector.ImageVector
import com.swiftshot.demo.R

/** When a habit is usually done; drives the filter chips on Today. */
enum class DayPart { Morning, Evening, Anytime }

@Immutable
data class Habit(
    val id: Int,
    @StringRes val title: Int,
    /** Today's amount, e.g. "3 of 8 glasses". */
    @StringRes val detail: Int,
    val icon: ImageVector,
    val progress: Float,
    val streak: Int,
    /** The last seven days, oldest first; the last one is today. */
    val week: List<Boolean>,
    /** Share of the last 30 days completed. */
    val rate: Float,
    val dayPart: DayPart,
) {
    val isDone: Boolean get() = progress >= 1f
}

/** The same five habits as the iOS demo, so both platforms' screenshots tell one story. */
object Habits {
    private const val T = true
    private const val F = false

    val all: List<Habit> = listOf(
        Habit(0, R.string.habit_water, R.string.detail_water, Icons.Rounded.WaterDrop, 0.375f, 12,
            listOf(T, T, T, T, T, T, F), 0.93f, DayPart.Morning),
        Habit(1, R.string.habit_run, R.string.detail_run, Icons.AutoMirrored.Rounded.DirectionsRun, 1f, 31,
            listOf(T, T, T, T, T, T, T), 1f, DayPart.Morning),
        Habit(2, R.string.habit_read, R.string.detail_read, Icons.AutoMirrored.Rounded.MenuBook, 0.4f, 5,
            listOf(F, T, T, T, T, T, F), 0.8f, DayPart.Evening),
        Habit(3, R.string.habit_meditate, R.string.detail_meditate, Icons.Rounded.SelfImprovement, 1f, 9,
            listOf(T, T, T, T, T, T, T), 0.9f, DayPart.Anytime),
        Habit(4, R.string.habit_journal, R.string.detail_journal, Icons.Rounded.EditNote, 0f, 0,
            listOf(F, F, T, F, F, F, F), 0.47f, DayPart.Evening),
    )

    val doneCount: Int get() = all.count { it.isDone }

    operator fun get(id: Int): Habit = all[id]
}

/** A reminder still to come today, at a fixed time in UTC on [History.TODAY]. */
@Immutable
data class Reminder(val habit: Int, val hour: Int, val minute: Int, @StringRes val note: Int) {
    val epochSeconds: Long get() = History.MIDNIGHT + hour * 3_600L + minute * 60L
}

/**
 * A fixed, believable completion history: no clock, no randomness, the same every run, and
 * consistent with the habits' own weeks and streaks.
 */
object History {
    /** The screenshots' fixed "today": Monday 21 September 2026, 12:53 UTC. */
    const val TODAY: Long = 1_790_000_000L

    /** Midnight UTC at the start of [TODAY]. */
    const val MIDNIGHT: Long = 1_789_948_800L

    const val DAY: Long = 86_400L

    /** The daily reminder in Settings: 08:00 UTC. */
    const val REMINDER_TIME: Long = MIDNIGHT + 8 * 3_600L

    /** The new habit's reminder in the add sheet: 21:30 UTC. */
    const val NEW_HABIT_TIME: Long = 1_790_026_200L

    private val pattern = intArrayOf(2, 4, 4, 4, 5, 4, 3, 5, 4, 3, 5, 5, 4, 3)

    /** Habits completed (0..5) on the day [daysAgo] before [TODAY]. */
    fun completed(daysAgo: Int): Int = pattern[daysAgo % pattern.size]

    /** Completion of each of the last seven days, oldest first (today last). */
    val week: List<Float> = (0 until 7).map { completed(6 - it) / 5f }

    val weekCheckIns: Int = (0 until 7).sumOf { completed(it) }

    fun dayAgo(daysAgo: Int): Long = TODAY - DAY * daysAgo

    val upNext: List<Reminder> = listOf(
        Reminder(0, 11, 0, R.string.note_next_glass),
        Reminder(2, 20, 30, R.string.note_pages_to_go),
        Reminder(4, 21, 30, R.string.note_three_lines),
    )

    /** The last 30 days in Monday-to-Sunday weeks, newest first ([TODAY] is a Monday). */
    val weeks: List<List<Int>> = listOf(listOf(0)) + (1 until 30 step 7).map { start ->
        (start until minOf(start + 7, 30)).toList()
    }

    /** Heat map level (0..4) of a day in the consistency grid, or -1 for the future. */
    fun level(week: Int, day: Int, weeks: Int): Int {
        if (week == weeks - 1 && day > 0) return -1
        val base = intArrayOf(3, 4, 2, 4, 4, 1, 3, 4, 4, 2, 0, 4, 3, 4, 4, 3, 2, 4, 1)[(week * 7 + day) % 19]
        return minOf(4, base + if (week > 7) 1 else 0)
    }

    const val COMPLETION_RATE = 0.74
    const val COMPLETION_DELTA = 0.06
    const val CURRENT_STREAK = 31
    const val BEST_STREAK = 48
    const val TOTAL_CHECK_INS = 1_234
    const val MILESTONE = 50
}
