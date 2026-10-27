package com.swiftshot.demo.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/*
 * The app's small design system: one accent (persimmon), warm neutrals, a 4 dp spacing grid.
 * A fixed brand palette in light and dark; dynamic color is deliberately off so the app (and its
 * screenshots) look the same on every device.
 */

private val Persimmon = Color(0xFFE4572E)
private val PersimmonDark = Color(0xFFFF6F4A)

private val LightColors = lightColorScheme(
    primary = Persimmon,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFFDBD1),
    onPrimaryContainer = Color(0xFF3B0A00),
    inversePrimary = Color(0xFFFFB5A0),
    secondary = Color(0xFF77574D),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFF9E2DA),
    onSecondaryContainer = Color(0xFF2C1610),
    tertiary = Color(0xFF8A5100),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFFFDCBD),
    onTertiaryContainer = Color(0xFF2C1600),
    background = Color(0xFFF6F3EF),
    onBackground = Color(0xFF1E1B19),
    surface = Color(0xFFF6F3EF),
    onSurface = Color(0xFF1E1B19),
    surfaceVariant = Color(0xFFEEE6E1),
    onSurfaceVariant = Color(0xFF5B524D),
    surfaceTint = Persimmon,
    inverseSurface = Color(0xFF33302D),
    inverseOnSurface = Color(0xFFF7F0EB),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    outline = Color(0xFF8D827C),
    outlineVariant = Color(0xFFDDD4CE),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFFFBF9F6),
    surfaceDim = Color(0xFFDED8D3),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFBF9F6),
    surfaceContainer = Color(0xFFF0EBE6),
    surfaceContainerHigh = Color(0xFFEAE4DF),
    surfaceContainerHighest = Color(0xFFE4DED9),
)

private val DarkColors = darkColorScheme(
    primary = PersimmonDark,
    onPrimary = Color(0xFF3D0E00),
    primaryContainer = Color(0xFF7A2A12),
    onPrimaryContainer = Color(0xFFFFDBD1),
    inversePrimary = Persimmon,
    secondary = Color(0xFFE7BDB1),
    onSecondary = Color(0xFF442A21),
    secondaryContainer = Color(0xFF4A342C),
    onSecondaryContainer = Color(0xFFFFDBD1),
    tertiary = Color(0xFFFFB86C),
    onTertiary = Color(0xFF4A2800),
    tertiaryContainer = Color(0xFF6A3C00),
    onTertiaryContainer = Color(0xFFFFDCBD),
    background = Color(0xFF0D0D0F),
    onBackground = Color(0xFFECE6E2),
    surface = Color(0xFF0D0D0F),
    onSurface = Color(0xFFECE6E2),
    surfaceVariant = Color(0xFF2A2624),
    onSurfaceVariant = Color(0xFFC3B9B3),
    surfaceTint = PersimmonDark,
    inverseSurface = Color(0xFFECE6E2),
    inverseOnSurface = Color(0xFF33302D),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    outline = Color(0xFF8D837E),
    outlineVariant = Color(0xFF3B3633),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFF353234),
    surfaceDim = Color(0xFF0D0D0F),
    surfaceContainerLowest = Color(0xFF08080A),
    surfaceContainerLow = Color(0xFF151416),
    surfaceContainer = Color(0xFF1C1B1D),
    surfaceContainerHigh = Color(0xFF252326),
    surfaceContainerHighest = Color(0xFF302D30),
)

/** Brand colors Material's scheme has no role for. */
@Immutable
data class BrandColors(
    /** Content cards on the canvas: white in light, a lifted warm grey in dark. */
    val card: Color,
    /** Empty tracks of rings, bars and dots. */
    val track: Color,
    /** The warm amber light behind the hero and summary. */
    val glow: Color,
)

private val LightBrand = BrandColors(card = Color(0xFFFFFFFF), track = Color(0x141E1B19), glow = Color(0xFFFFB866))
private val DarkBrand = BrandColors(card = Color(0xFF1C1B1D), track = Color(0x1FECE6E2), glow = Color(0xFFFFA24D))

private val LocalBrandColors = staticCompositionLocalOf { LightBrand }

private val Base = Typography()

private val AppTypography = Typography(
    displayLarge = Base.displayLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.02).em),
    displayMedium = Base.displayMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.02).em),
    displaySmall = Base.displaySmall.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.015).em),
    headlineLarge = Base.headlineLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.01).em),
    headlineMedium = Base.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
    headlineSmall = Base.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
    titleLarge = Base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    titleMedium = Base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
    titleSmall = Base.titleSmall.copy(fontWeight = FontWeight.SemiBold),
    bodyLarge = Base.bodyLarge,
    bodyMedium = Base.bodyMedium,
    bodySmall = Base.bodySmall,
    labelLarge = Base.labelLarge.copy(fontWeight = FontWeight.SemiBold),
    labelMedium = Base.labelMedium.copy(fontWeight = FontWeight.SemiBold),
    labelSmall = Base.labelSmall.copy(fontWeight = FontWeight.SemiBold),
)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(32.dp),
)

/** Spacing on a 4 dp grid. */
object Space {
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 24.dp
    val xxl = 32.dp

    /** Content never stretches wider than this on tablets; the rest becomes margin. */
    val readableWidth = 720.dp
}

/** Big figures (streaks, percentages): bold, with tabular digits so they line up. */
object Figures {
    val hero = TextStyle(fontSize = 64.sp, lineHeight = 68.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.03).em, fontFeatureSettings = "tnum")
    val large = TextStyle(fontSize = 32.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
    val medium = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
    val small = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")
}

object HabitsTheme {
    val brand: BrandColors
        @Composable @ReadOnlyComposable get() = LocalBrandColors.current
    val colors: ColorScheme
        @Composable @ReadOnlyComposable get() = MaterialTheme.colorScheme
}

@Composable
fun HabitsTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalBrandColors provides if (darkTheme) DarkBrand else LightBrand) {
        MaterialExpressiveTheme(
            colorScheme = if (darkTheme) DarkColors else LightColors,
            typography = AppTypography,
            shapes = AppShapes,
            content = content,
        )
    }
}
