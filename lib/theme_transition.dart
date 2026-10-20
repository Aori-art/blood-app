import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'theme_controller.dart';

/// What the reveal overlay paints: a picture of the old look, cut by a
/// growing circle through which the live new theme shows.
@immutable
class ThemeRevealState {
  final ui.Image image;
  final Offset origin;
  final double radius;

  /// The new theme's readable red, for the ring on the circle's edge.
  final Color ring;

  const ThemeRevealState({
    required this.image,
    required this.origin,
    required this.radius,
    required this.ring,
  });

  ThemeRevealState withRadius(double r) =>
      ThemeRevealState(image: image, origin: origin, radius: r, ring: ring);
}

/// Switches light / dark with a circular reveal that grows from [originKey]
/// (the switch the donor flipped).
class ThemeTransition {
  ThemeTransition._();

  /// Wraps the whole app (see main.dart) so the current look can be captured.
  static final GlobalKey boundaryKey = GlobalKey();

  /// True while a reveal runs. MaterialApp then switches its theme instantly,
  /// so nothing cross-fades underneath the reveal.
  static final ValueNotifier<bool> running = ValueNotifier(false);

  /// The overlay data, read by [ThemeRevealHost].
  static final ValueNotifier<ThemeRevealState?> state = ValueNotifier(null);

  static const Duration duration = Duration(milliseconds: 650);

  static Future<void> toggle(
    BuildContext context, {
    GlobalKey? originKey,
  }) async {
    if (running.value) return;
    final controller = ThemeController.instance;
    final toDark = !controller.isDark;

    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce || boundary == null || !boundary.attached) {
      await controller.setDark(toDark); // the plain 250 ms fade
      return;
    }

    final view = View.of(context);
    final screen = MediaQuery.sizeOf(context);
    final origin = _originOf(originKey) ?? Offset(screen.width / 2, 0);
    final maxRadius = [
      Offset.zero,
      Offset(screen.width, 0),
      Offset(0, screen.height),
      Offset(screen.width, screen.height),
    ].map((c) => (c - origin).distance).reduce(math.max);

    ui.Image? image;
    var switched = false;
    running.value = true;
    try {
      HapticFeedback.mediumImpact();

      // Capture the old look once the current frame is painted.
      await WidgetsBinding.instance.endOfFrame;
      image = await boundary.toImage(
        pixelRatio: math.min(view.devicePixelRatio, 2.0),
      );

      // Cover the screen with it, and only switch once that is on screen, so
      // the live app changes while it is fully hidden.
      state.value = ThemeRevealState(
        image: image,
        origin: origin,
        radius: 0,
        ring: (toDark ? AppPalette.dark : AppPalette.light).primaryText,
      );
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await controller.setDark(toDark);
      switched = true;

      final watch = Stopwatch()..start();
      while (true) {
        final t = (watch.elapsedMicroseconds / duration.inMicroseconds).clamp(
          0.0,
          1.0,
        );
        state.value = state.value?.withRadius(
          maxRadius * Curves.easeInOutCubic.transform(t),
        );
        if (t >= 1) break;
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {
      // Whatever went wrong, the mode below still switches.
    } finally {
      if (!switched) await controller.setDark(toDark);
      state.value = null;
      image?.dispose();
      running.value = false;
    }
  }

  static Offset? _originOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// Paints the reveal above the whole app (the last child of the app Stack).
class ThemeRevealHost extends StatelessWidget {
  const ThemeRevealHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeRevealState?>(
      valueListenable: ThemeTransition.state,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        return AbsorbPointer(
          child: ExcludeSemantics(
            child: CustomPaint(size: Size.infinite, painter: _RevealPainter(s)),
          ),
        );
      },
    );
  }
}

class _RevealPainter extends CustomPainter {
  final ThemeRevealState s;

  _RevealPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final circle = Rect.fromCircle(center: s.origin, radius: s.radius);

    // The old look everywhere outside the circle.
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addOval(circle),
      ),
    );
    final src = Rect.fromLTWH(
      0,
      0,
      s.image.width.toDouble(),
      s.image.height.toDouble(),
    );
    canvas.drawImageRect(
      s.image,
      src,
      screen,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    if (s.radius <= 0) return;
    // A soft glowing edge: wide faint strokes under a thin bright one.
    for (final (width, alpha) in const [
      (18.0, 0.06),
      (10.0, 0.10),
      (3.0, 0.35),
    ]) {
      canvas.drawCircle(
        s.origin,
        s.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = s.ring.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RevealPainter old) =>
      old.s.radius != s.radius || old.s.image != s.image;
}
