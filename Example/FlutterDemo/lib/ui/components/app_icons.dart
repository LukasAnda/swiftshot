import 'package:flutter/material.dart';

/// The Material Rounded and Outlined icons the app uses, under the names the other demos use.
abstract final class AppIcons {
  static const IconData water = Icons.water_drop_rounded;
  static const IconData run = Icons.directions_run_rounded;
  static const IconData read = Icons.menu_book_rounded;
  static const IconData meditate = Icons.self_improvement_rounded;
  static const IconData journal = Icons.edit_note_rounded;
  static const IconData bedtime = Icons.bedtime_rounded;

  static const IconData check = Icons.check_rounded;
  static const IconData today = Icons.check_circle_outline_rounded;
  static const IconData todaySelected = Icons.check_circle_rounded;
  static const IconData stats = Icons.insights_outlined;
  static const IconData statsSelected = Icons.insights_rounded;
  static const IconData history = Icons.calendar_month_outlined;
  static const IconData historySelected = Icons.calendar_month_rounded;
  static const IconData settings = Icons.settings_outlined;
  static const IconData settingsSelected = Icons.settings_rounded;

  static const IconData add = Icons.add_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData repeat = Icons.repeat_rounded;
  static const IconData notifications = Icons.notifications_active_rounded;
  static const IconData schedule = Icons.schedule_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData flame = Icons.local_fire_department_rounded;
  static const IconData flag = Icons.flag_rounded;
  static const IconData twilight = Icons.wb_twilight_rounded;
  static const IconData trophy = Icons.emoji_events_rounded;
  static const IconData verified = Icons.verified_rounded;
  static const IconData trendingUp = Icons.trending_up_rounded;
  static const IconData calendar = Icons.calendar_month_rounded;
  static const IconData volume = Icons.volume_up_rounded;
  static const IconData cloudSync = Icons.cloud_sync_rounded;
  static const IconData contrast = Icons.contrast_rounded;
  static const IconData health = Icons.monitor_heart_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData star = Icons.star_outline_rounded;
  static const IconData shield = Icons.shield_rounded;
  static const IconData info = Icons.info_outlined;
  static const IconData chevron = Icons.keyboard_arrow_right_rounded;

  /// Icons with a direction ("auto-mirrored" in Compose): flipped in right-to-left layouts.
  static const List<IconData> mirrored = [run, read, volume, chevron];
}

/// An [Icon] that mirrors the directional [AppIcons] in right-to-left layouts.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: size, color: color);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (rtl && AppIcons.mirrored.contains(icon)) {
      return Transform.flip(flipX: true, child: glyph);
    }
    return glyph;
  }
}
