import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import 'streak_controller.dart';
import 'streak_sheet.dart';

/// "Streak settings": the floating streak, Dugtong's chat and the bubble's
/// position (same controls, behavior and preferences as before).
Future<void> showStreakSettingsSheet(BuildContext context) => showStreakSheet(
  context,
  header: const StreakSheetHeader(title: 'Streak settings'),
  children: const [_SettingsRows()],
);

class _SettingsRows extends StatelessWidget {
  const _SettingsRows();

  @override
  Widget build(BuildContext context) {
    final c = StreakController.instance;
    final p = context.palette;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _SwitchRow(
                icon: Icons.bubble_chart_rounded,
                tint: p.primaryText,
                tintBg: p.accentBg,
                title: 'Show floating streak',
                subtitle: 'Dugtong floats over every screen',
                value: c.showBubblePref,
                onChanged: c.setShowBubble,
              ),
              Divider(height: 1, indent: 64, color: p.border),
              _SwitchRow(
                icon: Icons.chat_bubble_outline_rounded,
                tint: p.info,
                tintBg: p.infoBg,
                title: 'Dugtong chat',
                subtitle: 'Tips and cheers in a speech bubble',
                value: c.chatEnabled,
                onChanged: c.setChatEnabled,
              ),
              Divider(height: 1, indent: 64, color: p.border),
              InkWell(
                onTap: () async {
                  await c.resetBubblePosition();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Bubble position reset.'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      StreakIconTile(
                        icon: Icons.my_location_rounded,
                        color: p.success,
                        background: p.successBg,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Texts(
                          title: 'Reset bubble position',
                          subtitle: 'Move Dugtong back to the edge',
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Texts extends StatelessWidget {
  final String title, subtitle;
  const _Texts({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.foreground,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );
  }
}

/// The dark-mode switch row style: a white thumb on the brand track, the
/// border color when off.
class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final Color tint, tintBg;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.tint,
    required this.tintBg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    WidgetStateProperty<Color> track() => WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected) ? AppColors.primary : p.border,
    );
    return Semantics(
      container: true,
      label: title,
      toggled: value,
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              StreakIconTile(icon: icon, color: tint, background: tintBg),
              const SizedBox(width: 12),
              Expanded(
                child: _Texts(title: title, subtitle: subtitle),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                thumbColor: WidgetStateProperty.all(Colors.white),
                trackColor: track(),
                trackOutlineColor: track(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
