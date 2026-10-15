import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show appNavigatorKey;
import '../shared_design.dart';
import 'avatar_frame.dart';
import 'blood_bag_mascot.dart';
import 'mascot_stage_art.dart';
import 'streak_controller.dart';
import 'streak_particles.dart';
import 'streak_ladder_screen.dart' show badgeVisualFor;
import 'streak_share.dart';

const Color _kGold = Color(0xFFFFD54F);

/// Progress 0..1 of [ms] between [a] and [b], eased.
double _seg(double ms, double a, double b, [Curve curve = Curves.linear]) {
  if (b <= a) return ms >= b ? 1 : 0;
  return curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));
}

/// Shows the full-screen celebration for [event]. [origin] is where the
/// floating bubble was, so the mascot can fly out of it. Completes when the
/// celebration is closed.
Future<void> showMilestoneCelebration({
  required StreakCelebration event,
  required Offset origin,
}) async {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  await showGeneralDialog<void>(
    context: ctx,
    barrierDismissible: false,
    barrierLabel: 'Celebration',
    barrierColor: Colors.black.withValues(alpha: 0.88),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) =>
        MilestoneCelebration(event: event, origin: origin),
    transitionBuilder: (_, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.94,
          end: 1,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class MilestoneCelebration extends StatefulWidget {
  final StreakCelebration event;
  final Offset origin;

  const MilestoneCelebration({
    super.key,
    required this.event,
    required this.origin,
  });

  @override
  State<MilestoneCelebration> createState() => _MilestoneCelebrationState();
}

class _MilestoneCelebrationState extends State<MilestoneCelebration>
    with TickerProviderStateMixin {
  // One clock for the whole show; every phase is a function of its time in ms.
  late final AnimationController _clock;
  late final List<Particle> _spiral;
  late final List<Particle> _confetti;
  // Runs for the first 1.5 s: taps are ignored until it completes, and it
  // drives the card fade in reduced-motion mode.
  late final AnimationController _guard;

  bool _reduce = false;
  bool _started = false;
  bool _firedCharge = false;
  bool _firedBurst = false;
  String _initials = '?';
  bool _equipBusy = false;
  bool _shareBusy = false;
  String? _error;

  StreakCelebration get _event => widget.event;
  bool get _isVerified => _event.isVerifiedFrame;
  bool get _evolves => _event.evolved;
  bool get _hasMascot => !_isVerified;

  // Timeline (ms).
  double get _rewardStart => _isVerified ? 900 : (_evolves ? 2600 : 1100);
  double get _burstAt => _isVerified ? 700 : (_evolves ? 1600 : 900);
  double get _total => _rewardStart + 3600;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _total.round()),
    )..addListener(_onTick);
    _spiral = generateParticles(
      seed: _event.streak * 31 + 7,
      count: 36,
      palette: const [
        Color(0xFFFF8FA3),
        Color(0xFFFFE082),
        Colors.white,
        Color(0xFFEF4444),
      ],
      shapes: const [
        ParticleShape.drop,
        ParticleShape.sparkle,
        ParticleShape.heart,
      ],
      sizeMin: 5,
      sizeMax: 9,
      lifeMin: 0.7,
      lifeMax: 0.95,
      delayMax: 0.05,
      radiusMin: 90,
      radiusMax: 190,
    );
    _confetti = generateParticles(
      seed: _event.streak * 17 + _event.key.length,
      count: 70,
      palette: const [
        Color(0xFFDC2626),
        Color(0xFFFF8FA3),
        Color(0xFFFFD54F),
        Colors.white,
        Color(0xFF80DEEA),
      ],
      shapes: const [
        ParticleShape.drop,
        ParticleShape.star,
        ParticleShape.rect,
        ParticleShape.rect,
      ],
      speedMin: 140,
      speedMax: 420,
      sizeMin: 7,
      sizeMax: 14,
      lifeMin: 2.2,
      lifeMax: 3.2,
      delayMax: 0.25,
    );
    _guard = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _loadName();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduce) {
      _clock.value = 1;
    } else if (!_started) {
      _started = true;
      _clock.forward();
    }
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('userName') ?? '';
    if (mounted) setState(() => _initials = streakInitials(name));
  }

  void _onTick() {
    final ms = _clock.value * _total;
    if (_evolves && !_firedCharge && ms >= 800) {
      _firedCharge = true;
      HapticFeedback.mediumImpact();
    }
    if (!_firedBurst && ms >= _burstAt) {
      _firedBurst = true;
      if (_evolves) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _guard.dispose();
    super.dispose();
  }

  bool get _canTap => _guard.isCompleted;

  void _close() => Navigator.of(context).pop();

  Future<void> _equip() async {
    if (!_canTap || _equipBusy) return;
    setState(() {
      _equipBusy = true;
      _error = null;
    });
    final result = await StreakController.instance.setFrame(_event.key);
    if (!mounted) return;
    if (result.ok) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      _close();
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${_event.label} equipped!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      setState(() {
        _equipBusy = false;
        _error = result.message ?? "Couldn't equip it right now. Try again.";
      });
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (!_canTap || _shareBusy) return;
    final origin = shareOriginFor(buttonContext);
    setState(() {
      _shareBusy = true;
      _error = null;
    });
    try {
      await shareStreak(
        context,
        streak: _event.streak,
        stage: _event.newStage,
        origin: origin,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = "Couldn't create the share image. Please try again.",
        );
      }
    }
    if (mounted) setState(() => _shareBusy = false);
  }

  void _onBackdropTap() {
    if (_canTap) _close();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: AnimatedBuilder(
      animation: Listenable.merge([_clock, _guard]),
      builder: (context, _) {
        final ms = _reduce ? _total : _clock.value * _total;
        return LayoutBuilder(
          builder: (context, c) {
            final size = c.biggest;
            final center = Offset(size.width / 2, size.height * 0.33);
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onBackdropTap,
                  ),
                ),
                if (!_reduce)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _FxPainter(
                            ms: ms,
                            center: center,
                            evolves: _evolves,
                            hasMascot: _hasMascot,
                            burstAt: _burstAt,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_reduce && ms >= 800 && ms < 1650 && _evolves)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: ParticlePainter(
                            particles: _spiral,
                            mode: ParticleMode.spiralIn,
                            time: (ms - 800) / 1000,
                            origin: center,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_reduce && _hasMascot) _mascot(ms, center),
                if (!_reduce && _isVerified) _verifiedEmblem(ms, center),
                if (!_reduce && ms >= _burstAt)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: ParticlePainter(
                            particles: _confetti,
                            mode: ParticleMode.burst,
                            time: (ms - _burstAt) / 1000,
                            origin: center,
                            gravity: 420,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_reduce && _evolves) _evolvedText(ms, center),
                _card(ms, size),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _mascot(double ms, Offset center) {
    const base = 140.0;
    final fly = _seg(ms, 0, 800, Curves.easeOutCubic);
    var pos = Offset.lerp(widget.origin, center, fly)!;
    var scale = (58 / base) + (1 - 58 / base) * fly;

    final charging = _evolves && ms >= 800 && ms < 1600;
    if (charging) {
      final p = _seg(ms, 800, 1600);
      pos += Offset(
        math.sin(ms * 0.12) * (2 + 6 * p),
        math.cos(ms * 0.15) * (1 + 3 * p),
      );
    }

    final MascotMood mood = charging
        ? MascotMood.dragging
        : MascotMood.celebrate;
    final streak = _event.streak;

    Widget mascot(
      MascotStage stage, {
      int? rollFrom,
      double roll = 1,
      int? showStreak,
    }) => BloodBagMascot(
      size: base,
      streak: showStreak ?? streak,
      stage: stage,
      mood: mood,
      rollFrom: rollFrom,
      rollProgress: roll,
    );

    Widget body;
    if (_evolves) {
      final evo = _seg(ms, 1600, 2000);
      final pop = 1 + 0.25 * math.sin(math.pi * _seg(ms, 1600, 2300));
      scale *= pop;
      final oldStreak = streak > 0 ? streak - 1 : 0;
      body = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (evo < 1)
            Opacity(
              opacity: 1 - evo,
              child: mascot(_event.oldStage, showStreak: oldStreak),
            ),
          if (evo > 0)
            Opacity(
              opacity: evo,
              child: mascot(
                _event.newStage,
                rollFrom: oldStreak,
                roll: _seg(ms, 1700, 2300),
              ),
            ),
        ],
      );
    } else {
      body = mascot(_event.newStage);
    }

    return Positioned(
      left: pos.dx - base / 2,
      top: pos.dy - base / 2,
      width: base,
      height: base,
      child: IgnorePointer(
        child: Transform.scale(scale: scale, child: body),
      ),
    );
  }

  Widget _verifiedEmblem(double ms, Offset center) {
    final pop = Curves.elasticOut.transform(_seg(ms, 0, 900));
    return Positioned(
      left: center.dx - 60,
      top: center.dy - 60,
      width: 120,
      height: 120,
      child: IgnorePointer(
        child: Transform.scale(
          scale: pop,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.6),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.verified_rounded,
              size: 76,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _evolvedText(double ms, Offset center) {
    final t = _seg(ms, 1850, 2350, Curves.easeOutCubic);
    final t2 = _seg(ms, 2050, 2550, Curves.easeOutCubic);
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(36, center.dy - 168),
      child: IgnorePointer(
        child: Column(
          children: [
            Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 28 * (1 - t)),
                child: const Text(
                  'Evolved!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    shadows: [Shadow(color: _kGold, blurRadius: 22)],
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: t2,
              child: Transform.translate(
                offset: Offset(0, 22 * (1 - t2)),
                child: Text(
                  _event.newStage.stageName,
                  style: const TextStyle(
                    color: _kGold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Reward card ────────────────────────────────────────────────────────

  String get _title => switch (_event.kind) {
    CelebrationKind.frame =>
      _isVerified
          ? 'Verified Donor frame unlocked'
          : 'New frame unlocked: ${_event.label}',
    CelebrationKind.badge => 'Badge unlocked: ${_event.label}',
    CelebrationKind.evolution =>
      'You evolved into ${_event.newStage.stageName}!',
  };

  Widget _card(double ms, Size size) {
    final r = ms - _rewardStart;
    final slide = _reduce ? 1.0 : _seg(r, 0, 520, Curves.easeOutBack);
    final opacity = _reduce ? 1.0 : _seg(r, 0, 220);
    final textIn = _reduce ? 1.0 : _seg(r, 600, 1000);
    final buttonsIn = _reduce ? 1.0 : _seg(r, 700, 1100);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: _reduce ? _fadeIn(ms) : opacity,
        child: Transform.translate(
          offset: Offset(0, (1 - slide) * 460),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _rewardVisual(r),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: textIn,
                    child: Column(
                      children: [
                        Text(
                          _title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: kTextPrimary,
                          ),
                        ),
                        if (_event.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _event.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kTextMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: kCrimson),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Opacity(opacity: buttonsIn, child: _buttons()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Reduced motion: just fade the card in.
  double _fadeIn(double ms) => (_guard.value * 1500 / 400).clamp(0.0, 1.0);

  Widget _avatar(double radius) => CircleAvatar(
    radius: radius,
    backgroundColor: kCrimson,
    child: Text(
      _initials,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.7,
      ),
    ),
  );

  Widget _rewardVisual(double r) {
    const box = 96.0;
    switch (_event.kind) {
      case CelebrationKind.frame:
        // The lock opens, then the frame draws itself around the avatar.
        final open = _reduce ? 1.0 : _seg(r, 450, 1150, Curves.easeInOut);
        final swap = _reduce || _isVerified ? 1.0 : _seg(r, 1150, 1350);
        final drawStart = _isVerified ? 300.0 : 1200.0;
        final draw = _reduce
            ? 1.0
            : _seg(r, drawStart, drawStart + 800, Curves.easeInOutCubic);
        final shimmerT = _reduce ? 0.0 : (r - (drawStart + 800)) / 700;
        final shake = (r > 250 && r < 450) ? math.sin(r * 0.6) * 0.12 : 0.0;
        return SizedBox(
          width: box,
          height: box,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!_isVerified && swap < 1)
                Opacity(
                  opacity: 1 - swap,
                  child: Transform.rotate(
                    angle: shake,
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: CustomPaint(painter: _LockPainter(open: open)),
                    ),
                  ),
                ),
              if (swap > 0)
                Opacity(
                  opacity: swap,
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * swap,
                    child: StreakAvatarFrame(
                      frameKey: _event.key,
                      radius: 34,
                      drawProgress: draw,
                      shimmer: shimmerT > 0 && shimmerT < 1 ? shimmerT : null,
                      child: _avatar(34),
                    ),
                  ),
                ),
            ],
          ),
        );
      case CelebrationKind.badge:
        final (icon, color) = badgeVisualFor(_event.key, _event.streak);
        final pop = _reduce
            ? 1.0
            : Curves.elasticOut.transform(_seg(r, 300, 1100));
        return SizedBox(
          width: box,
          height: box,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!_reduce)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SparklesPainter(_seg(r, 350, 1500), color),
                  ),
                ),
              Transform.scale(
                scale: pop,
                child: Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                  ),
                  child: Icon(icon, size: 42, color: color),
                ),
              ),
            ],
          ),
        );
      case CelebrationKind.evolution:
        final pop = _reduce
            ? 1.0
            : Curves.elasticOut.transform(_seg(r, 300, 1100));
        return Transform.scale(
          scale: pop,
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 56,
            color: kCrimson,
          ),
        );
    }
  }

  Widget _buttons() {
    final isFrame = _event.kind == CelebrationKind.frame;
    final enabled = !_equipBusy;

    Widget share() => Builder(
      builder: (btnContext) => OutlinedButton(
        onPressed: _shareBusy ? null : () => _share(btnContext),
        style: OutlinedButton.styleFrom(
          foregroundColor: kCrimson,
          side: const BorderSide(color: kCrimson, width: 1.3),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _shareBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: kCrimson,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ios_share_rounded, size: 17),
                  SizedBox(width: 5),
                  Text('Share', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );

    return IgnorePointer(
      ignoring: !_canTapNow,
      child: Row(
        children: [
          if (isFrame) ...[
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: enabled ? _equip : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCrimson,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kCrimson.withValues(alpha: 0.7),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _equipBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Equip now',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(flex: 3, child: share()),
          const SizedBox(width: 8),
          Expanded(
            flex: isFrame ? 3 : 4,
            child: TextButton(
              onPressed: _equipBusy ? null : _close,
              style: TextButton.styleFrom(
                foregroundColor: kTextMuted,
                minimumSize: const Size(0, 48),
              ),
              child: Text(
                isFrame ? 'Later' : 'Great!',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canTapNow => _canTap;
}

// ─── Effects drawn behind and over the mascot ──────────────────────────────

class _FxPainter extends CustomPainter {
  final double ms;
  final Offset center;
  final bool evolves;
  final bool hasMascot;
  final double burstAt;

  const _FxPainter({
    required this.ms,
    required this.center,
    required this.evolves,
    required this.hasMascot,
    required this.burstAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Rotating light rays behind the centre.
    final rayAlpha = _seg(ms, 0, 800) * 0.9;
    if (rayAlpha > 0) {
      final reach = size.longestSide;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE082).withValues(alpha: 0.5 * rayAlpha),
            const Color(0xFFFFE082).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: reach * 0.8));
      const rays = 14;
      final half = math.pi / rays * 0.5;
      final rot = ms * 0.00035;
      for (var i = 0; i < rays; i++) {
        final a = rot + i * 2 * math.pi / rays;
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..lineTo(
              center.dx + math.cos(a - half) * reach,
              center.dy + math.sin(a - half) * reach,
            )
            ..lineTo(
              center.dx + math.cos(a + half) * reach,
              center.dy + math.sin(a + half) * reach,
            )
            ..close(),
          paint,
        );
      }
    }

    // Charge-up glow behind the mascot.
    if (evolves && ms >= 800 && ms < 2000) {
      final p = ms < 1600 ? _seg(ms, 800, 1600) : 1 - _seg(ms, 1600, 2000);
      final radius = 80 + 110 * p;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.2 + 0.6 * p),
              const Color(0xFFFFD54F).withValues(alpha: 0.35 * p),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Shock ring when the mascot evolves.
    if (evolves && ms >= 1600 && ms < 2300) {
      final p = _seg(ms, 1600, 2300, Curves.easeOutCubic);
      canvas.drawCircle(
        center,
        40 + 360 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 * (1 - p) + 1
          ..color = Colors.white.withValues(alpha: 0.85 * (1 - p)),
      );
    }

    // White flash right before the new form appears.
    if (evolves && ms >= 1450 && ms < 2000) {
      final a = ms < 1600 ? _seg(ms, 1450, 1600) : 1 - _seg(ms, 1600, 2000);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) =>
      old.ms != ms || old.center != center;
}

/// A gold padlock whose shackle lifts and swings open.
class _LockPainter extends CustomPainter {
  final double open;
  const _LockPainter({required this.open});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bodyTop = h * 0.46;

    canvas.save();
    // Pivot on the right leg so the shackle swings out as it lifts.
    canvas.translate(w * 0.66, bodyTop);
    canvas.rotate(-0.5 * open);
    canvas.translate(-w * 0.66, -bodyTop);
    canvas.translate(0, -h * 0.16 * open);
    final shackle = Path()
      ..moveTo(w * 0.34, bodyTop + h * 0.1)
      ..lineTo(w * 0.34, h * 0.3)
      ..arcToPoint(
        Offset(w * 0.66, h * 0.3),
        radius: Radius.circular(w * 0.16),
        clockwise: true,
      )
      ..lineTo(w * 0.66, bodyTop + h * 0.1);
    canvas.drawPath(
      shackle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.1
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF94A3B8),
    );
    canvas.restore();

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, bodyTop, w * 0.6, h * 0.42),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE082), Color(0xFFB8860B)],
        ).createShader(body.outerRect),
    );
    canvas.drawCircle(
      Offset(w * 0.5, bodyTop + h * 0.15),
      w * 0.06,
      Paint()..color = const Color(0xFF5B3A00),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, bodyTop + h * 0.24),
          width: w * 0.05,
          height: h * 0.12,
        ),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = const Color(0xFF5B3A00),
    );
  }

  @override
  bool shouldRepaint(covariant _LockPainter old) => old.open != open;
}

class _SparklesPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _SparklesPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final c = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + 0.3;
      final dist = 30 + 22 * progress;
      final r = 7 * math.sin(math.pi * progress);
      artSparkle(
        canvas,
        c + Offset(math.cos(a), math.sin(a)) * dist,
        r,
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklesPainter old) =>
      old.progress != progress;
}
