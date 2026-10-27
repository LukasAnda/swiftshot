package com.swiftshot.demo.ui.welcome

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swiftshot.demo.model.History
import com.swiftshot.demo.resources.Res
import com.swiftshot.demo.resources.app_name
import com.swiftshot.demo.resources.days_in_a_row
import com.swiftshot.demo.resources.detail_water
import com.swiftshot.demo.resources.get_started
import com.swiftshot.demo.resources.habit_run
import com.swiftshot.demo.resources.have_account
import com.swiftshot.demo.resources.personal_best
import com.swiftshot.demo.resources.welcome_body
import com.swiftshot.demo.resources.welcome_title
import com.swiftshot.demo.ui.Format
import com.swiftshot.demo.ui.components.IconBadge
import com.swiftshot.demo.ui.formatDate
import com.swiftshot.demo.ui.formatNumber
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.Figures
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space
import org.jetbrains.compose.resources.stringResource

/** First run: the wordmark, a streak card as the hero, the pitch and two actions. */
@Composable
fun WelcomeScreen(modifier: Modifier = Modifier, onGetStarted: () -> Unit = {}, onSignIn: () -> Unit = {}) {
    Surface(modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            // The hero takes what the text and buttons leave, so nothing is cut off on short screens.
            fun heroScale(reserved: Dp, max: Float) = ((maxHeight - reserved) / 400.dp).coerceIn(0.6f, max)
            if (maxWidth >= 840.dp) {
                // Tablets and unfolded foldables in landscape: the pitch beside the hero.
                Column(Modifier.fillMaxSize().padding(horizontal = 72.dp, vertical = Space.xl)) {
                    AppMark()
                    Row(
                        Modifier.weight(1f).widthIn(max = 1180.dp).align(Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(72.dp),
                    ) {
                        Column(Modifier.widthIn(max = 440.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(Space.xxl)) {
                            Pitch(large = true)
                            Actions(onGetStarted, onSignIn)
                        }
                        StreakHero(Modifier.weight(1f), scale = heroScale(160.dp, 1.25f))
                    }
                }
            } else if (maxWidth >= 600.dp) {
                // Tablet portrait and unfolded foldables: a large hero, the pitch below it.
                Column(Modifier.fillMaxSize().padding(horizontal = 72.dp, vertical = Space.xl)) {
                    AppMark()
                    Spacer(Modifier.weight(1f))
                    StreakHero(Modifier.fillMaxWidth(), scale = heroScale(480.dp, 1.3f))
                    Spacer(Modifier.weight(1f))
                    Column(
                        Modifier.widthIn(max = 560.dp).align(Alignment.CenterHorizontally),
                        verticalArrangement = Arrangement.spacedBy(Space.xxl),
                    ) {
                        Pitch(large = true)
                        Actions(onGetStarted, onSignIn)
                    }
                    Spacer(Modifier.weight(0.6f))
                }
            } else {
                Column(Modifier.fillMaxSize().padding(horizontal = Space.xl).padding(top = Space.s, bottom = Space.l)) {
                    AppMark()
                    Spacer(Modifier.weight(1f).heightIn(min = Space.l))
                    StreakHero(Modifier.fillMaxWidth(), scale = heroScale(440.dp, 1f))
                    Spacer(Modifier.weight(1f).heightIn(min = Space.l))
                    Pitch(large = false)
                    Spacer(Modifier.height(28.dp))
                    Actions(onGetStarted, onSignIn)
                }
            }
        }
    }
}

@Composable
private fun Pitch(large: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(Space.m)) {
        Text(
            stringResource(Res.string.welcome_title),
            style = if (large) MaterialTheme.typography.displayMedium else MaterialTheme.typography.headlineLarge,
        )
        Text(
            stringResource(Res.string.welcome_body),
            style = if (large) MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 26.sp) else MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Actions(onGetStarted: () -> Unit, onSignIn: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        Button(onClick = onGetStarted, modifier = Modifier.fillMaxWidth().height(56.dp)) {
            Text(stringResource(Res.string.get_started), style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = onSignIn, modifier = Modifier.fillMaxWidth().height(48.dp)) {
            Text(stringResource(Res.string.have_account), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** The wordmark: a persimmon tile with a check, and the name. */
@Composable
fun AppMark(modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
        Box(
            Modifier
                .size(30.dp)
                .background(Brush.linearGradient(listOf(HabitsTheme.brand.glow, MaterialTheme.colorScheme.primary)), RoundedCornerShape(9.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(AppIcons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
        Text(stringResource(Res.string.app_name), style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold))
    }
}

/** A month-long streak as a card floating over warm light, with two chips around it. */
@Composable
fun StreakHero(modifier: Modifier = Modifier, scale: Float = 1f) {
    val colors = MaterialTheme.colorScheme
    val glow = HabitsTheme.brand.glow
    Box(modifier.height(400.dp * scale), contentAlignment = Alignment.Center) {
        // The light behind the card: two soft radial glows.
        Canvas(Modifier.fillMaxSize()) {
            val c = center
            val r1 = 190.dp.toPx() * scale
            drawCircle(
                Brush.radialGradient(listOf(colors.primary.copy(alpha = 0.45f), Color.Transparent), center = c + Offset(-60.dp.toPx() * scale, -40.dp.toPx() * scale), radius = r1),
                radius = r1, center = c + Offset(-60.dp.toPx() * scale, -40.dp.toPx() * scale),
            )
            val r2 = 150.dp.toPx() * scale
            drawCircle(
                Brush.radialGradient(listOf(glow.copy(alpha = 0.55f), Color.Transparent), center = c + Offset(90.dp.toPx() * scale, 80.dp.toPx() * scale), radius = r2),
                radius = r2, center = c + Offset(90.dp.toPx() * scale, 80.dp.toPx() * scale),
            )
        }
        Box(Modifier.scale(scale), contentAlignment = Alignment.Center) {
            StreakCard()
            HeroChip(AppIcons.Rounded.EmojiEvents, stringResource(Res.string.personal_best), Modifier.offset(x = 92.dp, y = (-164).dp))
            HeroChip(AppIcons.Rounded.WaterDrop, stringResource(Res.string.detail_water), Modifier.offset(x = (-86).dp, y = 164.dp))
        }
    }
}

@Composable
private fun StreakCard() {
    val colors = MaterialTheme.colorScheme
    Surface(
        Modifier.width(284.dp),
        shape = RoundedCornerShape(32.dp),
        color = HabitsTheme.brand.card,
        shadowElevation = 12.dp,
    ) {
        Column(Modifier.padding(Space.xl), verticalArrangement = Arrangement.spacedBy(Space.m)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.s)) {
                IconBadge(AppIcons.AutoMirroredRounded.DirectionsRun, filled = true, size = 32.dp)
                Text(stringResource(Res.string.habit_run), style = MaterialTheme.typography.titleMedium)
            }
            Column {
                Text(formatNumber(History.CURRENT_STREAK), style = Figures.hero.copy(fontSize = 84.sp, lineHeight = 88.sp))
                Text(stringResource(Res.string.days_in_a_row), style = MaterialTheme.typography.titleSmall, color = colors.onSurfaceVariant)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                repeat(7) { i ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                        DayMark(done = i < 6, size = 28.dp)
                        Text(
                            formatDate(History.dayAgo(6 - i), Format.WEEKDAY_NARROW),
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/** A checked day, or today's dashed circle still to fill. */
@Composable
private fun DayMark(done: Boolean, size: Dp) {
    val primary = MaterialTheme.colorScheme.primary
    if (done) {
        Box(Modifier.size(size).background(primary, CircleShape), contentAlignment = Alignment.Center) {
            Icon(AppIcons.Rounded.Check, null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(size * 0.6f))
        }
    } else {
        Canvas(Modifier.size(size)) {
            val stroke = 2.dp.toPx()
            drawCircle(
                primary,
                radius = this.size.minDimension / 2 - stroke / 2,
                style = Stroke(stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
            )
        }
    }
}

@Composable
private fun HeroChip(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    Surface(
        modifier,
        shape = CircleShape,
        color = HabitsTheme.brand.card,
        shadowElevation = 6.dp,
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(text, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        }
    }
}

@Preview(name = "Welcome", showSystemUi = true)
@Composable
fun WelcomePreview() {
    HabitsTheme {
        WelcomeScreen()
    }
}
