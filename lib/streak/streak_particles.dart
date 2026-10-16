import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dugtong_stage_art.dart';

enum ParticleShape { drop, heart, star, rect, sparkle }

enum ParticleMode {
  /// Flies out from the origin, then falls with gravity.
  burst,

  /// Starts on a ring around the origin and spirals into it.
  spiralIn,
}

/// One particle's fixed recipe. Everything about its motion is a pure function
/// of time, so the painter is deterministic.
class Particle {
  final ParticleShape shape;
  final Color color;
  final double size;
  final Offset velocity; // px/s (burst)
  final double radius; // px (spiralIn)
  final double angle; // rad (spiralIn start angle)
  final double angularSpeed; // rad/s (spiralIn)
  final double rotation;
  final double spin;
  final double delay; // s
  final double life; // s

  const Particle({
    required this.shape,
    required this.color,
    required this.size,
    required this.velocity,
    required this.radius,
    required this.angle,
    required this.angularSpeed,
    required this.rotation,
    required this.spin,
    required this.delay,
    required this.life,
  });
}

/// Hard cap so a celebration can never get heavy.
const int kMaxParticles = 80;

List<Particle> generateParticles({
  required int seed,
  required int count,
  required List<Color> palette,
  required List<ParticleShape> shapes,
  double speedMin = 80,
  double speedMax = 200,
  double sizeMin = 5,
  double sizeMax = 11,
  double lifeMin = 1.2,
  double lifeMax = 2.0,
  double delayMax = 0.15,
  double radiusMin = 80,
  double radiusMax = 160,

  /// Burst directions: the full circle, or just upwards when false.
  bool fullCircle = true,
}) {
  final rand = math.Random(seed);
  final n = math.min(count, kMaxParticles);
  return List.generate(n, (i) {
    final a = fullCircle
        ? rand.nextDouble() * 2 * math.pi
        : -math.pi / 2 + (rand.nextDouble() - 0.5) * math.pi * 0.9;
    final speed = speedMin + rand.nextDouble() * (speedMax - speedMin);
    return Particle(
      shape: shapes[rand.nextInt(shapes.length)],
      color: palette[rand.nextInt(palette.length)],
      size: sizeMin + rand.nextDouble() * (sizeMax - sizeMin),
      velocity: Offset(math.cos(a) * speed, math.sin(a) * speed),
      radius: radiusMin + rand.nextDouble() * (radiusMax - radiusMin),
      angle: rand.nextDouble() * 2 * math.pi,
      angularSpeed: (rand.nextBool() ? 1 : -1) * (2.5 + rand.nextDouble() * 2),
      rotation: rand.nextDouble() * 2 * math.pi,
      spin: (rand.nextDouble() - 0.5) * 10,
      delay: rand.nextDouble() * delayMax,
      life: lifeMin + rand.nextDouble() * (lifeMax - lifeMin),
    );
  });
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final ParticleMode mode;

  /// Seconds since this system started.
  final double time;
  final Offset origin;
  final double gravity;

  ParticlePainter({
    required this.particles,
    required this.mode,
    required this.time,
    required this.origin,
    this.gravity = 300,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (time <= 0) return;
    for (final p in particles) {
      final tau = time - p.delay;
      if (tau < 0 || tau > p.life) continue;
      final f = tau / p.life;

      final Offset pos;
      final double alpha;
      switch (mode) {
        case ParticleMode.burst:
          pos = origin + p.velocity * tau + Offset(0, gravity * tau * tau / 2);
          alpha = f < 0.65 ? 1.0 : (1 - (f - 0.65) / 0.35);
        case ParticleMode.spiralIn:
          final r = p.radius * math.pow(1 - f, 1.3);
          final a = p.angle + p.angularSpeed * tau;
          pos = origin + Offset(math.cos(a) * r, math.sin(a) * r);
          alpha = f < 0.2 ? f / 0.2 : 1.0;
      }
      final paint = Paint()
        ..color = p.color.withValues(
          alpha: (alpha * p.color.a).clamp(0.0, 1.0),
        );

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotation + p.spin * tau);
      switch (p.shape) {
        case ParticleShape.drop:
          artDrop(canvas, Offset.zero, p.size * 1.6, paint);
        case ParticleShape.heart:
          artHeart(canvas, Offset.zero, p.size * 0.55, paint);
        case ParticleShape.star:
          artStar(canvas, Offset.zero, p.size * 0.7, paint);
        case ParticleShape.sparkle:
          artSparkle(canvas, Offset.zero, p.size * 0.8, paint);
        case ParticleShape.rect:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: p.size,
                height: p.size * 0.55,
              ),
              Radius.circular(p.size * 0.15),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter old) =>
      old.time != time || old.origin != origin || old.mode != mode;
}
