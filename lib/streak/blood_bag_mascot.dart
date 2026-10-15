import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mascot_stage_art.dart';

export 'mascot_stage_art.dart'
    show MascotStage, MascotStageInfo, kMascotStageThresholds, mascotStageFor;

enum MascotMood { idle, dragging, celebrate, sleepy, talking }

/// A cute blood-bag mascot drawn with [CustomPaint]. It evolves with the
/// streak (see [mascotStageFor]), blinks, follows [look] with its pupils and
/// changes face with [mood]. The streak number is printed on its label.
class BloodBagMascot extends StatefulWidget {
  final double size;
  final int streak;
  final MascotMood mood;

  /// Where the pupils should look, each axis in -1..1 (drag direction).
  final Offset look;

  /// Previews can force a stage; otherwise it comes from [streak].
  final MascotStage? stage;

  /// False draws one still frame (used for share images).
  final bool animate;

  /// While [rollProgress] < 1 the label rolls like an odometer from this
  /// number to [streak].
  final int? rollFrom;
  final double rollProgress;

  const BloodBagMascot({
    super.key,
    this.size = 58,
    required this.streak,
    this.mood = MascotMood.idle,
    this.look = Offset.zero,
    this.stage,
    this.animate = true,
    this.rollFrom,
    this.rollProgress = 1,
  });

  @override
  State<BloodBagMascot> createState() => _BloodBagMascotState();
}

class _Glyph {
  final TextPainter? oldDigit;
  final TextPainter? newDigit;
  final bool same;
  const _Glyph(this.oldDigit, this.newDigit, this.same);
}

class _Roll {
  final List<_Glyph> glyphs;
  final double cellWidth;
  final double height;
  const _Roll(this.glyphs, this.cellWidth, this.height);
}

class _BloodBagMascotState extends State<BloodBagMascot>
    with SingleTickerProviderStateMixin {
  // The only controller: a 2 s loop that drives the bob, idle pupil drift and
  // celebration sparkles. Blinking, talking and the release squash are derived
  // from timestamps so they need no controllers of their own.
  AnimationController? _ctrl;
  final math.Random _rand = math.Random();
  late DateTime _nextBlink = DateTime.now().add(_blinkDelay());
  DateTime? _blinkStart;
  DateTime? _squashStart;
  Offset _pupil = Offset.zero;
  double _tilt = 0;
  late TextPainter _label = _buildLabel();
  _Roll? _roll;

  MascotStage get _stage => widget.stage ?? mascotStageFor(widget.streak);
  bool get _detail => widget.size >= 72;

  Duration _blinkDelay() =>
      Duration(milliseconds: 3000 + _rand.nextInt(2001)); // 3–5 s

  bool _reduce() => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _roll = widget.rollFrom != null ? _buildRoll() : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  void _syncController() {
    final run = widget.animate && !_reduce();
    if (!run) {
      _ctrl?.stop();
      return;
    }
    _ctrl ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!_ctrl!.isAnimating) _ctrl!.repeat();
  }

  @override
  void didUpdateWidget(covariant BloodBagMascot old) {
    super.didUpdateWidget(old);
    if (old.mood == MascotMood.dragging && widget.mood != MascotMood.dragging) {
      _squashStart = DateTime.now();
    }
    if (old.streak != widget.streak ||
        old.size != widget.size ||
        old.stage != widget.stage) {
      _label = _buildLabel();
    }
    if (widget.rollFrom == null) {
      _roll = null;
    } else if (_roll == null ||
        old.rollFrom != widget.rollFrom ||
        old.streak != widget.streak ||
        old.size != widget.size ||
        old.stage != widget.stage) {
      _roll = _buildRoll();
    }
    if (old.animate != widget.animate) _syncController();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  double _fontFor(int digits) =>
      widget.size * 0.15 * (digits <= 2 ? 1.0 : (digits == 3 ? 0.82 : 0.66));

  TextPainter _tp(String text, double fontSize) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: mascotLookFor(_stage).number,
        fontWeight: FontWeight.w900,
        fontSize: fontSize,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  TextPainter _buildLabel() =>
      _tp('${widget.streak}', _fontFor(widget.streak.toString().length));

  _Roll _buildRoll() {
    final to = widget.streak.toString();
    final from = widget.rollFrom.toString();
    final n = math.max(to.length, from.length);
    final a = from.padLeft(n, ' ');
    final b = to.padLeft(n, ' ');
    final fs = _fontFor(n);
    final zero = _tp('0', fs);
    return _Roll(
      [
        for (var i = 0; i < n; i++)
          _Glyph(
            a[i] == ' ' ? null : _tp(a[i], fs),
            b[i] == ' ' ? null : _tp(b[i], fs),
            a[i] == b[i],
          ),
      ],
      zero.width,
      zero.height,
    );
  }

  _MascotPainter _frame(double t, {required bool animating}) {
    final now = DateTime.now();
    var blink = 0.0;
    if (animating) {
      if (_blinkStart == null && now.isAfter(_nextBlink)) _blinkStart = now;
      final start = _blinkStart;
      if (start != null) {
        final ms = now.difference(start).inMilliseconds;
        if (ms >= 120) {
          _blinkStart = null;
          _nextBlink = now.add(_blinkDelay());
        } else {
          blink = 1 - ((ms - 60).abs() / 60); // ~120 ms close-and-open
        }
      }
    }

    final dragging = widget.mood == MascotMood.dragging;
    final look = Offset(
      widget.look.dx.clamp(-1.0, 1.0),
      widget.look.dy.clamp(-1.0, 1.0),
    );
    final idleDrift = animating
        ? Offset(
            math.sin(t * 2 * math.pi) * 0.22,
            math.cos(t * 2 * math.pi) * 0.12,
          )
        : Offset.zero;
    final target = (dragging || look != Offset.zero) ? look : idleDrift;
    _pupil = Offset.lerp(_pupil, target, animating ? 0.2 : 1)!;

    final tiltTarget = dragging ? look.dx * 0.24 : 0.0;
    _tilt += (tiltTarget - _tilt) * (animating ? 0.2 : 1);

    var sx = 1.0, sy = 1.0;
    final squash = _squashStart;
    if (squash != null && animating) {
      final secs = now.difference(squash).inMilliseconds / 1000.0;
      if (secs > 0.55) {
        _squashStart = null;
      } else {
        final amp = math.exp(-7 * secs) * math.cos(16 * secs);
        sy = 1 - 0.18 * amp;
        sx = 1 + 0.18 * amp;
      }
    }

    final ms = now.millisecondsSinceEpoch;
    return _MascotPainter(
      stage: _stage,
      detail: _detail,
      t: animating ? t : 0,
      slow: animating ? (ms % 8000) / 8000.0 : 0.12,
      talk: animating ? (ms % 420) / 420.0 : 0.25,
      mood: widget.mood,
      pupil: _pupil,
      blink: blink,
      bob: animating ? math.sin(t * 2 * math.pi) * 2.0 * (widget.size / 58) : 0,
      tilt: _tilt,
      sx: sx,
      sy: sy,
      label: _label,
      roll: _roll,
      rollProgress: widget.rollProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final animating = widget.animate && !_reduce() && ctrl != null;
    final Widget paint = animating
        ? AnimatedBuilder(
            animation: ctrl,
            builder: (_, _) =>
                CustomPaint(painter: _frame(ctrl.value, animating: true)),
          )
        : CustomPaint(painter: _frame(0, animating: false));
    return Semantics(
      label: 'Daily streak: ${widget.streak} days, ${_stage.stageName}',
      child: RepaintBoundary(
        child: SizedBox.square(dimension: widget.size, child: paint),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  final MascotStage stage;
  final bool detail;
  final double t;
  final double slow;
  final double talk;
  final MascotMood mood;
  final Offset pupil;
  final double blink;
  final double bob;
  final double tilt;
  final double sx;
  final double sy;
  final TextPainter label;
  final _Roll? roll;
  final double rollProgress;

  _MascotPainter({
    required this.stage,
    required this.detail,
    required this.t,
    required this.slow,
    required this.talk,
    required this.mood,
    required this.pupil,
    required this.blink,
    required this.bob,
    required this.tilt,
    required this.sx,
    required this.sy,
    required this.label,
    required this.roll,
    required this.rollProgress,
  });

  static const Color _mouthInside = Color(0xFF450A0A);

  MascotLook get _look => mascotLookFor(stage);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final k = _look.scale;

    canvas.save();
    // Shrink the whole figure towards its feet so capes, wings, halos and
    // crowns stay inside the square canvas.
    canvas.translate(s * 0.5, s * 0.96);
    canvas.scale(k);
    canvas.translate(-s * 0.5, -s * 0.96);

    artAura(canvas, s, stage, t, slow);

    canvas.save();
    canvas.translate(0, bob);
    canvas.translate(s * 0.5, s * 0.56);
    canvas.rotate(tilt);
    canvas.translate(-s * 0.5, -s * 0.56);
    canvas.translate(s * 0.5, s * 0.95);
    canvas.scale(sx, sy);
    canvas.translate(-s * 0.5, -s * 0.95);

    final body = _bodyRRect(s);

    // Behind the body.
    artWings(canvas, s, stage, t);
    artCape(canvas, s, stage, t);
    if (detail && stage == MascotStage.champion) artLaurels(canvas, s);

    _tube(canvas, s);
    _tab(canvas, s);
    _body(canvas, s, body);
    _highlight(canvas, s);
    if (stage == MascotStage.platinumAura) {
      artIcy(canvas, s, body);
      if (detail) artShimmer(canvas, s, body, slow);
    }
    if (stage == MascotStage.spark) artHeadband(canvas, s, body);

    _face(canvas, s);
    if (detail && stage == MascotStage.crimsonHero) artEyebrows(canvas, s);
    _labelPlate(canvas, s);

    // In front of everything else.
    if (stage == MascotStage.guardian) artHalo(canvas, s);
    if (stage == MascotStage.legend) artCrown(canvas, s, detail: detail);
    if (detail) {
      if (stage == MascotStage.spark || stage == MascotStage.guardian) {
        artGlints(canvas, s, stage, t);
      }
      if (stage == MascotStage.platinumAura) artOrbitingDrops(canvas, s, slow);
      if (stage == MascotStage.legend) artFloatingHearts(canvas, s, t);
    }
    if (mood == MascotMood.celebrate) _celebration(canvas, s);

    canvas.restore();
    canvas.restore();
  }

  Rect _r(double s, double l, double t, double r, double b) =>
      Rect.fromLTRB(l * s, t * s, r * s, b * s);

  RRect _bodyRRect(double s) => RRect.fromRectAndCorners(
    _r(s, 0.13, 0.16, 0.87, 0.8),
    topLeft: Radius.circular(s * 0.13),
    topRight: Radius.circular(s * 0.13),
    bottomLeft: Radius.circular(s * 0.2),
    bottomRight: Radius.circular(s * 0.2),
  );

  void _tube(Canvas canvas, double s) {
    final path = Path()
      ..moveTo(s * 0.5, s * 0.76)
      ..cubicTo(s * 0.5, s * 0.9, s * 0.36, s * 0.86, s * 0.35, s * 0.93);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.07
        ..color = const Color(0xFFFECACA),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.03
        ..color = const Color(0xFFEF4444).withValues(alpha: .55),
    );
    final cap = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.35, s * 0.945),
        width: s * 0.1,
        height: s * 0.075,
      ),
      Radius.circular(s * 0.025),
    );
    canvas.drawRRect(cap, Paint()..color = _look.bodyB);
    canvas.drawRRect(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = Colors.white.withValues(alpha: .8),
    );
  }

  void _tab(Canvas canvas, double s) {
    final tab = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          _r(s, 0.36, 0.01, 0.64, 0.2),
          Radius.circular(s * 0.075),
        ),
      );
    final hole = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(s * 0.5, s * 0.085), radius: s * 0.032),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, tab, hole),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_look.bodyA, _look.bodyB],
        ).createShader(_r(s, 0.36, 0.01, 0.64, 0.2)),
    );
  }

  void _body(Canvas canvas, double s, RRect body) {
    canvas.drawShadow(
      Path()..addRRect(body),
      Colors.black.withValues(alpha: .45),
      s * 0.04,
      true,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_look.bodyA, _look.bodyB],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..color = _look.bodyB.withValues(alpha: .7),
    );
  }

  void _highlight(Canvas canvas, double s) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.2, s * 0.26, s * 0.05, s * 0.2),
        Radius.circular(s * 0.025),
      ),
      paint,
    );
    canvas.drawCircle(Offset(s * 0.225, s * 0.52), s * 0.024, paint);
  }

  void _face(Canvas canvas, double s) {
    final cheek = Paint()
      ..color = const Color(0xFFFFA8B8).withValues(alpha: .75);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.27, s * 0.505),
        width: s * 0.11,
        height: s * 0.07,
      ),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.73, s * 0.505),
        width: s * 0.11,
        height: s * 0.07,
      ),
      cheek,
    );
    _eye(canvas, s, Offset(s * 0.38, s * 0.4));
    _eye(canvas, s, Offset(s * 0.62, s * 0.4));
    _mouth(canvas, s);
  }

  void _eye(Canvas canvas, double s, Offset center) {
    final sleepy = mood == MascotMood.sleepy;
    final openness = sleepy ? 1.0 : (1 - blink * 0.92);
    final rx = s * 0.085;
    final ry = s * 0.098 * openness.clamp(0.08, 1.0);
    final eye = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    canvas.drawOval(eye, Paint()..color = Colors.white);

    if (openness > 0.3) {
      canvas.save();
      canvas.clipPath(Path()..addOval(eye));
      final pc =
          center +
          Offset(pupil.dx * s * 0.034, pupil.dy * s * 0.03 + s * 0.006);
      canvas.drawCircle(
        pc,
        s * 0.048,
        Paint()..color = const Color(0xFF1F2937),
      );
      canvas.drawCircle(
        pc + Offset(-s * 0.014, -s * 0.016),
        s * 0.015,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    if (sleepy) {
      canvas.save();
      canvas.clipPath(Path()..addOval(eye));
      canvas.drawRect(
        Rect.fromLTRB(
          eye.left,
          eye.top,
          eye.right,
          eye.top + eye.height * 0.56,
        ),
        Paint()..color = const Color(0xFFB91C1C),
      );
      canvas.restore();
      canvas.drawLine(
        Offset(eye.left, eye.top + eye.height * 0.56),
        Offset(eye.right, eye.top + eye.height * 0.56),
        Paint()
          ..color = _look.bodyB
          ..strokeWidth = s * 0.014
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _mouth(Canvas canvas, double s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.024
      ..color = Colors.white;
    switch (mood) {
      case MascotMood.idle:
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.44, s * 0.52)
            ..quadraticBezierTo(s * 0.5, s * 0.585, s * 0.56, s * 0.52),
          line,
        );
      case MascotMood.dragging:
        final o = Rect.fromCenter(
          center: Offset(s * 0.5, s * 0.545),
          width: s * 0.06,
          height: s * 0.075,
        );
        canvas.drawOval(o, Paint()..color = _mouthInside);
        canvas.drawOval(
          o,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.014
            ..color = Colors.white,
        );
      case MascotMood.talking:
        final open = 0.5 + 0.5 * math.sin(talk * 2 * math.pi);
        final m = Rect.fromCenter(
          center: Offset(s * 0.5, s * (0.532 + 0.014 * open)),
          width: s * (0.07 + 0.025 * open),
          height: s * (0.016 + 0.052 * open),
        );
        canvas.drawOval(m, Paint()..color = _mouthInside);
        canvas.drawOval(
          m,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.012
            ..color = Colors.white,
        );
        if (open > 0.55) {
          canvas.save();
          canvas.clipPath(Path()..addOval(m));
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(m.center.dx, m.bottom - s * 0.008),
              width: m.width * 0.6,
              height: s * 0.03,
            ),
            Paint()..color = const Color(0xFFFB7185),
          );
          canvas.restore();
        }
      case MascotMood.celebrate:
        final mouth = Path()
          ..moveTo(s * 0.4, s * 0.505)
          ..lineTo(s * 0.6, s * 0.505)
          ..quadraticBezierTo(s * 0.5, s * 0.69, s * 0.4, s * 0.505)
          ..close();
        canvas.drawPath(mouth, Paint()..color = _mouthInside);
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(s * 0.5, s * 0.6),
            width: s * 0.11,
            height: s * 0.06,
          ),
          Paint()..color = const Color(0xFFFB7185),
        );
        canvas.drawRect(
          Rect.fromLTRB(s * 0.4, s * 0.505, s * 0.6, s * 0.525),
          Paint()..color = Colors.white,
        );
        canvas.restore();
      case MascotMood.sleepy:
        canvas.drawLine(
          Offset(s * 0.45, s * 0.545),
          Offset(s * 0.55, s * 0.545),
          line..strokeWidth = s * 0.02,
        );
    }
  }

  void _labelPlate(Canvas canvas, double s) {
    final look = _look;
    final rect = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.705),
      width: s * 0.44,
      height: s * 0.175,
    );
    final plate = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.05));
    final white = look.plateA == Colors.white;
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = LinearGradient(
          colors: [
            white ? Colors.white.withValues(alpha: .96) : look.plateA,
            white ? Colors.white.withValues(alpha: .96) : look.plateB,
          ],
        ).createShader(rect),
    );
    if (!white) {
      canvas.drawRRect(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.01
          ..color = Colors.white.withValues(alpha: .55),
      );
    }
    if (stage == MascotStage.legend) {
      // Shimmer across the gold label.
      canvas.save();
      canvas.clipRRect(plate);
      final x = rect.left - rect.width * 0.4 + slow * rect.width * 1.8;
      canvas.drawRect(
        Rect.fromLTWH(x, rect.top, rect.width * 0.3, rect.height),
        Paint()
          ..shader =
              LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.7),
                  Colors.white.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromLTWH(x, rect.top, rect.width * 0.3, rect.height),
              ),
      );
      canvas.restore();
    }

    var cx = rect.center.dx;
    if (detail && stageHasLabelEmblem(stage)) {
      artLabelEmblem(
        canvas,
        stage,
        Offset(rect.left + rect.height * 0.7, rect.center.dy),
        rect.height * 0.62,
      );
      cx = rect.center.dx + rect.height * 0.3;
    }

    final r = roll;
    if (r != null && rollProgress < 1) {
      final e = Curves.easeOutCubic.transform(rollProgress.clamp(0.0, 1.0));
      canvas.save();
      canvas.clipRRect(plate);
      final total = r.cellWidth * r.glyphs.length;
      var x = cx - total / 2;
      final top = rect.center.dy - r.height / 2;
      for (final g in r.glyphs) {
        void draw(TextPainter? p, double dy) {
          if (p == null) return;
          p.paint(canvas, Offset(x + (r.cellWidth - p.width) / 2, top + dy));
        }

        if (g.same) {
          draw(g.newDigit, 0);
        } else {
          draw(g.oldDigit, -r.height * 1.1 * e);
          draw(g.newDigit, r.height * 1.1 * (1 - e));
        }
        x += r.cellWidth;
      }
      canvas.restore();
    } else {
      label.paint(
        canvas,
        Offset(cx - label.width / 2, rect.center.dy - label.height / 2),
      );
    }
  }

  void _celebration(Canvas canvas, double s) {
    final star = Paint()..color = const Color(0xFFFFE082);
    const spots = [
      (0.09, 0.26, 0.0),
      (0.92, 0.2, 0.33),
      (0.88, 0.62, 0.66),
      (0.06, 0.62, 0.15),
    ];
    for (final (x, y, phase) in spots) {
      final pulse = 0.55 + 0.45 * math.sin((t * 2 + phase) * 2 * math.pi);
      artSparkle(canvas, Offset(s * x, s * y), s * 0.075 * pulse, star);
    }
    for (var i = 0; i < 2; i++) {
      final progress = (t * 2 + i * 0.5) % 1.0;
      final heart = Paint()
        ..color = const Color(0xFFFF8FA3).withValues(alpha: 1 - progress);
      artHeart(
        canvas,
        Offset(s * (i == 0 ? 0.2 : 0.8), s * (0.3 - progress * 0.22)),
        s * 0.045,
        heart,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) => true;
}
