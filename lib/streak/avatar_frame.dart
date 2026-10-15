import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared_design.dart';

/// Frame keys the app knows how to draw.
const Set<String> kStreakFrameKeys = {
  'bronze',
  'silver',
  'gold',
  'crimson',
  'platinum',
  'legend',
};

const Set<String> _animatedFrames = {'crimson', 'platinum', 'legend'};

/// Draws an unlockable streak frame as a ring *around* [child]. A null or
/// unknown [frameKey] returns [child] untouched.
///
/// The ring is `max(3, radius * 0.12)` thick with a 2 px gap, so the total
/// diameter is `2 * radius + 2 * (ring + gap)`.
class StreakAvatarFrame extends StatefulWidget {
  final String? frameKey;
  final double radius;
  final Widget child;

  const StreakAvatarFrame({
    super.key,
    required this.frameKey,
    required this.radius,
    required this.child,
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
    final crown = widget.frameKey == 'legend'
        ? math.max(12.0, radius * 0.7)
        : 0.0;

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
              ),
            ),
          ),
          widget.child,
          if (crown > 0)
            Positioned(
              top: -crown * 0.62,
              left: 0,
              right: 0,
              child: Center(
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: crown,
                  color: const Color(0xFFFFD54F),
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
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

  _FramePainter({
    required this.frameKey,
    required this.radius,
    required this.ring,
    required this.gap,
    required this.anim,
  }) : super(repaint: anim);

  double get _t => anim?.value ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = radius + gap + ring / 2;
    final rect = Rect.fromCircle(center: center, radius: ringRadius + ring / 2);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      ..isAntiAlias = true;

    switch (frameKey) {
      case 'bronze':
        stroke.shader = _linear(
          rect,
          const Color(0xFFE0A66B),
          const Color(0xFF8C5A2B),
        );
        canvas.drawCircle(center, ringRadius, stroke);
      case 'silver':
        stroke.shader = _linear(
          rect,
          const Color(0xFFF1F5F9),
          const Color(0xFF94A3B8),
        );
        canvas.drawCircle(center, ringRadius, stroke);
      case 'gold':
        stroke.shader = _linear(
          rect,
          const Color(0xFFFFE082),
          const Color(0xFFB8860B),
        );
        canvas.drawCircle(center, ringRadius, stroke);
        final starPaint = Paint()..color = Colors.white;
        for (final deg in const [45.0, 135.0, 225.0, 315.0]) {
          final a = deg * math.pi / 180;
          _sparkle(
            canvas,
            center + Offset(math.cos(a), math.sin(a)) * ringRadius,
            math.max(3.0, radius * 0.17),
            starPaint,
          );
        }
      case 'crimson':
        final pulse = 0.5 + 0.5 * _t; // anim reverses, so 0..1..0
        canvas.drawCircle(
          center,
          ringRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring * (1.8 + pulse * 0.8)
            ..color = kCrimson.withValues(alpha: 0.22 + 0.3 * pulse)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              math.max(3.0, radius * 0.22),
            ),
        );
        stroke.shader = _linear(rect, kCrimson, kCrimsonDark);
        canvas.drawCircle(center, ringRadius, stroke);
        _drop(
          canvas,
          Offset(center.dx, center.dy - ringRadius),
          math.max(9.0, radius * 0.5),
        );
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
        canvas.drawCircle(center, ringRadius, stroke);
        for (final (deg, phase) in const [(-50.0, 0.0), (140.0, 0.5)]) {
          final a = deg * math.pi / 180;
          final twinkle =
              0.25 + 0.75 * (0.5 + 0.5 * math.sin((_t + phase) * 2 * math.pi));
          _sparkle(
            canvas,
            center + Offset(math.cos(a), math.sin(a)) * ringRadius,
            math.max(3.5, radius * 0.22) * twinkle,
            Paint()..color = Colors.white,
          );
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
        canvas.drawCircle(center, ringRadius, stroke);
    }
  }

  Shader _linear(Rect rect, Color a, Color b) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [a, b],
  ).createShader(rect);

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

  // Small white water-drop emblem sitting on the ring's top centre.
  void _drop(Canvas canvas, Offset c, double h) {
    final w = h * 0.72;
    final path = Path()
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
      old.anim != anim;
}
