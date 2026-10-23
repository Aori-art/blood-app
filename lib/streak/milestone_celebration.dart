import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:blood/app_colors.dart';
import 'package:flutter/services.dart';

import '../main.dart' show appNavigatorKey;
import '../shared_design.dart';
import 'avatar_frame.dart';
import 'dugtong.dart';
import 'dugtong_stage_art.dart';
import 'streak_controller.dart';
import 'streak_particles.dart';
import 'streak_ladder_screen.dart' show badgeVisualFor;
import 'streak_share.dart';
import '../app_palette.dart';
import '../my_avatar.dart';

const Color _kGold = Color(0xFFFFD54F);

/// Progress 0..1 of [ms] between [a] and [b], eased.
double _seg(double ms, double a, double b, [Curve curve = Curves.linear]) {
  if (b <= a) return ms >= b ? 1 : 0;
  return curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));
}

/// Shows the full-screen celebration for [event]. [origin] is where the
/// floating bubble was, so Dugtong can fly out of it. Completes when the
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

/// When each phase of one celebration starts and ends, in milliseconds.
///
///   A. count splash   [0, aEnd]       (only when the streak hit a ladder day)
///   B. evolution      [b0, bEnd]      (only when Dugtong changed stage)
///   C. reward reveal  [cStart, total] (only when a badge or frame is new)
///
/// A celebration without a reward closes itself when its last phase is done.
class CelebrationTimeline {
  final bool hasA;
  final bool hasB;
  final bool hasC;
  final bool verified;

  /// Dugtong flies out of the bubble over this long.
  final double fly;
  final double aEnd;
  final double b0;
  final double bEnd;
  final double cStart;

  /// When the reward's confetti goes off.
  final double burstC;
  final double total;

  const CelebrationTimeline._({
    required this.hasA,
    required this.hasB,
    required this.hasC,
    required this.verified,
    required this.fly,
    required this.aEnd,
    required this.b0,
    required this.bEnd,
    required this.cStart,
    required this.burstC,
    required this.total,
  });

  /// Length of the count splash.
  static const double countMs = 2800;

  /// Taps skip the count splash only after this long.
  static const double skipAfterMs = 800;

  factory CelebrationTimeline.of(StreakCelebration e) {
    final verified = e.isVerifiedFrame;
    final hasA = e.hasCount && !verified;
    final hasB = e.evolved && !verified;
    final hasC = e.hasReward;
    final fly = hasA ? 450.0 : 800.0;
    final aEnd = hasA ? countMs : 0.0;
    final b0 = hasA ? aEnd : fly;
    final bEnd = hasB ? b0 + 1800 : b0;
    final cStart = verified ? 900.0 : (hasB ? bEnd : (hasA ? aEnd : 1100.0));
    final burstC = hasB
        ? b0 + 800
        : (verified ? 700.0 : (hasA ? aEnd + 100 : 900.0));
    final total = hasC
        ? cStart + 3600
        : (hasB ? bEnd + 1500 : (hasA ? aEnd : 1500.0));
    return CelebrationTimeline._(
      hasA: hasA,
      hasB: hasB,
      hasC: hasC,
      verified: verified,
      fly: fly,
      aEnd: aEnd,
      b0: b0,
      bEnd: bEnd,
      cStart: cStart,
      burstC: burstC,
      total: total,
    );
  }
}

class _Burst {
  final double at;
  final List<Particle> particles;
  final double gravity;
  const _Burst(this.at, this.particles, this.gravity);
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
  static const double _base = 200; // Dugtong's size on this screen
  static const List<Color> _confettiColors = [
    AppColors.primary,
    Color(0xFFFF8FA3),
    Color(0xFFFFD54F),
    Colors.white,
    Color(0xFF80DEEA),
  ];

  // One clock for the whole show; every phase is a function of its time in ms.
  late final AnimationController _clock;
  late final CelebrationTimeline _t = CelebrationTimeline.of(widget.event);
  late final List<Particle> _spiral;
  late final List<_Burst> _bursts;
  // Runs for the first 1.5 s: in reduced-motion mode it fades the card in and
  // taps are ignored until it completes.
  late final AnimationController _guard;

  bool _reduce = false;
  bool _started = false;
  bool _closed = false;
  bool _hapticLand = false;
  bool _hapticCharge = false;
  bool _hapticBurst = false;
  bool _hapticReveal = false;
  bool _equipBusy = false;
  bool _shareBusy = false;
  String? _error;

  StreakCelebration get _event => widget.event;
  bool get _isVerified => _event.isVerifiedFrame;
  bool get _hasDugtong => !_isVerified;
  double get _ms => _reduce ? _t.total : _clock.value * _t.total;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _t.total.round()),
    )..addListener(_onTick);
    _clock.addStatusListener((status) {
      // No reward to wait for: the overlay closes itself when it is done.
      // (Reduced motion has no timeline: the clock only jumps to its end, and
      // the donor closes it with the button.)
      if (_reduce) return;
      if (status == AnimationStatus.completed && !_t.hasC) _close();
    });
    _spiral = generateParticles(
      seed: _event.streak * 31 + 7,
      count: 36,
      palette: const [
        Color(0xFFFF8FA3),
        Color(0xFFFFE082),
        Colors.white,
        AppColors.primary,
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
    _bursts = [
      if (_t.hasA) ...[
        // Blood drops, hearts and stars when the number lands, then a second,
        // smaller shower.
        _Burst(
          850,
          generateParticles(
            seed: _event.streak * 13 + 5,
            count: 56,
            palette: _confettiColors,
            shapes: const [
              ParticleShape.drop,
              ParticleShape.heart,
              ParticleShape.star,
            ],
            speedMin: 140,
            speedMax: 400,
            sizeMin: 8,
            sizeMax: 15,
            lifeMin: 1.6,
            lifeMax: 2.4,
            delayMax: 0.2,
          ),
          380,
        ),
        _Burst(
          1650,
          generateParticles(
            seed: _event.streak * 29 + 3,
            count: 36,
            palette: _confettiColors,
            shapes: const [
              ParticleShape.heart,
              ParticleShape.drop,
              ParticleShape.star,
            ],
            speedMin: 100,
            speedMax: 300,
            sizeMin: 7,
            sizeMax: 12,
            lifeMin: 1.4,
            lifeMax: 2.0,
            delayMax: 0.2,
          ),
          340,
        ),
      ],
      if (_t.hasB || (_t.hasC && !_t.hasA))
        _Burst(
          _t.burstC,
          generateParticles(
            seed: _event.streak * 17 + _event.key.length,
            count: 70,
            palette: _confettiColors,
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
          ),
          420,
        ),
      if (_t.hasC && _t.hasA && !_t.hasB)
        _Burst(
          _t.burstC,
          generateParticles(
            seed: _event.streak * 7 + _event.key.length,
            count: 60,
            palette: _confettiColors,
            shapes: const [
              ParticleShape.drop,
              ParticleShape.star,
              ParticleShape.rect,
              ParticleShape.rect,
            ],
            speedMin: 140,
            speedMax: 400,
            sizeMin: 7,
            sizeMax: 13,
            lifeMin: 2.0,
            lifeMax: 3.0,
            delayMax: 0.25,
          ),
          420,
        ),
    ];
    _guard = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      // Real time even with reduced motion (which would otherwise shrink it to
      // a few milliseconds): this is the tap guard.
      animationBehavior: AnimationBehavior.preserve,
    )..forward();
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


  void _onTick() {
    final ms = _clock.value * _t.total;
    if (_t.hasA && !_hapticLand && ms >= 700) {
      _hapticLand = true;
      HapticFeedback.mediumImpact();
    }
    if (_t.hasB && !_hapticCharge && ms >= _t.b0) {
      _hapticCharge = true;
      HapticFeedback.mediumImpact();
    }
    if (_t.hasB && !_hapticBurst && ms >= _t.b0 + 800) {
      _hapticBurst = true;
      HapticFeedback.heavyImpact();
    }
    if (_t.hasC && !_t.hasB && !_hapticReveal && ms >= _t.burstC) {
      _hapticReveal = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _guard.dispose();
    super.dispose();
  }

  // ─── Taps ───────────────────────────────────────────────────────────────

  bool get _inReward => _t.hasC && _ms >= _t.cStart;

  // The reward card can be dismissed once it has had time to be read; its
  // buttons come alive a little after it appears.
  bool get _canTap {
    if (_reduce) return _guard.isCompleted;
    final ms = _ms;
    if (_inReward) return ms >= _t.cStart + 800;
    return true;
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  // A tap during the count splash or the evolution jumps to the next phase,
  // or closes the overlay when nothing follows.
  void _skipTo(double? ms) {
    if (ms == null) {
      _close();
      return;
    }
    _clock.forward(from: (ms / _t.total).clamp(0.0, 1.0));
  }

  void _onBackdropTap() {
    if (_reduce) {
      if (_canTap && !_t.hasC) _close();
      if (_canTap && _t.hasC) _close();
      return;
    }
    final ms = _ms;
    if (_inReward) {
      if (_canTap) _close();
      return;
    }
    if (_t.hasA && ms < _t.aEnd) {
      if (ms >= CelebrationTimeline.skipAfterMs) {
        _skipTo(_t.hasB ? _t.b0 : (_t.hasC ? _t.cStart : null));
      }
      return;
    }
    if (_t.hasB && ms < _t.bEnd) {
      if (ms >= _t.b0 + CelebrationTimeline.skipAfterMs) {
        _skipTo(_t.hasC ? _t.cStart : null);
      }
      return;
    }
    // Reward-less ending, or the moment before the reward card.
    if (!_t.hasC && ms >= _t.bEnd + CelebrationTimeline.skipAfterMs) _close();
  }

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

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: AnimatedBuilder(
      animation: Listenable.merge([_clock, _guard]),
      builder: (context, _) {
        final ms = _ms;
        return LayoutBuilder(
          builder: (context, c) {
            final size = c.biggest;
            final center = Offset(size.width / 2, size.height * 0.31);
            if (_reduce) return _reducedLayout(size, center);
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
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _FxPainter(ms: ms, center: center, t: _t),
                      ),
                    ),
                  ),
                ),
                if (_t.hasB && ms >= _t.b0 && ms < _t.b0 + 850)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: ParticlePainter(
                            particles: _spiral,
                            mode: ParticleMode.spiralIn,
                            time: (ms - _t.b0) / 1000,
                            origin: center,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_hasDugtong) _dugtong(ms, center),
                if (_isVerified) _verifiedEmblem(ms, center),
                for (final burst in _bursts)
                  if (ms >= burst.at && ms < burst.at + 3600)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: ParticlePainter(
                              particles: burst.particles,
                              mode: ParticleMode.burst,
                              time: (ms - burst.at) / 1000,
                              origin: center,
                              gravity: burst.gravity,
                            ),
                          ),
                        ),
                      ),
                    ),
                if (_t.hasA) _dayText(ms, center),
                if (_t.hasB) _evolvedText(ms, center),
                if (_t.hasC) _card(ms, size),
              ],
            );
          },
        );
      },
    ),
  );

  // Reduced motion: no flying, shaking or confetti. A still picture of what
  // happened, then the reward card (or a single button) once the guard is up.
  Widget _reducedLayout(Size size, Offset center) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onBackdropTap,
          ),
        ),
        if (_hasDugtong)
          Positioned(
            left: center.dx - _base / 2,
            top: center.dy - _base / 2,
            width: _base,
            height: _base,
            child: IgnorePointer(
              child: Dugtong(
                size: _base,
                streak: _event.streak,
                stage: _event.newStage,
                mood: DugtongMood.celebrate,
              ),
            ),
          ),
        if (_isVerified)
          Positioned(
            left: center.dx - 60,
            top: center.dy - 60,
            width: 120,
            height: 120,
            child: IgnorePointer(child: _verifiedBadge()),
          ),
        if (_t.hasA) _dayText(_t.total, center),
        if (_t.hasB) _evolvedText(_t.total, center),
        if (_t.hasC)
          _card(_t.total, size)
        else
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(40, 0, 40, 28 + bottom),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _guard.isCompleted ? _close : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCrimson,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kCrimson.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white70,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Great!',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Dugtong flies out of the bubble, jumps while the number rolls, charges up
  // and morphs when it evolves, then makes room for the reward card.
  Widget _dugtong(double ms, Offset center) {
    final t = _t;
    final fly = _seg(ms, 0, t.fly, Curves.easeOutCubic);
    var pos = Offset.lerp(widget.origin, center, fly)!;
    var scale = (58 / _base) + (1 - 58 / _base) * fly;

    // Two hops while the count lands.
    if (t.hasA && ms >= 650 && ms < 1300) {
      final u = _seg(ms, 650, 1300);
      pos += Offset(0, -46 * math.sin(2 * math.pi * u).abs());
    }
    // The number "pops" as it lands.
    if (t.hasA) scale *= 1 + 0.14 * math.sin(math.pi * _seg(ms, 1000, 1400));

    final charging = t.hasB && ms >= t.b0 && ms < t.b0 + 800;
    if (charging) {
      final p = _seg(ms, t.b0, t.b0 + 800);
      pos += Offset(
        math.sin(ms * 0.12) * (2 + 6 * p),
        math.cos(ms * 0.15) * (1 + 3 * p),
      );
    }

    // Shrink a little to share the screen with the reward card.
    if (t.hasC) {
      final from = (t.hasA || t.hasB) ? t.cStart - 250 : t.fly;
      final to = (t.hasA || t.hasB) ? t.cStart + 150 : t.cStart;
      scale *= 1 - 0.28 * _seg(ms, from, to, Curves.easeInOut);
    }

    final DugtongMood mood = charging
        ? DugtongMood.dragging
        : DugtongMood.celebrate;
    final streak = _event.streak;
    final rolling = t.hasA && ms < t.aEnd;

    Widget dugtong(
      DugtongStage stage, {
      int? rollFrom,
      double roll = 1,
      int? showStreak,
    }) => Dugtong(
      size: _base,
      streak: showStreak ?? streak,
      stage: stage,
      mood: mood,
      rollFrom: rollFrom,
      rollProgress: roll,
    );

    Widget body;
    if (t.hasB) {
      // A count splash already rolled the number; on its own, the evolution
      // rolls it as the new form appears.
      final evo = _seg(ms, t.b0 + 800, t.b0 + 1200);
      final pop =
          1 + 0.25 * math.sin(math.pi * _seg(ms, t.b0 + 800, t.b0 + 1500));
      scale *= pop;
      final oldStreak = (!t.hasA && streak > 0) ? streak - 1 : streak;
      body = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (evo < 1 || rolling)
            Opacity(
              opacity: rolling ? 1 : 1 - evo,
              child: dugtong(
                _event.oldStage,
                showStreak: rolling ? null : oldStreak,
                rollFrom: rolling ? _event.countFrom : null,
                roll: rolling ? _seg(ms, 600, 1300) : 1,
              ),
            ),
          if (evo > 0 && !rolling)
            Opacity(
              opacity: evo,
              child: dugtong(
                _event.newStage,
                rollFrom: t.hasA ? null : oldStreak,
                roll: t.hasA ? 1 : _seg(ms, t.b0 + 900, t.b0 + 1500),
              ),
            ),
        ],
      );
    } else if (t.hasA) {
      body = dugtong(
        rolling ? _event.oldStage : _event.newStage,
        rollFrom: rolling ? _event.countFrom : null,
        roll: rolling ? _seg(ms, 600, 1300) : 1,
      );
    } else {
      body = dugtong(_event.newStage);
    }

    return Positioned(
      left: pos.dx - _base / 2,
      top: pos.dy - _base / 2,
      width: _base,
      height: _base,
      child: IgnorePointer(
        child: Transform.scale(scale: scale, child: body),
      ),
    );
  }

  // "Day 3 streak!" under Dugtong while the count lands.
  Widget _dayText(double ms, Offset center) {
    final t = _seg(ms, 900, 1300, Curves.easeOutBack);
    final out = _t.hasC ? 1 - _seg(ms, _t.cStart - 200, _t.cStart + 100) : 1.0;
    final opacity = (_seg(ms, 900, 1200) * out).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      top: center.dy + _base * 0.62,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: Text(
              'Day ${_event.streak} streak!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(color: kCrimson, blurRadius: 24),
                  Shadow(color: Colors.black54, blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verifiedBadge() => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [AppColors.info, Color(0xFF06B6D4)],
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
    child: const Icon(Icons.verified_rounded, size: 76, color: Colors.white),
  );

  Widget _verifiedEmblem(double ms, Offset center) {
    final pop = Curves.elasticOut.transform(_seg(ms, 0, 900));
    return Positioned(
      left: center.dx - 60,
      top: center.dy - 60,
      width: 120,
      height: 120,
      child: IgnorePointer(
        child: Transform.scale(scale: pop, child: _verifiedBadge()),
      ),
    );
  }

  // "Evolved!" and the new stage's name slide in above Dugtong.
  Widget _evolvedText(double ms, Offset center) {
    final b0 = _t.b0;
    final t = _reduce
        ? 1.0
        : _seg(ms, b0 + 1050, b0 + 1550, Curves.easeOutCubic);
    final t2 = _reduce
        ? 1.0
        : _seg(ms, b0 + 1250, b0 + 1750, Curves.easeOutCubic);
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(36, center.dy - _base * 0.5 - 76),
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
                  textAlign: TextAlign.center,
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
    CelebrationKind.count => 'Day ${_event.streak} streak!',
  };

  Widget _card(double ms, Size size) {
    final r = ms - _t.cStart;
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
              decoration: BoxDecoration(
                color: context.palette.surface,
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.palette.foreground,
                          ),
                        ),
                        if (_event.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _event.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.palette.muted,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.primaryText,
                      ),
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

  // The donor's own photo (initials without one); the frame is drawn around
  // it by the reveal.
  Widget _avatar(double radius) => MyAvatar(radius: radius, showFrame: false);

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
        final (icon, color) = badgeVisualFor(
          context,
          _event.key,
          _event.streak,
        );
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
      case CelebrationKind.count:
        final pop = _reduce
            ? 1.0
            : Curves.elasticOut.transform(_seg(r, 300, 1100));
        return Transform.scale(
          scale: pop,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 56,
            color: context.palette.primaryText,
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
          foregroundColor: context.palette.primaryText,
          side: BorderSide(color: context.palette.primaryText, width: 1.3),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _shareBusy
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
                  Icon(Icons.ios_share_rounded, size: 17),
                  SizedBox(width: 5),
                  Text('Share', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );

    return IgnorePointer(
      ignoring: !_canTap,
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
                foregroundColor: context.palette.muted,
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
}

// ─── Effects drawn behind and over Dugtong ──────────────────────────────

class _FxPainter extends CustomPainter {
  final double ms;
  final Offset center;
  final CelebrationTimeline t;

  const _FxPainter({required this.ms, required this.center, required this.t});

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

    // Phase A: two shock rings pulse out as the number lands.
    if (t.hasA) {
      for (var i = 0; i < 2; i++) {
        final start = 700.0 + i * 350;
        if (ms < start || ms >= start + 1000) continue;
        final p = _seg(ms, start, start + 1000, Curves.easeOutCubic);
        canvas.drawCircle(
          center,
          60 + 300 * p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8 * (1 - p) + 1.5
            ..color = (i == 0 ? Colors.white : const Color(0xFFFF8FA3))
                .withValues(alpha: 0.85 * (1 - p)),
        );
      }
    }

    if (!t.hasB) return;
    final b0 = t.b0;

    // Phase B: charge-up glow behind Dugtong.
    if (ms >= b0 && ms < b0 + 1200) {
      final p = ms < b0 + 800
          ? _seg(ms, b0, b0 + 800)
          : 1 - _seg(ms, b0 + 800, b0 + 1200);
      final radius = 90 + 110 * p;
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

    // Shock ring when Dugtong evolves.
    if (ms >= b0 + 800 && ms < b0 + 1500) {
      final p = _seg(ms, b0 + 800, b0 + 1500, Curves.easeOutCubic);
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
    if (ms >= b0 + 650 && ms < b0 + 1200) {
      final a = ms < b0 + 800
          ? _seg(ms, b0 + 650, b0 + 800)
          : 1 - _seg(ms, b0 + 800, b0 + 1200);
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
