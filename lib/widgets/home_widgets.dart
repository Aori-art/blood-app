// Visual building blocks for the Home tab (HomeContent in home.dart). They
// only draw what they are given: no data loading here.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anim.dart';
import '../app_colors.dart';
import '../app_palette.dart';
import '../shared_design.dart' show kHeaderGradient;
import '../skeleton.dart';
import 'count_up_text.dart';

/// The greeting header: brand gradient, soft decorative circles, a sun or
/// moon for the time of day beside the greeting, and a gentle entrance.
class HomeHeader extends StatelessWidget {
  final String greeting;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const HomeHeader({
    super.key,
    required this.greeting,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  static IconData timeOfDayIcon(int hour) {
    if (hour >= 5 && hour < 17) return Icons.wb_sunny_rounded;
    if (hour >= 17 && hour < 19) return Icons.wb_twilight_rounded;
    return Icons.nightlight_round;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: kHeaderGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(right: -40, top: -50, child: _Circle(160, .08)),
            const Positioned(right: 90, bottom: -70, child: _Circle(120, .06)),
            const Positioned(left: -36, top: 10, child: _Circle(80, .05)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                screenHeight * 0.06,
                20,
                screenHeight * 0.03,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FadeSlideIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                timeOfDayIcon(DateTime.now().hour),
                                size: 15,
                                color: AppColors.onPrimarySoft,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  greeting,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.onPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double alpha;
  const _Circle(this.size, this.alpha);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.onPrimary.withValues(alpha: alpha),
      ),
    ),
  );
}

/// The shared card look on Home: surface, radius 20, a hairline border and
/// the palette's soft shadow.
BoxDecoration homeCardDecoration(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: context.palette.border),
  boxShadow: context.palette.shadow,
);

/// Scales [child] to 0.97 while a finger is down. Purely visual: it adds no
/// tap action (and so nothing for screen readers to announce).
class PressFeedback extends StatefulWidget {
  final Widget child;
  final double scale;
  const PressFeedback({super.key, required this.child, this.scale = 0.97});

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// A small stat card: a tinted icon circle, the value and a label. A numeric
/// value counts up the first time it shows (not again on refresh).
class HomeStatTile extends StatefulWidget {
  final String label;
  final String? text;
  final int? number;
  final bool loading;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  /// Opens the preview of this stat. Not offered while the value loads.
  final VoidCallback? onTap;

  /// What a screen reader says about the card ("Blood type A+, double tap
  /// for details").
  final String? semanticLabel;

  const HomeStatTile({
    super.key,
    required this.label,
    this.text,
    this.number,
    required this.loading,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.onTap,
    this.semanticLabel,
  });

  @override
  State<HomeStatTile> createState() => _HomeStatTileState();
}

class _HomeStatTileState extends State<HomeStatTile> {
  // Counts up the first time only: after a refresh the value just appears.
  bool _countUp = true;

  @override
  void didUpdateWidget(covariant HomeStatTile old) {
    super.didUpdateWidget(old);
    if (!old.loading && widget.loading) _countUp = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: p.foreground,
    );
    Widget value;
    if (widget.loading) {
      value = const SkeletonPulse(child: SkeletonBox(width: 34, height: 18));
    } else if (widget.number != null && _countUp) {
      value = CountUpText(widget.number!, style: style);
    } else if (widget.number != null) {
      value = Text('${widget.number}', style: style);
    } else {
      value = Text(widget.text ?? '—', style: style);
    }
    final tappable = widget.onTap != null && !widget.loading;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, color: widget.iconColor, size: 18),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: value),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          ],
      ),
    );
    Widget card = Container(
      decoration: homeCardDecoration(context),
      // The ripple is painted on this Material, inside the rounded card.
      child: Material(
        type: MaterialType.transparency,
        child: tappable
            ? InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
                child: content,
              )
            : content,
      ),
    );
    if (tappable) {
      card = Semantics(
        button: true,
        label: widget.semanticLabel ?? widget.label,
        excludeSemantics: true,
        child: card,
      );
    }
    return PressFeedback(child: card);
  }
}

/// A rounded status chip: [dot] (a plain or pulsing dot) and the label.
class HomeStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final Widget dot;

  const HomeStatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    required this.dot,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Section titles on Home: 16, bold.
class HomeSectionTitle extends StatelessWidget {
  final String text;
  const HomeSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
      color: context.palette.foreground,
    ),
  );
}

/// Parses the long dates Home shows ("October 3, 2026") back to a date.
DateTime? parseLongDate(String s) {
  const months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  final m = RegExp(
    r'^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$',
  ).firstMatch(s.trim());
  if (m == null) return DateTime.tryParse(s);
  final month = months.indexOf(m.group(1)!.toLowerCase());
  if (month < 0) return null;
  return DateTime(int.parse(m.group(3)!), month + 1, int.parse(m.group(2)!));
}

/// A faint pattern of drops for the brand-red Request Blood tile.
class DropPatternPainter extends CustomPainter {
  const DropPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.onPrimary.withValues(alpha: .09);
    final rnd = math.Random(11);
    const step = 26.0;
    for (var y = 6.0; y < size.height; y += step) {
      for (var x = (y ~/ step).isEven ? 8.0 : 21.0; x < size.width; x += step) {
        if (rnd.nextDouble() < .35) continue;
        _drop(canvas, Offset(x, y), 5 + rnd.nextDouble() * 3, paint);
      }
    }
  }

  void _drop(Canvas canvas, Offset c, double r, Paint paint) {
    final h = r * 2.6;
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..cubicTo(
        c.dx + r * .4,
        c.dy + h * .25,
        c.dx + r,
        c.dy + h * .45,
        c.dx + r,
        c.dy + h - r,
      )
      ..arcToPoint(Offset(c.dx - r, c.dy + h - r), radius: Radius.circular(r))
      ..cubicTo(
        c.dx - r,
        c.dy + h * .45,
        c.dx - r * .4,
        c.dy + h * .25,
        c.dx,
        c.dy,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DropPatternPainter oldDelegate) => false;
}

/// A placeholder card for an appointment that is still loading.
class HomeAppointmentSkeleton extends StatelessWidget {
  const HomeAppointmentSkeleton({super.key});

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: homeCardDecoration(context),
      child: const Row(
        children: [
          SkeletonBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 10),
                SizedBox(height: 6),
                SkeletonBox(width: 120, height: 10),
              ],
            ),
          ),
          SkeletonBox(width: 64, height: 22, radius: 11),
        ],
      ),
    ),
  );
}
