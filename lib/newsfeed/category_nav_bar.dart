// The floating bar of post categories at the bottom of the newsfeed. It
// looks like Home's floating nav (same size, glass and shadow) and takes
// turns with "Go to Home": one is on screen while the other is away.
import 'dart:async';
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

/// The frosted pill: Home's glass (surface at 86 %, a 1 px border, blur 14)
/// over a soft shadow (none in dark).
class _Glass extends StatelessWidget {
  const _Glass({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(32);
    final frosted = FloatingNavMetrics.frosted;
    final glass = DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: frosted ? 0.86 : 0.94),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: p.isDark ? 0.10 : 0.60),
        ),
      ),
      child: child,
    );
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: p.isDark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: frosted
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: glass,
                )
              : glass,
        ),
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({
    required this.items,
    required this.selected,
    required this.counts,
    required this.onTap,
    required this.reduce,
  });

  final List<FeedCategory> items;
  final FeedCategory selected;
  final Map<FeedCategory, int> counts;
  final ValueChanged<FeedCategory> onTap;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = items.length;
    if (n == 0) return const SizedBox.shrink();
    final index = items.indexOf(selected).clamp(0, n - 1);
    final x = n == 1 ? 0.0 : -1 + 2 * index / (n - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotW = constraints.maxWidth / n;
        return Stack(
          children: [
            // The sliding indicator behind the selected item.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedAlign(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(x, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    child: Center(
                      child: Container(
                        width: slotW - 8 < 52 ? slotW - 8 : 52,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.accentBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final c in items)
                  Expanded(
                    child: _Item(
                      category: c,
                      count: counts[c] ?? 0,
                      selected: c == selected,
                      onTap: () => onTap(c),
                      reduce: reduce,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.category,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.reduce,
  });

  final FeedCategory category;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.primaryText : p.muted;
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
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 200),
            builder: (context, tint, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(category.icon, size: 22, color: tint),
                    // Urgent posts are waiting.
                    if (category == FeedCategory.urgent && count > 0)
                      const Positioned(
                        right: -5,
                        top: -4,
                        child: PulsingDot(color: AppColors.critical, size: 5),
                      ),
                  ],
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
                          color: tint,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
