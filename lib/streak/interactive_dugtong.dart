import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'dugtong.dart';
import 'dugtong_chatter.dart' show DugtongSpeechBubble;

/// What Dugtong does when tapped.
enum DugtongReaction { jump, spin, wiggle, nod, flutter, squish, giggle }

const Map<DugtongReaction, List<String>> _reactionLines = {
  DugtongReaction.jump: ['Boing!', 'Up, up and away!'],
  DugtongReaction.spin: ['Wheee!', 'Round and round!'],
  DugtongReaction.wiggle: ['Hehe, that tickles!', 'Wiggle wiggle!'],
  DugtongReaction.nod: ["Yep, you've got this!", 'Mm-hm! Keep it up!'],
  DugtongReaction.flutter: ['Look at my cape go!', 'Feel the breeze!'],
  DugtongReaction.squish: ['Squish!', 'Careful, I am squishy!'],
  DugtongReaction.giggle: ['Hehe, that tickles!', 'Again, again!', 'Hehe!'],
};

const String _dizzyLine = 'Dizzy... too many taps!';

/// A big, playful Dugtong for the Streak Ladder.
///
/// * Hold and drag: it is picked up (a little bigger, with a soft shadow) and
///   follows the finger anywhere inside [limitKey]'s box and a little beyond,
///   with rubber-band resistance past the edge. Its eyes look where it is
///   going, its mouth becomes an "o" and it tilts with the speed.
/// * Release: it springs back home with a bouncy spring and a squash and
///   stretch. A fast fling makes it spin once on the way.
/// * Tap: a random reaction (jump, spin, wiggle, nod, flutter, squish or
///   giggle), usually with a line in a speech bubble.
/// * Five taps within 2.5 s make it dizzy for about 2 s.
///
/// With reduced motion it snaps home and reacts with words only.
class InteractiveDugtong extends StatefulWidget {
  final int streak;
  final DugtongStage? stage;
  final double size;
  final DugtongMood restingMood;

  /// Its drag area: Dugtong may go anywhere inside this widget's box, plus a
  /// little beyond. Without it, it can only wander a short way from home.
  final GlobalKey? limitKey;

  /// False: taps still play a reaction but show no line of their own (the
  /// host shows its own words, see [onTapped]).
  final bool speaks;

  /// Called after every tap (not after a drag).
  final VoidCallback? onTapped;

  /// Where the eyes look while nobody holds it (each axis -1..1). Null keeps
  /// the idle drift.
  final Offset? restingLook;

  /// Test hooks.
  final math.Random? random;
  final DateTime Function()? clock;

  const InteractiveDugtong({
    super.key,
    required this.streak,
    this.stage,
    this.size = 110,
    this.restingMood = DugtongMood.idle,
    this.limitKey,
    this.speaks = true,
    this.onTapped,
    this.restingLook,
    this.random,
    this.clock,
  });

  @override
  State<InteractiveDugtong> createState() => InteractiveDugtongState();
}

class InteractiveDugtongState extends State<InteractiveDugtong>
    with TickerProviderStateMixin {
  // Tuning.
  static const double _tapSlop = 8;
  static const Duration _tapMaxHold = Duration(milliseconds: 450);
  static const double _flingSpeed = 900;
  static const double _bandReach = 36;
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 12,
  );

  late final math.Random _rand = widget.random ?? math.Random();
  DateTime _now() => (widget.clock ?? DateTime.now)();

  late final AnimationController _pick; // 0 = on the ground, 1 = held
  late final AnimationController _react; // tap reaction, 0..1
  late final AnimationController _spin; // fling spin, 0..1
  late final Ticker _springTicker;

  // Where Dugtong is, relative to home.
  Offset _offset = Offset.zero;
  Offset _look = Offset.zero;
  double _tilt = 0;
  Offset _velocity = Offset.zero; // px/s, for the squash and stretch

  // Pointer.
  int? _pointer;
  Offset _downAt = Offset.zero;
  Offset _offsetAtDown = Offset.zero;
  DateTime _downTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _moved = false;
  VelocityTracker? _tracker;

  // Spring back.
  SpringSimulation? _simX;
  SpringSimulation? _simY;
  Duration _springStart = Duration.zero;

  // Reactions.
  DugtongReaction? _reaction;
  DugtongReaction? _lastReaction;
  final List<DateTime> _taps = [];
  bool _dizzy = false;
  Timer? _dizzyTimer;

  // Speech.
  String? _line;
  bool _lineShowing = false;
  Timer? _lineTimer;

  /// The reaction played last (for tests).
  @visibleForTesting
  DugtongReaction? get debugLastReaction => _lastReaction;

  bool get _reduce => MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  DugtongStage get _stage => widget.stage ?? dugtongStageFor(widget.streak);

  @override
  void initState() {
    super.initState();
    _pick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _react = AnimationController(vsync: this);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _springTicker = createTicker(_onSpringTick);
  }

  @override
  void dispose() {
    _springTicker.dispose();
    _pick.dispose();
    _react.dispose();
    _spin.dispose();
    _dizzyTimer?.cancel();
    _lineTimer?.cancel();
    super.dispose();
  }

  // ─── Where Dugtong may go ───────────────────────────────────────────────

  // The range of offsets that keep Dugtong's box inside the limit box (plus a
  // margin), as a rectangle in offset space.
  Rect _range() {
    final box = context.findRenderObject();
    final limit = widget.limitKey?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return Rect.fromLTRB(-_bandReach, -_bandReach, _bandReach, _bandReach);
    }
    final home = box.localToGlobal(Offset.zero) & box.size;
    if (limit is! RenderBox || !limit.hasSize) {
      return Rect.fromLTRB(-_bandReach, -_bandReach, _bandReach, _bandReach);
    }
    final area = limit.localToGlobal(Offset.zero) & limit.size;
    // A little beyond the card (less at the bottom, where the next card is).
    final r = Rect.fromLTRB(
      area.left - 14,
      area.top - 14,
      area.right + 14,
      area.bottom + 8,
    );
    return Rect.fromLTRB(
      r.left - home.left,
      r.top - home.top,
      r.right - home.right,
      r.bottom - home.bottom,
    );
  }

  // Past the edge the finger has to travel further and further for each pixel
  // Dugtong moves (a rubber band).
  double _band(double over) => _bandReach * (1 - math.exp(-over / _bandReach));

  double _resist(double v, double lo, double hi) {
    if (v < lo) return lo - _band(lo - v);
    if (v > hi) return hi + _band(v - hi);
    return v;
  }

  // ─── Pointer ────────────────────────────────────────────────────────────

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downAt = e.position;
    _offsetAtDown = _offset;
    _downTime = _now();
    _moved = false;
    _tracker = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
    // Catch it mid-bounce.
    _stopSpring();
    _spin.stop();
    HapticFeedback.lightImpact();
    _pick.forward();
    if (!_reduce) _react.stop();
    _reaction = null;
    setState(() {});
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    final delta = e.position - _downAt;
    if (!_moved) {
      if (delta.distance < _tapSlop) return;
      _moved = true;
      _hideLine();
    }
    final range = _range();
    final raw = _offsetAtDown + delta;
    _offset = Offset(
      _resist(raw.dx, range.left, range.right),
      _resist(raw.dy, range.top, range.bottom),
    );
    final v = _tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
    // Eyes look where it is going; the body leans into the movement.
    final aim = Offset(
      (e.delta.dx / 6).clamp(-1.0, 1.0),
      (e.delta.dy / 6).clamp(-1.0, 1.0),
    );
    _look = Offset.lerp(_look, aim, 0.5)!;
    _tilt += ((v.dx / 2200).clamp(-1.0, 1.0) * 0.38 - _tilt) * 0.35;
    _velocity = v;
    setState(() {});
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    final v = _tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
    final quick = _now().difference(_downTime) <= _tapMaxHold;
    final wasTap = !_moved && quick;
    _endPointer();
    if (wasTap) {
      _tap();
    } else {
      _release(v);
    }
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _endPointer();
    _release(Offset.zero);
  }

  void _endPointer() {
    _pointer = null;
    _tracker = null;
    _look = Offset.zero;
    _pick.reverse();
  }

  // ─── Spring back ────────────────────────────────────────────────────────

  void _release(Offset velocity) {
    if (_offset == Offset.zero) {
      setState(() => _tilt = 0);
      return;
    }
    if (_reduce) {
      // No bounce, no spin: just put it back.
      setState(() {
        _offset = Offset.zero;
        _tilt = 0;
        _velocity = Offset.zero;
      });
      return;
    }
    // The pointer's speed carries into the spring (clamped, so a wild flick
    // does not send it flying).
    final v = Offset(
      velocity.dx.clamp(-2600.0, 2600.0),
      velocity.dy.clamp(-2600.0, 2600.0),
    );
    _simX = SpringSimulation(_spring, _offset.dx, 0, v.dx);
    _simY = SpringSimulation(_spring, _offset.dy, 0, v.dy);
    _springStart = Duration.zero;
    if (velocity.distance > _flingSpeed) _spin.forward(from: 0);
    _springTicker.stop();
    _springTicker.start();
  }

  void _stopSpring() {
    if (_springTicker.isActive) _springTicker.stop();
    _simX = null;
    _simY = null;
  }

  void _onSpringTick(Duration elapsed) {
    final sx = _simX, sy = _simY;
    if (sx == null || sy == null) return;
    final t = (elapsed - _springStart).inMicroseconds / 1e6;
    if (sx.isDone(t) && sy.isDone(t)) {
      _stopSpring();
      setState(() {
        _offset = Offset.zero;
        _tilt = 0;
        _velocity = Offset.zero;
      });
      return;
    }
    setState(() {
      _offset = Offset(sx.x(t), sy.x(t));
      _velocity = Offset(sx.dx(t), sy.dx(t));
      // The lean fades as it settles.
      _tilt *= 0.93;
    });
  }

  // ─── Taps ───────────────────────────────────────────────────────────────

  /// Plays a tap reaction. Public so tests (and a screen reader action) can
  /// trigger it without a gesture.
  void tapNow() => _tap();

  /// Plays [r] without a line (and without counting toward dizziness), unless
  /// it is held, dizzy or animations are removed.
  void playReaction(DugtongReaction r) {
    if (_pointer != null || _dizzy || _reduce || _react.isAnimating) return;
    _lastReaction = r;
    _reaction = r;
    _react.duration = _durationOf(r);
    _react.forward(from: 0).whenComplete(() {
      if (mounted && !_react.isAnimating && _reaction == r) {
        setState(() => _reaction = null);
      }
    });
    setState(() {});
  }

  void _tap() {
    widget.onTapped?.call();
    if (_dizzy) return;
    final now = _now();
    _taps
      ..add(now)
      ..removeWhere(
        (t) => now.difference(t) > const Duration(milliseconds: 2500),
      );
    if (_taps.length >= 5) {
      _taps.clear();
      _startDizzy();
      return;
    }
    _startReaction(_chooseReaction());
  }

  DugtongReaction _chooseReaction() {
    final options = [
      for (final r in DugtongReaction.values)
        if (r != _lastReaction &&
            (r != DugtongReaction.flutter || stageHasCapeOrWings(_stage)))
          r,
    ];
    return options[_rand.nextInt(options.length)];
  }

  Duration _durationOf(DugtongReaction r) => Duration(
    milliseconds: switch (r) {
      DugtongReaction.jump => 700,
      DugtongReaction.spin => 800,
      DugtongReaction.wiggle => 800,
      DugtongReaction.nod => 900,
      DugtongReaction.flutter => 1400,
      DugtongReaction.squish => 650,
      DugtongReaction.giggle => 1100,
    },
  );

  void _startReaction(DugtongReaction r) {
    _lastReaction = r;
    _reaction = r;
    final lines = _reactionLines[r]!;
    if (widget.speaks) {
      _say(
        lines[_rand.nextInt(lines.length)],
        const Duration(milliseconds: 2000),
      );
    }
    if (_reduce) {
      setState(() {});
      return;
    }
    _react.duration = _durationOf(r);
    _react.forward(from: 0).whenComplete(() {
      if (mounted && !_react.isAnimating && _reaction == r) {
        setState(() => _reaction = null);
      }
    });
    setState(() {});
  }

  void _startDizzy() {
    _dizzy = true;
    _reaction = null;
    if (widget.speaks) _say(_dizzyLine, const Duration(milliseconds: 2200));
    if (!_reduce) {
      _react.duration = const Duration(milliseconds: 2000);
      _react.forward(from: 0);
    }
    _dizzyTimer?.cancel();
    _dizzyTimer = Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _dizzy = false);
    });
    setState(() {});
  }

  // ─── Speech ─────────────────────────────────────────────────────────────

  void _say(String text, Duration shownFor) {
    _lineTimer?.cancel();
    _line = text;
    _lineShowing = true;
    _lineTimer = Timer(shownFor, _hideLine);
  }

  void _hideLine() {
    _lineTimer?.cancel();
    if (_lineShowing && mounted) setState(() => _lineShowing = false);
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  DugtongMood get _mood {
    if (_dizzy) return DugtongMood.dizzy;
    if (_pointer != null) return DugtongMood.picked;
    if (_lineShowing) return DugtongMood.talking;
    return widget.restingMood;
  }

  // What the current reaction adds on top of the drag: a shift, a turn and a
  // squash (x, y).
  ({Offset shift, double turn, double sx, double sy, double flutter})
  _reactionPose() {
    var shift = Offset.zero;
    var turn = 0.0;
    var sx = 1.0, sy = 1.0, flutter = 0.0;
    if (_reduce) return (shift: shift, turn: turn, sx: sx, sy: sy, flutter: 0);
    final u = _react.value;
    if (_dizzy) {
      // Staggering around, settling down by the end.
      final fade = 1 - u;
      turn = 0.36 * math.sin(u * 10 * math.pi) * fade;
      shift = Offset(7 * math.sin(u * 7 * math.pi) * fade, 0);
      return (shift: shift, turn: turn, sx: sx, sy: sy, flutter: 0);
    }
    switch (_reaction) {
      case null:
        break;
      case DugtongReaction.jump:
        final hop = math.sin(math.pi * u);
        shift = Offset(0, -30 * hop);
        // Stretch going up, squash on landing.
        sy =
            1 +
            0.1 * hop -
            (u > 0.85
                ? 0.14 * (u - 0.85) / 0.15 * (1 - (u - 0.85) / 0.15) * 4
                : 0);
        sx = 1 / sy;
      case DugtongReaction.spin:
        turn = 2 * math.pi * Curves.easeInOutCubic.transform(u);
        shift = Offset(0, -8 * math.sin(math.pi * u));
      case DugtongReaction.wiggle:
        turn = 0.28 * math.sin(u * 6 * math.pi) * (1 - u);
      case DugtongReaction.nod:
        final nod = math.sin(u * 4 * math.pi);
        turn = 0.1 * nod;
        sy = 1 - 0.06 * nod.abs();
        shift = Offset(0, 4 * nod.abs());
      case DugtongReaction.flutter:
        flutter = math.sin(math.pi * u).clamp(0.0, 1.0);
        shift = Offset(0, -3 * flutter);
      case DugtongReaction.squish:
        final s = math.sin(u * 3 * math.pi) * (1 - u);
        sx = 1 + 0.22 * s;
        sy = 1 - 0.26 * s;
      case DugtongReaction.giggle:
        turn = 0.07 * math.sin(u * 10 * math.pi);
        shift = Offset(0, -4 * math.sin(u * 6 * math.pi).abs());
    }
    return (shift: shift, turn: turn, sx: sx, sy: sy, flutter: flutter);
  }

  // Stretch along the direction of travel while it springs back.
  Matrix4 _stretch() {
    final speed = _velocity.distance;
    if (speed < 30 || _pointer != null) return Matrix4.identity();
    final a = (speed / 3200).clamp(0.0, 0.2);
    final angle = math.atan2(_velocity.dy, _velocity.dx);
    return Matrix4.identity()
      ..rotateZ(angle)
      ..scaleByDouble(1 + a, 1 - a, 1, 1)
      ..rotateZ(-angle);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      // The eager recognizer wins the gesture on touch-down, so the page's scroll
      // view (and its pull-to-refresh) never takes over while Dugtong is held.
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: Semantics(
            button: true,
            hint: 'Tap or drag to play with Dugtong',
            onTap: _tap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_pick, _react, _spin]),
              builder: (context, _) => _body(size),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(double size) {
    final p = Curves.easeOut.transform(_pick.value);
    final pose = _reactionPose();
    final spinTurn = _reduce
        ? 0.0
        : 2 * math.pi * Curves.easeOutCubic.transform(_spin.value);
    final lift = -9 * p;

    final body = Transform.translate(
      offset: _offset + pose.shift + Offset(0, lift),
      child: Transform.rotate(
        angle: spinTurn + pose.turn,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..rotateZ(_tilt)
            ..scaleByDouble(
              pose.sx * (1 + 0.1 * p),
              pose.sy * (1 + 0.1 * p),
              1,
              1,
            ),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: _stretch(),
            child: Dugtong(
              size: size,
              streak: widget.streak,
              stage: widget.stage,
              mood: _mood,
              look: _pointer == null && widget.restingLook != null
                  ? widget.restingLook!
                  : _look,
              flutter: pose.flutter,
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // A soft shadow on the ground that grows while it is held up.
        Positioned(
          left: size * 0.22,
          right: size * 0.22,
          bottom: size * 0.01,
          height: size * 0.09,
          child: Transform.translate(
            offset: _offset,
            child: Opacity(
              opacity: (0.9 * p).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body,
        if (_line != null) _speech(size),
      ],
    );
  }

  Widget _speech(double size) {
    final text = _line!;
    final bubble = DugtongSpeechBubble.measure(text);
    // The bubble goes on the side with room: toward the middle of the card.
    var onLeft = false;
    final box = context.findRenderObject();
    final limit = widget.limitKey?.currentContext?.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        limit is RenderBox &&
        limit.hasSize) {
      final center = box.localToGlobal(Offset.zero).dx + size / 2 + _offset.dx;
      final mid = limit.localToGlobal(Offset.zero).dx + limit.size.width / 2;
      onLeft = center > mid;
    }
    final top = _offset.dy + size * 0.28 - bubble.height / 2;
    return Positioned(
      left: onLeft ? _offset.dx - bubble.width - 2 : _offset.dx + size - 6,
      top: top,
      width: bubble.width,
      height: bubble.height,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _lineShowing ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedScale(
            scale: _lineShowing ? 1 : 0.85,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            alignment: onLeft ? Alignment.centerRight : Alignment.centerLeft,
            child: DugtongSpeechBubble(
              text: text,
              tailOnRight: onLeft,
              tailTop: bubble.height / 2,
            ),
          ),
        ),
      ),
    );
  }
}
