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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsRun
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.SelfImprovement
import androidx.compose.material.icons.rounded.WaterDrop
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.R
import com.swiftshot.demo.model.History
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.HabitsApp
import com.swiftshot.demo.ui.components.SegmentedColumn
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space

private val habitIcons = listOf(
    Icons.AutoMirrored.Rounded.MenuBook,
    Icons.Rounded.WaterDrop,
    Icons.AutoMirrored.Rounded.DirectionsRun,
    Icons.Rounded.SelfImprovement,
    Icons.Rounded.EditNote,
    Icons.Rounded.Bedtime,
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
                IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, stringResource(R.string.cancel)) }
                Text(
                    stringResource(R.string.new_habit),
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Button(onClick = onDismiss) { Text(stringResource(R.string.add)) }
            }
            OutlinedTextField(
                value = stringResource(R.string.habit_read),
                onValueChange = {},
                label = { Text(stringResource(R.string.name)) },
                singleLine = true,
                shape = MaterialTheme.shapes.medium,
                colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = HabitsTheme.brand.card),
                textStyle = MaterialTheme.typography.titleMedium,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.icon), style = MaterialTheme.typography.labelLarge, color = colors.onSurfaceVariant)
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
                    leadingContent = { Icon(Icons.Rounded.Repeat, null) },
                    trailingContent = { Text(stringResource(R.string.every_day), style = MaterialTheme.typography.bodyLarge) },
                    shapes = ListItemDefaults.segmentedShapes(0, 3),
                    colors = itemColors,
                ) { Text(stringResource(R.string.repeat)) }
                ListItem(
                    leadingContent = { Icon(Icons.Rounded.NotificationsActive, null) },
                    trailingContent = { Switch(checked = true, onCheckedChange = {}) },
                    shapes = ListItemDefaults.segmentedShapes(1, 3),
                    colors = itemColors,
                ) { Text(stringResource(R.string.remind_me)) }
                ListItem(
                    leadingContent = { Icon(Icons.Rounded.Schedule, null) },
                    trailingContent = {
                        Text(formatDate(History.NEW_HABIT_TIME, Format.TIME), style = MaterialTheme.typography.bodyLarge, color = colors.primary)
                    },
                    shapes = ListItemDefaults.segmentedShapes(2, 3),
                    colors = itemColors,
                ) { Text(stringResource(R.string.time)) }
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
        icon = { Icon(Icons.Rounded.DeleteOutline, null) },
        title = { Text(stringResource(R.string.delete_title), textAlign = TextAlign.Center) },
        text = { Text(stringResource(R.string.delete_body)) },
        confirmButton = {
            Button(
                onClick = onDelete,
                colors = ButtonDefaults.buttonColors(containerColor = colors.error, contentColor = colors.onError),
            ) { Text(stringResource(R.string.delete)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
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
