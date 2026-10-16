import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared_design.dart';
import 'dugtong_stage_art.dart';

/// Frame keys the app knows how to draw.
const Set<String> kStreakFrameKeys = {
  'bronze',
  'silver',
  'gold',
  'crimson',
  'platinum',
  'legend',
  'verified',
};

const Set<String> _animatedFrames = {
  'crimson',
  'platinum',
  'legend',
  'verified',
};

const Color _kVerifiedBlue = Color(0xFF2563EB);
const Color _kVerifiedCyan = Color(0xFF06B6D4);

/// Draws an unlockable streak frame as a ring *around* [child]. A null or
/// unknown [frameKey] returns [child] untouched.
///
/// The ring is `max(3, radius * 0.12)` thick with a 2 px gap, so the total
/// diameter is `2 * radius + 2 * (ring + gap)`.
class StreakAvatarFrame extends StatefulWidget {
  final String? frameKey;
  final double radius;
  final Widget child;

  /// 0..1: how much of the ring has been drawn (clockwise from the top). The
  /// celebration uses this to make a new frame draw itself. Emblems and
  /// sparkles appear once the ring is complete.
  final double drawProgress;

  /// 0..1: position of a one-off highlight sweeping round the ring, or null.
  final double? shimmer;

  const StreakAvatarFrame({
    super.key,
    required this.frameKey,
    required this.radius,
    required this.child,
    this.drawProgress = 1,
    this.shimmer,
  });

  @override
  State<StreakAvatarFrame> createState() => _StreakAvatarFrameState();
}

class _StreakAvatarFrameState extends State<StreakAvatarFrame>
    with TickerProviderStateMixin {
  AnimationController? _ctrl;

  bool get _known =>
      widget.frameKey != null && kStreakFrameKeys.contains(widget.frameKey);

  Duration get _duration => switch (widget.frameKey) {
    'crimson' => const Duration(milliseconds: 2600),
    'platinum' => const Duration(milliseconds: 2400),
    'verified' => const Duration(milliseconds: 4200),
    _ => const Duration(seconds: 7),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant StreakAvatarFrame old) {
    super.didUpdateWidget(old);
    if (old.frameKey != widget.frameKey) {
      _ctrl?.dispose();
      _ctrl = null;
      _syncController();
    }
  }

  // One controller, only for the animated frames and only when the user
  // hasn't asked the system to reduce motion.
  void _syncController() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final needed =
        _known && _animatedFrames.contains(widget.frameKey) && !reduce;
    if (needed && _ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: _duration)
        ..repeat(reverse: widget.frameKey == 'crimson');
    } else if (!needed && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_known) return widget.child;
    final radius = widget.radius;
    final ring = math.max(3.0, radius * 0.12);
    const gap = 2.0;
    final total = 2 * radius + 2 * (ring + gap);
    final complete = widget.drawProgress >= 1;
    final emblemOpacity = complete
        ? 1.0
        : ((widget.drawProgress - 0.9) / 0.1).clamp(0.0, 1.0);
    final crown = widget.frameKey == 'legend'
        ? math.max(12.0, radius * 0.7)
        : 0.0;

    // Verified: check badge sitting on the ring's bottom-right.
    final badge = widget.frameKey == 'verified'
        ? math.max(12.0, radius * 0.62)
        : 0.0;
    final ringRadius = radius + gap + ring / 2;
    final badgeCenter =
        Offset(total / 2, total / 2) +
        Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * ringRadius;

    Widget framed = SizedBox(
      width: total,
      height: total,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FramePainter(
                frameKey: widget.frameKey!,
                radius: radius,
                ring: ring,
                gap: gap,
                anim: _ctrl,
                progress: widget.drawProgress,
                shimmer: widget.shimmer,
              ),
            ),
          ),
          widget.child,
          if (crown > 0)
            Positioned(
              top: -crown * 0.62,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: emblemOpacity,
                child: Center(
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    size: crown,
                    color: const Color(0xFFFFD54F),
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ),
          if (badge > 0)
            Positioned(
              left: badgeCenter.dx - badge / 2,
              top: badgeCenter.dy - badge / 2,
              width: badge,
              height: badge,
              child: Opacity(
                opacity: emblemOpacity,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kVerifiedBlue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: math.max(1.2, badge * 0.1),
                    ),
                  ),
                  child: Icon(
                    Icons.verified_rounded,
                    size: badge * 0.78,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (_ctrl != null) framed = RepaintBoundary(child: framed);
    return framed;
  }
}

class _FramePainter extends CustomPainter {
  final String frameKey;
  final double radius;
  final double ring;
  final double gap;
  final Animation<double>? anim;
  final double progress;
  final double? shimmer;

  _FramePainter({
    required this.frameKey,
    required this.radius,
    required this.ring,
    required this.gap,
    required this.anim,
    required this.progress,
    required this.shimmer,
  }) : super(repaint: anim);

  double get _t => anim?.value ?? 0;
  bool get _complete => progress >= 1;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = radius + gap + ring / 2;
    final rect = Rect.fromCircle(center: center, radius: ringRadius + ring / 2);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      ..isAntiAlias = true;

    // The ring, fully or as a clockwise arc from the top while drawing.
    void drawRing(Paint paint) {
      if (_complete) {
        canvas.drawCircle(center, ringRadius, paint);
      } else if (progress > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ringRadius),
          -math.pi / 2,
          progress * 2 * math.pi,
          false,
          paint,
        );
      }
    }

    switch (frameKey) {
      case 'bronze':
        stroke.shader = _linear(
          rect,
          const Color(0xFFE0A66B),
          const Color(0xFF8C5A2B),
        );
        drawRing(stroke);
      case 'silver':
        stroke.shader = _linear(
          rect,
          const Color(0xFFF1F5F9),
          const Color(0xFF94A3B8),
        );
        drawRing(stroke);
      case 'gold':
        stroke.shader = _linear(
          rect,
          const Color(0xFFFFE082),
          const Color(0xFFB8860B),
        );
        drawRing(stroke);
        if (_complete) {
          final starPaint = Paint()..color = Colors.white;
          for (final deg in const [45.0, 135.0, 225.0, 315.0]) {
            final a = deg * math.pi / 180;
            artSparkle(
              canvas,
              center + Offset(math.cos(a), math.sin(a)) * ringRadius,
              math.max(3.0, radius * 0.17),
              starPaint,
            );
          }
        }
      case 'crimson':
        final pulse = 0.5 + 0.5 * _t; // anim reverses, so 0..1..0
        if (progress > 0) {
          canvas.drawCircle(
            center,
            ringRadius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring * (1.8 + pulse * 0.8)
              ..color = kCrimson.withValues(
                alpha: (0.22 + 0.3 * pulse) * progress,
              )
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                math.max(3.0, radius * 0.22),
              ),
          );
        }
        stroke.shader = _linear(rect, kCrimson, kCrimsonDark);
        drawRing(stroke);
        if (_complete) {
          _drop(
            canvas,
            Offset(center.dx, center.dy - ringRadius),
            math.max(9.0, radius * 0.5),
          );
        }
      case 'platinum':
        stroke.shader = const SweepGradient(
          colors: [
            Color(0xFFE0F7FA),
            Color(0xFF80DEEA),
            Color(0xFFB39DDB),
            Color(0xFF80DEEA),
            Color(0xFFE0F7FA),
          ],
        ).createShader(rect);
        drawRing(stroke);
        if (_complete) {
          for (final (deg, phase) in const [(-50.0, 0.0), (140.0, 0.5)]) {
            final a = deg * math.pi / 180;
            final twinkle =
                0.25 +
                0.75 * (0.5 + 0.5 * math.sin((_t + phase) * 2 * math.pi));
            artSparkle(
              canvas,
              center + Offset(math.cos(a), math.sin(a)) * ringRadius,
              math.max(3.5, radius * 0.22) * twinkle,
              Paint()..color = Colors.white,
            );
          }
        }
      case 'legend':
        stroke.shader = SweepGradient(
          colors: const [
            Color(0xFFFFD54F),
            kCrimson,
            Color(0xFFFFD54F),
            kCrimson,
            Color(0xFFFFD54F),
          ],
          transform: GradientRotation(_t * 2 * math.pi),
        ).createShader(rect);
        drawRing(stroke);
      case 'verified':
        stroke.shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [_kVerifiedBlue, _kVerifiedCyan],
        ).createShader(rect);
        drawRing(stroke);
        // Thin white line on the ring's inner edge.
        final inner = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, ring * 0.2)
          ..color = Colors.white.withValues(alpha: 0.9);
        if (_complete) {
          canvas.drawCircle(center, radius + gap + 0.5, inner);
        } else if (progress > 0) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius + gap + 0.5),
            -math.pi / 2,
            progress * 2 * math.pi,
            false,
            inner,
          );
        }
        // Slow shimmer travelling round the ring.
        if (_complete) {
          canvas.drawCircle(
            center,
            ringRadius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring
              ..shader = SweepGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.65),
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.42, 0.5, 0.58, 1],
                transform: GradientRotation(_t * 2 * math.pi),
              ).createShader(rect),
          );
        }
    }

    // A one-off highlight sweeping round the finished ring.
    final sweep = shimmer;
    if (sweep != null && _complete && sweep > 0 && sweep < 1) {
      final a = -math.pi / 2 + sweep * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        a - 0.35,
        0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ring * 1.15
          ..color = Colors.white.withValues(alpha: 0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ring * 0.3),
      );
    }
  }

  Shader _linear(Rect rect, Color a, Color b) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [a, b],
  ).createShader(rect);

  // Small white water-drop emblem sitting on the ring's top centre.
  void _drop(Canvas canvas, Offset c, double h) {
    final path = artDropPath(c, h);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = kCrimsonDark,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.frameKey != frameKey ||
      old.radius != radius ||
      old.ring != ring ||
      old.anim != anim ||
      old.progress != progress ||
      old.shimmer != shimmer;
}

/// The side of the square a framed avatar of [radius] takes up: the photo plus
/// the ring and its gap on every side. Lists use it to reserve the same room
/// for every row, framed or not.
double streakFrameExtent(double radius) =>
    2 * radius + 2 * (math.max(3.0, radius * 0.12) + 2.0);
