import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../shared_design.dart' show PrimaryButton, kCrimson;
import '../theme_transition.dart';
import 'avatar_frame.dart';
import 'dugtong.dart';
import 'dugtong_chatter.dart';
import 'dugtong_top_bubble.dart';
import 'interactive_dugtong.dart';
import 'streak_controller.dart';
import 'streak_ladder_screen.dart' show badgeVisualFor;
import 'streak_menu.dart';
import 'streak_scenery.dart';
import 'streak_screen.dart';
import 'streak_share.dart';

/// The streak home, opened from the floating Dugtong: the scenery, Dugtong,
/// the streak and a few key numbers on ONE screen that never scrolls. Things
/// shrink to fit (small phones, large text) instead.
class StreakHomeScreen extends StatefulWidget {
  const StreakHomeScreen({super.key});

  @override
  State<StreakHomeScreen> createState() => StreakHomeScreenState();
}

/// Layout of the home for a screen (all in screen pixels).
class StreakHomeLayout {
  final double width, height, top;

  /// 0.72 .. 1: everything scales with the height inside the safe area.
  final double s;
  final double ring, hero, panel, panelTop, groundY, dugtong;
  final bool showEvolve;

  static const double topBar = 52;

  factory StreakHomeLayout(
    Size size,
    EdgeInsets padding, {
    bool evolve = true,
  }) {
    final inner = size.height - padding.top - padding.bottom;
    final s = (inner / 760).clamp(0.72, 1.0);
    final ring = math.max(96.0, 132 * s);
    final showEvolve = evolve && s >= 0.85;
    final hero = ring + 10 + 28 + (showEvolve ? 20 : 0);
    final panel = 196 * s;
    final panelTop = padding.top + inner - 16 - panel;
    // Dugtong's feet: on the scene's ground line, just above the panel (the
    // pavement and the road show between them).
    final groundY = panelTop - 34;
    final stageTop = padding.top + topBar + hero;
    final dugtong = math.max(110.0, math.min(groundY - stageTop - 64, 240.0));
    return StreakHomeLayout._(
      size.width,
      size.height,
      padding.top,
      s,
      ring,
      hero,
      panel,
      panelTop,
      groundY,
      dugtong,
      showEvolve,
    );
  }

  const StreakHomeLayout._(
    this.width,
    this.height,
    this.top,
    this.s,
    this.ring,
    this.hero,
    this.panel,
    this.panelTop,
    this.groundY,
    this.dugtong,
    this.showEvolve,
  );

  double get groundFraction => groundY / height;

  /// Dugtong stands a little left of centre, so the hospital shows beside him.
  double get dugtongX => math.max(dugtong / 2 + 8, width * 0.42);

  Rect get dugtongRect => Rect.fromLTWH(
    dugtongX - dugtong / 2,
    groundY - dugtong * 0.96,
    dugtong,
    dugtong,
  );
}

class StreakHomeScreenState extends State<StreakHomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final StreakController _c = StreakController.instance;

  // The one-shot entrance: scenery, ring, count, Dugtong, panel (1.2 s).
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _introStarted = false;
  bool _reduce = false;

  // Dugtong's drag, for the scenery's parallax.
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);
  final GlobalKey _sunMoonKey = GlobalKey();
  final GlobalKey _sceneKey = GlobalKey();

  // What Dugtong says (typed out, 28 ms a letter).
  final DugtongChatter _chatter = DugtongChatter();
  String? _line;
  final ValueNotifier<int> _typed = ValueNotifier(0);
  Timer? _typer;
  Timer? _firstLine;
  bool _noticeSaid = false;

  // A new check-in while this screen is open: celebrate for ~2.5 s.
  int? _seenStreak;
  bool _celebrating = false;
  Timer? _celebrateTimer;

  String _initials = '?';
  bool _sharing = false;
  bool _refreshing = false;

  /// What Dugtong is saying (for tests).
  @visibleForTesting
  String? get currentLine => _line;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onStreak);
    _seenStreak = _c.data?.current;
    _loadName();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_introStarted) return;
    _introStarted = true;
    if (_reduce) {
      _intro.value = 1;
      _sayFirst();
    } else {
      _intro.forward();
      _firstLine = Timer(const Duration(milliseconds: 600), _sayFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onStreak);
    _intro.dispose();
    _drag.dispose();
    _typed.dispose();
    _typer?.cancel();
    _firstLine?.cancel();
    _celebrateTimer?.cancel();
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

  void _onStreak() {
    final d = _c.data;
    if (d == null) return;
    final seen = _seenStreak;
    _seenStreak = d.current;
    if (seen != null && d.current > seen) {
      setState(() => _celebrating = true);
      _celebrateTimer?.cancel();
      _celebrateTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _celebrating = false);
      });
    }
    if (_line == null && !(_firstLine?.isActive ?? false)) _sayFirst();
  }

  // ─── Speech ────────────────────────────────────────────────────────────

  /// What the latest check-in did, if Dugtong should tell the donor.
  String? get _notice {
    if (_c.streakLostNow) {
      final was = _c.previousStreak > 0
          ? ' (it was ${_c.previousStreak} days)'
          : '';
      return 'Your streak restarted$was. Your best streak keeps your rewards.';
    }
    if (_c.freezeUsedNow) return 'Your Streak Freeze just saved your streak!';
    return null;
  }

  void _sayFirst() {
    final notice = _notice;
    if (notice != null && !_noticeSaid) {
      _noticeSaid = true;
      _say(notice);
    } else {
      _sayNext();
    }
  }

  void _sayNext() {
    final d = _c.data;
    if (d == null || !_c.chatEnabled) return;
    String? line;
    for (var i = 0; i < 4; i++) {
      line = _chatter.next(d, screenId: 'streak_home');
      // That tip is for the floating bubble; here the donor already tapped.
      if (line != 'Tap me to see your streak!') break;
    }
    if (line != null) _say(line);
  }

  void _say(String text) {
    _typer?.cancel();
    setState(() => _line = text);
    if (_reduce) {
      _typed.value = text.length;
      return;
    }
    _typed.value = 0;
    _typer = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (_typed.value >= text.length) {
        t.cancel();
      } else {
        _typed.value++;
      }
    });
  }

  void _onDugtongTapped() {
    if (_c.chatEnabled) _sayNext();
  }

  // ─── Actions ───────────────────────────────────────────────────────────

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

  Future<void> _showFreezeInfo() async {
    final p = context.palette;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.ac_unit_rounded, color: p.info),
        title: Text(
          'Streak Freeze',
          style: TextStyle(fontWeight: FontWeight.w700, color: p.foreground),
        ),
        content: Text(
          'Protects 1 missed day, once every 30 days.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: p.primaryText),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─── Entrance ──────────────────────────────────────────────────────────

  Animation<double> _phase(
    double from,
    double to, [
    Curve curve = Curves.easeOut,
  ]) => CurvedAnimation(
    parent: _intro,
    curve: Interval(from / 1200, to / 1200, curve: curve),
  );

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => StreakScreen(
    id: 'streak_home',
    // This screen is Dugtong: the floating bubble steps aside.
    hideBubble: true,
    child: Scaffold(
      backgroundColor: context.palette.background,
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final d = _c.data;
            final current = d?.current ?? 0;
            final layout = StreakHomeLayout(
              box.biggest,
              MediaQuery.paddingOf(context),
              evolve: _nextStage(current) != null,
            );
            return Stack(
              children: [
                Positioned.fill(child: _scenery(layout, current)),
                _podium(layout),
                Positioned.fromRect(
                  rect: layout.dugtongRect,
                  child: _dugtong(layout, d),
                ),
                if (_line != null) _bubble(layout),
                Positioned(
                  left: 0,
                  right: 0,
                  top: layout.top,
                  height: StreakHomeLayout.topBar,
                  child: _topBar(d),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: layout.top + StreakHomeLayout.topBar,
                  height: layout.hero,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _hero(layout, d),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: layout.panelTop,
                  height: layout.panel,
                  child: _panel(layout, d),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _scenery(StreakHomeLayout layout, int current) => FadeTransition(
    opacity: _phase(0, 300),
    child: ValueListenableBuilder<Offset>(
      valueListenable: _drag,
      builder: (context, drag, _) => StreakScenery(
        key: _sceneKey,
        groundFraction: layout.groundFraction,
        litWindows: math.min(current, 24),
        drag: drag,
        celestial: Offset(
          layout.width - 54,
          layout.top + StreakHomeLayout.topBar + 46,
        ),
        captionAt: Offset(16, layout.top + StreakHomeLayout.topBar + 2),
        sunMoonKey: _sunMoonKey,
        onSunMoonTap: () {
          HapticFeedback.selectionClick();
          ThemeTransition.toggle(context, originKey: _sunMoonKey);
        },
      ),
    ),
  );

  // A soft podium under his feet.
  Widget _podium(StreakHomeLayout layout) {
    final p = context.palette;
    final w = layout.dugtong * 0.8;
    return Positioned(
      left: layout.dugtongX - w / 2,
      top: layout.groundY - 6,
      width: w,
      height: 14,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.6),
            borderRadius: const BorderRadius.all(Radius.elliptical(200, 14)),
            border: Border.all(color: p.border.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }

  DugtongMood _mood(int current) {
    if (_celebrating) return DugtongMood.celebrate;
    return current == 0 ? DugtongMood.sleepy : DugtongMood.idle;
  }

  Widget _dugtong(StreakHomeLayout layout, StreakData? d) {
    final current = d?.current ?? 0;
    final dugtong = InteractiveDugtong(
      size: layout.dugtong,
      streak: current,
      restingMood: _mood(current),
      limitKey: _sceneKey,
      // With chat on, his words go in the bubble above him.
      speaks: !_c.chatEnabled,
      onTapped: _onDugtongTapped,
      onDragOffset: (o) => _drag.value = o,
    );
    return AnimatedBuilder(
      animation: _phase(150, 650, Curves.easeOutBack),
      child: dugtong,
      builder: (context, child) {
        final u = _phase(150, 650, Curves.easeOutBack).value;
        final appear = _phase(150, 300).value;
        return Opacity(
          opacity: appear,
          child: Transform.scale(
            scale: 0.6 + 0.4 * u,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }

  Widget _bubble(StreakHomeLayout layout) {
    final text = _line!;
    final scaler = MediaQuery.textScalerOf(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: layout.height - layout.dugtongRect.top - 2,
      child: IgnorePointer(
        child: Align(
          // Centred on Dugtong (inside the 16 px margins).
          alignment: Alignment(
            ((layout.dugtongX - 16) / (layout.width - 32) * 2 - 1).clamp(
              -1.0,
              1.0,
            ),
            0,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: ValueListenableBuilder<int>(
              valueListenable: _typed,
              builder: (context, shown, _) => DugtongTopBubble(
                text: text,
                shown: shown.clamp(0, text.length),
                textScaler: scaler,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Top bar ───────────────────────────────────────────────────────────

  Widget _topBar(StreakData? d) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        _CircleButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        const Spacer(),
        Builder(
          builder: (buttonContext) => _CircleButton(
            icon: Icons.ios_share_rounded,
            label: 'Share your streak',
            busy: _sharing,
            onTap: d == null || _sharing
                ? null
                : () => _share(buttonContext, d),
          ),
        ),
        StreakMoreMenu(child: const _CircleFace(icon: Icons.more_vert_rounded)),
      ],
    ),
  );

  // ─── Count hero ────────────────────────────────────────────────────────

  int? _nextStage(int current) {
    for (final t in kDugtongStageThresholds) {
      if (t > current) return t;
    }
    return null;
  }

  Widget _hero(StreakHomeLayout layout, StreakData? d) {
    final p = context.palette;
    final current = d?.current ?? 0;
    final next = d?.nextMilestone;
    final progress = d == null
        ? 0.0
        : next == null || next.days <= 0
        ? 1.0
        : (current / next.days).clamp(0.0, 1.0);
    final stage = dugtongStageFor(current);
    final evolveAt = _nextStage(current);
    final ring = layout.ring;
    final ringIn = _phase(0, 700, Curves.easeOutCubic);
    return SizedBox(
      width: math.max(ring + 120, 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            image: true,
            label: d == null
                ? 'Current streak: unknown'
                : 'Current streak: $current ${current == 1 ? 'day' : 'days'}',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: ring,
              child: AnimatedBuilder(
                animation: ringIn,
                builder: (context, _) => CustomPaint(
                  painter: _RingPainter(
                    progress: progress * ringIn.value,
                    disc: p.surface.withValues(alpha: 0.8),
                    track: p.border.withValues(alpha: 0.6),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d == null
                              ? '–'
                              : '${(current * ringIn.value).round()}',
                          style: TextStyle(
                            fontSize: 44 * layout.s,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: p.foreground,
                          ),
                        ),
                        Text(
                          current == 0 ? 'Start your streak' : 'DAY STREAK',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: current == 0 ? 0.2 : 1.2,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: p.accentBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.primaryBorder),
            ),
            child: Text(
              '${stage.stageName} · Stage ${stage.index + 1} of 8',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: p.primaryText,
              ),
            ),
          ),
          if (layout.showEvolve && evolveAt != null) ...[
            const SizedBox(height: 4),
            _Frosted(
              child: Text(
                'Evolves in ${evolveAt - current} '
                '${evolveAt - current == 1 ? 'day' : 'days'}',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Bottom panel ──────────────────────────────────────────────────────

  Widget _panel(StreakHomeLayout layout, StreakData? d) {
    final p = context.palette;
    final slide = _phase(250, 650, Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: slide,
      builder: (context, child) => Opacity(
        opacity: slide.value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - slide.value)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.border),
          boxShadow: p.shadow,
        ),
        child: LayoutBuilder(
          builder: (context, box) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              child: d == null ? _panelEmpty() : _panelContent(d),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelEmpty() {
    final p = context.palette;
    if (_refreshing) {
      return SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: p.primaryText)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Couldn't load your streak",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: p.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Check your connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: p.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 180,
          child: PrimaryButton(label: 'Try Again', onTap: _refresh),
        ),
      ],
    );
  }

  Widget _panelContent(StreakData d) {
    final p = context.palette;
    Widget tile(int i, Widget child) {
      final fade = _phase(300 + i * 80.0, 650 + i * 80.0);
      return Expanded(
        child: FadeTransition(opacity: fade, child: child),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            tile(
              0,
              _StatTile(
                icon: Icons.emoji_events_rounded,
                tint: p.orange,
                tintBg: p.orangeBg,
                value: '${d.longest}',
                label: 'Best streak',
                semantics:
                    'Best streak, ${d.longest} ${d.longest == 1 ? 'day' : 'days'}',
              ),
            ),
            const SizedBox(width: 10),
            tile(
              1,
              _StatTile(
                icon: Icons.calendar_month_rounded,
                tint: p.info,
                tintBg: p.infoBg,
                value: '${d.totalCheckins}',
                label: 'Total days',
                semantics:
                    'Total days, ${d.totalCheckins} ${d.totalCheckins == 1 ? 'day' : 'days'}',
              ),
            ),
            const SizedBox(width: 10),
            tile(
              2,
              _StatTile(
                icon: Icons.ac_unit_rounded,
                tint: p.info,
                tintBg: p.infoBg,
                value: d.freezeAvailable ? 'Ready' : 'Recharging',
                valueColor: d.freezeAvailable ? p.successDark : p.warningText,
                label: 'Streak Freeze',
                semantics:
                    'Streak Freeze, ${d.freezeAvailable ? 'Ready' : 'Recharging'}',
                onTap: _showFreezeInfo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FadeTransition(
          opacity: _phase(520, 900),
          child: NextRewardRow(data: d, initials: _initials, grow: _intro),
        ),
      ],
    );
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────

/// A 44 px round button over the scene (48 px to tap).
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: _CircleFace(icon: icon, busy: busy),
          ),
        ),
      ),
    ),
  );
}

class _CircleFace extends StatelessWidget {
  final IconData icon;
  final bool busy;
  const _CircleFace({required this.icon, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surface.withValues(alpha: 0.78),
        border: Border.all(color: p.border),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: p.foreground,
              ),
            )
          : Icon(icon, size: 20, color: p.foreground),
    );
  }
}

/// Text over the scene sits on a frosted pill so it reads in both modes.
class _Frosted extends StatelessWidget {
  final Widget child;
  const _Frosted({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: context.palette.surface.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint, tintBg;
  final String value, label, semantics;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _StatTile({
    required this.icon,
    required this.tint,
    required this.tintBg,
    required this.value,
    required this.label,
    required this.semantics,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: valueColor ?? p.foreground,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: body,
              ),
            ),
    );
  }
}

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
        child: CircleAvatar(
          radius: 16,
          backgroundColor: kCrimson,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
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

/// The count's progress ring on a frosted disc.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color disc, track;
  const _RingPainter({
    required this.progress,
    required this.disc,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = disc);
    const stroke = 9.0;
    final arcRect = Rect.fromCircle(center: c, radius: r - stroke / 2 - 4);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: AppColors.primaryGradient,
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(arcRect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.disc != disc || old.track != track;
}
