import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_design.dart';
import 'avatar_frame.dart';
import 'dugtong.dart';
import 'interactive_dugtong.dart';
import 'streak_controller.dart';
import 'streak_screen.dart';
import 'streak_scenery.dart';
import 'streak_share.dart';
import '../app_palette.dart';
import '../theme_transition.dart';


/// Size of the big Dugtong in the summary card.
const double _kDugtongSize = 110;

/// Sky above Dugtong in the summary card's hospital scene (sun, moon, clouds).
const double _kSkyBand = 56;

/// Space under Dugtong's row where the pavement and the road show.
const double _kRoadGap = 48;

/// Shown in the "About Dugtong" card.
const String _kAboutDugtong =
    "Meet Dugtong! The name comes from the Tagalog word 'dugtong', which "
    "means 'to connect' or 'to join'. It also begins with 'dug', the start of "
    "'dugo' (blood). That is the idea behind it: every blood donation connects "
    "one person's gift to another person's life, and every day of your streak "
    "connects to the day before it. In Filipino, 'dugtong-buhay' even "
    "describes something that extends a life. Dugtong is the link, and you "
    'keep the connection going. Each day of your streak lights a window in '
    'the eDonate Hospital.';
// (the card shadow comes from the palette: context.palette.shadow)

/// Icon + colour for a badge reward. The server decides which badges exist;
/// this only picks a look for them.
(IconData, Color) badgeVisualFor(BuildContext context, String key, int index) {
  final p = context.palette;
  final looks = [
    (Icons.local_fire_department_rounded, p.orange),
    (Icons.bolt_rounded, p.warning),
    (Icons.favorite_rounded, p.pink),
    (Icons.military_tech_rounded, p.info),
    (Icons.emoji_events_rounded, p.warning),
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
  bool _sharing = false;

  // The summary card is the area the interactive Dugtong can be dragged in.
  final GlobalKey _summaryKey = GlobalKey();

  // The scene's sun / moon (a theme switch grows from it) and the scroll
  // offset for its parallax.
  final GlobalKey _sunMoonKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _loadName();
    _refresh();
    _scroll.addListener(() {
      if (_scroll.hasClients) _scrollOffset.value = _scroll.offset;
    });
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
    _scroll.dispose();
    _scrollOffset.dispose();
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

  Future<void> _share(BuildContext buttonContext, StreakData d) async {
    if (_sharing) return;
    final origin = shareOriginFor(buttonContext);
    setState(() => _sharing = true);
    try {
      await shareStreak(
        context,
        streak: d.current,
        stage: dugtongStageFor(d.current),
        origin: origin,
      );
    } catch (_) {
      _snack("Couldn't create the share image. Please try again.");
    }
    if (mounted) setState(() => _sharing = false);
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
  Widget build(BuildContext context) => StreakScreen(
    id: 'streak_ladder',
    // The ladder has its own interactive Dugtong.
    hideBubble: true,
    child: Scaffold(
      backgroundColor: context.palette.background,
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
              color: context.palette.primaryText,
              onRefresh: _refresh,
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final data = _c.data;
                  if (data == null) return _emptyState();
                  return SingleChildScrollView(
                    controller: _scroll,
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
        Center(child: CircularProgressIndicator(color: context.palette.primaryText))
      else ...[
        Icon(Icons.cloud_off_rounded, size: 52, color: context.palette.muted),
        const SizedBox(height: 14),
        Text(
          "Couldn't load your streak",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Check your connection and pull down to try again.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.palette.muted, height: 1.4),
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
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryCard(d),
        const SizedBox(height: 14),
        _aboutCard(),
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
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.palette.primaryText,
                        ),
                      )
                    : const Icon(Icons.layers_clear_rounded, size: 16),
                label: const Text('Remove frame'),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.primaryText,
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
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No rewards to show yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.palette.muted),
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
        Text(
          'Rewards are cosmetic. Your best streak keeps your unlocked rewards '
          'even if your current streak resets.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: context.palette.muted, height: 1.5),
        ),
      ],
    );

    // The interactive Dugtong sits in a layer above every card, so it never
    // slides under the cards that follow the summary.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        column,
        Positioned(
          left: 16,
          // Dugtong stands on the scene's ground line.
          top: 16 + _kSkyBand,
          width: _kDugtongSize,
          height: _kDugtongSize,
          child: InteractiveDugtong(
            size: _kDugtongSize,
            streak: d.current,
            restingMood: d.current == 0 ? DugtongMood.sleepy : DugtongMood.idle,
            limitKey: _summaryKey,
          ),
        ),
      ],
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────

  Widget _card({required Widget child, Color? border, Key? key}) => Container(
    key: key,
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? context.palette.border),
      boxShadow: context.palette.shadow,
    ),
    child: child,
  );

  Widget _aboutCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_rounded, size: 18, color: context.palette.primaryText),
            SizedBox(width: 8),
            Text(
              'About Dugtong',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.palette.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _kAboutDugtong,
          style: TextStyle(fontSize: 13, color: context.palette.muted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _summaryCard(StreakData d) {
    final notice = _c.streakLostNow
        ? 'Your streak restarted${_c.previousStreak > 0 ? ' (it was ${_c.previousStreak} days)' : ''}. '
              'Your best streak keeps your rewards.'
        : (_c.freezeUsedNow
              ? 'Your Streak Freeze just saved your streak!'
              : null);
    return _sceneCard(
      d,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: _kSkyBand),
          Row(
            children: [
              // Where the interactive Dugtong rests (it is drawn in a layer above).
              const SizedBox(width: _kDugtongSize, height: _kDugtongSize),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _frosted(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${d.current}',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: context.palette.primaryText,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'day streak',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.accentBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        dugtongStageFor(d.current).stageName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: context.palette.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _kRoadGap),
          _frosted(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    ? context.palette.success
                    : context.palette.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: context.palette.muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Protects 1 missed day, once every 30 days',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (buttonContext) => SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _sharing ? null : () => _share(buttonContext, d),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.primaryText,
                  side: BorderSide(color: context.palette.primaryText, width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _sharing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: context.palette.primaryText,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ios_share_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Share',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.palette.infoBg,
                border: Border.all(color: context.palette.infoBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                notice,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.infoText,
                  height: 1.4,
                ),
              ),
            ),
          ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Text over the scene sits on a frosted panel so it reads in both modes.
  Widget _frosted({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.palette.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  /// The summary card, with the day / night eDonate Hospital behind it.
  Widget _sceneCard(StreakData d, {required Widget child}) {
    final groundY = 16 + _kSkyBand + _kDugtongSize * 0.96;
    return Container(
      key: _summaryKey,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.border),
        boxShadow: context.palette.shadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: ValueListenableBuilder<double>(
          valueListenable: _scrollOffset,
          builder: (context, offset, content) => StreakScenery(
            height: groundY + StreakScenery.roadBand,
            litWindows: math.min(d.current, 24),
            parallax: offset,
            sunMoonKey: _sunMoonKey,
            onSunMoonTap: () {
              HapticFeedback.selectionClick();
              ThemeTransition.toggle(context, originKey: _sunMoonKey);
            },
            child: content,
          ),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  Widget _chip(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      border: Border.all(color: context.palette.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.palette.primaryText),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: context.palette.muted),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor ?? context.palette.foreground,
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
        child: Row(
          children: [
            Icon(
              Icons.emoji_events_rounded,
              color: context.palette.warning,
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "You've climbed the whole ladder!",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
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
          Text(
            'NEXT REWARD',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.palette.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$remaining more ${remaining == 1 ? 'day' : 'days'} to ${next.label}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration:
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                color: context.palette.primaryText,
                backgroundColor: context.palette.surfaceAlt,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${d.current} / ${next.days}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.palette.muted,
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
                color: context.palette.border,
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
        color: unlocked ? kCrimson : context.palette.surface,
        border: Border.all(
          color: unlocked ? context.palette.primaryText : context.palette.border,
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
        color: unlocked ? Colors.white : context.palette.hint,
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
                color: unlocked ? context.palette.primaryText : context.palette.muted,
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
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isNext
                  ? kCrimson.withValues(alpha: .45)
                  : context.palette.border,
              width: isNext ? 1.5 : 1,
            ),
            boxShadow: context.palette.shadow,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.palette.foreground,
                      ),
                    ),
                    if (m.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
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
    final (icon, color) = badgeVisualFor(context, m.key, index);
    final tint = unlocked ? color : context.palette.hint;
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
      return _SmallPill(
        icon: Icons.check_circle_rounded,
        label: 'Equipped',
        color: context.palette.success,
      );
    }
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: _busyFrame != null ? null : () => _setFrame(m.key),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.palette.primaryText,
          side: BorderSide(color: context.palette.primaryText, width: 1.3),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.primaryText,
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
        Text(
          'Settings',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Show floating streak',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.foreground,
                ),
              ),
            ),
            Switch(
              value: _c.showBubblePref,
              activeThumbColor: context.palette.primaryText,
              onChanged: (v) => _c.setShowBubble(v),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Dugtong chat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.foreground,
                ),
              ),
            ),
            Switch(
              value: _c.chatEnabled,
              activeThumbColor: context.palette.primaryText,
              onChanged: (v) => _c.setChatEnabled(v),
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
              foregroundColor: context.palette.primaryText,
              side: BorderSide(color: context.palette.primaryBorder),
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
