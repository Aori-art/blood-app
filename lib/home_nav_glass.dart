// The glass of Home's floating nav: the capsule's tint, sheen and rim, its
// shadow, and the lens that follows the tab while the donor swipes.
//
// Everything is painted inside the nav's own outline (the capsule with the
// scoop around the Check button), which home.dart builds and passes in as a
// path; nothing here changes that shape.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// A color matrix with saturation x1.5 (the page behind the glass looks
/// richer, like frosted glass, not gray).
const List<double> kNavSaturation15 = [
  1.3937, -0.3576, -0.0361, 0, 0, //
  -0.1063, 1.1424, -0.0361, 0, 0, //
  -0.1063, -0.3576, 1.4639, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// The backdrop of the glass: blur first, then more color.
final ui.ImageFilter kNavGlassFilter = ui.ImageFilter.compose(
  outer: const ColorFilter.matrix(kNavSaturation15),
  inner: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
);

/// The colors of the glass for [p]. [frosted] false: no blur behind it, so
/// a solid surface at 94 %.
class NavGlassColors {
  const NavGlassColors({
    required this.tintTop,
    required this.tintBottom,
    required this.sheen,
    required this.rimStart,
    required this.rimMid,
    required this.rimEnd,
  });

  factory NavGlassColors.of(AppPalette p, {required bool frosted}) {
    final dark = p.isDark;
    final Color top;
    final Color bottom;
    if (!frosted) {
      top = bottom = p.surface.withValues(alpha: 0.94);
    } else {
      // Lighter at the top, where the light catches. Never more transparent.
      top = p.surface.withValues(alpha: dark ? 0.52 : 0.60);
      bottom = p.surface.withValues(alpha: dark ? 0.68 : 0.76);
    }
    return NavGlassColors(
      tintTop: top,
      tintBottom: bottom,
      sheen: Colors.white.withValues(alpha: dark ? 0.10 : 0.22),
      rimStart: Colors.white.withValues(alpha: dark ? 0.35 : 0.85),
      rimMid: Colors.white.withValues(alpha: dark ? 0.05 : 0.15),
      rimEnd: Colors.white.withValues(alpha: dark ? 0.20 : 0.55),
    );
  }

  final Color tintTop;
  final Color tintBottom;
  final Color sheen;
  final Color rimStart;
  final Color rimMid;
  final Color rimEnd;

  @override
  bool operator ==(Object other) =>
      other is NavGlassColors &&
      other.tintTop == tintTop &&
      other.tintBottom == tintBottom &&
      other.sheen == sheen &&
      other.rimStart == rimStart &&
      other.rimMid == rimMid &&
      other.rimEnd == rimEnd;

  @override
  int get hashCode =>
      Object.hash(tintTop, tintBottom, sheen, rimStart, rimMid, rimEnd);
}

/// The glass inside the nav's outline: tint, sheen over the upper left, and
/// a rim (a 2.4 px stroke of which the clip keeps the inner 1.2 px).
class NavGlassPainter extends CustomPainter {
  NavGlassPainter({required this.path, required this.colors, super.repaint});

  /// The nav's outline for a size (it changes as the Check button sinks).
  final Path Function(Size size) path;
  final NavGlassColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = path(size);
    final rect = Offset.zero & size;

    canvas.drawPath(
      outline,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.tintTop, colors.tintBottom],
        ).createShader(rect),
    );
    // Sheen: a diagonal highlight from the top left, gone by 45 % down. It
    // fills the same outline, so it follows the scoop.
    canvas.drawPath(
      outline,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.5, size.height * 0.45),
          [colors.sheen, colors.sheen.withValues(alpha: 0)],
        ),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.rimStart, colors.rimMid, colors.rimEnd],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(NavGlassPainter old) => old.colors != colors;
}

/// The shadow under the glass and a hairline around it (so the glass is
/// still defined on a white page). Painted outside the clip.
class NavShadowPainter extends CustomPainter {
  NavShadowPainter({
    required this.path,
    required this.shadow,
    required this.blurSigma,
    required this.hairline,
    this.offsetY = 10,
    super.repaint,
  });

  final Path Function(Size size) path;
  final Color shadow;
  final double blurSigma;
  final Color hairline;

  /// How far below the outline the shadow falls.
  final double offsetY;

  /// Light: black 10 %, blur 28. Dark: black 38 %, blur 30. Both 10 px down.
  factory NavShadowPainter.of(
    AppPalette p, {
    required Path Function(Size size) path,
    Listenable? repaint,
  }) => NavShadowPainter(
    path: path,
    shadow: Colors.black.withValues(alpha: p.isDark ? 0.38 : 0.10),
    blurSigma: p.isDark ? 15 : 14,
    hairline: p.border.withValues(alpha: 0.5),
    repaint: repaint,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final outline = path(size);
    canvas.save();
    canvas.translate(0, offsetY);
    canvas.drawPath(
      outline,
      Paint()
        ..color = shadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
  }

  @override
  bool shouldRepaint(NavShadowPainter old) =>
      old.offsetY != offsetY ||
      old.shadow != shadow ||
      old.blurSigma != blurSigma ||
      old.hairline != hairline;
}

// ── The lens ────────────────────────────────────────────────────────────────

/// Where the lens is and how it looks at a fractional tab [position].
class NavLensGeometry {
  const NavLensGeometry({
    required this.centerX,
    required this.width,
    required this.height,
    required this.visibility,
  });

  /// The lens at rest: the old pill's footprint.
  static const double restWidth = 52;
  static const double restHeight = 40;

  /// The Check button's slot: the lens fades out as it reaches it.
  static const int checkSlot = 2;

  /// [slotWidth] is a fifth of the bar (the Check slot included). With
  /// [reduceMotion] the lens never stretches.
  factory NavLensGeometry.at(
    double position, {
    required double slotWidth,
    bool reduceMotion = false,
  }) {
    final frac = position - position.floorToDouble();
    // 0 on a whole tab, 1 half way between two.
    final s = reduceMotion ? 0.0 : 1 - (2 * frac - 1).abs();
    final width = math.min(restWidth * (1 + 0.22 * s), slotWidth - 2);
    return NavLensGeometry(
      centerX: (position + 0.5) * slotWidth,
      width: width,
      height: restHeight * (1 - 0.04 * s),
      visibility: (position - checkSlot).abs().clamp(0.0, 1.0),
    );
  }

  final double centerX;
  final double width;
  final double height;
  final double visibility;
}

/// How close a tab is to the position: 1 on it, 0 a tab away or more.
double navCloseness(double position, int index) =>
    (1 - (position - index).abs()).clamp(0.0, 1.0);

/// An item's color at the position: from muted to the brand red.
Color navItemColor(AppPalette p, double position, int index) =>
    Color.lerp(p.muted, p.primaryText, navCloseness(position, index))!;

/// The glass lens behind the selected item, placed by [geometry] inside a
/// bar [barHeight] tall. It swells to 1.08 while the bar is [pressed].
class NavGlassLens extends StatelessWidget {
  const NavGlassLens({
    super.key,
    required this.geometry,
    required this.barHeight,
    this.pressed = false,
    this.reduceMotion = false,
  });

  final NavLensGeometry geometry;
  final double barHeight;
  final bool pressed;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.isDark;
    final g = geometry;
    if (g.visibility < 0.01) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: g.centerX - g.width / 2,
          top: (barHeight - g.height) / 2,
          width: g.width,
          height: g.height,
          child: AnimatedScale(
            scale: pressed && !reduceMotion ? 1.08 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: CustomPaint(
              key: const ValueKey('nav-lens'),
              painter: NavLensPainter(
                fillTop: Colors.white.withValues(alpha: dark ? 0.20 : 0.70),
                fillBottom: Colors.white.withValues(alpha: dark ? 0.08 : 0.35),
                tint: AppColors.primary.withValues(alpha: 0.10),
                rim: Colors.white.withValues(alpha: dark ? 0.30 : 0.90),
                shadow: dark ? null : Colors.black.withValues(alpha: 0.08),
                opacity: g.visibility,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small piece of glass: a gradient fill tinted with the brand red, a
/// rim, and (in light) a soft shadow. [opacity] scales every color (no
/// layer is needed to fade it).
class NavLensPainter extends CustomPainter {
  const NavLensPainter({
    required this.fillTop,
    required this.fillBottom,
    required this.tint,
    required this.rim,
    required this.shadow,
    this.opacity = 1,
  });

  final Color fillTop;
  final Color fillBottom;
  final Color tint;
  final Color rim;
  final Color? shadow;
  final double opacity;

  Color _o(Color c) => c.withValues(alpha: c.a * opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final capsule = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );
    final s = shadow;
    if (s != null) {
      canvas.drawRRect(
        capsule.shift(const Offset(0, 3)),
        Paint()
          ..color = _o(s)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_o(fillTop), _o(fillBottom)],
        ).createShader(rect),
    );
    canvas.drawRRect(capsule, Paint()..color = _o(tint));
    canvas.drawRRect(
      capsule.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _o(rim),
    );
  }

  @override
  bool shouldRepaint(NavLensPainter old) =>
      old.fillTop != fillTop ||
      old.fillBottom != fillBottom ||
      old.tint != tint ||
      old.rim != rim ||
      old.shadow != shadow ||
      old.opacity != opacity;
}

// ── The handle ──────────────────────────────────────────────────────────────

/// The small glass capsule that brings the nav back after the donor swiped
/// it away: the bar's glass (tint, sheen, rim, shadow) without the blur, and
/// an arrow up. 52 x 28, in a 48 px tall target.
///
/// Each time [nudge] changes the arrow nudges up twice (not a loop).
class GlassHandle extends StatefulWidget {
  const GlassHandle({super.key, required this.onTap, this.nudge = 0});

  final VoidCallback onTap;
  final int nudge;

  static const double width = 52;
  static const double height = 28;
  static const double targetHeight = 48;

  @override
  State<GlassHandle> createState() => _GlassHandleState();
}

class _GlassHandleState extends State<GlassHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(GlassHandle old) {
    super.didUpdateWidget(old);
    if (old.nudge != widget.nudge &&
        !MediaQuery.disableAnimationsOf(context)) {
      _bump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  static Path _capsule(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.isDark;
    // No blur behind it: a denser tint (0.80) keeps it readable on anything.
    final colors = NavGlassColors(
      tintTop: p.surface.withValues(alpha: 0.80),
      tintBottom: p.surface.withValues(alpha: 0.88),
      sheen: Colors.white.withValues(alpha: dark ? 0.10 : 0.22),
      rimStart: Colors.white.withValues(alpha: dark ? 0.35 : 0.85),
      rimMid: Colors.white.withValues(alpha: dark ? 0.05 : 0.15),
      rimEnd: Colors.white.withValues(alpha: dark ? 0.20 : 0.55),
    );
    final radius = BorderRadius.circular(GlassHandle.height / 2);
    return Semantics(
      button: true,
      label: 'Show navigation bar',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 64,
          height: GlassHandle.targetHeight,
          child: Center(
            child: SizedBox(
              width: GlassHandle.width,
              height: GlassHandle.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: NavShadowPainter(
                      path: _capsule,
                      shadow: Colors.black.withValues(
                        alpha: dark ? 0.38 : 0.10,
                      ),
                      blurSigma: 6,
                      offsetY: 3,
                      hairline: p.border.withValues(alpha: 0.5),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: radius,
                    child: CustomPaint(
                      painter: NavGlassPainter(path: _capsule, colors: colors),
                    ),
                  ),
                  Center(
                    child: AnimatedBuilder(
                      animation: _bump,
                      builder: (context, child) => Transform.translate(
                        // Two little nudges up.
                        offset: Offset(
                          0,
                          -3 * math.sin(2 * math.pi * _bump.value).abs(),
                        ),
                        child: child,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: p.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
