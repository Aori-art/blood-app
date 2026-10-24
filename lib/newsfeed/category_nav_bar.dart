// The floating bar of post categories at the bottom of the newsfeed. It
// looks like Home's floating nav (same size, glass and shadow) and takes
// turns with "Go to Home": one is on screen while the other is away.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../home.dart' show FloatingNavMetrics;
import 'feed_chrome.dart' show PulsingDot;

/// The feed's categories, by the post `type` the server sends.
enum FeedCategory {
  all('All', Icons.dynamic_feed_rounded),
  events('Events', Icons.event_rounded),
  urgent('Urgent', Icons.emergency_rounded),
  stories('Stories', Icons.auto_stories_rounded),
  updates('Updates', Icons.campaign_rounded);

  const FeedCategory(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The category of a post `type` ("event", "urgent", "story", "milestone").
  static FeedCategory of(String type) => switch (type) {
    'event' => events,
    'urgent' => urgent,
    'milestone' => updates,
    _ => stories,
  };

  bool matches(String type) => this == all || of(type) == this;

  /// The bar's items for posts of [types]: "All" plus each category that has
  /// a post, or nothing when there is only one category.
  static List<FeedCategory> available(Iterable<String> types) {
    final present = types.map(of).toSet();
    if (present.length < 2) return const [];
    return [all, ...values.where(present.contains)];
  }
}

/// "1 post" / "4 posts".
String postsLabel(int n) => '$n ${n == 1 ? 'post' : 'posts'}';

class CategoryNavBar extends StatefulWidget {
  const CategoryNavBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.visible,
    this.counts = const {},
    this.pageController,
    this.onScrub,
    this.onScrubEnd,
  });

  final List<FeedCategory> items;
  final FeedCategory selected;
  final ValueChanged<FeedCategory> onSelected;

  /// True while the bar is on screen (and "Go to Home" is away).
  final bool visible;

  /// Posts per category, for the labels read out and the Urgent dot.
  final Map<FeedCategory, int> counts;

  /// The pages of the feed: the bar follows its fractional page while the
  /// donor swipes. Null: the selected item is the page.
  final PageController? pageController;

  /// The donor drags a finger along the bar: how many pages that moved (a
  /// slot's width is one page; positive is toward the later items).
  final ValueChanged<double>? onScrub;

  /// The drag along the bar ended (or was cancelled): settle on a page.
  final VoidCallback? onScrubEnd;

  /// The bar's height at normal text size; it grows to [largeTextHeight]
  /// when the system font is large.
  static const double height = FloatingNavMetrics.barHeight;
  static const double largeTextHeight = 72;
  static const double maxWidth = 360;
  static const double sideMargin = 16;

  @override
  State<CategoryNavBar> createState() => _CategoryNavBarState();
}

class _CategoryNavBarState extends State<CategoryNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.visible ? 1 : 0,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    // Out: slow at first, then away (ease-in), as the controller runs back.
    reverseCurve: Curves.easeInCubic.flipped,
  );
  Timer? _delay;
  bool _reduce = false;

  // Kept so the bar can leave with its items when the feed reloads.
  late List<FeedCategory> _items = widget.items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduce) {
      _reduce = reduce;
      // A short cross-fade, no slide.
      _c.duration = reduce
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 280);
      _c.reverseDuration = reduce
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 200);
    }
  }

  @override
  void didUpdateWidget(CategoryNavBar old) {
    super.didUpdateWidget(old);
    if (widget.items.isNotEmpty) _items = widget.items;
    if (old.visible != widget.visible) _sync();
  }

  void _sync() {
    _delay?.cancel();
    if (!widget.visible) {
      _c.reverse();
    } else if (_reduce) {
      _c.forward();
    } else {
      // "Go to Home" starts leaving first; the bar follows a moment later.
      _delay = Timer(const Duration(milliseconds: 90), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _tap(FeedCategory c) {
    HapticFeedback.selectionClick();
    widget.onSelected(c);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 11.5;
    final height = large
        ? CategoryNavBar.largeTextHeight
        : CategoryNavBar.height;
    final slide = _reduce ? 0.0 : 72.0;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Nothing to paint (and no blur to pay for) while it is away.
        if (_c.isDismissed && !widget.visible) return const SizedBox.shrink();
        final t = _t.value;
        return IgnorePointer(
          ignoring: !widget.visible,
          child: ExcludeSemantics(
            excluding: !widget.visible,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * slide),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            CategoryNavBar.sideMargin,
            0,
            CategoryNavBar.sideMargin,
            FloatingNavMetrics.bottomMargin + inset,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: CategoryNavBar.maxWidth,
            ),
            child: RepaintBoundary(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Post categories',
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: _Glass(
                    height: height,
                    child: _Items(
                      items: _items,
                      selected: widget.selected,
                      counts: widget.counts,
                      onTap: _tap,
                      reduce: _reduce,
                      pageController: widget.pageController,
                      onScrub: widget.onScrub,
                      onScrubEnd: widget.onScrubEnd,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass capsule, bottom to top: a soft shadow, the blurred and more
/// saturated page behind it, a tint that is lighter at the top, a sheen over
/// the upper left, a rim that catches the light, and a hairline outside.
class _Glass extends StatelessWidget {
  const _Glass({required this.height, required this.child});

  final double height;
  final Widget child;

  static const double radius = 32;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.isDark;
    final frosted = FloatingNavMetrics.frosted;
    final shape = BorderRadius.circular(radius);

    // The surface, lighter at the top. Never more transparent than this.
    final Color tintTop;
    final Color tintBottom;
    if (!frosted) {
      tintTop = tintBottom = p.surface.withValues(alpha: 0.94);
    } else if (dark) {
      tintTop = p.surface.withValues(alpha: 0.52);
      tintBottom = p.surface.withValues(alpha: 0.68);
    } else {
      tintTop = p.surface.withValues(alpha: 0.60);
      tintBottom = p.surface.withValues(alpha: 0.76);
    }

    final layer = SizedBox.expand(
      child: CustomPaint(
        painter: _GlassPainter(
          tintTop: tintTop,
          tintBottom: tintBottom,
          sheen: Colors.white.withValues(alpha: dark ? 0.10 : 0.22),
          rimStart: Colors.white.withValues(alpha: dark ? 0.35 : 0.85),
          rimMid: Colors.white.withValues(alpha: dark ? 0.05 : 0.15),
          rimEnd: Colors.white.withValues(alpha: dark ? 0.20 : 0.55),
          radius: radius,
        ),
      ),
    );

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.38 : 0.10),
              blurRadius: dark ? 30 : 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: DecoratedBox(
          // The outer hairline keeps the glass defined on a white page.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: p.border.withValues(alpha: 0.5)),
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (frosted)
                  BackdropFilter(
                    // Blur first, then more color: the page shows through
                    // as frosted glass, not as gray.
                    filter: ui.ImageFilter.compose(
                      outer: const ColorFilter.matrix(_saturation15),
                      inner: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    ),
                    child: layer,
                  )
                else
                  layer,
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A color matrix with saturation x1.5.
const List<double> _saturation15 = [
  1.3937, -0.3576, -0.0361, 0, 0, //
  -0.1063, 1.1424, -0.0361, 0, 0, //
  -0.1063, -0.3576, 1.4639, 0, 0, //
  0, 0, 0, 1, 0, //
];

class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.tintTop,
    required this.tintBottom,
    required this.sheen,
    required this.rimStart,
    required this.rimMid,
    required this.rimEnd,
    required this.radius,
  });

  final Color tintTop;
  final Color tintBottom;
  final Color sheen;
  final Color rimStart;
  final Color rimMid;
  final Color rimEnd;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final capsule = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Tint: lighter at the top, where the light catches.
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tintTop, tintBottom],
        ).createShader(rect),
    );

    // Sheen: a diagonal highlight over the upper left, gone by 45 % down.
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.5, size.height * 0.45),
          [sheen, sheen.withValues(alpha: 0)],
        ),
    );

    // Rim: 1.2 px, bright at the top left, faint in the middle, bright again
    // at the bottom right.
    canvas.drawRRect(
      capsule.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rimStart, rimMid, rimEnd],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.tintTop != tintTop ||
      old.tintBottom != tintBottom ||
      old.sheen != sheen ||
      old.rimStart != rimStart ||
      old.rimMid != rimMid ||
      old.rimEnd != rimEnd ||
      old.radius != radius;
}

/// The fractional page of [controller] (what the donor's finger is doing),
/// or the selected index while nothing drives it. Rebuilds [builder] as the
/// page moves, and nothing else.
class _PageBuilder extends StatelessWidget {
  const _PageBuilder({
    required this.controller,
    required this.selectedIndex,
    required this.max,
    required this.reduce,
    required this.builder,
  });

  final PageController? controller;
  final int selectedIndex;
  final int max;
  final bool reduce;
  final Widget Function(BuildContext context, double page) builder;

  double _page() {
    final c = controller;
    if (c != null && c.hasClients) {
      final position = c.position;
      if (position.hasPixels && position.hasContentDimensions) {
        return (c.page ?? selectedIndex.toDouble()).clamp(0.0, max * 1.0);
      }
    }
    return selectedIndex.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      // No pages to follow: glide to the selected item.
      return TweenAnimationBuilder<double>(
        tween: Tween(end: selectedIndex.toDouble()),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, page, _) => builder(context, page),
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => builder(context, _page()),
    );
  }
}

class _Items extends StatefulWidget {
  const _Items({
    required this.items,
    required this.selected,
    required this.counts,
    required this.onTap,
    required this.reduce,
    this.pageController,
    this.onScrub,
    this.onScrubEnd,
  });

  final List<FeedCategory> items;
  final FeedCategory selected;
  final Map<FeedCategory, int> counts;
  final ValueChanged<FeedCategory> onTap;
  final bool reduce;
  final PageController? pageController;
  final ValueChanged<double>? onScrub;
  final VoidCallback? onScrubEnd;

  @override
  State<_Items> createState() => _ItemsState();
}

class _ItemsState extends State<_Items> {
  // The bar is being pressed: the lens swells a little.
  final ValueNotifier<bool> _pressed = ValueNotifier(false);

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = widget.items;
    final n = items.length;
    if (n == 0) return const SizedBox.shrink();
    final selectedIndex = items.indexOf(widget.selected).clamp(0, n - 1);
    final dark = p.isDark;

    return Listener(
      onPointerDown: (_) => _pressed.value = true,
      onPointerUp: (_) => _pressed.value = false,
      onPointerCancel: (_) => _pressed.value = false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotW = constraints.maxWidth / n;
          final lensW = math.min(slotW - 10, 76.0);
          // A finger dragged along the bar moves the pages with it (the lens
          // follows the pages); letting go settles on one.
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: widget.onScrub == null
                ? null
                : (d) => widget.onScrub!(d.delta.dx / slotW),
            onHorizontalDragEnd: widget.onScrubEnd == null
                ? null
                : (_) => widget.onScrubEnd!(),
            onHorizontalDragCancel: widget.onScrubEnd,
            child: _PageBuilder(
              controller: widget.pageController,
              selectedIndex: selectedIndex,
              max: n - 1,
              reduce: widget.reduce,
              builder: (context, page) {
                // 0 at a whole page, 1 halfway between two (never while
                // animations are off).
                final k = widget.reduce
                    ? 0.0
                    : ((page - page.round()).abs() * 2).clamp(0.0, 1.0);
                final stretchX = 1 + 0.22 * k;
                final squashY = 1 - 0.04 * k;
                return Stack(
                  children: [
                    // The glass lens behind the selected item, at the page.
                    Positioned(
                      left: page * slotW + (slotW - lensW) / 2,
                      width: lensW,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _pressed,
                            builder: (context, pressed, child) => AnimatedScale(
                              scale: pressed && !widget.reduce ? 1.08 : 1,
                              duration: widget.reduce
                                  ? Duration.zero
                                  : const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              child: child,
                            ),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.diagonal3Values(
                                stretchX,
                                squashY,
                                1,
                              ),
                              child: CustomPaint(
                                key: const ValueKey('glass-lens'),
                                size: Size(lensW, 44),
                                painter: _LensPainter(
                                  fillTop: Colors.white.withValues(
                                    alpha: dark ? 0.20 : 0.70,
                                  ),
                                  fillBottom: Colors.white.withValues(
                                    alpha: dark ? 0.08 : 0.35,
                                  ),
                                  tint: AppColors.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  rim: Colors.white.withValues(
                                    alpha: dark ? 0.30 : 0.90,
                                  ),
                                  shadow: dark
                                      ? null
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _Item(
                              category: items[i],
                              count: widget.counts[items[i]] ?? 0,
                              selected: items[i] == widget.selected,
                              // 1 on the item the page is on, fading to 0 a
                              // whole page away.
                              closeness: (1 - (page - i).abs()).clamp(0.0, 1.0),
                              onTap: () => widget.onTap(items[i]),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The lens: a small piece of glass, brighter than the bar, with a rim and
/// (in light) a soft shadow.
class _LensPainter extends CustomPainter {
  const _LensPainter({
    required this.fillTop,
    required this.fillBottom,
    required this.tint,
    required this.rim,
    required this.shadow,
  });

  final Color fillTop;
  final Color fillBottom;
  final Color tint;
  final Color rim;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final capsule = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );
    final shadowColor = shadow;
    if (shadowColor != null) {
      canvas.drawRRect(
        capsule.shift(const Offset(0, 3)),
        Paint()
          ..color = shadowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fillBottom],
        ).createShader(rect),
    );
    canvas.drawRRect(capsule, Paint()..color = tint);
    canvas.drawRRect(
      capsule.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim,
    );
  }

  @override
  bool shouldRepaint(_LensPainter old) =>
      old.fillTop != fillTop ||
      old.fillBottom != fillBottom ||
      old.tint != tint ||
      old.rim != rim ||
      old.shadow != shadow;
}

class _Item extends StatelessWidget {
  const _Item({
    required this.category,
    required this.count,
    required this.selected,
    required this.closeness,
    required this.onTap,
  });

  final FeedCategory category;
  final int count;
  final bool selected;
  final double closeness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = Color.lerp(p.muted, p.primaryText, closeness)!;
    return Semantics(
      button: true,
      selected: selected,
      label: '${category.label}, ${postsLabel(count)}',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: 1 + 0.08 * closeness,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(category.icon, size: 22, color: color),
                    // Urgent posts are waiting.
                    if (category == FeedCategory.urgent && count > 0)
                      const Positioned(
                        right: -5,
                        top: -4,
                        child: PulsingDot(color: AppColors.critical, size: 5),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    category.label,
                    maxLines: 1,
                    style: DefaultTextStyle.of(context).style.merge(
                      TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
