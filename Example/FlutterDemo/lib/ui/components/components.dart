import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'app_icons.dart';

/// Progress ring in the accent colour; a filled check once complete (unless [checkWhenDone] is false).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 32,
    this.strokeWidth = 4,
    this.checkWhenDone = true,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final bool checkWhenDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (checkWhenDone && progress >= 1) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(AppIcons.check, size: size * 0.6, color: colors.onPrimary),
      );
    }
    return CustomPaint(
      size: Size.square(size),
      painter: _RingPainter(
        progress: progress.clamp(0, 1),
        strokeWidth: strokeWidth,
        color: colors.primary,
        track: context.brand.track,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.strokeWidth, required this.color, required this.track});

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.strokeWidth != strokeWidth || old.color != color || old.track != track;
}

/// A habit's icon in a circle: solid accent once done, a soft accent wash before.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.filled = false, this.size = 44, this.radius});

  final IconData icon;
  final bool filled;
  final double size;

  /// Corner radius; a circle when null.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? colors.primary : colors.primary.withValues(alpha: 0.12),
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius == null ? null : BorderRadius.circular(radius!),
      ),
      child: AppIcon(icon, size: size * 0.5, color: filled ? colors.onPrimary : colors.primary),
    );
  }
}

/// A solid content card on the warm canvas; its children are stacked 16 px apart.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.children,
    this.radius = Corners.large,
    this.color,
    this.padding = 20,
  });

  final List<Widget> children;
  final double radius;
  final Color? color;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? context.brand.card,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.l,
          children: children,
        ),
      ),
    );
  }
}

/// A card's title row: headline on the leading side, a quieter note on the trailing side.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: context.text.titleMedium)),
        if (trailing != null)
          Text(trailing!, style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    );
  }
}

/// The gap between the items of a segmented group.
const double segmentedGap = 2;

/// The shape of item [index] of [count] in a segmented group: large outer corners, small inner
/// ones (the grouped list style of Material 3 Expressive).
BorderRadiusGeometry segmentRadius(int index, int count, {double outer = 24, double inner = 6}) {
  final o = Radius.circular(outer);
  final i = Radius.circular(inner);
  if (count == 1) return BorderRadius.all(o);
  if (index == 0) return BorderRadius.only(topLeft: o, topRight: o, bottomLeft: i, bottomRight: i);
  if (index == count - 1) return BorderRadius.only(topLeft: i, topRight: i, bottomLeft: o, bottomRight: o);
  return BorderRadius.all(i);
}

/// Items stacked with the gap of a segmented group.
class SegmentedColumn extends StatelessWidget {
  const SegmentedColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: segmentedGap, children: children);
  }
}

/// Seven small dots, oldest first; today (last) is outlined until it's done.
class WeekDots extends StatelessWidget {
  const WeekDots(this.days, {super.key, this.dot = 10, this.spacing = 5});

  final List<bool> days;
  final double dot;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final track = context.brand.track;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: spacing,
      children: [
        for (var i = 0; i < days.length; i++)
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == days.length - 1 && !days[i] ? null : (days[i] ? primary : track),
              border: i == days.length - 1 && !days[i]
                  ? Border.all(color: primary.withValues(alpha: 0.6), width: 1.5)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// A rounded horizontal bar, filled to [fraction]. Mirrors in right-to-left layouts.
class FractionBar extends StatelessWidget {
  const FractionBar(this.fraction, {super.key, this.height = 8, this.color});

  final double fraction;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: context.brand.track),
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0, 1),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: ShapeDecoration(shape: const StadiumBorder(), color: color ?? context.colors.primary),
        ),
      ),
    );
  }
}

/// Centres content and caps its width on wide screens (tablets, landscape).
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = Space.readableWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Width classes used by the screens' own layouts (breakpoints of the Material window size classes).
abstract final class WidthClass {
  static const double medium = 600;
  static const double expanded = 840;
}

/// The screens' shared header: a large title with an optional subtitle, on the canvas. It
/// scrolls with the content and pads for the status bar itself.
class HabitsHeader extends StatelessWidget {
  const HabitsHeader({super.key, required this.title, this.subtitle, this.horizontalPadding = Space.l});

  final String title;
  final String? subtitle;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(horizontalPadding + Space.xs, top + 40, horizontalPadding, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(title, style: context.text.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(
              subtitle!,
              style: context.text.bodyLarge!.copyWith(color: context.colors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// A translucent accent made opaque over the canvas, so cards never show what's behind them.
Color overCanvas(BuildContext context, Color color) => Color.alphaBlend(color, context.colors.surface);
