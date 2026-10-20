import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_palette.dart';
import '../streak/dugtong.dart';
import '../streak/dugtong_chatter.dart' show DugtongSpeechBubble;
import '../streak/interactive_dugtong.dart';
import '../streak/streak_controller.dart';
import 'result_clock.dart';
import 'result_style.dart';

/// What Dugtong says on each result (one at random each time the result
/// appears; a tap shows the next).
const Map<ResultKind, List<String>> kResultLines = {
  ResultKind.eligible: [
    "You did it! You're eligible to donate.",
    "Great news! Let's book your donation.",
    'Heroes like you save lives!',
  ],
  ResultKind.notEligible: [
    'Not this time, but thank you for trying.',
    'Rest up. You can try again later.',
    "I'm still proud of you for checking!",
  ],
  ResultKind.deferred: [
    "Just a short wait. I'll be right here!",
    'Every wait keeps donors and patients safe.',
    'See you on your date!',
  ],
  ResultKind.review: [
    'Our team is taking a look. Hang tight!',
    "Almost there. We'll let you know!",
    'Thanks for your patience!',
  ],
};

// Entrance, on the result clock.
const _dugtongIn = Duration(milliseconds: 150);
const _dugtongPop = Duration(milliseconds: 500);
const _propsIn = Duration(milliseconds: 350);
const _propsFade = Duration(milliseconds: 300);
const _typeFrom = Duration(milliseconds: 500);
const _perChar = Duration(milliseconds: 28);
const _confettiFrom = Duration(milliseconds: 450);
const _confettiFor = Duration(milliseconds: 2400);

/// Where things sit on the stage, shared by the painters and the widgets.
class _StageLayout {
  final Size size;
  final double dugtong;
  const _StageLayout(this.size, this.dugtong);

  double get groundY => size.height - 26;
  Rect get dugtongRect => Rect.fromLTWH(
    size.width / 2 - dugtong / 2,
    groundY - dugtong * 0.96,
    dugtong,
    dugtong,
  );
  Rect get podium => Rect.fromCenter(
    center: Offset(size.width / 2, groundY + 7),
    width: dugtong * 0.82,
    height: 14,
  );
  Offset get medal => Offset(
    dugtongRect.right - dugtong * 0.04,
    dugtongRect.top + dugtong * 0.3,
  );
}

/// The hero panel at the top of a result: Dugtong on a little stage, in the
/// result's colors, with a prop, a speech bubble and (the first time someone
/// is eligible) confetti. Pure decoration: it is excluded from semantics.
class ResultStage extends StatefulWidget {
  final ResultStyle style;
  final bool celebrate;

  const ResultStage({super.key, required this.style, this.celebrate = false});

  /// 250 tall, 200 on short screens. Phones around 780 tall get 220 so the
  /// main button stays above the floating navigation bar.
  static double heightFor(BuildContext context) =>
      _heightFor(MediaQuery.sizeOf(context).height);

  static double _heightFor(double screen) => screen < 700
      ? 200
      : screen < 840
      ? 220
      : 250;

  /// Dugtong's size for a stage [height]: 150 (120 on the short layout).
  static double dugtongFor(double height) => (height * 0.6).clamp(120.0, 150.0);

  @override
  State<ResultStage> createState() => ResultStageState();
}

class ResultStageState extends State<ResultStage> {
  final GlobalKey _stageKey = GlobalKey();
  final GlobalKey<InteractiveDugtongState> _dugtongKey = GlobalKey();
  late int _line = math.Random().nextInt(3);
  Duration _lineStart = _typeFrom;
  Duration _lastJump = Duration.zero;
  ValueListenable<Duration>? _clock;

  ResultKind get _kind => widget.style.kind;

  /// The line Dugtong is saying (for tests).
  @visibleForTesting
  String get currentLine => kResultLines[_kind]![_line];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = ResultClock.of(context);
    if (clock != _clock) {
      _clock?.removeListener(_onTick);
      _clock = clock..addListener(_onTick);
    }
  }

  @override
  void dispose() {
    _clock?.removeListener(_onTick);
    super.dispose();
  }

  // Eligible: a small celebratory jump every ~3 s.
  void _onTick() {
    if (_kind != ResultKind.eligible || ResultClock.stillOf(context)) return;
    final now = _clock!.value;
    if (now < const Duration(milliseconds: 1500)) return;
    if (now - _lastJump >= const Duration(seconds: 3)) {
      _lastJump = now;
      _dugtongKey.currentState?.playReaction(DugtongReaction.jump);
    }
  }

  void _nextLine() {
    setState(() {
      _line = (_line + 1) % 3;
      _lineStart = _clock?.value ?? _typeFrom;
    });
  }

  DugtongMood get _mood => switch (_kind) {
    ResultKind.eligible => DugtongMood.celebrate,
    ResultKind.notEligible => DugtongMood.sleepy,
    _ => DugtongMood.idle,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = widget.style;
    final height = ResultStage.heightFor(context);
    final still = ResultClock.stillOf(context);
    final clock = ResultClock.of(context);
    return ExcludeSemantics(
      child: Container(
        key: _stageKey,
        height: height,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: style.border),
          boxShadow: p.shadow,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final layout = _StageLayout(
              box.biggest,
              ResultStage.dugtongFor(height),
            );
            final d = layout.dugtongRect;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScenePainter(
                        clock: clock,
                        style: style,
                        palette: p,
                        layout: layout,
                        still: still,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(rect: d, child: _dugtong(clock, still, d)),
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _PropPainter(
                          clock: clock,
                          style: style,
                          palette: p,
                          layout: layout,
                          still: still,
                        ),
                      ),
                    ),
                  ),
                ),
                _bubble(clock, still, layout),
                if (widget.celebrate && !still && _kind == ResultKind.eligible)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _ConfettiPainter(
                            clock: clock,
                            origin: layout.medal,
                            colors: [
                              style.accent,
                              p.primaryText,
                              p.warning,
                              p.info,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dugtong(ValueListenable<Duration> clock, bool still, Rect d) {
    Widget dugtong(Offset? look) => ListenableBuilder(
      listenable: StreakController.instance,
      builder: (context, _) => InteractiveDugtong(
        key: _dugtongKey,
        streak: StreakController.instance.data?.current ?? 0,
        size: d.width,
        restingMood: _mood,
        limitKey: _stageKey,
        speaks: false,
        onTapped: _nextLine,
        restingLook: look,
      ),
    );
    if (still) {
      return dugtong(_kind == ResultKind.review ? Offset.zero : null);
    }
    final review = _kind == ResultKind.review;
    // The pop-in (and, under review, the eyes following the magnifier).
    return ValueListenableBuilder<Duration>(
      valueListenable: clock,
      child: review ? null : dugtong(null),
      builder: (context, now, child) {
        final u = clockProgress(now, _dugtongIn, _dugtongPop);
        final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(u);
        return Opacity(
          opacity: u == 0 ? 0 : math.min(1, u * 3),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: child ?? dugtong(Offset(_sweep(now) * 0.9, 0.15)),
          ),
        );
      },
    );
  }

  Widget _bubble(
    ValueListenable<Duration> clock,
    bool still,
    _StageLayout layout,
  ) {
    final text = currentLine;
    final scale = MediaQuery.textScalerOf(context);
    final width = math.min(240.0, layout.size.width - 24);
    final d = layout.dugtongRect;
    return Positioned(
      left: 12,
      right: 12,
      bottom: layout.size.height - d.top - 6,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: still
              ? _StageBubble(text: text, shown: text.length)
              : ValueListenableBuilder<Duration>(
                  valueListenable: clock,
                  builder: (context, now, _) {
                    final elapsed = now - _lineStart;
                    final shown = elapsed.isNegative
                        ? 0
                        : (elapsed.inMicroseconds / _perChar.inMicroseconds)
                              .floor()
                              .clamp(0, text.length);
                    return Opacity(
                      opacity: elapsed.isNegative ? 0 : 1,
                      child: _StageBubble(
                        text: text,
                        shown: shown,
                        textScaler: scale,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// -1..1, the magnifier's sweep under review (0 at rest).
double _sweep(Duration now) =>
    math.sin(now.inMilliseconds / 3200 * 2 * math.pi);

/// The app's Dugtong speech bubble (palette.surface, a 1 px border, the
/// same text), with its tail pointing down at him. The full text is laid
/// out from the start so the bubble does not grow while it types.
class _StageBubble extends StatelessWidget {
  final String text;
  final int shown;
  final TextScaler? textScaler;
  const _StageBubble({
    required this.text,
    required this.shown,
    this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = DugtongSpeechBubble.textStyle.copyWith(
      color: p.foreground,
      fontSize: 13,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: DugtongSpeechBubble.padding,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text.substring(0, shown)),
                TextSpan(
                  text: text.substring(shown),
                  style: const TextStyle(color: Color(0x00000000)),
                ),
              ],
            ),
            style: base,
            textAlign: TextAlign.center,
            textScaler: textScaler,
          ),
        ),
        CustomPaint(
          size: const Size(16, 8),
          painter: _DownTailPainter(fill: p.surface, border: p.border),
        ),
      ],
    );
  }
}

class _DownTailPainter extends CustomPainter {
  final Color fill;
  final Color border;
  const _DownTailPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -1)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -1);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _DownTailPainter old) =>
      old.fill != fill || old.border != border;
}

// ─── The scene ─────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  final ValueListenable<Duration> clock;
  final ResultStyle style;
  final AppPalette palette;
  final _StageLayout layout;
  final bool still;

  _ScenePainter({
    required this.clock,
    required this.style,
    required this.palette,
    required this.layout,
    required this.still,
  }) : super(repaint: still ? null : clock);

  static final List<(double, double, double, double)> _stars = () {
    final r = math.Random(24);
    return [
      for (var i = 0; i < 24; i++)
        (
          r.nextDouble(),
          r.nextDouble() * 0.62,
          0.7 + r.nextDouble(),
          r.nextDouble(),
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value.inMicroseconds / 1e6;
    final rect = Offset.zero & size;
    final a = style.accent;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [style.tint, palette.surface],
        ).createShader(rect),
    );

    // Soft decorative shapes.
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.18),
      54,
      Paint()..color = a.withValues(alpha: .08),
    );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.72),
      38,
      Paint()
        ..color = a.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    for (final (x, y, r) in const [
      (0.18, 0.62, 4.0),
      (0.84, 0.2, 5.0),
      (0.7, 0.1, 3.0),
      (0.28, 0.12, 3.0),
    ]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        r,
        Paint()..color = a.withValues(alpha: .14),
      );
    }

    if (palette.isDark) {
      for (final (x, y, r, phase) in _stars) {
        final tw = still ? 0.5 : (math.sin((t * 1.6 + phase * 6)) + 1) / 2;
        canvas.drawCircle(
          Offset(x * size.width, y * size.height),
          r,
          Paint()
            ..color = palette.foreground.withValues(alpha: 0.18 + 0.45 * tw),
        );
      }
    }

    final d = layout.dugtongRect;
    switch (style.kind) {
      case ResultKind.eligible:
        _rays(canvas, d.center, size, still ? 0 : t);
        _sparkles(canvas, d, still ? 0 : t);
      case ResultKind.notEligible:
        _clouds(canvas, size, still ? 0 : t);
      case ResultKind.deferred:
        _motes(canvas, size, still ? 0 : t);
      case ResultKind.review:
        _scanLines(canvas, size, still ? 0 : t);
    }

    // The ground: a soft shadow and a little podium.
    final podium = layout.podium;
    canvas.drawOval(
      Rect.fromCenter(
        center: podium.bottomCenter + const Offset(0, 3),
        width: podium.width * 1.25,
        height: 12,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: palette.isDark ? .4 : .1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    final top = RRect.fromRectAndRadius(podium, const Radius.circular(8));
    canvas.drawRRect(top, Paint()..color = palette.surfaceAlt);
    canvas.drawRRect(
      top,
      Paint()
        ..color = palette.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _rays(Canvas canvas, Offset c, Size size, double t) {
    final paint = Paint()..color = style.accent.withValues(alpha: .1);
    final reach = size.width;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi / 40);
    for (var i = 0; i < 12; i++) {
      final a0 = i * 2 * math.pi / 12;
      final a1 = a0 + math.pi / 24;
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(math.cos(a0) * reach, math.sin(a0) * reach)
          ..lineTo(math.cos(a1) * reach, math.sin(a1) * reach)
          ..close(),
        paint,
      );
    }
    canvas.restore();
  }

  void _sparkles(Canvas canvas, Rect d, double t) {
    const spots = [
      (-0.18, 0.15, 0.0),
      (1.12, 0.05, 0.3),
      (-0.28, 0.6, 0.55),
      (1.22, 0.62, 0.8),
      (0.1, -0.05, 0.15),
    ];
    for (final (x, y, phase) in spots) {
      final tw = t == 0 ? 0.6 : (math.sin(t * 3 + phase * 6) + 1) / 2;
      _star4(
        canvas,
        Offset(d.left + d.width * x, d.top + d.height * y),
        4 + 4 * tw,
        style.accent.withValues(alpha: 0.25 + 0.5 * tw),
      );
    }
  }

  void _clouds(Canvas canvas, Size size, double t) {
    final paint = Paint()..color = style.accent.withValues(alpha: .1);
    for (final (y, speed, s, x0) in const [
      (0.16, 0.012, 1.0, 0.1),
      (0.34, 0.008, 0.7, 0.6),
      (0.08, 0.006, 0.55, 0.85),
    ]) {
      final span = size.width + 120;
      final x = ((x0 + t * speed) % 1.0) * span - 60;
      _cloud(canvas, Offset(x, size.height * y), 30 * s, paint);
    }
  }

  void _motes(Canvas canvas, Size size, double t) {
    final r = math.Random(5);
    for (var i = 0; i < 9; i++) {
      final x = r.nextDouble() * size.width;
      final speed = 8 + r.nextDouble() * 8;
      final phase = r.nextDouble();
      final y =
          size.height -
          ((phase * size.height + t * speed) % (size.height + 20));
      final paint = Paint()..color = style.accent.withValues(alpha: .14);
      if (i.isEven) {
        _clockGlyph(canvas, Offset(x, y), 5 + r.nextDouble() * 3, paint);
      } else {
        canvas.drawCircle(Offset(x, y), 2 + r.nextDouble() * 2, paint);
      }
    }
  }

  void _scanLines(Canvas canvas, Size size, double t) {
    final paint = Paint()
      ..color = style.accent.withValues(alpha: .1)
      ..strokeWidth = 1.5;
    const gap = 14.0;
    final shift = (t * 10) % gap;
    for (var y = size.height - shift; y > 0; y -= gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.style.kind != style.kind ||
      old.palette != palette ||
      old.layout.size != layout.size ||
      old.still != still;
}

// ─── Props ─────────────────────────────────────────────────────────────────

class _PropPainter extends CustomPainter {
  final ValueListenable<Duration> clock;
  final ResultStyle style;
  final AppPalette palette;
  final _StageLayout layout;
  final bool still;

  _PropPainter({
    required this.clock,
    required this.style,
    required this.palette,
    required this.layout,
    required this.still,
  }) : super(repaint: still ? null : clock);

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final t = now.inMicroseconds / 1e6;
    final fade = still ? 1.0 : clockProgress(now, _propsIn, _propsFade);
    if (fade == 0) return;
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, fade),
    );
    final d = layout.dugtongRect;
    switch (style.kind) {
      case ResultKind.eligible:
        final bob = still ? 0.0 : math.sin(t * 2 * math.pi / 2.4) * 4;
        _medal(canvas, layout.medal + Offset(0, bob), d.width * 0.13);
      case ResultKind.notEligible:
        _zzz(canvas, d, still ? 0.4 : t);
        final c = Offset(d.left - d.width * 0.1, d.top + d.height * 0.24);
        _cloud(
          canvas,
          c + Offset(0, still ? 0 : math.sin(t * 1.2) * 2),
          d.width * 0.16,
          Paint()..color = style.accent.withValues(alpha: .18),
        );
      case ResultKind.deferred:
        _hourglass(canvas, d, still ? null : t);
      case ResultKind.review:
        _magnifier(canvas, d, still ? 0 : _sweep(now));
    }
    canvas.restore();
  }

  // A seal (scalloped circle) with ribbon tails and a white check.
  void _medal(Canvas canvas, Offset c, double r) {
    final a = style.accent;
    final dark = Color.lerp(a, Colors.black, .25)!;
    for (final dx in [-0.45, 0.45]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + r * dx * 0.6, c.dy + r * 0.4)
          ..lineTo(c.dx + r * dx * 1.2, c.dy + r * 1.75)
          ..lineTo(c.dx + r * dx * 0.55, c.dy + r * 1.45)
          ..lineTo(c.dx + r * dx * 0.1, c.dy + r * 1.8)
          ..close(),
        Paint()..color = dark,
      );
    }
    final seal = Path();
    const bumps = 12;
    for (var i = 0; i <= bumps * 2; i++) {
      final ang = i * math.pi / bumps;
      final rr = i.isEven ? r : r * 0.86;
      final p = c + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
      i == 0 ? seal.moveTo(p.dx, p.dy) : seal.lineTo(p.dx, p.dy);
    }
    seal.close();
    canvas.drawPath(seal, Paint()..color = a);
    canvas.drawCircle(
      c,
      r * 0.68,
      Paint()
        ..color = Colors.white.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * 0.38, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.3)
        ..lineTo(c.dx + r * 0.42, c.dy - r * 0.28),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // "Z z z" rising slowly from his head.
  void _zzz(Canvas canvas, Rect d, double t) {
    for (var i = 0; i < 3; i++) {
      final u = ((t / 3.6) + i / 3) % 1.0;
      final alpha = math.sin(u * math.pi);
      final s = 8 + i * 2.5 + u * 3;
      final x = d.right - d.width * 0.02 + u * 16 + math.sin(u * 6) * 3;
      final y = d.top + d.height * 0.42 - u * 40;
      // A "z", drawn (so it needs no font).
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..lineTo(x + s, y)
          ..lineTo(x, y + s)
          ..lineTo(x + s, y + s),
        Paint()
          ..color = style.accent.withValues(alpha: 0.75 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + s * 0.12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  // Sand drains over 4 s, then the glass flips in 400 ms. Still: half full.
  void _hourglass(Canvas canvas, Rect d, double? t) {
    final h = d.height * 0.42;
    final w = h * 0.58;
    final base = Offset(d.right + w * 0.55, layout.groundY - h / 2 - 2);
    double drain = 0.5, flip = 0;
    if (t != null) {
      final u = t % 4.4;
      if (u < 4) {
        drain = u / 4;
      } else {
        drain = 1;
        flip = Curves.easeInOut.transform((u - 4) / 0.4);
      }
    }
    final a = style.accent;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(flip * math.pi);
    final half = h / 2 - 4;
    final glass = Path()
      ..moveTo(-w / 2 + 3, -half)
      ..lineTo(w / 2 - 3, -half)
      ..quadraticBezierTo(w / 2 - 3, -half * 0.25, 2, 0)
      ..quadraticBezierTo(w / 2 - 3, half * 0.25, w / 2 - 3, half)
      ..lineTo(-w / 2 + 3, half)
      ..quadraticBezierTo(-w / 2 + 3, half * 0.25, -2, 0)
      ..quadraticBezierTo(-w / 2 + 3, -half * 0.25, -w / 2 + 3, -half)
      ..close();
    canvas.drawPath(
      glass,
      Paint()..color = palette.surface.withValues(alpha: .7),
    );
    canvas.save();
    canvas.clipPath(glass);
    final sand = Paint()..color = a.withValues(alpha: .85);
    final top = (1 - drain) * half;
    canvas.drawRect(Rect.fromLTRB(-w, -top, w, 0), sand);
    final bottom = drain * half;
    canvas.drawRect(Rect.fromLTRB(-w, half - bottom, w, half), sand);
    if (drain > 0 && drain < 1) {
      canvas.drawRect(Rect.fromLTRB(-0.8, 0, 0.8, half - bottom), sand);
    }
    canvas.restore();
    canvas.drawPath(
      glass,
      Paint()
        ..color = a.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final cap = Paint()..color = a;
    for (final y in [-h / 2, h / 2 - 4]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-w / 2, y, w, 4),
          const Radius.circular(2),
        ),
        cap,
      );
    }
    canvas.restore();
  }

  // A magnifying glass sweeping side to side in front of him.
  void _magnifier(Canvas canvas, Rect d, double sweep) {
    final a = style.accent;
    final r = d.width * 0.15;
    final c = Offset(
      d.center.dx + sweep * d.width * 0.42,
      d.top + d.height * 0.62,
    );
    final handleDir = Offset(math.cos(math.pi / 4), math.sin(math.pi / 4));
    canvas.drawLine(
      c + handleDir * r,
      c + handleDir * r * 2.1,
      Paint()
        ..color = Color.lerp(a, Colors.black, .3)!
        ..strokeWidth = r * 0.34
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, r, Paint()..color = a.withValues(alpha: .14));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.68),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      Paint()
        ..color = palette.surface.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = a
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22,
    );
  }

  @override
  bool shouldRepaint(covariant _PropPainter old) =>
      old.style.kind != style.kind ||
      old.palette != palette ||
      old.layout.size != layout.size ||
      old.still != still;
}

// ─── Confetti ──────────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final ValueListenable<Duration> clock;
  final Offset origin;
  final List<Color> colors;

  _ConfettiPainter({
    required this.clock,
    required this.origin,
    required this.colors,
  }) : super(repaint: clock);

  static const int count = 70;

  static final List<_Bit> _bits = () {
    final r = math.Random(70);
    return [
      for (var i = 0; i < count; i++)
        _Bit(
          angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.3,
          speed: 140 + r.nextDouble() * 220,
          spin: (r.nextDouble() - 0.5) * 12,
          size: 4 + r.nextDouble() * 4,
          shape: i % 3,
          color: i % 4,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = (clock.value - _confettiFrom).inMicroseconds / 1e6;
    final total = _confettiFor.inMicroseconds / 1e6;
    if (t <= 0 || t >= total) return;
    final fade = (1 - t / total).clamp(0.0, 1.0);
    for (final b in _bits) {
      final pos =
          origin +
          Offset(
            math.cos(b.angle) * b.speed * t,
            math.sin(b.angle) * b.speed * t + 0.5 * 520 * t * t,
          );
      final paint = Paint()..color = colors[b.color].withValues(alpha: fade);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(b.spin * t);
      switch (b.shape) {
        case 0:
          canvas.drawPath(_drop(b.size), paint);
        case 1:
          canvas.drawPath(_heart(b.size), paint);
        default:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: b.size * 1.4,
                height: b.size * 0.7,
              ),
              Radius.circular(b.size * 0.2),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  static Path _drop(double s) => Path()
    ..moveTo(0, -s)
    ..cubicTo(s * 0.5, -s * 0.3, s * 0.7, s * 0.1, s * 0.7, s * 0.35)
    ..arcToPoint(Offset(-s * 0.7, s * 0.35), radius: Radius.circular(s * 0.7))
    ..cubicTo(-s * 0.7, s * 0.1, -s * 0.5, -s * 0.3, 0, -s)
    ..close();

  static Path _heart(double s) => Path()
    ..moveTo(0, s * 0.8)
    ..cubicTo(-s * 1.2, -s * 0.1, -s * 0.5, -s * 1.0, 0, -s * 0.35)
    ..cubicTo(s * 0.5, -s * 1.0, s * 1.2, -s * 0.1, 0, s * 0.8)
    ..close();

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.origin != origin || !listEquals(old.colors, colors);
}

class _Bit {
  final double angle, speed, spin, size;
  final int shape, color;
  const _Bit({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.size,
    required this.shape,
    required this.color,
  });
}

// ─── Shared shapes ─────────────────────────────────────────────────────────

// One path, so the puffs do not darken where they overlap.
void _cloud(Canvas canvas, Offset c, double r, Paint paint) {
  final path = Path()
    ..addOval(Rect.fromCircle(center: c, radius: r * 0.62))
    ..addOval(
      Rect.fromCircle(
        center: c + Offset(-r * 0.62, r * 0.18),
        radius: r * 0.44,
      ),
    )
    ..addOval(
      Rect.fromCircle(center: c + Offset(r * 0.66, r * 0.16), radius: r * 0.48),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(c.dx - r * 1.05, c.dy, c.dx + r * 1.12, c.dy + r * 0.62),
        Radius.circular(r * 0.3),
      ),
    );
  canvas.drawPath(path, paint);
}

void _clockGlyph(Canvas canvas, Offset c, double r, Paint paint) {
  final stroke = Paint()
    ..color = paint.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3;
  canvas.drawCircle(c, r, stroke);
  canvas.drawLine(c, c + Offset(0, -r * 0.65), stroke);
  canvas.drawLine(c, c + Offset(r * 0.5, 0), stroke);
}

void _star4(Canvas canvas, Offset c, double r, Color color) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}
