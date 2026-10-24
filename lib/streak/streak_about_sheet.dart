import 'package:flutter/material.dart';

import '../app_palette.dart';
import 'dugtong.dart';
import 'streak_controller.dart';
import 'streak_sheet.dart';

/// Shown in "About Dugtong".
const String kAboutDugtong =
    "Meet Dugtong! The name comes from the Tagalog word 'dugtong', which "
    "means 'to connect' or 'to join'. It also begins with 'dug', the start of "
    "'dugo' (blood). That is the idea behind it: every blood donation connects "
    "one person's gift to another person's life, and every day of your streak "
    "connects to the day before it. In Filipino, 'dugtong-buhay' even "
    "describes something that extends a life. Dugtong is the link, and you "
    'keep the connection going. Each day of your streak lights a window in '
    'the Dugtong Hospital.';

/// "About Dugtong": the story of the name, then his eight forms.
Future<void> showStreakAboutSheet(BuildContext context) {
  final current = StreakController.instance.data?.current ?? 0;
  return showStreakSheet(
    context,
    header: StreakSheetHeader(
      title: 'About Dugtong',
      leading: ExcludeSemantics(
        child: Dugtong(size: 72, streak: current, animate: false),
      ),
    ),
    children: [
      Text(
        kAboutDugtong,
        style: TextStyle(
          fontSize: 13.5,
          color: context.palette.muted,
          height: 1.55,
        ),
      ),
      const SizedBox(height: 20),
      Text(
        "Dugtong's forms",
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: context.palette.foreground,
        ),
      ),
      const SizedBox(height: 10),
      _StageList(current: current),
    ],
  );
}

class _StageList extends StatelessWidget {
  final int current;
  const _StageList({required this.current});

  @override
  Widget build(BuildContext context) {
    final now = dugtongStageFor(current);
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: DugtongStage.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final stage = DugtongStage.values[i];
          return _StageCard(
            stage: stage,
            reached: current >= stage.minStreak,
            isYou: stage == now,
          );
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final DugtongStage stage;
  final bool reached;
  final bool isYou;
  const _StageCard({
    required this.stage,
    required this.reached,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final day = stage.minStreak == 0 ? 1 : stage.minStreak;
    return Semantics(
      label:
          '${stage.stageName}, day $day'
          '${isYou
              ? ', your current form'
              : reached
              ? ''
              : ', locked'}',
      excludeSemantics: true,
      child: Container(
        width: 104,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isYou ? p.primaryText : p.border,
            width: isYou ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: reached ? 1 : 0.35,
                  child: Dugtong(
                    size: 64,
                    streak: stage.minStreak,
                    stage: stage,
                    animate: false,
                  ),
                ),
                if (!reached)
                  Icon(Icons.lock_rounded, size: 22, color: p.muted),
                if (isYou)
                  Positioned(
                    top: -6,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: p.accentBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.primaryBorder),
                      ),
                      child: Text(
                        'You',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: p.primaryText,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              stage.stageName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: reached ? p.foreground : p.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text('Day $day', style: TextStyle(fontSize: 10.5, color: p.muted)),
          ],
        ),
      ),
    );
  }
}
