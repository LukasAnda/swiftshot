package com.swiftshot.demo.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.model.History
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.add
import com.swiftshot.demo.resources.cancel
import com.swiftshot.demo.resources.delete
import com.swiftshot.demo.resources.delete_body
import com.swiftshot.demo.resources.delete_title
import com.swiftshot.demo.resources.every_day
import com.swiftshot.demo.resources.habit_read
import com.swiftshot.demo.resources.icon
import com.swiftshot.demo.resources.name
import com.swiftshot.demo.resources.new_habit
import com.swiftshot.demo.resources.remind_me
import com.swiftshot.demo.resources.repeat
import com.swiftshot.demo.resources.time
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.HabitsApp
import com.swiftshot.demo.ui.components.SegmentedColumn
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.stringResource

private val habitIcons = listOf(
    AppIcons.AutoMirroredRounded.MenuBook,
    AppIcons.Rounded.WaterDrop,
    AppIcons.AutoMirroredRounded.DirectionsRun,
    AppIcons.Rounded.SelfImprovement,
    AppIcons.Rounded.EditNote,
    AppIcons.Rounded.Bedtime,
)

/** A sheet state that is already expanded, so the sheet is open from the first frame. */
@Composable
fun rememberOpenSheetState(): SheetState =
    rememberBottomSheetState(SheetValue.Expanded, setOf(SheetValue.Hidden, SheetValue.Expanded))

/** The "New habit" sheet: name, icon, schedule and reminder. */
@Composable
fun AddHabitSheet(onDismiss: () -> Unit, sheetState: SheetState = rememberOpenSheetState()) {
    val colors = MaterialTheme.colorScheme
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = colors.surfaceContainerLow) {
        Column(Modifier.padding(horizontal = Space.xl).padding(bottom = Space.xl), verticalArrangement = Arrangement.spacedBy(Space.l)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onDismiss) { Icon(AppIcons.Rounded.Close, stringResource(Res.string.cancel)) }
                Text(
                    stringResource(Res.string.new_habit),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Button(onClick = onDismiss) { Text(stringResource(Res.string.add)) }
            }
            OutlinedTextField(
                value = stringResource(Res.string.habit_read),
                onValueChange = {},
                label = { Text(stringResource(Res.string.name)) },
                singleLine = true,
                shape = MaterialTheme.shapes.medium,
                colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = HabitsTheme.brand.card),
                textStyle = MaterialTheme.typography.titleMedium,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(Res.string.icon), style = MaterialTheme.typography.labelLarge, color = colors.onSurfaceVariant)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                habitIcons.forEachIndexed { i, icon ->
                    val selected = i == 0
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(if (selected) colors.primary else colors.primary.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(icon, null, tint = if (selected) colors.onPrimary else colors.primary, modifier = Modifier.size(22.dp))
                    }
                }
            }
            SegmentedColumn {
                val itemColors = ListItemDefaults.segmentedColors(containerColor = HabitsTheme.brand.card)
                ListItem(
                    onClick = {},
                    leadingContent = { Icon(AppIcons.Rounded.Repeat, null) },
                    trailingContent = { Text(stringResource(Res.string.every_day), style = MaterialTheme.typography.bodyLarge) },
                    shapes = ListItemDefaults.segmentedShapes(0, 3),
                    colors = itemColors,
                ) { Text(stringResource(Res.string.repeat)) }
                ListItem(
                    onClick = {},
                    leadingContent = { Icon(AppIcons.Rounded.NotificationsActive, null) },
                    trailingContent = { Switch(checked = true, onCheckedChange = {}) },
                    shapes = ListItemDefaults.segmentedShapes(1, 3),
                    colors = itemColors,
                ) { Text(stringResource(Res.string.remind_me)) }
                ListItem(
                    onClick = {},
                    leadingContent = { Icon(AppIcons.Rounded.Schedule, null) },
                    trailingContent = {
                        Text(formatDate(History.NEW_HABIT_TIME, Format.TIME), style = MaterialTheme.typography.bodyLarge, color = colors.primary)
                    },
                    shapes = ListItemDefaults.segmentedShapes(2, 3),
                    colors = itemColors,
                ) { Text(stringResource(Res.string.time)) }
            }
        }
    }
}

/** Confirms deleting a habit and its streak. */
@Composable
fun DeleteHabitDialog(onDismiss: () -> Unit, onDelete: () -> Unit = onDismiss) {
    val colors = MaterialTheme.colorScheme
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(AppIcons.Rounded.DeleteOutline, null) },
        title = { Text(stringResource(Res.string.delete_title), textAlign = TextAlign.Center) },
        text = { Text(stringResource(Res.string.delete_body)) },
        confirmButton = {
            Button(
                onClick = onDelete,
                colors = ButtonDefaults.buttonColors(containerColor = colors.error, contentColor = colors.onError),
            ) { Text(stringResource(Res.string.delete)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(Res.string.cancel)) } },
        containerColor = colors.surfaceContainerHigh,
        iconContentColor = colors.error,
    )
}

@Preview(name = "Add habit sheet", showSystemUi = true)
@Composable
fun AddHabitSheetPreview() {
    HabitsTheme {
        HabitsApp()
        AddHabitSheet(onDismiss = {})
    }
}

@Preview(name = "Delete dialog", showSystemUi = true)
@Composable
fun DeleteDialogPreview() {
    HabitsTheme {
        HabitsApp()
        DeleteHabitDialog(onDismiss = {})
    }
}
