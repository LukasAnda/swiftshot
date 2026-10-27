import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../previews/preview_support.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';

/// First run: the wordmark, a streak card as the hero, the pitch and two actions.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onGetStarted, this.onSignIn});

  final VoidCallback? onGetStarted;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The hero takes what the text and buttons leave, so nothing is cut off on short screens.
            double heroScale(double reserved, double max) =>
                ((constraints.maxHeight - reserved) / 400).clamp(0.6, max);
            final actions = _Actions(onGetStarted: onGetStarted, onSignIn: onSignIn);
            if (constraints.maxWidth >= WidthClass.expanded) {
              // Tablets and unfolded foldables in landscape: the pitch beside the hero.
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 72, vertical: Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppMark(),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Row(
                            spacing: 72,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  spacing: Space.xxl,
                                  children: [const _Pitch(large: true), actions],
                                ),
                              ),
                              Expanded(child: StreakHero(scale: heroScale(160, 1.25))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            if (constraints.maxWidth >= WidthClass.medium) {
              // Tablet portrait and unfolded foldables: a large hero, the pitch below it.
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 72, vertical: Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppMark(),
                    const Spacer(flex: 10),
                    StreakHero(scale: heroScale(480, 1.3)),
                    const Spacer(flex: 10),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.xxl,
                          children: [const _Pitch(large: true), actions],
                        ),
                      ),
                    ),
                    const Spacer(flex: 6),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: AlignmentDirectional.centerStart, child: AppMark()),
                  // The hero takes the height the pitch and actions leave, at least 16 px from each.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Center(
                        child: StreakHero(scale: ((box.maxHeight - 2 * Space.l) / 400).clamp(0.3, 1.0)),
                      ),
                    ),
                  ),
                  const _Pitch(large: false),
                  const SizedBox(height: 28),
                  actions,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({required this.large});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = large
        ? context.text.bodyLarge!.copyWith(fontSize: 18, height: 26 / 18)
        : context.text.bodyLarge!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.m,
      children: [
        Text(l.welcomeTitle, style: large ? context.text.displayMedium : context.text.headlineLarge),
        Text(l.welcomeBody, style: body.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({this.onGetStarted, this.onSignIn});

  final VoidCallback? onGetStarted;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs,
      children: [
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onGetStarted ?? () {},
            child: Text(l.getStarted, style: context.text.titleMedium!.copyWith(color: context.colors.onPrimary)),
          ),
        ),
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: onSignIn ?? () {},
            child: Text(l.haveAccount, style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }
}

/// The wordmark: a persimmon tile with a check, and the name.
class AppMark extends StatelessWidget {
  const AppMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.s,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: LinearGradient(colors: [context.brand.glow, context.colors.primary]),
          ),
          child: const Icon(AppIcons.check, size: 20, color: Colors.white),
        ),
        Text(
          AppLocalizations.of(context).appName,
          style: context.text.titleLarge!.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// A month-long streak as a card floating over warm light, with two chips around it.
class StreakHero extends StatelessWidget {
  const StreakHero({super.key, this.scale = 1});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Like Compose's offset modifier, the chips trade sides in right-to-left layouts.
    final dir = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return SizedBox(
      height: 400 * scale,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GlowPainter(primary: context.colors.primary, glow: context.brand.glow, scale: scale),
            ),
          ),
          Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const _StreakCard(),
                Transform.translate(
                  offset: Offset(92 * dir, -164),
                  child: _HeroChip(icon: AppIcons.trophy, text: l.personalBest),
                ),
                Transform.translate(
                  offset: Offset(-86 * dir, 164),
                  child: _HeroChip(icon: AppIcons.water, text: l.detailWater),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The light behind the card: two soft radial glows.
class _GlowPainter extends CustomPainter {
  const _GlowPainter({required this.primary, required this.glow, required this.scale});

  final Color primary;
  final Color glow;
  final double scale;

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    _glow(canvas, c + Offset(-60 * scale, -40 * scale), 190 * scale, primary.withValues(alpha: 0.45));
    _glow(canvas, c + Offset(90 * scale, 80 * scale), 150 * scale, glow.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.primary != primary || old.glow != glow || old.scale != scale;
}

class _StreakCard extends StatelessWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final muted = context.colors.onSurfaceVariant;
    return Material(
      color: context.brand.card,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(32),
      child: SizedBox(
        width: 284,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.m,
            children: [
              Row(
                spacing: Space.s,
                children: [
                  const IconBadge(AppIcons.run, filled: true, size: 32),
                  Flexible(
                    child: Text(l.habitRun, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.formatNumber(History.currentStreak),
                    style: Figures.hero.copyWith(fontSize: 84, height: 88 / 84, letterSpacing: -0.03 * 84),
                  ),
                  Text(l.daysInARow, style: context.text.titleSmall!.copyWith(color: muted)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < 7; i++)
                    Column(
                      spacing: Space.xs,
                      children: [
                        _DayMark(done: i < 6, size: 28),
                        Text(
                          context.formatDate(History.dayAgo(6 - i), DateStyle.weekdayNarrow),
                          style: context.text.labelSmall!.copyWith(color: muted),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A checked day, or today's dashed circle still to fill.
class _DayMark extends StatelessWidget {
  const _DayMark({required this.done, required this.size});

  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (done) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
        child: Icon(AppIcons.check, size: size * 0.6, color: colors.onPrimary),
      );
    }
    return CustomPaint(size: Size.square(size), painter: _DashedCirclePainter(colors.primary));
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    const dash = 3.0;
    final circle = Path()..addOval((Offset.zero & size).deflate(stroke / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final metric in circle.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash * 2) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand.card,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: context.colors.primary),
            const SizedBox(width: 6),
            Text(text, style: context.text.labelLarge, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'Welcome', wrapper: screenWrapper)
Widget welcomePreview() => const WelcomeScreen();
