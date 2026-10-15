import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared_design.dart';

enum MascotMood { idle, dragging, celebrate, sleepy }

/// A cute blood-bag mascot drawn with [CustomPaint]. It blinks, its pupils
/// follow [look], and its mouth/eyes change with [mood]. The streak number is
/// printed on its label.
class BloodBagMascot extends StatefulWidget {
  final double size;
  final int streak;
  final MascotMood mood;

  /// Where the pupils should look, each axis in -1..1 (drag direction).
  final Offset look;

  const BloodBagMascot({
    super.key,
    this.size = 58,
    required this.streak,
    this.mood = MascotMood.idle,
    this.look = Offset.zero,
  });

  @override
  State<BloodBagMascot> createState() => _BloodBagMascotState();
}

class _BloodBagMascotState extends State<BloodBagMascot>
    with SingleTickerProviderStateMixin {
  // The only controller: a 2 s loop that drives the bob, idle pupil drift and
  // celebration sparkles. Blinking and the release squash are derived from
  // timestamps so they need no controllers of their own.
  AnimationController? _ctrl;
  final math.Random _rand = math.Random();
  late DateTime _nextBlink = DateTime.now().add(_blinkDelay());
  DateTime? _blinkStart;
  DateTime? _squashStart;
  Offset _pupil = Offset.zero;
  double _tilt = 0;
  late TextPainter _label = _buildLabel();

  Duration _blinkDelay() =>
      Duration(milliseconds: 3000 + _rand.nextInt(2001)); // 3–5 s

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _ctrl?.stop();
    } else {
      _ctrl ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
      );
      if (!_ctrl!.isAnimating) _ctrl!.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant BloodBagMascot old) {
    super.didUpdateWidget(old);
    if (old.mood == MascotMood.dragging && widget.mood != MascotMood.dragging) {
      _squashStart = DateTime.now();
    }
    if (old.streak != widget.streak || old.size != widget.size) {
      _label = _buildLabel();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  TextPainter _buildLabel() {
    final digits = widget.streak.toString().length;
    final factor = digits <= 2 ? 1.0 : (digits == 3 ? 0.82 : 0.66);
    return TextPainter(
      text: TextSpan(
        text: '${widget.streak}',
        style: TextStyle(
          color: const Color(0xFF991B1B),
          fontWeight: FontWeight.w900,
          fontSize: widget.size * 0.15 * factor,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  _MascotPainter _frame(double t, {required bool reduce}) {
    final now = DateTime.now();
    var blink = 0.0;
    if (!reduce) {
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
    final idleDrift = reduce
        ? Offset.zero
        : Offset(
            math.sin(t * 2 * math.pi) * 0.22,
            math.cos(t * 2 * math.pi) * 0.12,
          );
    final target = (dragging || look != Offset.zero) ? look : idleDrift;
    _pupil = Offset.lerp(_pupil, target, reduce ? 1 : 0.2)!;

    final tiltTarget = dragging ? look.dx * 0.24 : 0.0;
    _tilt += (tiltTarget - _tilt) * (reduce ? 1 : 0.2);

    var sx = 1.0, sy = 1.0;
    final squash = _squashStart;
    if (squash != null && !reduce) {
      final secs = now.difference(squash).inMilliseconds / 1000.0;
      if (secs > 0.55) {
        _squashStart = null;
      } else {
        final amp = math.exp(-7 * secs) * math.cos(16 * secs);
        sy = 1 - 0.18 * amp;
        sx = 1 + 0.18 * amp;
      }
    }

    return _MascotPainter(
      t: t,
      mood: widget.mood,
      pupil: _pupil,
      blink: blink,
      bob: reduce ? 0 : math.sin(t * 2 * math.pi) * 2.0 * (widget.size / 58),
      tilt: _tilt,
      sx: sx,
      sy: sy,
      label: _label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ctrl = _ctrl;
    final Widget paint = (reduce || ctrl == null)
        ? CustomPaint(painter: _frame(0, reduce: true))
        : AnimatedBuilder(
            animation: ctrl,
            builder: (_, _) =>
                CustomPaint(painter: _frame(ctrl.value, reduce: false)),
          );
    return Semantics(
      label: 'Daily streak: ${widget.streak} days',
      child: RepaintBoundary(
        child: SizedBox.square(dimension: widget.size, child: paint),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  final double t;
  final MascotMood mood;
  final Offset pupil;
  final double blink;
  final double bob;
  final double tilt;
  final double sx;
  final double sy;
  final TextPainter label;

  _MascotPainter({
    required this.t,
    required this.mood,
    required this.pupil,
    required this.blink,
    required this.bob,
    required this.tilt,
    required this.sx,
    required this.sy,
    required this.label,
  });

  static const Color _dark = Color(0xFF7F1D1D);
  static const Color _mouthInside = Color(0xFF450A0A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.save();
    canvas.translate(0, bob);
    canvas.translate(s * 0.5, s * 0.56);
    canvas.rotate(tilt);
    canvas.translate(-s * 0.5, -s * 0.56);
    canvas.translate(s * 0.5, s * 0.95);
    canvas.scale(sx, sy);
    canvas.translate(-s * 0.5, -s * 0.95);

    _tube(canvas, s);
    _tab(canvas, s);
    _body(canvas, s);
    _highlight(canvas, s);
    _face(canvas, s);
    _labelPlate(canvas, s);
    if (mood == MascotMood.celebrate) _celebration(canvas, s);

    canvas.restore();
  }

  Rect _r(double s, double l, double t, double r, double b) =>
      Rect.fromLTRB(l * s, t * s, r * s, b * s);

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
    // Cap.
    final cap = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.35, s * 0.945),
        width: s * 0.1,
        height: s * 0.075,
      ),
      Radius.circular(s * 0.025),
    );
    canvas.drawRRect(cap, Paint()..color = _dark);
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
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
        ).createShader(_r(s, 0.36, 0.01, 0.64, 0.2)),
    );
  }

  void _body(Canvas canvas, double s) {
    final rect = _r(s, 0.13, 0.16, 0.87, 0.8);
    final body = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(s * 0.13),
      topRight: Radius.circular(s * 0.13),
      bottomLeft: Radius.circular(s * 0.2),
      bottomRight: Radius.circular(s * 0.2),
    );
    canvas.drawShadow(
      Path()..addRRect(body),
      Colors.black.withValues(alpha: .45),
      s * 0.04,
      true,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kCrimson, _dark],
        ).createShader(rect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..color = _dark.withValues(alpha: .7),
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
    // Cheeks first so eyes sit on top.
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
      // Droopy lid over the top half of the eye.
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
          ..color = _dark
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
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.705),
        width: s * 0.44,
        height: s * 0.175,
      ),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(
      plate,
      Paint()..color = Colors.white.withValues(alpha: .96),
    );
    label.paint(
      canvas,
      Offset(s * 0.5 - label.width / 2, s * 0.705 - label.height / 2),
    );
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
      _sparkle(canvas, Offset(s * x, s * y), s * 0.075 * pulse, star);
    }
    for (var i = 0; i < 2; i++) {
      final progress = (t * 2 + i * 0.5) % 1.0;
      final heart = Paint()
        ..color = const Color(0xFFFF8FA3).withValues(alpha: 1 - progress);
      _heart(
        canvas,
        Offset(s * (i == 0 ? 0.2 : 0.8), s * (0.3 - progress * 0.22)),
        s * 0.045,
        heart,
      );
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close(),
      paint,
    );
  }

  void _heart(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + r * 0.9)
        ..cubicTo(
          c.dx - r * 1.6,
          c.dy - r * 0.2,
          c.dx - r * 0.7,
          c.dy - r * 1.2,
          c.dx,
          c.dy - r * 0.4,
        )
        ..cubicTo(
          c.dx + r * 0.7,
          c.dy - r * 1.2,
          c.dx + r * 1.6,
          c.dy - r * 0.2,
          c.dx,
          c.dy + r * 0.9,
        )
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) => true;
}
