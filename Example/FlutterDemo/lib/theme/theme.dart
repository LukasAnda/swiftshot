import 'package:flutter/material.dart';

/*
 * The app's small design system: one accent (persimmon), warm neutrals, a 4 px spacing grid.
 * A fixed brand palette in light and dark; nothing comes from the platform, so the app (and its
 * screenshots) look the same on every device.
 */

const Color _persimmon = Color(0xFFE4572E);
const Color _persimmonDark = Color(0xFFFF6F4A);

const ColorScheme _lightColors = ColorScheme(
  brightness: Brightness.light,
  primary: _persimmon,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDBD1),
  onPrimaryContainer: Color(0xFF3B0A00),
  inversePrimary: Color(0xFFFFB5A0),
  secondary: Color(0xFF77574D),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF9E2DA),
  onSecondaryContainer: Color(0xFF2C1610),
  tertiary: Color(0xFF8A5100),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFDCBD),
  onTertiaryContainer: Color(0xFF2C1600),
  surface: Color(0xFFF6F3EF),
  onSurface: Color(0xFF1E1B19),
  onSurfaceVariant: Color(0xFF5B524D),
  surfaceTint: _persimmon,
  inverseSurface: Color(0xFF33302D),
  onInverseSurface: Color(0xFFF7F0EB),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  outline: Color(0xFF8D827C),
  outlineVariant: Color(0xFFDDD4CE),
  scrim: Color(0xFF000000),
  shadow: Color(0xFF000000),
  surfaceBright: Color(0xFFFBF9F6),
  surfaceDim: Color(0xFFDED8D3),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFBF9F6),
  surfaceContainer: Color(0xFFF0EBE6),
  surfaceContainerHigh: Color(0xFFEAE4DF),
  surfaceContainerHighest: Color(0xFFE4DED9),
);

const ColorScheme _darkColors = ColorScheme(
  brightness: Brightness.dark,
  primary: _persimmonDark,
  onPrimary: Color(0xFF3D0E00),
  primaryContainer: Color(0xFF7A2A12),
  onPrimaryContainer: Color(0xFFFFDBD1),
  inversePrimary: _persimmon,
  secondary: Color(0xFFE7BDB1),
  onSecondary: Color(0xFF442A21),
  secondaryContainer: Color(0xFF4A342C),
  onSecondaryContainer: Color(0xFFFFDBD1),
  tertiary: Color(0xFFFFB86C),
  onTertiary: Color(0xFF4A2800),
  tertiaryContainer: Color(0xFF6A3C00),
  onTertiaryContainer: Color(0xFFFFDCBD),
  surface: Color(0xFF0D0D0F),
  onSurface: Color(0xFFECE6E2),
  onSurfaceVariant: Color(0xFFC3B9B3),
  surfaceTint: _persimmonDark,
  inverseSurface: Color(0xFFECE6E2),
  onInverseSurface: Color(0xFF33302D),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  outline: Color(0xFF8D837E),
  outlineVariant: Color(0xFF3B3633),
  scrim: Color(0xFF000000),
  shadow: Color(0xFF000000),
  surfaceBright: Color(0xFF353234),
  surfaceDim: Color(0xFF0D0D0F),
  surfaceContainerLowest: Color(0xFF08080A),
  surfaceContainerLow: Color(0xFF151416),
  surfaceContainer: Color(0xFF1C1B1D),
  surfaceContainerHigh: Color(0xFF252326),
  surfaceContainerHighest: Color(0xFF302D30),
);

/// Brand colors Material's scheme has no role for.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({required this.card, required this.track, required this.glow});

  /// Content cards on the canvas: white in light, a lifted warm grey in dark.
  final Color card;

  /// Empty tracks of rings, bars and dots.
  final Color track;

  /// The warm amber light behind the hero and summary.
  final Color glow;

  static const BrandColors light = BrandColors(
    card: Color(0xFFFFFFFF),
    track: Color(0x141E1B19),
    glow: Color(0xFFFFB866),
  );
  static const BrandColors dark = BrandColors(
    card: Color(0xFF1C1B1D),
    track: Color(0x1FECE6E2),
    glow: Color(0xFFFFA24D),
  );

  @override
  BrandColors copyWith({Color? card, Color? track, Color? glow}) => BrandColors(
    card: card ?? this.card,
    track: track ?? this.track,
    glow: glow ?? this.glow,
  );

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors(
      card: Color.lerp(card, other.card, t)!,
      track: Color.lerp(track, other.track, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

/// Spacing on a 4 px grid.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Content never stretches wider than this on tablets; the rest becomes margin.
  static const double readableWidth = 720;
}

/// Corner radii of the shape scale.
abstract final class Corners {
  static const double extraSmall = 8;
  static const double small = 12;
  static const double medium = 16;
  static const double large = 24;
  static const double extraLarge = 32;
}

/// Big figures (streaks, percentages): bold, with tabular digits so they line up.
abstract final class Figures {
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static const TextStyle hero = TextStyle(
    fontSize: 64,
    height: 68 / 64,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.03 * 64,
    fontFeatures: _tnum,
  );
  static const TextStyle large = TextStyle(
    fontSize: 32,
    height: 36 / 32,
    fontWeight: FontWeight.w700,
    fontFeatures: _tnum,
  );
  static const TextStyle medium = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    fontFeatures: _tnum,
  );
  static const TextStyle small = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    fontFeatures: _tnum,
  );
}

TextTheme _typography(TextTheme base) {
  TextStyle tune(TextStyle? style, FontWeight weight, [double tracking = 0]) {
    final s = style!;
    return s.copyWith(
      fontWeight: weight,
      letterSpacing: tracking == 0 ? s.letterSpacing : tracking * s.fontSize!,
    );
  }

  return base.copyWith(
    displayLarge: tune(base.displayLarge, FontWeight.w700, -0.02),
    displayMedium: tune(base.displayMedium, FontWeight.w700, -0.02),
    displaySmall: tune(base.displaySmall, FontWeight.w700, -0.015),
    headlineLarge: tune(base.headlineLarge, FontWeight.w700, -0.01),
    headlineMedium: tune(base.headlineMedium, FontWeight.w600),
    headlineSmall: tune(base.headlineSmall, FontWeight.w600),
    titleLarge: tune(base.titleLarge, FontWeight.w600),
    titleMedium: tune(base.titleMedium, FontWeight.w600),
    titleSmall: tune(base.titleSmall, FontWeight.w600),
    labelLarge: tune(base.labelLarge, FontWeight.w600),
    labelMedium: tune(base.labelMedium, FontWeight.w600),
    labelSmall: tune(base.labelSmall, FontWeight.w600),
  );
}

/// The app's Material 3 theme for [brightness].
ThemeData habitsTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? _darkColors : _lightColors;
  final brand = dark ? BrandColors.dark : BrandColors.light;
  final base = ThemeData(useMaterial3: true, colorScheme: colors);
  // ThemeData keeps sizes apart from colours until it is localized; tune the full styles.
  final text = _typography(Typography.englishLike2021.merge(base.textTheme));
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: colors.surface,
    extensions: [brand],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected) ? colors.onSurface : colors.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.secondaryContainer,
      labelType: NavigationRailLabelType.all,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(textStyle: text.labelLarge, shape: const StadiumBorder()),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: text.labelLarge, shape: const StadiumBorder()),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      extendedTextStyle: text.titleSmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.medium)),
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant.withValues(alpha: 0.6), space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      titleTextStyle: text.bodyLarge!.copyWith(color: colors.onSurface),
      subtitleTextStyle: text.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
      contentPadding: const EdgeInsetsDirectional.only(start: Space.l, end: Space.l),
      minTileHeight: 56,
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check_rounded) : null,
      ),
    ),
  );
}

/// Shortcuts to the theme from a [BuildContext].
extension HabitsThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  BrandColors get brand => Theme.of(this).extension<BrandColors>() ?? BrandColors.light;
}
