// The Dugtong name as it is drawn in the app: "Dug" in the brand red and
// "tong" in the text color, heavy and tight. DugtongLockup puts the app icon
// beside (or above) it.
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import 'edonate_logo.dart';

/// Progress (0..1) of each part of the lockup, for the splash: the icon pops
/// in, "Dug" slides in from the left and "tong" from the right (they meet in
/// the middle: "dugtong" means to connect), then the tagline fades in.
class DugtongReveal {
  const DugtongReveal({
    required this.icon,
    required this.dug,
    required this.tong,
    required this.tagline,
  });

  final Animation<double> icon;
  final Animation<double> dug;
  final Animation<double> tong;
  final Animation<double> tagline;

  /// Everything shown, nothing moving.
  static const DugtongReveal done = DugtongReveal(
    icon: AlwaysStoppedAnimation(1),
    dug: AlwaysStoppedAnimation(1),
    tong: AlwaysStoppedAnimation(1),
    tagline: AlwaysStoppedAnimation(1),
  );
}

const String kDugtongTagline = 'BLOOD DONATION NETWORK';

class DugtongWordmark extends StatelessWidget {
  const DugtongWordmark({
    super.key,
    this.size = 18,
    this.onGradient = false,
    this.tagline = false,
    this.centered = false,
    this.reveal,
  });

  final double size;

  /// The tagline centered under the name (the splash) rather than left.
  final bool centered;

  /// On the red gradient: "Dug" white, "tong" the soft pink.
  final bool onGradient;

  /// "BLOOD DONATION NETWORK" under the name.
  final bool tagline;

  /// Animates the parts in (the splash); null: all there.
  final DugtongReveal? reveal;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.4 * size / 18,
    );
    final dug = base.copyWith(color: onGradient ? Colors.white : p.primaryText);
    final tong = base.copyWith(
      color: onGradient ? AppColors.onPrimarySoft : p.foreground,
    );

    final Widget name;
    if (reveal == null) {
      // Text.rich, so the name takes the app's font like every other text.
      name = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Dug', style: dug),
            TextSpan(text: 'tong', style: tong),
          ],
        ),
        // The size and weight, for tools that read the text's own style.
        style: base,
        textScaler: scaler,
      );
    } else {
      Widget half(
        String text,
        TextStyle style,
        Animation<double> t,
        double d,
      ) => AnimatedBuilder(
        animation: t,
        builder: (context, child) => Opacity(
          opacity: t.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(d * (1 - t.value), 0),
            child: child,
          ),
        ),
        child: Text(text, style: style, textScaler: scaler),
      );
      name = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          half('Dug', dug, reveal!.dug, -24),
          half('tong', tong, reveal!.tong, 24),
        ],
      );
    }

    Widget line = name;
    if (tagline) {
      final text = Text(
        kDugtongTagline,
        maxLines: 1,
        textScaler: scaler,
        style: TextStyle(
          fontSize: size * 0.52,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: onGradient ? AppColors.onPrimarySoft : p.muted,
        ),
      );
      line = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          name,
          // Never wider than the room it is given.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: reveal == null
                  ? text
                  : FadeTransition(opacity: reveal!.tagline, child: text),
            ),
          ),
        ],
      );
    }
    return Semantics(label: 'Dugtong', excludeSemantics: true, child: line);
  }
}

class DugtongLockup extends StatelessWidget {
  const DugtongLockup({
    super.key,
    this.iconSize = 36,
    this.onGradient = false,
    this.tagline = true,
    this.axis = Axis.horizontal,
    this.wordmarkSize,
    this.reveal,
  });

  final double iconSize;

  /// On the red gradient: the icon gets a soft white ring so it does not melt
  /// into the red, and the name uses its light colors.
  final bool onGradient;
  final bool tagline;

  /// Horizontal: the icon beside the name. Vertical: above it, centered (the
  /// splash).
  final Axis axis;

  /// The name's size; by default half the icon (horizontal) or 0.4 of it
  /// (vertical).
  final double? wordmarkSize;

  final DugtongReveal? reveal;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final size = wordmarkSize ?? iconSize * (vertical ? 0.4 : 0.5);

    Widget icon = EdonateLogo(size: iconSize);
    if (onGradient) {
      icon = Stack(
        children: [
          icon,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(iconSize * 0.23),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final r = reveal;
    if (r != null) {
      icon = AnimatedBuilder(
        animation: r.icon,
        builder: (context, child) => Opacity(
          opacity: r.icon.value.clamp(0.0, 1.0),
          // 0.7 → 1 with a small overshoot.
          child: Transform.scale(scale: 0.7 + 0.3 * r.icon.value, child: child),
        ),
        child: icon,
      );
    }

    final name = DugtongWordmark(
      size: size,
      onGradient: onGradient,
      tagline: tagline,
      centered: vertical,
      reveal: r,
    );

    final Widget body = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              SizedBox(height: iconSize * 0.25),
              name,
            ],
          )
        : LayoutBuilder(
            builder: (context, constraints) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 10),
                // The name gives way when the room is tight; with no limit
                // (an unbounded Row) it simply takes its size.
                if (constraints.maxWidth.isFinite)
                  Flexible(child: name)
                else
                  name,
              ],
            ),
          );
    return Semantics(label: 'Dugtong', excludeSemantics: true, child: body);
  }
}
