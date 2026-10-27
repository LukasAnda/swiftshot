package com.swiftshot.demo.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.model.History
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.appearance
import com.swiftshot.demo.resources.appearance_system
import com.swiftshot.demo.resources.backup_sync
import com.swiftshot.demo.resources.daily_reminder
import com.swiftshot.demo.resources.data_footer
import com.swiftshot.demo.resources.export_history
import com.swiftshot.demo.resources.health_connect
import com.swiftshot.demo.resources.monday
import com.swiftshot.demo.resources.plan_since
import com.swiftshot.demo.resources.privacy
import com.swiftshot.demo.resources.rate_habits
import com.swiftshot.demo.resources.reminder_time
import com.swiftshot.demo.resources.section_about
import com.swiftshot.demo.resources.section_data
import com.swiftshot.demo.resources.section_general
import com.swiftshot.demo.resources.section_reminders
import com.swiftshot.demo.resources.sounds
import com.swiftshot.demo.resources.tab_settings
import com.swiftshot.demo.resources.version
import com.swiftshot.demo.resources.week_starts_on
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.HabitsTopBar
import com.swiftshot.demo.ui.components.Readable
import com.swiftshot.demo.ui.components.SegmentedColumn
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.stringResource

/** Settings in grouped, segmented lists; a readable column on wide screens. */
@Composable
fun SettingsScreen(modifier: Modifier = Modifier) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    var reminders by rememberSaveable { mutableStateOf(true) }
    var sounds by rememberSaveable { mutableStateOf(false) }
    var sync by rememberSaveable { mutableStateOf(true) }
    var health by rememberSaveable { mutableStateOf(true) }
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { HabitsTopBar(title = stringResource(Res.string.tab_settings), scrollBehavior = scrollBehavior) },
    ) { padding ->
        Readable(Modifier.padding(padding).fillMaxSize()) {
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Space.l).padding(bottom = Space.xxl),
                verticalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                Profile()
                Section(stringResource(Res.string.section_reminders)) {
                    SettingRow(0, 3, AppIcons.Rounded.NotificationsActive, stringResource(Res.string.daily_reminder), onClick = { reminders = !reminders }) {
                        Switch(reminders, { reminders = it })
                    }
                    SettingRow(1, 3, AppIcons.Rounded.Schedule, stringResource(Res.string.reminder_time)) {
                        Value(formatDate(History.REMINDER_TIME, Format.TIME))
                    }
                    SettingRow(2, 3, AppIcons.AutoMirroredRounded.VolumeUp, stringResource(Res.string.sounds), onClick = { sounds = !sounds }) {
                        Switch(sounds, { sounds = it })
                    }
                }
                Section(stringResource(Res.string.section_general)) {
                    SettingRow(0, 3, AppIcons.Rounded.CalendarMonth, stringResource(Res.string.week_starts_on)) {
                        Value(stringResource(Res.string.monday))
                    }
                    SettingRow(1, 3, AppIcons.Rounded.CloudSync, stringResource(Res.string.backup_sync), onClick = { sync = !sync }) {
                        Switch(sync, { sync = it })
                    }
                    SettingRow(2, 3, AppIcons.Rounded.Contrast, stringResource(Res.string.appearance)) {
                        Value(stringResource(Res.string.appearance_system))
                    }
                }
                Section(stringResource(Res.string.section_data)) {
                    SettingRow(0, 2, AppIcons.Rounded.MonitorHeart, stringResource(Res.string.health_connect), onClick = { health = !health }) {
                        Switch(health, { health = it })
                    }
                    SettingRow(1, 2, AppIcons.Rounded.Upload, stringResource(Res.string.export_history)) { Chevron() }
                }
                Section(stringResource(Res.string.section_about)) {
                    SettingRow(0, 3, AppIcons.Rounded.StarOutline, stringResource(Res.string.rate_habits)) { Chevron() }
                    SettingRow(1, 3, AppIcons.Rounded.Shield, stringResource(Res.string.privacy)) { Chevron() }
                    SettingRow(2, 3, AppIcons.Outlined.Info, stringResource(Res.string.version)) { Value("1.0") }
                }
                Text(
                    stringResource(Res.string.data_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = Space.l, vertical = Space.s),
                )
            }
        }
    }
}

@Composable
private fun Profile() {
    val colors = MaterialTheme.colorScheme
    Surface(shape = MaterialTheme.shapes.large, color = HabitsTheme.brand.card) {
        ListItem(
            headlineContent = { Text("Mara Keller", style = MaterialTheme.typography.titleMedium) },
            supportingContent = { Text(stringResource(Res.string.plan_since)) },
            leadingContent = {
                Box(
                    Modifier
                        .size(52.dp)
                        .background(Brush.linearGradient(listOf(HabitsTheme.brand.glow, colors.primary)), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("MK", style = Figures.small, color = colors.onPrimary)
                }
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.padding(vertical = Space.xs),
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = Space.l, top = Space.l, bottom = Space.s),
        )
        SegmentedColumn { content() }
    }
}

@Composable
private fun SettingRow(
    index: Int,
    count: Int,
    icon: ImageVector,
    title: String,
    onClick: () -> Unit = {},
    trailing: @Composable () -> Unit,
) {
    ListItem(
        onClick = onClick,
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingContent = trailing,
        shapes = ListItemDefaults.segmentedShapes(index, count),
        colors = ListItemDefaults.segmentedColors(containerColor = HabitsTheme.brand.card),
    ) { Text(title) }
}

@Composable
private fun Value(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun Chevron() {
    Icon(AppIcons.AutoMirroredRounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
}
