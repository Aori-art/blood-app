// The pieces around the posts: loading skeletons, the empty
// and error messages, and the "all caught up" footer.
import 'package:flutter/material.dart';

import '../app_palette.dart';
import '../skeleton.dart';
import '../streak/dugtong.dart';
import '../streak/streak_controller.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A small dot with a soft ring that breathes out from it. Still under
/// reduced motion.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s * 2,
        child: CustomPaint(painter: _DotPainter(_c, widget.color, s / 2)),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.t, this.color, this.radius) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final v = Curves.easeOut.transform(t.value);
    if (v > 0) {
      canvas.drawCircle(
        c,
        radius * (1 + v),
        Paint()..color = color.withValues(alpha: 0.45 * (1 - v)),
      );
    }
    canvas.drawCircle(c, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Loading ─────────────────────────────────────────────────────────────────

/// Three post-shaped placeholders that breathe together.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading posts',
      child: SkeletonPulse(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              _SkeletonPost(withImage: i != 1),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonPost extends StatelessWidget {
  const _SkeletonPost({required this.withImage});

  final bool withImage;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SkeletonBox.circle(44),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 12),
                  SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 12),
          const SizedBox(height: 8),
          const SkeletonBox(height: 12),
          const SizedBox(height: 8),
          const SkeletonBox(width: 180, height: 12),
          if (withImage) ...[
            const SizedBox(height: 16),
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: SkeletonBox(height: double.infinity, radius: 18),
            ),
          ],
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 36, radius: 999)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 36, radius: 999)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 36, radius: 999)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty, error, end ───────────────────────────────────────────────────────

/// A sleepy Dugtong over a short message, with an optional Retry.
class FeedMessage extends StatelessWidget {
  const FeedMessage({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Dugtong(
                size: 120,
                streak: StreakController.instance.data?.current ?? 0,
                mood: DugtongMood.sleepy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: p.foreground,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.primaryText,
                  side: BorderSide(color: p.primaryBorder),
                  minimumSize: const Size(120, 48),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The end of the feed.
class CaughtUpFooter extends StatelessWidget {
  const CaughtUpFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 18, color: p.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              "You're all caught up",
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}
