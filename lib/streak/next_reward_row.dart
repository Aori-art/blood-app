import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../my_avatar.dart';
import 'avatar_frame.dart';
import 'streak_controller.dart';
import 'streak_ladder_screen.dart' show badgeVisualFor;

/// "N more days to" the next reward: a preview of it, a slim bar and the
/// count. Shared by the home and the ladder page.
class NextRewardRow extends StatelessWidget {
  final StreakData data;
  final String initials;

  /// Grows the bar in (0..1); null shows it at once.
  final Animation<double>? grow;

  const NextRewardRow({
    super.key,
    required this.data,
    required this.initials,
    this.grow,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final next = data.nextMilestone;
    if (next == null) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.warningBg,
            ),
            child: Icon(Icons.star_rounded, color: p.warning, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You've climbed the whole ladder!",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: p.foreground,
              ),
            ),
          ),
        ],
      );
    }
    final remaining = next.remaining ?? (next.days - data.current);
    final progress = next.days <= 0
        ? 1.0
        : (data.current / next.days).clamp(0.0, 1.0);
    final index = data.ladder.indexWhere((m) => m.days == next.days);
    final Widget preview;
    if (next.isFrame) {
      preview = StreakAvatarFrame(
        frameKey: next.key,
        radius: 16,
        // The donor's own photo in the reward's frame.
        child: const MyAvatar(radius: 16, showFrame: false),
      );
    } else {
      final (icon, color) = badgeVisualFor(context, next.key, index);
      preview = Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .14),
        ),
        child: Icon(icon, color: color, size: 22),
      );
    }
    final bar = grow;
    return MergeSemantics(
      child: Row(
        children: [
          SizedBox.square(dimension: 40, child: Center(child: preview)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$remaining more ${remaining == 1 ? 'day' : 'days'} to ${next.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: p.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 8,
                    child: bar == null
                        ? _Bar(value: progress)
                        : AnimatedBuilder(
                            animation: bar,
                            builder: (context, _) => _Bar(
                              value:
                                  progress *
                                  Curves.easeOutCubic.transform(
                                    ((bar.value - 0.4) / 0.6).clamp(0.0, 1.0),
                                  ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${data.current}/${next.days}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  const _Bar({required this.value});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: context.palette.surfaceAlt),
      FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: AppColors.primaryGradient),
          ),
        ),
      ),
    ],
  );
}
