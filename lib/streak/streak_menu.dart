import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_palette.dart';
import 'streak_about_sheet.dart';
import 'streak_routes.dart';
import 'streak_settings_sheet.dart';
import 'streak_sheet.dart';

/// The streak home's top-right "more" menu: About Dugtong, Streak settings
/// and Streak ladder.
class StreakMoreMenu extends StatelessWidget {
  final Widget child;
  const StreakMoreMenu({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      Color tint,
      Color tintBg,
      String title,
      String subtitle,
    ) => PopupMenuItem<String>(
      value: value,
      height: 60,
      child: Semantics(
        label: '$title, $subtitle',
        excludeSemantics: true,
        child: Row(
          children: [
            StreakIconTile(icon: icon, color: tint, background: tintBg),
            const SizedBox(width: 12),
            // Wraps (instead of overflowing) with large text.
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: p.foreground,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'More options',
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: p.isDark ? 0 : 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border),
      ),
      onOpened: HapticFeedback.selectionClick,
      onSelected: (value) {
        HapticFeedback.selectionClick();
        switch (value) {
          case 'about':
            showStreakAboutSheet(context);
          case 'settings':
            showStreakSettingsSheet(context);
          case 'ladder':
            Navigator.push(context, streakLadderRoute());
        }
      },
      itemBuilder: (context) => [
        item(
          'about',
          Icons.info_outline_rounded,
          p.primaryText,
          p.accentBg,
          'About Dugtong',
          'Meet your buddy',
        ),
        item(
          'settings',
          Icons.tune_rounded,
          p.info,
          p.infoBg,
          'Streak settings',
          'Bubble and chat',
        ),
        item(
          'ladder',
          Icons.stairs_rounded,
          p.orange,
          p.orangeBg,
          'Streak ladder',
          'Your rewards and frames',
        ),
      ],
      child: SizedBox.square(dimension: 48, child: Center(child: child)),
    );
  }
}
