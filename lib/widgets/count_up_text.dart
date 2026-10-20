import 'package:flutter/material.dart';

/// A number that counts up to [value] the first time it shows (and eases to a
/// new value when it changes). With animations removed it just shows [value].
class CountUpText extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final String Function(int value)? format;
  final TextAlign? textAlign;

  const CountUpText(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.format,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    String text(int v) => format?.call(v) ?? '$v';
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(text(value), style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        text(v.round()),
        style: style,
        textAlign: textAlign,
        semanticsLabel: text(value),
      ),
    );
  }
}

/// A slim rounded progress bar whose fill grows into place.
class SlimProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color trackColor;
  final double height;

  const SlimProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.trackColor,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ColoredBox(
          color: trackColor,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduce ? v : 0, end: v),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, f, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
