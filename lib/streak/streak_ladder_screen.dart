import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_design.dart';
import 'avatar_frame.dart';
import 'blood_bag_mascot.dart';
import 'streak_controller.dart';
import 'streak_hidden.dart';

const Color _kTrackGray = Color(0xFFE5E7EB);
const List<BoxShadow> _kSoftShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
];

/// Icon + colour for a badge reward. The server decides which badges exist;
/// this only picks a look for them.
(IconData, Color) badgeVisualFor(String key, int index) {
  const looks = [
    (Icons.local_fire_department_rounded, Color(0xFFF97316)),
    (Icons.bolt_rounded, Color(0xFFF59E0B)),
    (Icons.favorite_rounded, Color(0xFFEC4899)),
    (Icons.military_tech_rounded, Color(0xFF2563EB)),
    (Icons.emoji_events_rounded, Color(0xFFD97706)),
  ];
  return looks[(index.abs()) % looks.length];
}

class StreakLadderScreen extends StatefulWidget {
  const StreakLadderScreen({super.key});

  @override
  State<StreakLadderScreen> createState() => _StreakLadderScreenState();
}

class _StreakLadderScreenState extends State<StreakLadderScreen>
    with SingleTickerProviderStateMixin {
  final StreakController _c = StreakController.instance;
  late final AnimationController _pulse;

  String _initials = '?';
  // Frame key whose request is running ('' while removing a frame).
  String? _busyFrame;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _loadName();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('userName') ?? '';
    if (mounted) setState(() => _initials = streakInitials(name));
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _refreshing = true);
    await _c.refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _setFrame(String? key) async {
    if (_busyFrame != null) return;
    setState(() => _busyFrame = key ?? '');
    final result = await _c.setFrame(key);
    if (!mounted) return;
    setState(() => _busyFrame = null);
    if (!result.ok) {
      final fallback = result.code == 'FRAME_NOT_UNLOCKED'
          ? "That frame isn't unlocked yet."
          : "Couldn't change your frame. Please try again.";
      _snack(result.message ?? fallback);
    }
  }

  @override
  Widget build(BuildContext context) => StreakBubbleHidden(
    child: Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          EdonateHeader(
            title: 'Streak Ladder',
            subtitle: 'Open eDonate every day to climb',
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: kCrimson,
              onRefresh: _refresh,
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final data = _c.data;
                  if (data == null) return _emptyState();
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    child: _content(data),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 60),
      if (_refreshing)
        const Center(child: CircularProgressIndicator(color: kCrimson))
      else ...[
        const Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFF9CA3AF)),
        const SizedBox(height: 14),
        const Text(
          "Couldn't load your streak",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Check your connection and pull down to try again.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: kTextMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 180,
            child: PrimaryButton(label: 'Try Again', onTap: _refresh),
          ),
        ),
      ],
    ],
  );

  Widget _content(StreakData d) {
    final rungs = [...d.ladder]..sort((a, b) => b.days.compareTo(a.days));
    // The largest milestone the donor has reached (list is highest-first).
    final here = rungs.where((m) => m.days <= d.current).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryCard(d),
        const SizedBox(height: 14),
        _nextRewardCard(d),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: SectionTitle('THE LADDER')),
            if (d.equippedFrame != null)
              TextButton.icon(
                onPressed: _busyFrame != null ? null : () => _setFrame(null),
                icon: _busyFrame == ''
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kCrimson,
                        ),
                      )
                    : const Icon(Icons.layers_clear_rounded, size: 16),
                label: const Text('Remove frame'),
                style: TextButton.styleFrom(
                  foregroundColor: kCrimson,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (rungs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No rewards to show yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kTextMuted),
            ),
          )
        else
          for (var i = 0; i < rungs.length; i++)
            _rung(
              d,
              rungs,
              i,
              isHere: here != null && rungs[i].days == here.days,
            ),
        const SizedBox(height: 18),
        _settingsCard(),
        const SizedBox(height: 16),
        const Text(
          'Rewards are cosmetic. Your best streak keeps your unlocked rewards '
          'even if your current streak resets.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: kTextMuted, height: 1.5),
        ),
      ],
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────

  Widget _card({required Widget child, Color? border}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? const Color(0xFFE5E7EB)),
      boxShadow: _kSoftShadow,
    ),
    child: child,
  );

  Widget _summaryCard(StreakData d) {
    final notice = _c.streakLostNow
        ? 'Your streak restarted${_c.previousStreak > 0 ? ' (it was ${_c.previousStreak} days)' : ''}. '
              'Your best streak keeps your rewards.'
        : (_c.freezeUsedNow
              ? 'Your Streak Freeze just saved your streak!'
              : null);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BloodBagMascot(
                size: 96,
                streak: d.current,
                mood: d.current == 0 ? MascotMood.sleepy : MascotMood.idle,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${d.current}',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: kCrimson,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'day streak',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.emoji_events_rounded, 'Best streak', '${d.longest}'),
              _chip(
                Icons.calendar_month_rounded,
                'Total days',
                '${d.totalCheckins}',
              ),
              _chip(
                Icons.ac_unit_rounded,
                'Streak Freeze',
                d.freezeAvailable ? 'Ready' : 'Recharging',
                valueColor: d.freezeAvailable
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFD97706),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: kTextMuted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Protects 1 missed day, once every 30 days',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: kTextMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (notice != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFBFDBFE)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                notice,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1D4ED8),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    IconData icon,
    String label,
    String value, {
    Color valueColor = kTextPrimary,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: kInputFill,
      border: Border.all(color: const Color(0xFFE5E7EB)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: kCrimson),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: kTextMuted),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _nextRewardCard(StreakData d) {
    final next = d.nextMilestone;
    if (next == null) {
      return _card(
        child: const Row(
          children: [
            Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFD97706),
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "You've climbed the whole ladder!",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final remaining = next.remaining ?? (next.days - d.current);
    final progress = next.days <= 0
        ? 1.0
        : (d.current / next.days).clamp(0.0, 1.0);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEXT REWARD',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: kTextMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$remaining more ${remaining == 1 ? 'day' : 'days'} to ${next.label}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: kCrimson,
              backgroundColor: const Color(0xFFF3F4F6),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${d.current} / ${next.days}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: kTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── The ladder ──────────────────────────────────────────────────────────

  // Progress through the gap between two rungs, 0..1.
  double _gap(StreakData d, int lowDays, int highDays) {
    if (highDays <= lowDays) return d.current >= highDays ? 1 : 0;
    return ((d.current - lowDays) / (highDays - lowDays)).clamp(0.0, 1.0);
  }

  Widget _rung(
    StreakData d,
    List<Milestone> rungs,
    int i, {
    required bool isHere,
  }) {
    final m = rungs[i];
    final higher = i > 0 ? rungs[i - 1] : null;
    final lower = i < rungs.length - 1 ? rungs[i + 1] : null;
    final isNext =
        !m.unlocked &&
        d.nextMilestone != null &&
        d.nextMilestone!.days == m.days;

    // A gap is filled from the lower rung upwards; its lower half sits in the
    // upper rung's track and its upper half in the lower rung's track.
    final fillAbove = higher == null
        ? 0.0
        : (2 * _gap(d, m.days, higher.days)).clamp(0.0, 1.0);
    final fillBelow = lower == null
        ? 0.0
        : (2 * _gap(d, lower.days, m.days) - 1).clamp(0.0, 1.0);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Expanded(
                  child: _trackHalf(visible: higher != null, fill: fillAbove),
                ),
                _node(m.unlocked, isNext),
                Expanded(
                  child: _trackHalf(visible: lower != null, fill: fillBelow),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: _rungCard(d, m, i, isNext: isNext, isHere: isHere),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackHalf({required bool visible, required double fill}) {
    if (!visible) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _kTrackGray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (fill > 0)
              FractionallySizedBox(
                heightFactor: fill,
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kCrimson,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _node(bool unlocked, bool isNext) {
    final circle = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unlocked ? kCrimson : Colors.white,
        border: Border.all(
          color: unlocked ? kCrimson : const Color(0xFFD1D5DB),
          width: 2,
        ),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: kCrimson.withValues(alpha: .3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Icon(
        unlocked ? Icons.check_rounded : Icons.lock_rounded,
        size: 18,
        color: unlocked ? Colors.white : const Color(0xFF9CA3AF),
      ),
    );
    if (!isNext) return circle;
    return AnimatedBuilder(
      animation: _pulse,
      child: circle,
      builder: (_, child) {
        final grow = 8 * _pulse.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 34 + grow,
              height: 34 + grow,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: kCrimson.withValues(alpha: .55 * (1 - _pulse.value)),
                  width: 2,
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }

  Widget _rungCard(
    StreakData d,
    Milestone m,
    int index, {
    required bool isNext,
    required bool isHere,
  }) {
    final unlocked = m.unlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Day ${m.days}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: unlocked ? kCrimson : kTextMuted,
              ),
            ),
            if (isHere) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kCrimson,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'You are here',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isNext
                  ? kCrimson.withValues(alpha: .45)
                  : const Color(0xFFE5E7EB),
              width: isNext ? 1.5 : 1,
            ),
            boxShadow: _kSoftShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _preview(m, unlocked, index),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary,
                      ),
                    ),
                    if (m.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (m.isFrame && unlocked) ...[
                      const SizedBox(height: 8),
                      _equipButton(d, m),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(Milestone m, bool unlocked, int index) {
    if (m.isFrame) {
      return Opacity(
        opacity: unlocked ? 1 : 0.5,
        child: StreakAvatarFrame(
          frameKey: m.key,
          radius: 20,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: kCrimson,
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }
    final (icon, color) = badgeVisualFor(m.key, index);
    final tint = unlocked ? color : const Color(0xFF9CA3AF);
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: .14),
      ),
      child: Icon(icon, color: tint, size: 26),
    );
  }

  Widget _equipButton(StreakData d, Milestone m) {
    final equipped = d.equippedFrame == m.key;
    final busy = _busyFrame == m.key;
    if (equipped) {
      return const _SmallPill(
        icon: Icons.check_circle_rounded,
        label: 'Equipped',
        color: Color(0xFF16A34A),
      );
    }
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: _busyFrame != null ? null : () => _setFrame(m.key),
        style: OutlinedButton.styleFrom(
          foregroundColor: kCrimson,
          side: const BorderSide(color: kCrimson, width: 1.3),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kCrimson,
                ),
              )
            : const Text('Equip'),
      ),
    );
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  Widget _settingsCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Show floating streak',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary,
                ),
              ),
            ),
            Switch(
              value: _c.showBubblePref,
              activeThumbColor: kCrimson,
              onChanged: (v) => _c.setShowBubble(v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () async {
              await _c.resetBubblePosition();
              _snack('Bubble position reset.');
            },
            icon: const Icon(Icons.open_with_rounded, size: 18),
            label: const Text('Reset bubble position'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCrimson,
              side: const BorderSide(color: Color(0xFFFECACA)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SmallPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SmallPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}
