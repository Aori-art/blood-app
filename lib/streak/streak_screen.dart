import 'package:flutter/widgets.dart';

import 'streak_controller.dart';

/// The one observer every [StreakScreen] listens to. Add it to
/// `MaterialApp.navigatorObservers`.
///
/// Dialogs and bottom sheets are ignored: they sit on top of a screen without
/// replacing it, so Dugtong should keep talking about the screen underneath.
final RouteObserver<ModalRoute<dynamic>> streakRouteObserver =
    _StreakRouteObserver();

class _StreakRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  bool _overlay(Route<dynamic> r) => r is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_overlay(route) || (previousRoute != null && _overlay(previousRoute))) {
      return;
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_overlay(route) || (previousRoute != null && _overlay(previousRoute))) {
      return;
    }
    super.didPop(route, previousRoute);
  }
}

/// Tells the [StreakScreen]s inside a tab host which tab is showing. Tabs are
/// not routes (an IndexedStack keeps them all mounted), so without this every
/// tab would claim to be the current screen.
class StreakTabScope extends InheritedWidget {
  final bool active;

  const StreakTabScope({super.key, required this.active, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StreakTabScope>()?.active ??
      true;

  @override
  bool updateShouldNotify(StreakTabScope old) => active != old.active;
}

/// Wrap every screen in this so Dugtong knows where the donor is.
///
/// * [id] names the screen (used for screen-aware chat).
/// * [hideBubble] keeps the floating bubble off it.
///
/// The screen counts as "current" from the moment its route is pushed (or
/// uncovered again) until another route covers or pops it. Nothing is counted,
/// so a screen that is left in an odd way can never keep the bubble hidden.
class StreakScreen extends StatefulWidget {
  final String id;
  final bool hideBubble;
  final Widget child;

  const StreakScreen({
    super.key,
    required this.id,
    this.hideBubble = false,
    required this.child,
  });

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> with RouteAware {
  ModalRoute<dynamic>? _route;
  bool _routeCurrent = false;
  bool _tabActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabActive = StreakTabScope.isActive(context);
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) streakRouteObserver.unsubscribe(this);
      _route = route;
      _routeCurrent = false;
      // subscribe() calls didPush() straight away.
      if (route != null) streakRouteObserver.subscribe(this, route);
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant StreakScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.hideBubble != widget.hideBubble) _sync();
  }

  @override
  void dispose() {
    streakRouteObserver.unsubscribe(this);
    StreakController.instance.screenLeft(this);
    super.dispose();
  }

  // ─── RouteAware ──────────────────────────────────────────────────────────

  @override
  void didPush() {
    _routeCurrent = true;
    _sync();
  }

  @override
  void didPopNext() {
    _routeCurrent = true;
    _sync();
  }

  @override
  void didPushNext() {
    _routeCurrent = false;
    _sync();
  }

  @override
  void didPop() {
    _routeCurrent = false;
    _sync();
  }

  void _sync() {
    final c = StreakController.instance;
    // A replaced route (pushReplacement) is told nothing by the observer, but
    // it is no longer active, so it must not claim to be the current screen.
    final alive = _route?.isActive ?? false;
    if (_routeCurrent && _tabActive && alive) {
      c.screenEntered(this, widget.id, hidden: widget.hideBubble);
    } else {
      c.screenLeft(this);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
