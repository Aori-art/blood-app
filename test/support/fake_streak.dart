// A streak state for tests, set straight on StreakController.instance (no
// network).
import 'package:blood/streak/streak_controller.dart';

const _ladder = [
  (3, 'badge', 'first_steps', 'First Steps'),
  (7, 'frame', 'bronze', 'Bronze Frame'),
  (14, 'badge', 'two_weeks', 'Two Weeks Strong'),
  (30, 'frame', 'silver', 'Silver Frame'),
  (60, 'badge', 'steady', 'Steady Heart'),
  (100, 'frame', 'gold', 'Gold Frame'),
  (200, 'badge', 'devoted', 'Devoted Donor'),
  (365, 'frame', 'crimson', 'Crimson Frame'),
];

/// [current] days; the ladder is fully climbed when [current] >= 365.
StreakData fakeStreak({
  int current = 12,
  int? longest,
  bool freeze = true,
  String? equipped,
}) {
  final ladder = [
    for (final (days, type, key, label) in _ladder)
      Milestone(
        days: days,
        type: type,
        key: key,
        label: label,
        description: 'Reach a $days-day streak.',
        unlocked: current >= days,
      ),
  ];
  final next = ladder.where((m) => !m.unlocked).firstOrNull;
  return StreakData(
    current: current,
    longest: longest ?? current,
    totalCheckins: current + 9,
    lastCheckinDate: '2026-10-21',
    freezeAvailable: freeze,
    equippedFrame: equipped,
    unlockedFrames: [
      for (final m in ladder)
        if (m.isFrame && m.unlocked) m.key,
    ],
    nextMilestone: next == null
        ? null
        : Milestone(
            days: next.days,
            type: next.type,
            key: next.key,
            label: next.label,
            description: next.description,
            remaining: next.days - current,
          ),
    ladder: ladder,
  );
}

void useFakeStreak(StreakData? data) {
  final c = StreakController.instance;
  c.reset(forgetSeen: true);
  c.loggedIn = data != null;
  c.data = data;
}
