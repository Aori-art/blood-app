import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Makes the skeleton shapes inside it breathe slowly. With reduced motion
/// they just stay still.
class SkeletonPulse extends StatefulWidget {
  final Widget child;
  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: 1 - 0.45 * Curves.easeInOut.transform(_c.value),
        child: child,
      ),
      child: widget.child,
    ),
  );
}

/// A gray placeholder: a rounded bar, or a circle.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final bool circle;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.circle = false,
    this.radius = 8,
  });

  /// A circle of [diameter].
  const SkeletonBox.circle(double diameter, {super.key})
    : width = diameter,
      height = diameter,
      circle = true,
      radius = 0;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.palette.border,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}
