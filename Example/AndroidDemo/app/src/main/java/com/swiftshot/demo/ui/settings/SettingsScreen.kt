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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.CloudSync
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material.icons.rounded.MonitorHeart
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.StarOutline
import androidx.compose.material.icons.rounded.Upload
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.R
import com.swiftshot.demo.model.History
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.HabitsTopBar
import com.swiftshot.demo.ui.components.Readable
import com.swiftshot.demo.ui.components.SegmentedColumn
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space

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
        topBar = { HabitsTopBar(title = stringResource(R.string.tab_settings), scrollBehavior = scrollBehavior) },
    ) { padding ->
        Readable(Modifier.padding(padding).fillMaxSize()) {
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Space.l).padding(bottom = Space.xxl),
                verticalArrangement = Arrangement.spacedBy(Space.s),
            ) {
                Profile()
                Section(stringResource(R.string.section_reminders)) {
                    SettingRow(0, 3, Icons.Rounded.NotificationsActive, stringResource(R.string.daily_reminder)) {
                        Switch(reminders, { reminders = it })
                    }
                    SettingRow(1, 3, Icons.Rounded.Schedule, stringResource(R.string.reminder_time)) {
                        Value(formatDate(History.REMINDER_TIME, Format.TIME))
                    }
                    SettingRow(2, 3, Icons.AutoMirrored.Rounded.VolumeUp, stringResource(R.string.sounds)) {
                        Switch(sounds, { sounds = it })
                    }
                }
                Section(stringResource(R.string.section_general)) {
                    SettingRow(0, 3, Icons.Rounded.CalendarMonth, stringResource(R.string.week_starts_on)) {
                        Value(stringResource(R.string.monday))
                    }
                    SettingRow(1, 3, Icons.Rounded.CloudSync, stringResource(R.string.backup_sync)) {
                        Switch(sync, { sync = it })
                    }
                    SettingRow(2, 3, Icons.Rounded.Contrast, stringResource(R.string.appearance)) {
                        Value(stringResource(R.string.appearance_system))
                    }
                }
                Section(stringResource(R.string.section_data)) {
                    SettingRow(0, 2, Icons.Rounded.MonitorHeart, stringResource(R.string.health_connect)) {
                        Switch(health, { health = it })
                    }
                    SettingRow(1, 2, Icons.Rounded.Upload, stringResource(R.string.export_history)) { Chevron() }
                }
                Section(stringResource(R.string.section_about)) {
                    SettingRow(0, 3, Icons.Rounded.StarOutline, stringResource(R.string.rate_habits)) { Chevron() }
                    SettingRow(1, 3, Icons.Rounded.Shield, stringResource(R.string.privacy)) { Chevron() }
                    SettingRow(2, 3, Icons.Outlined.Info, stringResource(R.string.version)) { Value("1.0") }
                }
                Text(
                    stringResource(R.string.data_footer),
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
            supportingContent = { Text(stringResource(R.string.plan_since)) },
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
        ) { Text("Mara Keller", style = MaterialTheme.typography.titleMedium) }
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
private fun SettingRow(index: Int, count: Int, icon: ImageVector, title: String, trailing: @Composable () -> Unit) {
    ListItem(
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
    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
}
