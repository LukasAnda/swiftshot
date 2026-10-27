import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../model/habits.dart';
import '../../theme/theme.dart';
import '../components/app_icons.dart';
import '../components/components.dart';
import '../format.dart';

/// Settings in grouped, segmented lists; a readable column on wide screens.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _reminders = true;
  bool _sounds = false;
  bool _sync = true;
  bool _health = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        child: Readable(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s,
              children: [
                HabitsHeader(title: l.tabSettings, horizontalPadding: 0),
                const _Profile(),
                _Section(
                  title: l.sectionReminders,
                  rows: [
                    _SettingRow(
                      icon: AppIcons.notifications,
                      title: l.dailyReminder,
                      onTap: () => setState(() => _reminders = !_reminders),
                      trailing: Switch(value: _reminders, onChanged: (v) => setState(() => _reminders = v)),
                    ),
                    _SettingRow(
                      icon: AppIcons.schedule,
                      title: l.reminderTime,
                      trailing: _Value(context.formatDate(History.reminderTime, DateStyle.time)),
                    ),
                    _SettingRow(
                      icon: AppIcons.volume,
                      title: l.sounds,
                      onTap: () => setState(() => _sounds = !_sounds),
                      trailing: Switch(value: _sounds, onChanged: (v) => setState(() => _sounds = v)),
                    ),
                  ],
                ),
                _Section(
                  title: l.sectionGeneral,
                  rows: [
                    _SettingRow(icon: AppIcons.calendar, title: l.weekStartsOn, trailing: _Value(l.monday)),
                    _SettingRow(
                      icon: AppIcons.cloudSync,
                      title: l.backupSync,
                      onTap: () => setState(() => _sync = !_sync),
                      trailing: Switch(value: _sync, onChanged: (v) => setState(() => _sync = v)),
                    ),
                    _SettingRow(icon: AppIcons.contrast, title: l.appearance, trailing: _Value(l.appearanceSystem)),
                  ],
                ),
                _Section(
                  title: l.sectionData,
                  rows: [
                    _SettingRow(
                      icon: AppIcons.health,
                      title: l.healthConnect,
                      onTap: () => setState(() => _health = !_health),
                      trailing: Switch(value: _health, onChanged: (v) => setState(() => _health = v)),
                    ),
                    _SettingRow(icon: AppIcons.upload, title: l.exportHistory, trailing: const _Chevron()),
                  ],
                ),
                _Section(
                  title: l.sectionAbout,
                  rows: [
                    _SettingRow(icon: AppIcons.star, title: l.rateHabits, trailing: const _Chevron()),
                    _SettingRow(icon: AppIcons.shield, title: l.privacy, trailing: const _Chevron()),
                    _SettingRow(icon: AppIcons.info, title: l.version, trailing: const _Value('1.0')),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                  child: Text(
                    l.dataFooter,
                    style: context.text.bodySmall!.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: context.brand.card,
      borderRadius: BorderRadius.circular(Corners.large),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: Row(
          spacing: Space.l,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [context.brand.glow, colors.primary]),
              ),
              child: Text('MK', style: Figures.small.copyWith(color: colors.onPrimary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mara Keller', style: context.text.titleMedium),
                  Text(
                    AppLocalizations.of(context).planSince,
                    style: context.text.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_SettingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: Space.l, top: Space.l, bottom: Space.s),
          child: Text(title, style: context.text.labelLarge!.copyWith(color: context.colors.primary)),
        ),
        SegmentedColumn(
          children: [
            for (var i = 0; i < rows.length; i++)
              Material(
                color: context.brand.card,
                borderRadius: segmentRadius(i, rows.length),
                clipBehavior: Clip.antiAlias,
                child: rows[i],
              ),
          ],
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.title, required this.trailing, this.onTap});

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap ?? () {},
      leading: AppIcon(icon, color: context.colors.onSurfaceVariant),
      title: Text(title),
      trailing: trailing,
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.text.bodyLarge!.copyWith(color: context.colors.onSurfaceVariant));
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => AppIcon(AppIcons.chevron, color: context.colors.onSurfaceVariant);
}
