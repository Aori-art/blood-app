import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';

/// A soft pulsing halo AROUND [child] (a button), in both modes.
///
/// It never changes the child's size and never blocks touches. The halo is
/// clipped to the outside of the button's shape, so the inside of a
/// transparent / outlined button is never tinted (which a BoxShadow would do).
/// [sheen] adds a light band sweeping across a FILLED button now and then.
class GlowPulse extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// The halo color in light mode; in dark mode its lighter palette
  /// counterpart is used. Defaults to the brand red.
  final Color? color;
  final bool enabled;
  final double intensity;
  final bool sheen;

  const GlowPulse({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.color,
    this.enabled = true,
    this.intensity = 1.0,
    this.sheen = false,
  });

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse> with TickerProviderStateMixin {
  AnimationController? _pulse;
  AnimationController? _sheen;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowPulse old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled || old.sheen != widget.sheen) _sync();
  }

  /// Tickers run only while there is something to animate.
  void _sync() {
    final animate = widget.enabled && !_reduce;
    if (animate) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
    if (animate && widget.sheen) {
      _sheen ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3600),
      )..repeat();
    } else {
      _sheen?.dispose();
      _sheen = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _sheen?.dispose();
    super.dispose();
  }

  Color _haloColor(AppPalette p) {
    final c = widget.color;
    if (!p.isDark) return c ?? AppColors.primary;
    if (c == null || c == AppColors.primary) return p.primaryText;
    if (c == AppColors.success) return p.success;
    if (c == AppColors.warning) return p.warning;
    if (c == AppColors.info) return p.info;
    if (c == AppColors.orange) return p.orange;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final on = widget.enabled;
    return RepaintBoundary(
      child: CustomPaint(
        painter: on
            ? _HaloPainter(
                pulse: _pulse,
                color: _haloColor(p),
                dark: p.isDark,
                radius: widget.borderRadius,
                intensity: widget.intensity,
              )
            : null,
        foregroundPainter: on && widget.sheen && _sheen != null
            ? _SheenPainter(sheen: _sheen!, radius: widget.borderRadius)
            : null,
        child: widget.child,
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  final Animation<double>? pulse;
  final Color color;
  final bool dark;
  final BorderRadius radius;
  final double intensity;

  _HaloPainter({
    required this.pulse,
    required this.color,
    required this.dark,
    required this.radius,
    required this.intensity,
  }) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    // Mid intensity when nothing animates (reduced motion).
    final t = Curves.easeInOut.transform(pulse?.value ?? 0.5);
    final (wideLo, wideHi) = dark ? (0.28, 0.55) : (0.18, 0.38);
    final (tightLo, tightHi) = dark ? (0.35, 0.70) : (0.25, 0.50);
    final wideA = ((wideLo + (wideHi - wideLo) * t) * intensity).clamp(
      0.0,
      1.0,
    );
    final tightA = ((tightLo + (tightHi - tightLo) * t) * intensity).clamp(
      0.0,
      1.0,
    );
    final spread = 2.0 * t;

    final shape = radius.toRRect(Offset.zero & size);
    // Never tint the inside of the button.
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(80)),
        Path()..addRRect(shape),
      ),
    );
    canvas.drawRRect(
      shape.inflate(3 + spread),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 + spread * 2
        ..color = color.withValues(alpha: wideA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      shape.inflate(1 + spread * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: tightA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      old.pulse != pulse ||
      old.color != color ||
      old.dark != dark ||
      old.radius != radius ||
      old.intensity != intensity;
}

/// A diagonal light band sweeping left to right over 900 ms, then resting
/// until the 3.6 s cycle ends. Clipped to the button.
class _SheenPainter extends CustomPainter {
  final Animation<double> sheen;
  final BorderRadius radius;

  _SheenPainter({required this.sheen, required this.radius})
    : super(repaint: sheen);

  @override
  void paint(Canvas canvas, Size size) {
    final p = sheen.value * 3600 / 900;
    if (p >= 1) return;
    final shape = radius.toRRect(Offset.zero & size);
    final band = size.height * 1.2;
    final x = -band + (size.width + band * 2) * Curves.easeInOut.transform(p);
    canvas.save();
    canvas.clipRRect(shape);
    canvas.translate(x, size.height / 2);
    canvas.skew(-0.5, 0);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: band,
      height: size.height * 2,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0x40FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) =>
      old.sheen != sheen || old.radius != radius;
}
