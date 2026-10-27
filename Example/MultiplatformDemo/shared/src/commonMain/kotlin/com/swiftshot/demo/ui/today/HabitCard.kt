package com.swiftshot.demo.ui.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.model.Habit
import com.swiftshot.demo.model.Habits
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.days
import com.swiftshot.demo.ui.components.IconBadge
import com.swiftshot.demo.ui.components.ProgressRing
import com.swiftshot.demo.ui.components.WeekDots
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.pluralStringResource
import org.jetbrains.compose.resources.stringResource

/**
 * One habit: its icon, today's amount and streak, and a progress ring. Wide layouts also show
 * the last seven days as dots.
 */
@Composable
fun HabitCard(
    habit: Habit,
    modifier: Modifier = Modifier,
    shape: Shape = MaterialTheme.shapes.large,
    showWeek: Boolean = false,
    selected: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val colors = MaterialTheme.colorScheme
    val container = if (selected) colors.secondaryContainer else HabitsTheme.brand.card
    val content: @Composable () -> Unit = {
        Row(
            Modifier.padding(horizontal = Space.l, vertical = if (showWeek) Space.l else 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconBadge(habit.icon, filled = habit.isDone)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(habit.title), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                HabitSubtitle(habit)
            }
            Spacer(Modifier.width(Space.s))
            if (showWeek) {
                WeekDots(habit.week, Modifier.padding(end = Space.l))
            }
            ProgressRing(habit.progress, size = 30.dp, strokeWidth = 3.5.dp)
        }
    }
    if (onClick != null) {
        Surface(onClick = onClick, modifier = modifier, shape = shape, color = container) { content() }
    } else {
        Surface(modifier = modifier, shape = shape, color = container) { content() }
    }
}

/** "3 of 8 glasses · (flame) 12 days", or just the amount while there's no streak. */
@Composable
fun HabitSubtitle(habit: Habit, modifier: Modifier = Modifier) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
        val style = MaterialTheme.typography.bodyMedium
        Text(stringResource(habit.detail), style = style, color = muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false))
        if (habit.streak > 0) {
            Text("·", style = style, color = muted)
            Icon(AppIcons.Rounded.LocalFireDepartment, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
            Text(pluralStringResource(Res.plurals.days, habit.streak, habit.streak), style = style, color = muted, maxLines = 1)
        }
    }
}

@Preview(name = "Habit card", showBackground = true, backgroundColor = 0xFFF6F3EF, widthDp = 400)
@Composable
fun HabitCardPreview() {
    HabitsTheme {
        HabitCard(Habits[0], Modifier.padding(Space.l), showWeek = true)
    }
}
