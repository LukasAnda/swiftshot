package com.swiftshot.demo.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.swiftshot.demo.ui.icons.AppIcons
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.theme.Space

/** Progress ring in the accent colour; a filled check once complete (unless [checkWhenDone] is false). */
@Composable
fun ProgressRing(
    progress: Float,
    modifier: Modifier = Modifier,
    size: Dp = 32.dp,
    strokeWidth: Dp = 4.dp,
    checkWhenDone: Boolean = true,
) {
    val primary = MaterialTheme.colorScheme.primary
    val track = HabitsTheme.brand.track
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        if (checkWhenDone && progress >= 1f) {
            Box(Modifier.size(size).background(primary, CircleShape))
            Icon(AppIcons.Rounded.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(size * 0.6f))
        } else {
            Canvas(Modifier.size(size)) {
                val stroke = strokeWidth.toPx()
                val inset = stroke / 2
                val arcSize = androidx.compose.ui.geometry.Size(this.size.width - stroke, this.size.height - stroke)
                val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
                drawArc(track, 0f, 360f, useCenter = false, topLeft = topLeft, size = arcSize, style = Stroke(stroke))
                if (progress > 0f) {
                    drawArc(primary, -90f, 360f * progress, useCenter = false, topLeft = topLeft, size = arcSize,
                        style = Stroke(stroke, cap = StrokeCap.Round))
                }
            }
        }
    }
}

/** A habit's icon in a circle: solid accent once done, a soft accent wash before. */
@Composable
fun IconBadge(icon: ImageVector, modifier: Modifier = Modifier, filled: Boolean = false, size: Dp = 44.dp, shape: Shape = CircleShape) {
    val colors = MaterialTheme.colorScheme
    Box(
        modifier
            .size(size)
            .background(if (filled) colors.primary else colors.primary.copy(alpha = 0.12f), shape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (filled) colors.onPrimary else colors.primary, modifier = Modifier.size(size * 0.5f))
    }
}

/** A solid content card on the warm canvas. */
@Composable
fun SurfaceCard(
    modifier: Modifier = Modifier,
    shape: Shape = MaterialTheme.shapes.large,
    color: Color = HabitsTheme.brand.card,
    padding: Dp = 20.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(modifier.fillMaxWidth(), shape = shape, color = color) {
        Column(Modifier.padding(padding), verticalArrangement = Arrangement.spacedBy(Space.l), content = content)
    }
}

/** A card's title row: headline on the leading side, a quieter note on the trailing side. */
@Composable
fun CardHeader(title: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        if (trailing != null) {
            Text(trailing, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * The shape of item [index] of [count] in a segmented group: large outer corners, small inner
 * ones (the grouped list style of Material 3 Expressive).
 */
fun segmentShape(index: Int, count: Int, outer: Dp = 24.dp, inner: Dp = 6.dp): Shape = when {
    count == 1 -> RoundedCornerShape(outer)
    index == 0 -> RoundedCornerShape(topStart = outer, topEnd = outer, bottomStart = inner, bottomEnd = inner)
    index == count - 1 -> RoundedCornerShape(topStart = inner, topEnd = inner, bottomStart = outer, bottomEnd = outer)
    else -> RoundedCornerShape(inner)
}

/** Items stacked with the gap of a segmented group. */
@Composable
fun SegmentedColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(ListItemDefaults.SegmentedGap), content = content)
}

/** Seven small dots, oldest first; today (last) is outlined until it's done. */
@Composable
fun WeekDots(days: List<Boolean>, modifier: Modifier = Modifier, dot: Dp = 10.dp, spacing: Dp = 5.dp) {
    val primary = MaterialTheme.colorScheme.primary
    val track = HabitsTheme.brand.track
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(spacing)) {
        days.forEachIndexed { i, done ->
            val isOpenToday = i == days.lastIndex && !done
            Box(
                Modifier
                    .size(dot)
                    .clip(CircleShape)
                    .then(
                        if (isOpenToday) Modifier.border(1.5.dp, primary.copy(alpha = 0.6f), CircleShape)
                        else Modifier.background(if (done) primary else track)
                    )
            )
        }
    }
}

/** A rounded horizontal bar, filled to [fraction]. Mirrors in right-to-left layouts. */
@Composable
fun FractionBar(fraction: Float, modifier: Modifier = Modifier, height: Dp = 8.dp, color: Color = MaterialTheme.colorScheme.primary) {
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(HabitsTheme.brand.track)
    ) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction.coerceIn(0f, 1f)).clip(CircleShape).background(color))
    }
}

/** Centres content and caps its width on wide screens (tablets, landscape). */
@Composable
fun Readable(modifier: Modifier = Modifier, maxWidth: Dp = Space.readableWidth, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = maxWidth).fillMaxWidth()) { content() }
    }
}

/** Width classes used by the screens' own layouts (dp breakpoints of the Material window size classes). */
object WidthClass {
    val Medium = 600.dp
    val Expanded = 840.dp
}

/** Runs [content] with the width available to it, for layouts that adapt to their container. */
@Composable
fun AdaptiveBox(modifier: Modifier = Modifier, content: @Composable (maxWidth: Dp) -> Unit) {
    BoxWithConstraints(modifier) { content(maxWidth) }
}
