import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_palette.dart';

/// A day / night hospital scene drawn in code (no assets), used as the
/// background of the Streak Ladder's summary card. Dugtong stands on its
/// ground line; the card's content sits on top as [child].
///
/// Every color and position is a function of `night` (0 = sunny noon,
/// 1 = clear midnight, animated when the mode changes) and of the time in one
/// 60 s loop.
class StreakScenery extends StatefulWidget {
  /// Height of the landscape band, from the top of the card to the bottom of
  /// the road. The ground line sits [roadBand] px above it.
  final double height;

  /// Windows of the eDonate Hospital that are lit (one per streak day, max 24).
  final int litWindows;

  /// The card's content, painted over the scene.
  final Widget? child;

  /// Scroll offset of the screen, for a subtle parallax (far layers move less
  /// on screen than near ones).
  final double parallax;

  /// Tapping the sun / moon.
  final VoidCallback? onSunMoonTap;

  /// Placed on the sun / moon button, so a theme switch can grow from it.
  final GlobalKey? sunMoonKey;

  const StreakScenery({
    super.key,
    required this.height,
    required this.litWindows,
    this.child,
    this.parallax = 0,
    this.onSunMoonTap,
    this.sunMoonKey,
  });

  /// The road and pavement below the ground line.
  static const double roadBand = 44;

  /// Where the sun (by day) and the moon (by night) rest, from the top right.
  static const Offset celestialFromTopRight = Offset(38, 30);

  @override
  State<StreakScenery> createState() => _StreakSceneryState();
}

class _StreakSceneryState extends State<StreakScenery>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  final _SceneData _data = _SceneData.seeded(7);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.isDark;
    final groundY = widget.height - StreakScenery.roadBand;
    final lit = widget.litWindows.clamp(0, 24);
    final parallax = (widget.parallax * 0.08).clamp(0.0, 12.0);

    CustomPaint scene(double night, {Animation<double>? clock}) => CustomPaint(
      painter: _ScenePainter(
        night: night,
        clock: clock,
        staticTime: 0.25,
        groundY: groundY,
        lit: lit,
        parallax: parallax,
        data: _data,
      ),
    );

    final Widget painted;
    if (_reduce) {
      // One static frame per mode (noon / midnight), cross-faded.
      painted = Stack(
        fit: StackFit.expand,
        children: [
          scene(0),
          AnimatedOpacity(
            opacity: dark ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: scene(1),
          ),
        ],
      );
    } else {
      painted = TweenAnimationBuilder<double>(
        tween: Tween(end: dark ? 1 : 0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, night, _) => scene(night, clock: _clock),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(child: RepaintBoundary(child: painted)),
        ),
        ?widget.child,
        // The sun / moon button (where both rest).
        Positioned(
          right: StreakScenery.celestialFromTopRight.dx - 24,
          top: StreakScenery.celestialFromTopRight.dy - 24,
          width: 48,
          height: 48,
          child: Semantics(
            button: true,
            label: dark ? 'Switch to light mode' : 'Switch to dark mode',
            excludeSemantics: true,
            child: GestureDetector(
              key: widget.sunMoonKey,
              behavior: HitTestBehavior.opaque,
              onTap: widget.onSunMoonTap,
            ),
          ),
        ),
        // A tiny caption on the road.
        Positioned(
          left: 12,
          top: groundY + 12,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                    size: 11,
                    color: dark ? p.info : p.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dark ? 'Clear night' : 'Sunny day',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Seeded scene data (computed once, never per frame) ─────────────────────

class _Star {
  final double x, y, r, phase, speed;
  const _Star(this.x, this.y, this.r, this.phase, this.speed);
}

class _Cloud {
  final double y, scale, speed, phase;
  const _Cloud(this.y, this.scale, this.speed, this.phase);
}

class _Block {
  final double x, w, h;
  const _Block(this.x, this.w, this.h);
}

class _Tree {
  final double x, size, phase;
  const _Tree(this.x, this.size, this.phase);
}

class _SceneData {
  final List<_Star> stars;
  final List<_Cloud> clouds;
  final List<_Block> blocks;
  final List<_Tree> trees;

  /// Seconds (within the 60 s loop) at which a shooting star starts.
  final List<double> shootingStars;

  _SceneData(
    this.stars,
    this.clouds,
    this.blocks,
    this.trees,
    this.shootingStars,
  );

  factory _SceneData.seeded(int seed) {
    final r = math.Random(seed);
    final stars = [
      for (var i = 0; i < 50; i++)
        _Star(
          r.nextDouble(),
          r.nextDouble() * 0.8,
          0.6 + r.nextDouble() * 1.1,
          r.nextDouble(),
          0.5 + r.nextDouble() * 2.5,
        ),
    ];
    const clouds = [
      _Cloud(0.12, 1.0, 9, 0.05),
      _Cloud(0.24, 0.75, 6, 0.55),
      _Cloud(0.06, 0.6, 4, 0.8),
    ];
    final blocks = <_Block>[];
    var x = -0.02;
    while (x < 1.02) {
      final w = 0.05 + r.nextDouble() * 0.06;
      blocks.add(_Block(x, w, 0.18 + r.nextDouble() * 0.22));
      x += w + 0.01;
    }
    const trees = [
      _Tree(0.035, 1.0, 0.0),
      _Tree(0.395, 0.8, 0.4),
      _Tree(0.655, 0.95, 0.7),
      _Tree(0.965, 0.85, 0.2),
    ];
    // Every 15 to 25 s.
    const shooting = [6.0, 27.0, 46.0];
    return _SceneData(stars, clouds, blocks, trees, shooting);
  }
}

// ── The painter ─────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  final double night;
  final Animation<double>? clock;
  final double staticTime;
  final double groundY;
  final int lit;
  final double parallax;
  final _SceneData data;

  _ScenePainter({
    required this.night,
    required this.clock,
    required this.staticTime,
    required this.groundY,
    required this.lit,
    required this.parallax,
    required this.data,
  }) : super(repaint: clock);

  Color _mix(int day, int nightColor) =>
      Color.lerp(Color(day), Color(nightColor), night)!;

  static Paint _fill(Color c) => Paint()..color = c;

  void _glow(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gY = groundY;
    final sec = (clock?.value ?? staticTime) * 60.0;
    final n = night;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // ── Sky ──
    final sky = Rect.fromLTWH(0, 0, w, gY + 2);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_mix(0xFF7EC8F8, 0xFF060B1F), _mix(0xFFE6F6FF, 0xFF1B2B5A)],
        ).createShader(sky),
    );
    if (n > 0) {
      // A faint glow at the horizon.
      final band = Rect.fromLTWH(0, gY - 46, w, 46);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0x003F5BA8),
              Color.fromRGBO(63, 91, 168, 0.35 * n),
            ],
          ).createShader(band),
      );
    }

    final far = parallax; // far layers shift most inside the card

    // ── Stars and a shooting star ──
    if (n > 0.02) {
      for (final s in data.stars) {
        final tw =
            0.55 +
            0.45 * math.sin(2 * math.pi * (sec / 60 * s.speed + s.phase));
        canvas.drawCircle(
          Offset(s.x * w, s.y * (gY - 30) + far),
          s.r,
          _fill(Color.fromRGBO(255, 255, 240, (n * tw).clamp(0.0, 1.0))),
        );
      }
      for (final start in data.shootingStars) {
        final p = (sec - start) / 1.1;
        if (p < 0 || p > 1 || n < 0.5) continue;
        final from = Offset(w * (0.2 + start / 120), 14 + start % 9 + far);
        final head = from + Offset(90 * p, 34 * p);
        final tail = head - const Offset(34, 13);
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [
                const Color(0x00FFFFFF),
                Color.fromRGBO(255, 255, 255, 0.9 * (1 - p) * n),
              ],
            ).createShader(Rect.fromPoints(tail, head)),
        );
      }
    }

    // ── Sun (sets along an arc) and moon (rises) ──
    final rest = Offset(
      w - StreakScenery.celestialFromTopRight.dx,
      StreakScenery.celestialFromTopRight.dy,
    );
    final sun = Offset(
      rest.dx + 70 * n,
      rest.dy + (gY + 30 - rest.dy) * n * n,
    ).translate(0, far);
    if (n < 0.99) {
      _glow(canvas, sun, 58, const Color(0x66FFD54F));
      final rays = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x40FFD54F);
      final turn = sec / 60 * 2 * math.pi;
      for (var i = 0; i < 12; i++) {
        final a = turn + i * math.pi / 6;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(sun + d * 27, sun + d * 36, rays);
      }
      canvas.drawCircle(sun, 22, _fill(const Color(0xFFFFD54F)));
    }
    final m = 1 - n;
    final moon = Offset(
      rest.dx - 72 * m,
      rest.dy + (gY + 30 - rest.dy) * m * m,
    ).translate(0, far);
    if (n > 0.01) {
      _glow(canvas, moon, 46, const Color(0x40F4F1DE));
      canvas.drawCircle(moon, 18, _fill(const Color(0xFFF4F1DE)));
      final crater = _fill(const Color(0xFFDCD7BF));
      canvas.drawCircle(moon + const Offset(-6, -4), 3.6, crater);
      canvas.drawCircle(moon + const Offset(5, 6), 2.6, crater);
    }

    // ── Clouds ──
    for (final c in data.clouds) {
      final span = w + 140;
      final x = ((sec * c.speed + c.phase * span) % span) - 70;
      _cloud(
        canvas,
        Offset(x, c.y * gY + far * 0.9),
        c.scale,
        Color.lerp(const Color(0xF2FFFFFF), const Color(0xE62A3557), n)!,
      );
    }

    // ── Birds (day) ──
    if (n < 0.8) {
      final cycle = sec % 30;
      if (cycle < 12) {
        final p = cycle / 12;
        final bird = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(40, 55, 75, 0.7 * (1 - n));
        for (var i = 0; i < 3; i++) {
          final x = -20 + (w + 40) * p - i * 14;
          final y = 26 + i * 6 + 4 * math.sin(p * 8 + i) + far * 0.8;
          final flap = 3 * math.sin(sec * 9 + i * 1.7);
          final path = Path()
            ..moveTo(x - 5, y - flap)
            ..quadraticBezierTo(x - 2, y - 2, x, y)
            ..quadraticBezierTo(x + 2, y - 2, x + 5, y - flap);
          canvas.drawPath(path, bird);
        }
      }
    }

    // ── Back row of blocks ──
    final blockColor = _mix(0xFFB9C9DA, 0xFF18223B);
    for (final b in data.blocks) {
      final bh = b.h * gY;
      canvas.drawRect(
        Rect.fromLTWH(b.x * w, gY - bh + far * 0.7, b.w * w, bh + 12),
        _fill(blockColor),
      );
    }

    // ── Hills ──
    _hill(canvas, w, gY, 30, far * 0.6, _mix(0xFF9BD5A2, 0xFF16324F), 0.0);
    _hill(canvas, w, gY, 18, far * 0.45, _mix(0xFF7FC48E, 0xFF10263F), 0.5);

    // ── Buildings ──
    final bShift = far * 0.3;
    _building(
      canvas,
      Rect.fromLTRB(w * 0.27, gY - 50 + bShift, w * 0.27 + 34, gY + 4),
      body: _mix(0xFFF2F7FC, 0xFF1E2A44),
      trim: _mix(0xFFCFE2F3, 0xFF26344F),
      rows: 2,
      cols: 2,
    );
    _building(
      canvas,
      Rect.fromLTRB(w * 0.70, gY - 62 + bShift, w * 0.70 + 54, gY + 4),
      body: _mix(0xFFF4FAFF, 0xFF1E2A44),
      trim: _mix(0xFFCFE6F7, 0xFF26344F),
      rows: 2,
      cols: 3,
    );
    _hospital(canvas, w, gY, bShift, sec);

    // ── Trees (sway gently) ──
    for (final t in data.trees) {
      _tree(canvas, Offset(t.x * w, gY + 2 + far * 0.1), t.size, sec, t.phase);
    }

    // ── Ground: grass, pavement, road ──
    canvas.drawRect(
      Rect.fromLTWH(0, gY, w, h - gY),
      _fill(_mix(0xFF8BCB78, 0xFF0E2A2A)),
    );
    final pave = Rect.fromLTWH(0, gY + 8, w, 7);
    canvas.drawRect(pave, _fill(_mix(0xFFDADDE2, 0xFF2A2F3A)));
    final road = Rect.fromLTWH(0, gY + 15, w, StreakScenery.roadBand - 15);
    canvas.drawRect(road, _fill(_mix(0xFF5B6573, 0xFF161B26)));
    final dash = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.85 - 0.45 * n)
      ..strokeWidth = 2;
    for (var x = 4.0; x < w; x += 22) {
      canvas.drawLine(
        Offset(x, road.center.dy),
        Offset(x + 11, road.center.dy),
        dash,
      );
    }

    // ── Street lamps ──
    final lampsOn = ((n - 0.6) / 0.4).clamp(0.0, 1.0);
    for (final fx in const [0.33, 0.62, 0.9]) {
      _lamp(canvas, Offset(fx * w, gY + 12), lampsOn, road);
    }

    // ── Ambulance ──
    _ambulance(canvas, w, road, sec);

    // ── Low fog ──
    if (n > 0) {
      final fog = Rect.fromLTWH(0, gY - 12, w, 20);
      canvas.drawRect(
        fog,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0x00FFFFFF),
              Color.fromRGBO(255, 255, 255, 0.06 * n),
              const Color(0x00FFFFFF),
            ],
          ).createShader(fog),
      );
    }
    canvas.restore();
  }

  void _cloud(Canvas canvas, Offset c, double s, Color color) {
    final p = _fill(color);
    canvas.drawCircle(c + Offset(-14 * s, 2 * s), 9 * s, p);
    canvas.drawCircle(c, 13 * s, p);
    canvas.drawCircle(c + Offset(14 * s, 3 * s), 10 * s, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          c.dx - 22 * s,
          c.dy + 2 * s,
          c.dx + 24 * s,
          c.dy + 12 * s,
        ),
        Radius.circular(6 * s),
      ),
      p,
    );
  }

  void _hill(
    Canvas canvas,
    double w,
    double gY,
    double height,
    double dy,
    Color color,
    double phase,
  ) {
    final path = Path()..moveTo(0, gY + 4);
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      final x0 = w * i / steps;
      final x1 = w * (i + 1) / steps;
      final peak = gY - height * (0.6 + 0.4 * math.sin((i + phase) * 2.1));
      path.quadraticBezierTo((x0 + x1) / 2, peak + dy, x1, gY + 2 + dy * 0.2);
    }
    path
      ..lineTo(w, gY + 6)
      ..lineTo(0, gY + 6)
      ..close();
    canvas.drawPath(path, _fill(color));
  }

  void _building(
    Canvas canvas,
    Rect r, {
    required Color body,
    required Color trim,
    required int rows,
    required int cols,
  }) {
    canvas.drawRect(r, _fill(body));
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 4), _fill(trim));
    final glass = _fill(_mix(0xFFA9D6F5, 0xFF2B3A5C));
    final ww = r.width / (cols * 2 + 1);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        canvas.drawRect(
          Rect.fromLTWH(
            r.left + ww * (col * 2 + 1),
            r.top + 10 + row * 14,
            ww,
            8,
          ),
          glass,
        );
      }
    }
  }

  void _hospital(Canvas canvas, double w, double gY, double dy, double sec) {
    final n = night;
    final cx = w * 0.49;
    final wingW = math.min(96.0, w * 0.27);
    final towerW = wingW * 0.72;
    final wingTop = gY - 62 + dy;
    final towerTop = gY - 128 + dy;
    final body = _mix(0xFFFFFFFF, 0xFF1E2A44);
    final side = _mix(0xFFDDEFFB, 0xFF26344F);

    // Wing (lower, wider) and tower (setback).
    final wing = Rect.fromLTRB(cx - wingW / 2, wingTop, cx + wingW / 2, gY + 4);
    final tower = Rect.fromLTRB(
      cx - towerW / 2,
      towerTop,
      cx + towerW / 2,
      wingTop,
    );
    canvas.drawRect(wing, _fill(body));
    canvas.drawRect(
      Rect.fromLTWH(wing.left, wing.top, wing.width, 5),
      _fill(side),
    );
    canvas.drawRect(tower, _fill(body));
    canvas.drawRect(
      Rect.fromLTWH(tower.right - 6, tower.top, 6, tower.height),
      _fill(side),
    );

    // Roof: helipad with an "H", and an antenna.
    final roof = Rect.fromLTWH(
      tower.left + 4,
      towerTop - 4,
      tower.width - 8,
      4,
    );
    canvas.drawRect(roof, _fill(side));
    final pad = Offset(cx - 4, towerTop - 7);
    canvas.drawOval(
      Rect.fromCenter(center: pad, width: 26, height: 7),
      _fill(_mix(0xFF9AA6B2, 0xFF3A4766)),
    );
    final hPaint = Paint()
      ..color = _mix(0xFFFFFFFF, 0xFFE8ECF5)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      pad + const Offset(-3, -2),
      pad + const Offset(-3, 2),
      hPaint,
    );
    canvas.drawLine(
      pad + const Offset(3, -2),
      pad + const Offset(3, 2),
      hPaint,
    );
    canvas.drawLine(
      pad + const Offset(-3, 0),
      pad + const Offset(3, 0),
      hPaint,
    );
    final antennaTop = Offset(tower.right - 9, towerTop - 20);
    canvas.drawLine(
      Offset(tower.right - 9, towerTop - 4),
      antennaTop,
      Paint()
        ..color = _mix(0xFF8A97A5, 0xFF4A5878)
        ..strokeWidth = 1.4,
    );
    // Helipad and antenna lights blink at night.
    if (n > 0.3) {
      final on = (sec * 1.2) % 1 < 0.5;
      if (on) {
        for (final o in [
          antennaTop,
          pad + const Offset(-13, 0),
          pad + const Offset(13, 0),
        ]) {
          _glow(canvas, o, 6, Color.fromRGBO(255, 80, 80, 0.55 * n));
          canvas.drawCircle(o, 1.4, _fill(Color.fromRGBO(255, 120, 120, n)));
        }
      }
    }

    // Sign: a white plus on a crimson rounded square (not the red-cross
    // emblem, which is protected).
    final sign = Rect.fromCenter(
      center: Offset(cx - 3, towerTop + 11),
      width: 15,
      height: 15,
    );
    if (n > 0) {
      _glow(canvas, sign.center, 22, Color.fromRGBO(196, 30, 58, 0.45 * n));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(sign, const Radius.circular(3.5)),
      _fill(const Color(0xFFC41E3A)),
    );
    final plus = _fill(Colors.white);
    canvas.drawRect(
      Rect.fromCenter(center: sign.center, width: 3, height: 9),
      plus,
    );
    canvas.drawRect(
      Rect.fromCenter(center: sign.center, width: 9, height: 3),
      plus,
    );

    // Window grid: 4 columns by 6 rows (3 in the tower, 3 in the wing). They
    // light from the bottom left upward, one per streak day.
    const cols = 4;
    const rows = 6;
    final colW = towerW / (cols * 2 + 1);
    final unlit = _mix(0xFFA9D6F5, 0xFF2B3A5C);
    final litDay = const Color(0xFFFFE3A0);
    const litNight = Color(0xFFFFC857);
    final litColor = Color.lerp(litDay, litNight, n)!;
    for (var row = 0; row < rows; row++) {
      final inTower = row < 3;
      final top = inTower
          ? towerTop + 24 + row * 13.0
          : wingTop + 9 + (row - 3) * 12.0;
      for (var col = 0; col < cols; col++) {
        // Index from the bottom left: bottom row first, left to right.
        final index = (rows - 1 - row) * cols + col;
        final isLit = index < lit;
        final rect = Rect.fromLTWH(
          tower.left + colW * (col * 2 + 1) - 1,
          top,
          colW + 1,
          7.5,
        );
        if (isLit && n > 0.05) {
          _glow(
            canvas,
            rect.center,
            11,
            Color.fromRGBO(255, 200, 87, 0.30 * n),
          );
        }
        canvas.drawRect(rect, _fill(isLit ? litColor : unlit));
      }
    }

    // Entrance canopy and door.
    final door = Rect.fromCenter(
      center: Offset(cx, gY - 5 + dy * 0),
      width: 14,
      height: 12,
    );
    canvas.drawRect(door, _fill(_mix(0xFF5C87B0, 0xFF0F1830)));
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, gY - 12), width: 30, height: 3.5),
      _fill(const Color(0xFFC41E3A)),
    );
  }

  void _tree(Canvas canvas, Offset base, double s, double sec, double phase) {
    final trunk = Rect.fromLTWH(
      base.dx - 2 * s,
      base.dy - 16 * s,
      4 * s,
      16 * s,
    );
    canvas.drawRect(trunk, _fill(_mix(0xFF8D6E63, 0xFF3A2E2A)));
    final sway = math.sin(2 * math.pi * (sec / 4 + phase)) * 0.05;
    canvas.save();
    canvas.translate(base.dx, base.dy - 14 * s);
    canvas.rotate(sway);
    canvas.drawCircle(
      Offset(0, -9 * s),
      10 * s,
      _fill(_mix(0xFF4CAF50, 0xFF1B3A35)),
    );
    canvas.drawCircle(
      Offset(-5 * s, -4 * s),
      7 * s,
      _fill(_mix(0xFF66BB6A, 0xFF22463F)),
    );
    canvas.drawCircle(
      Offset(6 * s, -5 * s),
      6.5 * s,
      _fill(_mix(0xFF66BB6A, 0xFF22463F)),
    );
    canvas.restore();
  }

  void _lamp(Canvas canvas, Offset foot, double on, Rect road) {
    final pole = Paint()
      ..color = _mix(0xFF6E7A88, 0xFF3D4A63)
      ..strokeWidth = 1.6;
    final head = foot - const Offset(0, 34);
    canvas.drawLine(foot, head, pole);
    canvas.drawLine(head, head + const Offset(6, 0), pole);
    final bulb = head + const Offset(6, 1.5);
    if (on > 0) {
      // A soft warm cone of light on the road.
      final cone = Path()
        ..moveTo(bulb.dx - 2, bulb.dy)
        ..lineTo(bulb.dx + 2, bulb.dy)
        ..lineTo(bulb.dx + 16, road.bottom)
        ..lineTo(bulb.dx - 12, road.bottom)
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 214, 120, 0.35 * on),
              const Color(0x00FFD678),
            ],
          ).createShader(cone.getBounds()),
      );
      _glow(canvas, bulb, 9, Color.fromRGBO(255, 214, 120, 0.6 * on));
    }
    canvas.drawCircle(
      bulb,
      2,
      _fill(Color.lerp(const Color(0xFFB0BAC5), const Color(0xFFFFE08A), on)!),
    );
  }

  void _ambulance(Canvas canvas, double w, Rect road, double sec) {
    final n = night;
    final p = (sec % 25) / 25;
    final x = -70 + (w + 90) * p;
    final y = road.top + 3;
    final body = Rect.fromLTWH(x, y, 40, 15);
    final cab = Rect.fromLTWH(x + 40, y + 4, 13, 11);
    final paint = _fill(_mix(0xFFFFFFFF, 0xFFC9CFDB));
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cab, const Radius.circular(3)),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cab.left + 4, cab.top + 2, 7, 4),
      _fill(_mix(0xFF9FD3F5, 0xFF5878A8)),
    );
    canvas.drawRect(
      Rect.fromLTWH(body.left, body.top + 10, 53, 2),
      _fill(const Color(0xFF1565C0)),
    );
    // The blue Star of Life: three bars, 60 degrees apart.
    final star = Offset(body.left + 15, body.top + 6.5);
    final blue = _fill(const Color(0xFF1565C0));
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(star.dx, star.dy);
      canvas.rotate(i * math.pi / 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 3, height: 10),
          const Radius.circular(1),
        ),
        blue,
      );
      canvas.restore();
    }
    canvas.drawLine(
      star - const Offset(0, 3),
      star + const Offset(0, 3),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 0.8,
    );
    // Wheels.
    final wheel = _fill(const Color(0xFF2B2F36));
    canvas.drawCircle(Offset(body.left + 9, body.bottom + 1), 3.4, wheel);
    canvas.drawCircle(Offset(cab.right - 5, body.bottom + 1), 3.4, wheel);
    // Night: a flashing red and blue light bar with a soft glow on the road.
    if (n > 0.2) {
      final red = (sec * 4) % 1 < 0.5;
      final c = red ? const Color(0xFFFF3B3B) : const Color(0xFF3B7BFF);
      final bar = Offset(body.left + 20 + (red ? -4 : 4), body.top - 2);
      _glow(canvas, bar, 16, c.withValues(alpha: 0.35 * n));
      _glow(
        canvas,
        Offset(bar.dx, road.bottom - 6),
        22,
        c.withValues(alpha: 0.18 * n),
      );
      canvas.drawRect(
        Rect.fromCenter(center: bar, width: 7, height: 3),
        _fill(c),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.night != night ||
      old.groundY != groundY ||
      old.lit != lit ||
      old.parallax != parallax ||
      old.clock != clock;
}
