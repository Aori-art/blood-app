import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared_design.dart';

/// Visual-only evolution stages of the blood-bag mascot.
enum MascotStage {
  rookie,
  spark,
  cadet,
  guardian,
  champion,
  crimsonHero,
  platinumAura,
  legend,
}

/// Streak needed for each stage (index = stage). Visual only.
const List<int> kMascotStageThresholds = [0, 7, 14, 30, 60, 100, 200, 365];

/// The one place that decides which stage a streak maps to. It is given the
/// CURRENT streak today; switch the argument at the call sites (or this
/// function) to use the longest streak instead.
MascotStage mascotStageFor(int streak) {
  var index = 0;
  for (var i = 0; i < kMascotStageThresholds.length; i++) {
    if (streak >= kMascotStageThresholds[i]) index = i;
  }
  return MascotStage.values[index];
}

extension MascotStageInfo on MascotStage {
  String get stageName => switch (this) {
    MascotStage.rookie => 'Rookie Bag',
    MascotStage.spark => 'Spark Bag',
    MascotStage.cadet => 'Cadet Hero',
    MascotStage.guardian => 'Silver Guardian',
    MascotStage.champion => 'Golden Champion',
    MascotStage.crimsonHero => 'Crimson Hero',
    MascotStage.platinumAura => 'Platinum Aura',
    MascotStage.legend => 'Legend',
  };

  int get minStreak => kMascotStageThresholds[index];
}

/// Everything about a stage that is a plain colour or number.
class MascotLook {
  final Color bodyA;
  final Color bodyB;
  final Color plateA;
  final Color plateB;
  final Color number;

  /// The art is scaled down so capes, wings, halos and crowns stay inside the
  /// square canvas.
  final double scale;

  const MascotLook({
    required this.bodyA,
    required this.bodyB,
    required this.plateA,
    required this.plateB,
    required this.number,
    required this.scale,
  });
}

const Color _white = Colors.white;

MascotLook mascotLookFor(MascotStage stage) => switch (stage) {
  MascotStage.rookie => const MascotLook(
    bodyA: kCrimson,
    bodyB: Color(0xFF8B0000),
    plateA: _white,
    plateB: _white,
    number: Color(0xFF991B1B),
    scale: 1.0,
  ),
  MascotStage.spark => const MascotLook(
    bodyA: Color(0xFFEF4444),
    bodyB: Color(0xFFB91C1C),
    plateA: _white,
    plateB: _white,
    number: Color(0xFF991B1B),
    scale: 0.98,
  ),
  MascotStage.cadet => const MascotLook(
    bodyA: Color(0xFFEF4444),
    bodyB: Color(0xFFB91C1C),
    plateA: Color(0xFFB91C1C),
    plateB: Color(0xFF7F1D1D),
    number: _white,
    scale: 0.96,
  ),
  MascotStage.guardian => const MascotLook(
    bodyA: Color(0xFFEF4444),
    bodyB: Color(0xFFB91C1C),
    plateA: Color(0xFFF1F5F9),
    plateB: Color(0xFF94A3B8),
    number: Color(0xFF334155),
    scale: 0.9,
  ),
  MascotStage.champion => const MascotLook(
    bodyA: Color(0xFFEF4444),
    bodyB: Color(0xFFB91C1C),
    plateA: Color(0xFFFFE082),
    plateB: Color(0xFFB8860B),
    number: Color(0xFF5B3A00),
    scale: 0.9,
  ),
  MascotStage.crimsonHero => const MascotLook(
    bodyA: Color(0xFFB91C1C),
    bodyB: Color(0xFF450A0A),
    plateA: Color(0xFF7F1D1D),
    plateB: Color(0xFF450A0A),
    number: _white,
    scale: 0.84,
  ),
  MascotStage.platinumAura => const MascotLook(
    bodyA: Color(0xFFDC2626),
    bodyB: Color(0xFF7F1D1D),
    plateA: Color(0xFFE0F7FA),
    plateB: Color(0xFFB39DDB),
    number: Color(0xFF312E81),
    scale: 0.84,
  ),
  MascotStage.legend => const MascotLook(
    bodyA: Color(0xFFDC2626),
    bodyB: Color(0xFF7F1D1D),
    plateA: Color(0xFFFFE082),
    plateB: Color(0xFFB8860B),
    number: Color(0xFF5B3A00),
    scale: 0.76,
  ),
};

// ─── Small shapes shared with the particle systems ─────────────────────────

void artSparkle(Canvas c, Offset ctr, double r, Paint paint) {
  c.drawPath(
    Path()
      ..moveTo(ctr.dx, ctr.dy - r)
      ..quadraticBezierTo(ctr.dx, ctr.dy, ctr.dx + r, ctr.dy)
      ..quadraticBezierTo(ctr.dx, ctr.dy, ctr.dx, ctr.dy + r)
      ..quadraticBezierTo(ctr.dx, ctr.dy, ctr.dx - r, ctr.dy)
      ..quadraticBezierTo(ctr.dx, ctr.dy, ctr.dx, ctr.dy - r)
      ..close(),
    paint,
  );
}

void artHeart(Canvas c, Offset ctr, double r, Paint paint) {
  c.drawPath(
    Path()
      ..moveTo(ctr.dx, ctr.dy + r * 0.9)
      ..cubicTo(
        ctr.dx - r * 1.6,
        ctr.dy - r * 0.2,
        ctr.dx - r * 0.7,
        ctr.dy - r * 1.2,
        ctr.dx,
        ctr.dy - r * 0.4,
      )
      ..cubicTo(
        ctr.dx + r * 0.7,
        ctr.dy - r * 1.2,
        ctr.dx + r * 1.6,
        ctr.dy - r * 0.2,
        ctr.dx,
        ctr.dy + r * 0.9,
      )
      ..close(),
    paint,
  );
}

/// A water drop, tip up, [h] tall.
Path artDropPath(Offset c, double h) {
  final w = h * 0.72;
  return Path()
    ..moveTo(c.dx, c.dy - h / 2)
    ..cubicTo(
      c.dx,
      c.dy - h / 2,
      c.dx - w / 2,
      c.dy + h * 0.02,
      c.dx - w / 2,
      c.dy + h * 0.16,
    )
    ..cubicTo(
      c.dx - w / 2,
      c.dy + h * 0.42,
      c.dx - w * 0.22,
      c.dy + h / 2,
      c.dx,
      c.dy + h / 2,
    )
    ..cubicTo(
      c.dx + w * 0.22,
      c.dy + h / 2,
      c.dx + w / 2,
      c.dy + h * 0.42,
      c.dx + w / 2,
      c.dy + h * 0.16,
    )
    ..cubicTo(
      c.dx + w / 2,
      c.dy + h * 0.02,
      c.dx,
      c.dy - h / 2,
      c.dx,
      c.dy - h / 2,
    )
    ..close();
}

void artDrop(Canvas c, Offset ctr, double h, Paint paint) =>
    c.drawPath(artDropPath(ctr, h), paint);

void artStar(Canvas c, Offset ctr, double r, Paint paint) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? r : r * 0.45;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = Offset(
      ctr.dx + math.cos(a) * radius,
      ctr.dy + math.sin(a) * radius,
    );
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  c.drawPath(path..close(), paint);
}

void artShield(Canvas c, Offset ctr, double h, Paint paint) {
  final w = h * 0.82;
  c.drawPath(
    Path()
      ..moveTo(ctr.dx - w / 2, ctr.dy - h / 2)
      ..lineTo(ctr.dx + w / 2, ctr.dy - h / 2)
      ..lineTo(ctr.dx + w / 2, ctr.dy + h * 0.08)
      ..quadraticBezierTo(
        ctr.dx + w / 2,
        ctr.dy + h * 0.36,
        ctr.dx,
        ctr.dy + h / 2,
      )
      ..quadraticBezierTo(
        ctr.dx - w / 2,
        ctr.dy + h * 0.36,
        ctr.dx - w / 2,
        ctr.dy + h * 0.08,
      )
      ..close(),
    paint,
  );
}

// ─── Aura (behind everything) ──────────────────────────────────────────────

void artAura(Canvas c, double s, MascotStage stage, double t, double slow) {
  final center = Offset(s * 0.5, s * 0.5);
  switch (stage) {
    case MascotStage.champion:
      _glow(c, center, s * 0.62, const Color(0xFFFFD54F), 0.42);
    case MascotStage.crimsonHero:
      final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
      _glow(c, center, s * (0.6 + 0.05 * pulse), kCrimson, 0.28 + 0.24 * pulse);
    case MascotStage.platinumAura:
      c.drawCircle(
        center,
        s * 0.64,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFE0F7FA).withValues(alpha: 0.55),
              const Color(0xFF80DEEA).withValues(alpha: 0.28),
              const Color(0xFFB39DDB).withValues(alpha: 0.0),
            ],
            stops: const [0.2, 0.62, 1],
          ).createShader(Rect.fromCircle(center: center, radius: s * 0.64)),
      );
      c.drawCircle(
        center,
        s * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.045
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03)
          ..shader = SweepGradient(
            colors: const [
              Color(0xFFE0F7FA),
              Color(0xFF80DEEA),
              Color(0xFFB39DDB),
              Color(0xFFE0F7FA),
            ],
            transform: GradientRotation(slow * 2 * math.pi),
          ).createShader(Rect.fromCircle(center: center, radius: s * 0.5)),
      );
    case MascotStage.legend:
      _glow(c, center, s * 0.6, const Color(0xFFFFD54F), 0.3);
      c.drawCircle(
        center,
        s * 0.54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.085
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.035)
          ..shader = SweepGradient(
            colors: const [
              Color(0xFFFFD54F),
              kCrimson,
              Color(0xFFFFD54F),
              kCrimson,
              Color(0xFFFFD54F),
            ],
            transform: GradientRotation(slow * 2 * math.pi),
          ).createShader(Rect.fromCircle(center: center, radius: s * 0.54)),
      );
    default:
      break;
  }
}

void _glow(Canvas c, Offset center, double radius, Color color, double alpha) {
  c.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
}

// ─── Cape (behind the body) ────────────────────────────────────────────────

void artCape(Canvas c, double s, MascotStage stage, double t) {
  final (Color a, Color b) = switch (stage) {
    MascotStage.cadet => (const Color(0xFFDC2626), const Color(0xFF7F1D1D)),
    MascotStage.guardian => (const Color(0xFFE2E8F0), const Color(0xFF94A3B8)),
    MascotStage.champion => (const Color(0xFFFFE082), const Color(0xFFB8860B)),
    MascotStage.crimsonHero => (kCrimson, const Color(0xFF450A0A)),
    _ => (Colors.transparent, Colors.transparent),
  };
  if (a == Colors.transparent) return;
  final flow = stage == MascotStage.crimsonHero
      ? math.sin(t * 2 * math.pi)
      : 0.0;
  final w1 = s * 0.025 * flow;
  final cape = Path()
    ..moveTo(s * 0.22, s * 0.26)
    ..cubicTo(
      s * 0.08,
      s * 0.38,
      s * 0.01 + w1,
      s * 0.62,
      s * 0.05 + w1,
      s * 0.9,
    )
    ..quadraticBezierTo(s * 0.27, s * 0.82 - w1, s * 0.5, s * 0.92)
    ..quadraticBezierTo(s * 0.73, s * 0.82 + w1, s * 0.95 - w1, s * 0.9)
    ..cubicTo(s * 0.99 - w1, s * 0.62, s * 0.92, s * 0.38, s * 0.78, s * 0.26)
    ..close();
  c.drawPath(
    cape,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [a, b],
      ).createShader(Rect.fromLTWH(0, s * 0.26, s, s * 0.66)),
  );
  c.drawPath(
    cape,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..color = b.withValues(alpha: 0.8),
  );
}

// ─── Wings (behind the body) ───────────────────────────────────────────────

void artWings(Canvas c, double s, MascotStage stage, double t) {
  final flap = math.sin(t * 2 * math.pi) * 3; // degrees
  switch (stage) {
    case MascotStage.crimsonHero:
      _wingPair(
        c,
        s,
        n: 3,
        length: 0.25,
        fanStart: -50 + flap,
        fanEnd: -8 + flap,
        widthFactor: 0.32,
        colors: const [Color(0xFFDC2626), Color(0xFF7F1D1D)],
        outline: true,
      );
    case MascotStage.platinumAura:
      _wingPair(
        c,
        s,
        n: 5,
        length: 0.32,
        fanStart: -66 + flap,
        fanEnd: -4 + flap,
        widthFactor: 0.34,
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.95),
          const Color(0xFF80DEEA).withValues(alpha: 0.6),
        ],
        glow: true,
      );
    case MascotStage.legend:
      _wingPair(
        c,
        s,
        n: 7,
        length: 0.36,
        fanStart: -72 + flap,
        fanEnd: 2 + flap,
        widthFactor: 0.36,
        colors: const [Color(0xFFFFF8E1), Color(0xFFFFD54F)],
        outline: true,
      );
    default:
      break;
  }
}

void _wingPair(
  Canvas c,
  double s, {
  required int n,
  required double length,
  required double fanStart,
  required double fanEnd,
  required List<Color> colors,
  double widthFactor = 0.24,
  bool outline = false,
  bool glow = false,
}) {
  void one() {
    final attach = Offset(s * 0.82, s * 0.47);
    // Draw from the lowest feather up so the long ones sit behind.
    for (var i = n - 1; i >= 0; i--) {
      final f = n == 1 ? 0.0 : i / (n - 1);
      final angle = (fanStart + (fanEnd - fanStart) * f) * math.pi / 180;
      final len = s * length * (1 - 0.1 * i);
      final w = len * widthFactor;
      c.save();
      c.translate(attach.dx, attach.dy);
      c.rotate(angle);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(len * 0.5, -w, len, 0)
        ..quadraticBezierTo(len * 0.5, w * 0.6, 0, 0)
        ..close();
      if (glow) {
        c.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF80DEEA).withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.025),
        );
      }
      c.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: colors,
          ).createShader(Rect.fromLTWH(0, -w, len, 2 * w)),
      );
      if (outline) {
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.008
            ..color = const Color(0xFFB8860B).withValues(alpha: 0.7),
        );
      }
      c.restore();
    }
  }

  one();
  c.save();
  c.translate(s * 0.5, 0);
  c.scale(-1, 1);
  c.translate(-s * 0.5, 0);
  one();
  c.restore();
}

// ─── In front of the body ──────────────────────────────────────────────────

void artHeadband(Canvas c, double s, RRect body) {
  final band = Rect.fromLTRB(s * 0.13, s * 0.19, s * 0.87, s * 0.255);
  final shader = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE0A66B), Color(0xFF8C5A2B)],
  ).createShader(band);
  c.save();
  c.clipRRect(body);
  c.drawRect(band, Paint()..shader = shader);
  c.restore();
  // Knot and tails on the right.
  final knot = Offset(s * 0.8, s * 0.222);
  final tails = Path()
    ..moveTo(knot.dx, knot.dy)
    ..quadraticBezierTo(s * 0.86, s * 0.27, s * 0.9, s * 0.33)
    ..lineTo(s * 0.85, s * 0.32)
    ..lineTo(s * 0.8, s * 0.26)
    ..close()
    ..moveTo(knot.dx, knot.dy)
    ..quadraticBezierTo(s * 0.74, s * 0.28, s * 0.73, s * 0.35)
    ..lineTo(s * 0.78, s * 0.33)
    ..lineTo(s * 0.8, s * 0.26)
    ..close();
  c.drawPath(tails, Paint()..color = const Color(0xFF8C5A2B));
  c.drawCircle(knot, s * 0.036, Paint()..color = const Color(0xFFE0A66B));
}

void artHalo(Canvas c, double s) {
  final rect = Rect.fromCenter(
    center: Offset(s * 0.5, -s * 0.045),
    width: s * 0.42,
    height: s * 0.1,
  );
  c.drawOval(
    rect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
  );
  c.drawOval(
    rect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03
      ..shader = const LinearGradient(
        colors: [Color(0xFFF1F5F9), Color(0xFF94A3B8), Color(0xFFF1F5F9)],
      ).createShader(rect),
  );
}

void artCrown(Canvas c, double s, {required bool detail}) {
  final crown = Path()
    ..moveTo(s * 0.35, s * 0.03)
    ..lineTo(s * 0.34, -s * 0.06)
    ..lineTo(s * 0.425, -s * 0.02)
    ..lineTo(s * 0.5, -s * 0.11)
    ..lineTo(s * 0.575, -s * 0.02)
    ..lineTo(s * 0.66, -s * 0.06)
    ..lineTo(s * 0.65, s * 0.03)
    ..close();
  final box = Rect.fromLTRB(s * 0.34, -s * 0.11, s * 0.66, s * 0.03);
  c.drawPath(
    crown,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE082), Color(0xFFB8860B)],
      ).createShader(box),
  );
  c.drawPath(
    crown,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.01
      ..color = const Color(0xFF7A5200),
  );
  if (detail) {
    for (final p in [
      (0.34, -0.06, kCrimson),
      (0.5, -0.11, const Color(0xFF2563EB)),
      (0.66, -0.06, kCrimson),
    ]) {
      c.drawCircle(Offset(s * p.$1, s * p.$2), s * 0.02, Paint()..color = p.$3);
    }
  }
}

void artLaurels(Canvas c, double s) {
  final paint = Paint()
    ..shader = const LinearGradient(
      colors: [Color(0xFFFFE082), Color(0xFFB8860B)],
    ).createShader(Rect.fromLTWH(0, 0, s, s));
  void side(bool left) {
    for (var i = 0; i < 6; i++) {
      final a = (100 + i * 22) * math.pi / 180;
      final p = Offset(
        s * 0.5 + math.cos(a) * s * 0.47 * (left ? 1 : -1),
        s * 0.5 + math.sin(a) * s * 0.47,
      );
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a + math.pi / 2 * (left ? 1 : -1) + (left ? 0.5 : -0.5));
      c.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: s * 0.075,
          height: s * 0.032,
        ),
        paint,
      );
      c.restore();
    }
  }

  side(true);
  side(false);
}

void artGlints(Canvas c, double s, MascotStage stage, double t) {
  final Color color;
  final List<(double, double, double)> spots;
  switch (stage) {
    case MascotStage.spark:
      color = const Color(0xFFE0A66B);
      spots = const [(0.07, 0.3, 0.0), (0.94, 0.24, 0.33), (0.9, 0.72, 0.66)];
    case MascotStage.guardian:
      color = const Color(0xFFF1F5F9);
      spots = const [(0.08, 0.2, 0.0), (0.93, 0.36, 0.4), (0.88, 0.8, 0.7)];
    default:
      return;
  }
  final paint = Paint()..color = color;
  for (final (x, y, phase) in spots) {
    final pulse = 0.5 + 0.5 * math.sin((t + phase) * 2 * math.pi);
    artSparkle(c, Offset(s * x, s * y), s * 0.05 * (0.5 + 0.5 * pulse), paint);
  }
}

void artIcy(Canvas c, double s, RRect body) {
  c.save();
  c.clipRRect(body);
  final paint = Paint()..color = const Color(0xFFE0F7FA).withValues(alpha: 0.3);
  c.drawPath(
    Path()
      ..moveTo(s * 0.5, s * 0.16)
      ..lineTo(s * 0.64, s * 0.16)
      ..lineTo(s * 0.3, s * 0.8)
      ..lineTo(s * 0.16, s * 0.8)
      ..close(),
    paint,
  );
  c.drawPath(
    Path()
      ..moveTo(s * 0.7, s * 0.16)
      ..lineTo(s * 0.76, s * 0.16)
      ..lineTo(s * 0.46, s * 0.8)
      ..lineTo(s * 0.4, s * 0.8)
      ..close(),
    Paint()..color = const Color(0xFF80DEEA).withValues(alpha: 0.18),
  );
  c.restore();
  c.drawRRect(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..shader = const LinearGradient(
        colors: [Color(0xFFE0F7FA), Color(0xFF80DEEA), Color(0xFFB39DDB)],
      ).createShader(Rect.fromLTWH(0, 0, s, s)),
  );
}

/// A bright diagonal band that slides across the body.
void artShimmer(Canvas c, double s, RRect body, double slow) {
  c.save();
  c.clipRRect(body);
  final x = -s * 0.3 + slow * s * 1.5;
  final band = Path()
    ..moveTo(x, s * 0.16)
    ..lineTo(x + s * 0.14, s * 0.16)
    ..lineTo(x - s * 0.06, s * 0.8)
    ..lineTo(x - s * 0.2, s * 0.8)
    ..close();
  c.drawPath(
    band,
    Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(x - s * 0.2, 0, s * 0.34, s)),
  );
  c.restore();
}

void artOrbitingDrops(Canvas c, double s, double slow) {
  for (var i = 0; i < 3; i++) {
    final a = slow * 2 * math.pi + i * 2 * math.pi / 3;
    final p = Offset(
      s * 0.5 + math.cos(a) * s * 0.5,
      s * 0.5 + math.sin(a) * s * 0.22,
    );
    final depth = 0.55 + 0.45 * math.sin(a);
    artDrop(
      c,
      p,
      s * 0.08 * (0.8 + 0.3 * depth),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE0F7FA), Color(0xFFB39DDB)],
        ).createShader(Rect.fromCircle(center: p, radius: s * 0.06))
        ..color = Colors.white.withValues(alpha: 0.5 + 0.5 * depth),
    );
  }
}

void artFloatingHearts(Canvas c, double s, double t) {
  for (var i = 0; i < 3; i++) {
    final progress = (t + i / 3) % 1.0;
    final x = [0.1, 0.9, 0.5][i] + 0.03 * math.sin((t + i) * 2 * math.pi);
    artHeart(
      c,
      Offset(s * x, s * (0.85 - progress * 0.75)),
      s * 0.04,
      Paint()
        ..color = const Color(
          0xFFFF8FA3,
        ).withValues(alpha: (1 - progress) * 0.9),
    );
  }
}

void artEyebrows(Canvas c, double s) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = s * 0.03
    ..color = const Color(0xFF2A0A0A);
  c.drawLine(Offset(s * 0.3, s * 0.295), Offset(s * 0.45, s * 0.335), paint);
  c.drawLine(Offset(s * 0.7, s * 0.295), Offset(s * 0.55, s * 0.335), paint);
}

/// The emblem printed on the label plate (fine detail, large sizes only).
void artLabelEmblem(Canvas c, MascotStage stage, Offset center, double size) {
  switch (stage) {
    case MascotStage.cadet:
      artStar(c, center, size * 0.55, Paint()..color = Colors.white);
    case MascotStage.guardian:
      artShield(c, center, size, Paint()..color = const Color(0xFF475569));
      artShield(
        c,
        center,
        size * 0.6,
        Paint()..color = const Color(0xFFE2E8F0),
      );
    case MascotStage.crimsonHero:
      artDrop(c, center, size, Paint()..color = Colors.white);
    default:
      break;
  }
}

/// Which stages put an emblem on the label.
bool stageHasLabelEmblem(MascotStage stage) =>
    stage == MascotStage.cadet ||
    stage == MascotStage.guardian ||
    stage == MascotStage.crimsonHero;
