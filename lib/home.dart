import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'streak/streak_screen.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'alerts.dart';
import 'anim.dart';
import 'blood_requests/blood_request_api.dart';
import 'blood_requests/blood_request_detail_screen.dart';
import 'blood_requests/blood_request_models.dart';
import 'blood_requests/blood_request_widgets.dart';
import 'blood_requests/blood_requests_screen.dart';
import 'blood_requests/request_blood_screen.dart';
import 'book.dart';
import 'check.dart';
import 'config.dart';
import 'digital_id.dart';
import 'digital_id_service.dart';
import 'history.dart';
import 'home_nav_glass.dart';
import 'home_nav.dart';
import 'home_nav_visibility.dart';
import 'home_stat_sheets.dart';
import 'newsfeed.dart';
import 'donation_history.dart';
import 'notification_service.dart';
import 'shared_design.dart';
import 'unread_notifications.dart';
import 'verify.dart';
import 'app_palette.dart';
import 'my_avatar.dart';
import 'my_avatar_controller.dart';
import 'skeleton.dart';
import 'widgets/count_up_text.dart';
import 'widgets/glow_pulse.dart';
import 'widgets/home_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin
    implements HomeNavHost {
  int _selectedIndex = 0;
  int _donorId = 0;

  late List<Widget> _screens;
  StreamSubscription<void>? _alertsTapSub;

  // The five tabs are pages side by side: a swipe moves between them and a
  // tap on the nav glides there. The controller's animation is the
  // fractional tab the nav's lens follows.
  late final TabController _tabs;

  // The route Home is on, so HomeNav can pop back to it.
  ModalRoute<dynamic>? _route;

  // Dragging a finger along the nav moves the pages with it: the drag is
  // given to the TabBarView's own scroll position (found under this key),
  // so the pages, the lens and the items all follow the finger.
  final GlobalKey _pagerKey = GlobalKey();
  Drag? _scrub;
  double _scrubPage = 0;
  int _scrubTab = 0;

  @override
  void initState() {
    super.initState();
    _loadDonorId();
    _screens = [
      HomeContent(onNavigateToTab: _selectTab),
      const BookScreen(),
      const CheckScreen(),
      DonationHistoryScreen(),
      const SizedBox(child: Center(child: CircularProgressIndicator())),
    ];

    if (NotificationService.instance.openAlertsOnStart) {
      _selectedIndex = 4;
      NotificationService.instance.consumeOpenAlertsOnStart();
    }

    _tabs = TabController(
      length: 5,
      vsync: this,
      initialIndex: _selectedIndex,
    );
    _tabs.animation!.addListener(_onTabPosition);
    HomeNav.register(this);

    _alertsTapSub = NotificationService.instance.onAlertsTapped.listen((_) {
      if (mounted) _selectTab(4);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    // Every other screen keeps the nav's full room again.
    HomeNavVisibility.instance.reset();
    HomeNav.unregister(this);
    _tabs.animation?.removeListener(_onTabPosition);
    _tabs.dispose();
    _alertsTapSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDonorId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorIdString = prefs.getString('donorId');
    final id = int.tryParse(donorIdString ?? '0') ?? 0;

    if (mounted) {
      setState(() {
        _donorId = id;
        _screens = [
          HomeContent(onNavigateToTab: _selectTab),
          const BookScreen(),
          const CheckScreen(),
          DonationHistoryScreen(),
          AlertsScreen(donorId: _donorId),
        ];
      });
    }

    if (id > 0) {
      // Keep the Alerts badge in step with the server while Home is open.
      UnreadNotifications.instance.start();
      await _saveFcmTokenToServer(id);
    } else {
      debugPrint("FCM token not saved: donorId is missing.");
    }
  }

  Future<void> _saveFcmTokenToServer(int donorId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) {
        debugPrint("FCM token is null or empty.");
        return;
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/save_fcm_token.php'),
            body: {'donor_id': donorId.toString(), 'fcm_token': token},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("Save FCM token response: ${response.body}");
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  /// A tab became the current one: what selecting a tab has always done
  /// (the nav, and with it the Check button, reacts to [_selectedIndex]).
  void _activate(int index) {
    setState(() => _selectedIndex = index);
  }

  /// A tap on the nav, or a tab chosen from code: the pages glide there (a
  /// jump when animations are off) and the tab is current at once.
  void _selectTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    _activate(index);
    if (_tabs.index != index) {
      _tabs.animateTo(
        index,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// The pages moved. While a swipe drags them, the tab under the finger
  /// becomes current once it is more than 0.55 of a page away from the last
  /// one (so hovering half way does not make the Check button flicker). A
  /// tap's glide is ignored here: its tab was made current at the tap.
  void _onTabPosition() {
    if (_tabs.indexIsChanging) return;
    final position = _tabs.animation!.value;
    if ((position - _selectedIndex).abs() <= 0.55) return;
    final next = position.round().clamp(0, _screens.length - 1);
    if (next != _selectedIndex) _activate(next);
  }

  // ── Dragging along the nav ──────────────────────────────────────────────

  /// The TabBarView's scroll position (its PageView is the first horizontal
  /// scrollable below it).
  ScrollPosition? _pagerPosition() {
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (s.position.axis == Axis.horizontal) {
          found = s;
          return;
        }
      }
      e.visitChildElements(visit);
    }

    _pagerKey.currentContext?.visitChildElements(visit);
    final position = found?.position;
    if (position == null ||
        !position.hasPixels ||
        !position.hasViewportDimension) {
      return null;
    }
    return position;
  }

  /// A fifth of the nav (it is the screen less 16 px on each side).
  double get _slotWidth => (MediaQuery.sizeOf(context).width - 32) / 5;

  void _scrubStart(DragStartDetails d) {
    final position = _pagerPosition();
    if (position == null) return;
    _scrub?.cancel();
    _scrubTab = _selectedIndex;
    _scrub = position.drag(d, () => _scrub = null);
    _scrubTo(d.localPosition.dx, d.globalPosition, d.sourceTimeStamp);
  }

  void _scrubUpdate(DragUpdateDetails d) =>
      _scrubTo(d.localPosition.dx, d.globalPosition, d.sourceTimeStamp);

  /// The finger at [x] along the nav: the pages go to the tab under it
  /// (fractional between two), a tick for each tab passed.
  void _scrubTo(double x, Offset global, Duration? timeStamp) {
    final position = _pagerPosition();
    final drag = _scrub;
    if (position == null || drag == null) return;
    final page = (x / _slotWidth - 0.5).clamp(0.0, 4.0);
    _scrubPage = page;
    final delta = page * position.viewportDimension - position.pixels;
    if (delta.abs() > 0.01) {
      // A drag moves the content against the finger: pixels grow as the
      // update's delta goes negative.
      drag.update(
        DragUpdateDetails(
          globalPosition: global,
          delta: Offset(-delta, 0),
          primaryDelta: -delta,
          sourceTimeStamp: timeStamp,
        ),
      );
    }
    final tab = page.round();
    if (tab != _scrubTab) {
      _scrubTab = tab;
      HapticFeedback.selectionClick();
    }
  }

  void _scrubEnd(DragEndDetails d) => _settleScrub(d.primaryVelocity ?? 0);

  void _scrubCancel() => _settleScrub(0);

  /// The finger left the nav: on to the nearest tab, or the next one in the
  /// direction of a flick (faster than 300 px/s).
  void _settleScrub(double velocity) {
    final drag = _scrub;
    if (drag == null) return;
    _scrub = null;
    drag.end(DragEndDetails(primaryVelocity: 0));
    final position = _pagerPosition();
    if (position == null) return;
    final page = _scrubPage;
    var target = page.round();
    if (velocity > 300) {
      target = (page - 1e-6).floor() + 1;
    } else if (velocity < -300) {
      target = (page + 1e-6).ceil() - 1;
    }
    target = target.clamp(0, _screens.length - 1);
    final to = target * position.viewportDimension;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(to);
    } else {
      position.animateTo(
        to,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ── HomeNavHost ─────────────────────────────────────────────────────────

  /// HomeNav.goTo: back to Home (closing every screen above it), then the
  /// tab, the same way a tap selects it.
  @override
  void showTab(int index) {
    final route = _route;
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    _selectTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Theme(
      // Floating snack bars are laid out against the bottom of the screen;
      // lift them over the floating nav.
      data: theme.copyWith(
        snackBarTheme: theme.snackBarTheme.copyWith(
          insetPadding: const EdgeInsets.fromLTRB(
            16,
            5,
            16,
            kBottomNavBarHeight + 8,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: context.palette.background,
        // The nav floats over the tabs and nothing is painted behind it. The
        // tabs resize for the keyboard themselves; the keyboard just covers
        // the nav, as it did before.
        resizeToAvoidBottomInset: false,
        // The tabs rebuild their bottom room when the nav hides or shows.
        body: HomeNavScope(child: Stack(
          children: [
            // The tabs are pages: swipe between them. Every tab stays alive
            // once it has been shown, so switching tabs (e.g. tapping Home
            // mid eligibility-check) never loses its state.
            Positioned.fill(
              child: TabBarView(
                key: _pagerKey,
                controller: _tabs,
                children: [
                  for (var i = 0; i < _screens.length; i++)
                    _KeepAliveTab(
                      // A tab off screen stops its animations.
                      child: AnimatedBuilder(
                        animation: _tabs.animation!,
                        builder: (context, child) => TickerMode(
                          enabled: (_tabs.animation!.value - i).abs() < 1,
                          child: child!,
                        ),
                        // The tabs are not routes: tell each one whether it
                        // is showing, so Dugtong knows which tab the donor
                        // is on (and the tab can freshen up when it is).
                        child: StreakTabScope(
                          active: i == _selectedIndex,
                          child: _screens[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: safeBottom + FloatingNavMetrics.bottomMargin,
              // A finger dragged along the nav (from an item or the Check
              // button) moves the pages; a tap still goes to the item.
              child: RawGestureDetector(
                behavior: HitTestBehavior.deferToChild,
                gestures: {
                  HorizontalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        HorizontalDragGestureRecognizer
                      >(HorizontalDragGestureRecognizer.new, (r) {
                        r.onStart = _scrubStart;
                        r.onUpdate = _scrubUpdate;
                        r.onEnd = _scrubEnd;
                        r.onCancel = _scrubCancel;
                      }),
                },
                child: RepaintBoundary(
                  child: _FloatingNav(
                    selectedIndex: _selectedIndex,
                    onSelect: _selectTab,
                    position: _tabs.animation,
                  ),
                ),
              ),
            ),
          ],
        )),
      ),
    );
  }
}

// ── FLOATING BOTTOM NAV ───────────────────────────────────────────────────────

/// Sizes of the floating bottom bar, shared with every screen that scrolls
/// under it.
class FloatingNavMetrics {
  FloatingNavMetrics._();

  /// Height of the glass bar.
  static const double barHeight = 64;

  /// Gap between the bar and the system inset at the bottom of the screen.
  static const double bottomMargin = 10;

  /// How far the raised Check button sticks out above the bar.
  static const double overhang = 38;

  /// The Check button: raised out of the bar, and sunk into it.
  static const double checkSize = 62;
  static const double checkBlendedSize = 48;

  /// Raised, the button's centre sits this far above the bar's top edge.
  static const double checkRise = 6;

  /// The scoop in the bar's top edge is concentric with the raised button:
  /// button radius + 8.
  static const double scoopRadius = checkSize / 2 + 8;
  static const double scoopDepth = scoopRadius - checkRise;

  /// What every scrollable inside [HomeScreen] ends with, so its last item
  /// is never hidden behind the bar.
  /// While the donor has swiped the bar away it is the handle's room
  /// instead (the same value as always while the bar is shown).
  static double bottomPadding(BuildContext context) =>
      HomeNavScope.reserveOf(context, shown: barHeight + bottomMargin) +
      MediaQuery.paddingOf(context).bottom +
      24;

  /// True while the bar blurs what is behind it. The bar switches this off by
  /// itself (solid white at 94 %) if frames keep taking too long.
  static bool frosted = true;
}

/// Height the nav takes at the bottom of the screen, the raised Check button
/// included but the system inset excluded (add `MediaQuery.padding.bottom`).
/// Anything floating over the shell, like the Dugtong bubble, stays above it.
const double kBottomNavBarHeight =
    FloatingNavMetrics.barHeight +
    FloatingNavMetrics.bottomMargin +
    FloatingNavMetrics.overhang;

/// The bar's outline: a pill whose top edge has a circular scoop around the
/// Check button, [depth] pixels deep, with eased corners where the scoop meets
/// the edge. Fill, border, shadow and the backdrop clip all use this one path.
Path _floatingNavPath(Size size, double depth) {
  final w = size.width;
  final h = size.height;
  final r = h / 2;
  if (depth < 1) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)),
    );
  }

  const radius = FloatingNavMetrics.scoopRadius;
  const fillet = 14.0;
  final d = math.min(depth, radius - 2);
  final cx = w / 2;
  final yc = d - radius; // the scoop circle's centre, relative to the top edge
  // The fillet circles touch the top edge and the scoop from the bar's side.
  final xf = math.sqrt(d * (2 * radius + 2 * fillet - d));
  final left = Offset(cx - xf, fillet);
  final right = Offset(cx + xf, fillet);
  final phiLeft = math.atan2(yc - fillet, xf);
  final phiRight = math.atan2(yc - fillet, -xf);
  final psiLeft = math.atan2(fillet - yc, -xf);
  final psiRight = math.atan2(fillet - yc, xf);

  return Path()
    ..moveTo(r, 0)
    ..lineTo(left.dx, 0)
    ..arcTo(
      Rect.fromCircle(center: left, radius: fillet),
      -math.pi / 2,
      phiLeft + math.pi / 2,
      false,
    )
    ..arcTo(
      Rect.fromCircle(center: Offset(cx, yc), radius: radius),
      psiLeft,
      psiRight - psiLeft,
      false,
    )
    ..arcTo(
      Rect.fromCircle(center: right, radius: fillet),
      phiRight,
      -math.pi / 2 - phiRight,
      false,
    )
    ..lineTo(w - r, 0)
    ..arcTo(Rect.fromLTWH(w - h, 0, h, h), -math.pi / 2, math.pi, false)
    ..lineTo(r, h)
    ..arcTo(Rect.fromLTWH(0, 0, h, h), math.pi / 2, math.pi, false)
    ..close();
}

class _NavClipper extends CustomClipper<Path> {
  final ValueGetter<double> depth;

  _NavClipper(this.depth, Listenable reclip) : super(reclip: reclip);

  @override
  Path getClip(Size size) => _floatingNavPath(size, depth());

  @override
  bool shouldReclip(covariant _NavClipper oldClipper) => true;
}

class _RingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double width;
  final Color color;

  const _RingPainter(this.center, this.radius, this.width, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.width != width ||
      old.color != color;
}

class _NavDef {
  final int index;
  final IconData icon;
  final String label;

  const _NavDef(this.index, this.icon, this.label);
}

const _kNavDefs = <_NavDef>[
  _NavDef(0, Icons.home_rounded, 'Home'),
  _NavDef(1, Icons.calendar_month_rounded, 'Book an appointment'),
  _NavDef(3, Icons.history_rounded, 'Donation history'),
  _NavDef(4, Icons.notifications_rounded, 'Notifications'),
];

/// The floating bar: Home, Book, [Check], History, Alerts.
///
/// Every animation is driven by the selected index changing, so a tap and a
/// tab switch made from code (a "Check Eligibility" button on Home) look the
/// same.
///
/// * `_move` runs the Check button between BLENDED (t = 0: a 48 px circle
///   inside the bar, the bar's top edge flat) and RAISED (t = 1: a 62 px
///   circle 6 px above the top edge, with a scoop in the bar around it).
/// * A glass lens sits behind the selected tab. It follows the pages'
///   fractional position ([_FloatingNav.position]), so it moves with a swipe
///   and glides with a tap's page animation; it has no animation of its own.
class _FloatingNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The fractional tab the pages are at (the TabController's animation):
  /// the lens and the item colors follow it while the donor swipes.
  final Animation<double>? position;

  const _FloatingNav({
    required this.selectedIndex,
    required this.onSelect,
    this.position,
  });

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav>
    with TickerProviderStateMixin {
  static const int _check = 2;
  static const int _slotCount = 5;

  /// Room above the bar for the raised button, its bob and the overshoot.
  static const double _top = FloatingNavMetrics.overhang + 8;

  // t: 0 = blended, 1 = raised. One linear controller; the curve depends on
  // the direction so an interrupted move continues from where it was.
  late final AnimationController _move;
  double _tFrom = 1;
  double _tTo = 1;
  bool _raising = true;
  double _glowFrom = 1;

  // The bar is being pressed: the lens swells a little.
  final ValueNotifier<bool> _pressed = ValueNotifier(false);

  late final AnimationController _pop; // the selected icon's small pop
  late final AnimationController _squash; // the Check press
  late final AnimationController _settle; // the ring after sinking
  late final AnimationController _idle; // bob (3 s) and ring (4 s): 12 s loop

  int _popIndex = 0;
  int _gen = 0;
  bool _reduced = false;
  bool _depsReady = false;

  int _frames = 0;
  int _slowFrames = 0;

  @override
  void initState() {
    super.initState();
    final onCheck = widget.selectedIndex == _check;
    _tFrom = _tTo = onCheck ? 0 : 1;
    _raising = !onCheck;
    _glowFrom = onCheck ? 0 : 1;
    _popIndex = widget.selectedIndex;

    _move = AnimationController(vsync: this, value: 1)
      ..addStatusListener(_moveStatus);
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _squash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    // Debug builds are slow by nature: only judge release/profile frames.
    if (!kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!_depsReady || reduced != _reduced) {
      _depsReady = true;
      _reduced = reduced;
      _syncIdle();
    }
  }

  @override
  void didUpdateWidget(covariant _FloatingNav old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _changed(old.selectedIndex, widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    _move.dispose();
    _pressed.dispose();
    _pop.dispose();
    _squash.dispose();
    _settle.dispose();
    _idle.dispose();
    super.dispose();
  }

  // ── Transitions ───────────────────────────────────────────────────────────

  void _changed(int from, int to) {
    final gen = ++_gen;
    final toCheck = to == _check;
    final fromCheck = from == _check;

    if (!toCheck && _squash.value > 0) _squash.reverse();
    if (toCheck) HapticFeedback.mediumImpact();
    if (!toCheck) {
      _popIndex = to;
      if (!_reduced) _pop.forward(from: 0);
    }

    if (toCheck) {
      if (_reduced) {
        _beginMove(0);
      } else {
        _squash.forward(from: 0).then((_) {
          if (!mounted || gen != _gen) return;
          _squash.reverse();
          _beginMove(0);
        });
      }
    } else if (fromCheck) {
      // The circle rises out of the bar (the lens comes with the pages).
      _beginMove(1);
    }
  }

  void _beginMove(double target) {
    final p = _move.value;
    final t0 = _tAt(p);
    final g0 = _glowAt(p);
    if ((t0 - target).abs() < 0.001 && !_move.isAnimating) {
      _tFrom = _tTo = target;
      return;
    }
    _glowFrom = g0;
    _tFrom = t0;
    _tTo = target;
    _raising = target > t0;
    _move.duration = Duration(
      milliseconds: _reduced ? 120 : (_raising ? 520 : 420),
    );
    _move.forward(from: 0);
    _syncIdle();
  }

  void _moveStatus(AnimationStatus status) {
    // The settle ring after the circle has sunk into the bar.
    if (status == AnimationStatus.completed &&
        !_raising &&
        _tTo == 0 &&
        !_reduced) {
      _settle.forward(from: 0);
    }
  }

  void _syncIdle() {
    final want = _tTo > 0.5 && !_reduced;
    if (want && !_idle.isAnimating) {
      _idle.repeat();
    } else if (!want && _idle.isAnimating) {
      _idle.stop();
    }
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (!mounted || !FloatingNavMetrics.frosted) return;
    if (!_move.isAnimating && !_lensMoving) return;
    for (final t in timings) {
      _frames++;
      if (t.totalSpan > const Duration(milliseconds: 24)) _slowFrames++;
    }
    if (_frames >= 45 && _slowFrames / _frames > 0.3) {
      setState(() => FloatingNavMetrics.frosted = false);
    }
  }

  // ── Values read while painting ────────────────────────────────────────────

  double _tAt(double p) {
    if (_reduced) return _tTo;
    final curve = _raising ? Curves.easeOutBack : Curves.easeInOutCubic;
    return _tFrom + (_tTo - _tFrom) * curve.transform(p);
  }

  /// Glow and "Check" label: gone within the first 40 % of the sink, back
  /// during the last 60 % of the rise.
  double _glowAt(double p) {
    if (_reduced) return _tTo;
    if (_raising) {
      final k = Curves.easeOut.transform(((p - 0.4) / 0.6).clamp(0.0, 1.0));
      return _glowFrom + (1 - _glowFrom) * k;
    }
    final k = Curves.easeOut.transform((p / 0.4).clamp(0.0, 1.0));
    return _glowFrom * (1 - k);
  }

  double _depth() => (FloatingNavMetrics.scoopDepth * _tAt(_move.value)).clamp(
    0.0,
    FloatingNavMetrics.scoopRadius - 2,
  );

  /// The fractional tab the lens and the items follow.
  Animation<double> get _position =>
      widget.position ??
      AlwaysStoppedAnimation(widget.selectedIndex.toDouble());

  /// The pages are between two tabs (a swipe or a tap's glide).
  bool get _lensMoving {
    final v = widget.position?.value ?? 0;
    return v != v.roundToDouble();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  void _tap(int i) {
    HapticFeedback.selectionClick();
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    const barH = FloatingNavMetrics.barHeight;
    final frosted = FloatingNavMetrics.frosted;
    final p = context.palette;
    final glassColors = NavGlassColors.of(p, frosted: frosted);
    Path outline(Size size) => _floatingNavPath(size, _depth());

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final slotW = w / _slotCount;
          return SizedBox(
            height: _top + barH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Soft shadow and the hairline, outside the glass.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: barH,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: NavShadowPainter.of(
                        p,
                        path: outline,
                        repaint: _move,
                      ),
                    ),
                  ),
                ),
                // The glass: blur + color, tint, sheen and rim, all inside
                // the one path.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: barH,
                  child: ClipPath(
                    clipper: _NavClipper(_depth, _move),
                    child: frosted
                        ? BackdropFilter(
                            filter: kNavGlassFilter,
                            child: CustomPaint(
                              painter: NavGlassPainter(
                                path: outline,
                                colors: glassColors,
                                repaint: _move,
                              ),
                            ),
                          )
                        : CustomPaint(
                            painter: NavGlassPainter(
                              path: outline,
                              colors: glassColors,
                              repaint: _move,
                            ),
                          ),
                  ),
                ),
                // The lens and the items follow the pages; nothing else
                // rebuilds while the donor swipes.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: barH,
                  child: Listener(
                    onPointerDown: (_) => _pressed.value = true,
                    onPointerUp: (_) => _pressed.value = false,
                    onPointerCancel: (_) => _pressed.value = false,
                    child: AnimatedBuilder(
                      animation: _position,
                      builder: (context, _) {
                        final position = _position.value;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _pressed,
                                  builder: (context, pressed, _) =>
                                      NavGlassLens(
                                        geometry: NavLensGeometry.at(
                                          position,
                                          slotWidth: slotW,
                                          reduceMotion: _reduced,
                                        ),
                                        barHeight: barH,
                                        pressed: pressed,
                                        reduceMotion: _reduced,
                                      ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < _slotCount; i++)
                                  SizedBox(
                                    width: slotW,
                                    height: barH,
                                    child: i == _check
                                        ? null
                                        : _item(i, position),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Positioned.fill(child: _checkLayer(w)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _item(int i, double position) {
    final def = _kNavDefs.firstWhere((d) => d.index == i);
    final selected = widget.selectedIndex == i;
    final badge = i == 4 ? UnreadNotifications.instance.count : null;

    // The color and size follow the pages: from muted to the brand red, a
    // little bigger, as the position reaches this tab.
    Widget icon = Transform.scale(
      scale: 1 + 0.08 * navCloseness(position, i),
      child: Icon(
        def.icon,
        size: 24,
        color: navItemColor(context.palette, position, i),
      ),
    );
    // A small pop (1.0 -> 1.12 -> 1.0) when the tab becomes the selected one.
    icon = AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Transform.scale(
        scale: _popIndex == i
            ? 1.0 + 0.12 * math.sin(math.pi * _pop.value)
            : 1.0,
        child: child,
      ),
      child: icon,
    );
    final face = SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: icon),
          if (badge != null)
            Positioned(top: -7, right: -9, child: _UnreadBadge(count: badge)),
        ],
      ),
    );

    Widget button(String label) => Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: () => _tap(i),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(i),
        child: Center(child: face),
      ),
    );

    if (badge == null) return button(def.label);
    return ValueListenableBuilder<int>(
      valueListenable: badge,
      builder: (context, n, _) =>
          button(n > 0 ? '${def.label}, $n unread' : def.label),
    );
  }

  Widget _checkLayer(double w) {
    return AnimatedBuilder(
      animation: Listenable.merge([_move, _idle, _squash, _settle]),
      builder: (context, _) {
        final p = _move.value;
        final t = _tAt(p);
        final tc = t.clamp(0.0, 1.0);
        final size = ui.lerpDouble(
          FloatingNavMetrics.checkBlendedSize,
          FloatingNavMetrics.checkSize,
          t,
        )!;
        final cx = w / 2;
        final cy =
            _top +
            ui.lerpDouble(
              FloatingNavMetrics.barHeight / 2,
              -FloatingNavMetrics.checkRise,
              t,
            )!;

        final cycle = _idle.value * 12.0; // seconds in the 12 s loop
        final bob = _reduced ? 0.0 : tc * 2 * math.sin(2 * math.pi * cycle / 3);
        final center = Offset(cx, cy + bob);
        final glow = _glowAt(p);

        final rings = <Widget>[];
        // A soft ring every 4 s while raised.
        if (!_reduced && _idle.isAnimating && tc > 0.98) {
          final phase = (cycle % 4) / 4;
          if (phase < 0.4) {
            final k = Curves.easeOut.transform(phase / 0.4);
            rings.add(
              _ring(center, size / 2 + 2 + 16 * k, 2, 0.28 * (1 - k)),
            );
          }
        }
        // The settle ring once the circle has sunk into the bar.
        if (_settle.isAnimating) {
          final k = Curves.easeOut.transform(_settle.value);
          rings.add(
            _ring(center, size / 2 * (1 + 0.6 * k), 1.5, 0.35 * (1 - k)),
          );
        }

        final hit = math.max(size, 48.0);
        Widget face = Transform.scale(
          scale: 1 - 0.1 * Curves.easeOut.transform(_squash.value),
          child: _face(size, tc, glow),
        );
        if (_reduced && p < 1) {
          face = Opacity(opacity: Curves.easeOut.transform(p), child: face);
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            ...rings,
            Positioned(
              left: center.dx - hit / 2,
              top: center.dy - hit / 2,
              width: hit,
              height: hit,
              child: Semantics(
                container: true,
                button: true,
                selected: widget.selectedIndex == _check,
                label: 'Check eligibility',
                onTap: () => widget.onSelect(_check),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSelect(_check),
                  child: Center(child: face),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ring(Offset center, double radius, double width, double alpha) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _RingPainter(
            center,
            radius,
            width,
            AppColors.primary.withValues(alpha: alpha.clamp(0.0, 1.0)),
          ),
        ),
      ),
    );
  }

  /// The circle: gradient, 3 px white ring, drop icon, and (raised only) the
  /// "Check" label and the glow.
  Widget _face(double size, double t, double glow) {
    final g = glow.clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // The ring blends with the bar: white in light, the dark surface in dark.
        border: Border.all(color: context.palette.surface, width: 3),
        boxShadow: g < 0.01
            ? const []
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28 * g),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.water_drop_rounded,
            size: ui.lerpDouble(22, 26, t)!,
            color: AppColors.onPrimary,
          ),
          if (g > 0.01)
            Align(
              heightFactor: g,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Check',
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.onPrimary.withValues(alpha: g),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps a tab alive while it is swiped away (TabBarView would drop it), so a
/// half-finished eligibility check, the Book form and every scroll position
/// survive a trip to another tab.
class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The crimson count bubble on the Alerts icon: hidden at 0, "99+" above 99,
/// and a small pop (1.0 -> 1.25 -> 1.0) whenever the number goes up.
class _UnreadBadge extends StatefulWidget {
  final ValueNotifier<int> count;

  const _UnreadBadge({required this.count});

  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge>
    with SingleTickerProviderStateMixin {
  // Made in initState (not lazily): a badge that never popped must not
  // create its ticker while being disposed.
  late final AnimationController _pop;
  late int _last = widget.count.value;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    widget.count.addListener(_onCount);
  }

  @override
  void didUpdateWidget(covariant _UnreadBadge old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) {
      old.count.removeListener(_onCount);
      widget.count.addListener(_onCount);
      _last = widget.count.value;
    }
  }

  @override
  void dispose() {
    widget.count.removeListener(_onCount);
    _pop.dispose();
    super.dispose();
  }

  void _onCount() {
    final n = widget.count.value;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (n > _last && !reduce) _pop.forward(from: 0);
    _last = n;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.count,
      builder: (context, n, _) {
        if (n <= 0) return const SizedBox.shrink();
        return IgnorePointer(
          child: Semantics(
            label: n == 1 ? '1 unread notification' : '$n unread notifications',
            excludeSemantics: true,
            child: AnimatedBuilder(
              animation: _pop,
              builder: (context, child) => Transform.scale(
                scale: 1 + 0.25 * math.sin(math.pi * _pop.value),
                child: child,
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  n > 99 ? '99+' : '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── HOME CONTENT ──────────────────────────────────────────────────────────────

class HomeContent extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const HomeContent({super.key, required this.onNavigateToTab});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  String userName = "User";
  String bloodType = "—";
  int totalDonations = 0;
  String nextEligibleDate = "Loading...";
  String eligibilityStatus = "Loading...";
  bool isProfileLoading = true;
  bool isEligibilityLoading = true;

  List<Map<String, dynamic>> appointments = [];
  bool isAppointmentsLoading = true;

  BloodRequestSummary? _brSummary;
  bool _brLoading = true;
  bool _brError = false;

  DigitalIdData? _digitalId;
  bool _digitalIdLoaded = false;
  bool _digitalIdMasked = false;

  @override
  void initState() {
    super.initState();
    loadUserName();
    loadProfileData();
    loadEligibilityData();
    loadAppointments();
    loadBloodRequestSummary();
    loadDigitalId();
  }

  Future<void> loadDigitalId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) {
      if (mounted) setState(() => _digitalIdLoaded = true);
      return;
    }
    try {
      final masked = await DigitalIdService.isMasked(donorId);
      final data = await DigitalIdService.fetch(donorId);
      if (!mounted) return;
      setState(() {
        _digitalId = data;
        _digitalIdMasked = masked;
        _digitalIdLoaded = true;
      });
    } catch (_) {
      // Keep whatever was last known — this card should never show an
      // error state, it just quietly doesn't update.
      if (mounted) setState(() => _digitalIdLoaded = true);
    }
  }

  Future<void> _openDigitalId() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DigitalIdScreen()),
    );
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) return;
    final masked = await DigitalIdService.isMasked(donorId);
    if (mounted) setState(() => _digitalIdMasked = masked);
  }

  Future<void> _refreshHomeData() async {
    if (mounted) {
      setState(() {
        isProfileLoading = true;
        isEligibilityLoading = true;
        isAppointmentsLoading = true;
        _brLoading = true;
      });
    }

    await Future.wait([
      loadUserName(),
      MyAvatarController.instance.refresh(),
      loadProfileData(),
      loadEligibilityData(),
      loadAppointments(),
      loadBloodRequestSummary(),
    ]);
  }

  Future<void> loadBloodRequestSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) {
      if (mounted)
        setState(() {
          _brLoading = false;
          _brError = true;
        });
      return;
    }
    try {
      final summary = await BloodRequestApi.fetchSummary(donorId);
      if (!mounted) return;
      setState(() {
        _brSummary = summary;
        _brLoading = false;
        _brError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _brLoading = false;
        _brError = true;
      });
    }
  }

  Future<void> _openBloodRequestsHub({int tab = 0}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BloodRequestsScreen(initialTab: tab)),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _openBloodRequestDetail(int requestId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestDetailScreen(requestId: requestId),
      ),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _openRequestBlood() async {
    final summary = _brSummary;
    if (summary != null && !summary.canRequest) {
      await _showRequestBlockedSheet(summary.requestBlock);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _showRequestBlockedSheet(VolunteerBlock? block) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.palette.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'Unable to Request Blood',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              block?.message ?? 'You cannot create a request right now.',
              style: TextStyle(
                fontSize: 13,
                color: context.palette.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (block?.action == 'verify')
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VerifyScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: context.palette.border,
                    disabledForegroundColor: context.palette.muted,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Verify Now',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.muted,
                    side: BorderSide(color: context.palette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => userName = prefs.getString('userName') ?? 'User');
    }
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          bloodType = "N/A";
          isProfileLoading = false;
        });
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_profile.php?donor_id=$donorId"),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded["status"] == "success" && decoded["data"] != null) {
          final d = decoded["data"];
          if (mounted) {
            setState(() {
              bloodType = (d["blood_type"] ?? "N/A").toString();
              totalDonations =
                  int.tryParse(d["total_donations"].toString()) ?? 0;
              isProfileLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              bloodType = "N/A";
              isProfileLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          bloodType = "N/A";
          isProfileLoading = false;
        });
      }
    }
  }

  Future<void> loadEligibilityData() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          nextEligibleDate = "N/A";
          eligibilityStatus = "Unknown";
          isEligibilityLoading = false;
        });
      }
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              "${AppConfig.baseUrl}/get_eligibility.php?donor_id=$donorId",
            ),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["status"] == "success") {
          if (mounted) {
            setState(() {
              nextEligibleDate =
                  data["next_eligible_date"] == null ||
                      data["next_eligible_date"].toString().trim().isEmpty
                  ? "N/A"
                  : formatDate(data["next_eligible_date"].toString());
              eligibilityStatus = (data["eligibility"] ?? "Unknown").toString();
              isEligibilityLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              nextEligibleDate = "N/A";
              eligibilityStatus = "Unknown";
              isEligibilityLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          nextEligibleDate = "N/A";
          eligibilityStatus = "Unknown";
          isEligibilityLoading = false;
        });
      }
    }
  }

  Future<void> loadAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) setState(() => isAppointmentsLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "${AppConfig.baseUrl}/get_appointments.php?donor_id=$donorId",
        ),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded["status"] == "success" && decoded["data"] != null) {
          if (mounted) {
            setState(() {
              final list = List<Map<String, dynamic>>.from(decoded["data"]);
              appointments = list.isNotEmpty ? [list.first] : [];
              isAppointmentsLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => isAppointmentsLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => isAppointmentsLoading = false);
    }
  }

  String formatDate(String dateString) {
    if (dateString.isEmpty) return "N/A";
    try {
      final date = DateTime.parse(dateString);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return "${months[date.month - 1]} ${date.day}, ${date.year}";
    } catch (_) {
      return dateString;
    }
  }

  String formatTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return "N/A";
    try {
      final parts = timeString.split(":");
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? "PM" : "AM";
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return "$hour:${minute.toString().padLeft(2, '0')} $period";
    } catch (_) {
      return timeString;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'cancelled':
        return context.palette.primaryText;
      case 'pending':
        return context.palette.warning;
      case 'approved':
      case 'completed':
        return context.palette.success;
      default:
        return context.palette.hint;
    }
  }

  Color getStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'cancelled':
        return context.palette.accentBg;
      case 'pending':
        return context.palette.warningBg;
      case 'approved':
      case 'completed':
        return context.palette.successBg;
      default:
        return context.palette.surfaceAlt;
    }
  }

  // pending and for_review are the same state to the donor: "Under Review".
  bool _isUnderReview(String status) {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'for_review';
  }

  Color getEligibilityStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'eligible':
        return context.palette.success;
      case 'pending':
      case 'for_review':
      case 'temporary_deferred':
      case 'not_checked':
        return context.palette.warning;
      case 'not_eligible':
      default:
        return context.palette.primaryText;
    }
  }

  // Maps raw backend eligibility_status.status values to donor-facing text
  // so the UI never shows a raw snake_case value like "not_eligible".
  String formatEligibilityStatus(String status) {
    switch (status.toLowerCase()) {
      case 'eligible':
        return 'Eligible';
      case 'not_eligible':
        return 'Not Eligible';
      case 'pending':
      case 'for_review':
        return 'Under Review';
      case 'temporary_deferred':
        return 'Temporarily Deferred';
      case 'not_checked':
        return 'Not Checked';
      case 'unknown':
        return 'Unknown';
      default:
        return status
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  // ── Digital Donor ID card ────────────────────────────────────────────────

  Widget _digitalIdCard() {
    final data = _digitalId;
    if (data == null) return const SizedBox.shrink();
    final donor = data.donor;
    final code = _digitalIdMasked ? data.card.codeMasked : data.card.code;

    return PressableScale(
      onTap: _openDigitalId,
      child: Container(
        clipBehavior: Clip.antiAlias,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -14,
              child: CustomPaint(
                size: const Size(90, 108),
                painter: _MiniCardDropPainter(),
              ),
            ),
            const _LightSweep(),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: donor.photoUrl != null
                        ? Image.network(
                            donor.photoUrl!,
                            fit: BoxFit.cover,
                            width: 44,
                            height: 44,
                            errorBuilder: (_, _, _) =>
                                _initialsCircle(donor.fullName),
                          )
                        : _initialsCircle(donor.fullName),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DIGITAL DONOR ID',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        donor.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  // A white chip on the red card: the same in both modes.
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    donor.bloodType ?? '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // The donor's initials on the red ID card: white and brand red in both modes.
  Widget _initialsCircle(String name) => Container(
    color: Colors.white,
    alignment: Alignment.center,
    child: Text(
      _initialsFor(name),
      style: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
  );

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // ── Blood Requests card ─────────────────────────────────────────────────

  Widget _bloodRequestsCardShell(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: homeCardDecoration(context),
    child: child,
  );

  Widget _brHeaderRow() => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.accentBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.bloodtype_rounded,
          color: context.palette.primaryText,
          size: 22,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeSectionTitle('Blood Requests'),
            Text(
              'Request blood or help a patient in need',
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
          ],
        ),
      ),
      TextButton(
        onPressed: () => _openBloodRequestsHub(),
        style: TextButton.styleFrom(
          foregroundColor: context.palette.primaryText,
          padding: EdgeInsets.zero,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View all',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
    ],
  );

  Widget _brUrgentBanner(BloodRequestSummary summary) {
    final n = summary.urgentMatchingCount;
    final top = summary.topUrgent;
    return PressableScale(
      onTap: top != null
          ? () => _openBloodRequestDetail(top.requestId)
          : () => _openBloodRequestsHub(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const _PulsingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 1
                        ? '1 urgent request needs your blood type'
                        : '$n urgent requests need your blood type',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (top != null)
                    Text(
                      [
                        top.facilityName,
                        top.timeLeftLabel,
                      ].where((e) => e != null && e.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _brRequestTile() => PressableScale(
    onTap: _openRequestBlood,
    child: Container(
      height: 118,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(
              alpha: context.palette.isDark ? .18 : .3,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: CustomPaint(
        painter: const DropPatternPainter(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Blood',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'For you or a loved one',
                style: TextStyle(fontSize: 11, color: AppColors.onPrimary),
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    ),
  );

  Widget _brHelpTile(BloodRequestSummary summary) => PressableScale(
    onTap: () => _openBloodRequestsHub(),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 118,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.accentBg,
            border: Border.all(color: context.palette.primaryBorder, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  color: context.palette.primaryText,
                  size: 20,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Help a Patient',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.palette.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.matchingCount > 0
                        ? '${summary.matchingCount} match your type'
                        : summary.openCount > 0
                        ? '${summary.openCount} open request${summary.openCount == 1 ? '' : 's'}'
                        : 'No requests right now',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (summary.openCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                '${summary.openCount}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _brYourRequestSection(BloodRequestSummary summary) {
    final r = summary.myActiveRequest!;
    return GestureDetector(
      onTap: () => _openBloodRequestDetail(r.requestId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR REQUEST',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.palette.muted,
                  letterSpacing: 0.8,
                ),
              ),
              if (summary.myActiveCount > 1) ...[
                const SizedBox(width: 6),
                Text(
                  '+${summary.myActiveCount - 1} more',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BloodDropBadge(bloodType: r.bloodType, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.reference,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.palette.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RequestStatusChip(status: r.status, label: r.statusLabel),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${r.volunteersCount}/${r.requiredDonors} donors',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.palette.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DonorProgressBar(
                      volunteers: r.volunteersCount,
                      required: r.requiredDonors,
                      showLabel: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brYourCommitmentSection(BloodRequestSummary summary) {
    final r = summary.myCommitment!;
    return GestureDetector(
      onTap: () => _openBloodRequestDetail(r.requestId),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.successBg,
          border: Border.all(color: context.palette.successBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.favorite_rounded,
              size: 18,
              color: context.palette.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "You're donating for ${r.reference}",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.palette.successDark,
                    ),
                  ),
                  Text(
                    [
                      r.facility?.name,
                      r.neededBy != null
                          ? 'needed by ${brShortDate(r.neededBy)}'
                          : null,
                    ].where((e) => e != null && e.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.successDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.palette.success),
          ],
        ),
      ),
    );
  }

  Widget _brHeaderRowSkeleton() => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(child: HomeSectionTitle('Blood Requests')),
    ],
  );

  Widget _brSkeletonTile() => const SkeletonBox(height: 118, radius: 16);

  Widget _brLoadingBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brHeaderRowSkeleton(),
      const SizedBox(height: 14),
      SkeletonPulse(
        child: Row(
          children: [
            Expanded(child: _brSkeletonTile()),
            const SizedBox(width: 12),
            Expanded(child: _brSkeletonTile()),
          ],
        ),
      ),
    ],
  );

  Widget _brErrorBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brHeaderRowSkeleton(),
      const SizedBox(height: 14),
      Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 16,
            color: context.palette.muted,
          ),
          const SizedBox(width: 8),
          Text(
            "Couldn't load blood requests",
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          const Spacer(),
          TextButton(
            onPressed: loadBloodRequestSummary,
            style: TextButton.styleFrom(
              foregroundColor: context.palette.primaryText,
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _bloodRequestsCard() {
    if (_brLoading) return _bloodRequestsCardShell(_brLoadingBody());
    final summary = _brSummary;
    if (_brError || summary == null)
      return _bloodRequestsCardShell(_brErrorBody());

    return _bloodRequestsCardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brHeaderRow(),
          if (summary.urgentMatchingCount > 0) ...[
            const SizedBox(height: 14),
            _brUrgentBanner(summary),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _brRequestTile()),
              const SizedBox(width: 12),
              Expanded(child: _brHelpTile(summary)),
            ],
          ),
          if (summary.myActiveRequest != null) ...[
            Divider(height: 28, color: context.palette.surfaceAlt),
            _brYourRequestSection(summary),
          ],
          if (summary.myCommitment != null) ...[
            const SizedBox(height: 10),
            _brYourCommitmentSection(summary),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'home', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final firstName = userName.split(' ').first;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          HomeHeader(
            greeting: _greetingText(),
            title: firstName,
            subtitle: 'Thank you for saving lives',
            actions: [
              HeaderIconButton(
                icon: Icons.dynamic_feed_rounded,
                tooltip: 'Newsfeed',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewsfeedPage()),
                ),
              ),
              PressableScale(
                onTap: _navigateToHistory,
                // The donor's own photo and frame (initials without a photo).
                child: const MyAvatar(
                  radius: 22,
                  onGradient: true,
                  ringColor: Colors.white38,
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: context.palette.primaryText,
              backgroundColor: context.palette.surface,
              strokeWidth: 2.5,
              displacement: 32,
              onRefresh: _refreshHomeData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  20,
                  16,
                  FloatingNavMetrics.bottomPadding(context),
                ),
                child: Column(
                  children: [
                    FadeSlideIn(
                      index: 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: HomeStatTile(
                              label: 'Blood Type',
                              text: bloodType,
                              loading: isProfileLoading,
                              icon: Icons.water_drop_rounded,
                              iconColor: context.palette.primaryText,
                              iconBg: context.palette.accentBg,
                              semanticLabel: normalizeBloodType(bloodType) ==
                                      null
                                  ? 'Blood type not set, double tap for details'
                                  : 'Blood type ${normalizeBloodType(bloodType)}, '
                                      'double tap for details',
                              onTap: () => showStatPreview(
                                context,
                                StatKind.bloodType,
                                bloodType: bloodType,
                                donations: totalDonations,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: HomeStatTile(
                              label: 'Donations',
                              number: totalDonations,
                              loading: isProfileLoading,
                              icon: Icons.favorite_rounded,
                              iconColor: context.palette.pink,
                              iconBg: context.palette.pinkBg,
                              semanticLabel:
                                  'Donations $totalDonations, double tap for details',
                              onTap: () => showStatPreview(
                                context,
                                StatKind.donations,
                                bloodType: bloodType,
                                donations: totalDonations,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: HomeStatTile(
                              label: 'Lives Saved',
                              number: totalDonations * 3,
                              loading: isProfileLoading,
                              icon: Icons.people_rounded,
                              iconColor: context.palette.success,
                              iconBg: context.palette.successBg,
                              semanticLabel:
                                  'Lives saved ${totalDonations * 3}, double tap for details',
                              onTap: () => showStatPreview(
                                context,
                                StatKind.lives,
                                bloodType: bloodType,
                                donations: totalDonations,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_digitalIdLoaded && _digitalId != null) ...[
                      FadeSlideIn(index: 1, child: _digitalIdCard()),
                      const SizedBox(height: 16),
                    ],
                    FadeSlideIn(index: 2, child: _eligibilityCard()),
                    const SizedBox(height: 16),
                    FadeSlideIn(index: 3, child: _bloodRequestsCard()),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: _actionCard(
                              icon: Icons.calendar_month_rounded,
                              iconColor: context.palette.info,
                              iconBg: context.palette.infoBg,
                              title: 'Book Appointment',
                              subtitle: 'Schedule your donation',
                              onTap: () => widget.onNavigateToTab(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _actionCard(
                              icon: Icons.history_rounded,
                              iconColor: context.palette.purple,
                              iconBg: context.palette.purpleBg,
                              title: 'Donation History',
                              subtitle: 'View past donations',
                              onTap: () => widget.onNavigateToTab(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const HomeSectionTitle('Upcoming Appointment'),
                          if (!isAppointmentsLoading && appointments.isNotEmpty)
                            GestureDetector(
                              onTap: () => widget.onNavigateToTab(3),
                              child: Text(
                                'See all',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.primaryText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isAppointmentsLoading)
                      const HomeAppointmentSkeleton()
                    else if (appointments.isEmpty)
                      FadeSlideIn(
                        index: 6,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: homeCardDecoration(context),
                          child: Column(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                color: context.palette.faint,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No upcoming appointments.',
                                style: TextStyle(
                                  color: context.palette.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Book one to get started!',
                                style: TextStyle(
                                  color: context.palette.hint,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...appointments.map(
                        (appt) => FadeSlideIn(
                          index: 6,
                          child: _appointmentCard(appt),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 7,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: AppColors.primaryGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your Impact',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$totalDonations donations · ${totalDonations * 3} lives potentially saved',
                                    style: const TextStyle(
                                      color: AppColors.onPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.emoji_events_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      index: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: context.palette.successBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.palette.successBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.volunteer_activism_rounded,
                              color: context.palette.success,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Thank you for being a hero in your community. Every donation makes a difference.',
                                style: TextStyle(
                                  color: context.palette.successDark,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  // ── Donation Eligibility card ───────────────────────────────────────────

  Widget _eligibilityCard() {
    final p = context.palette;
    final underReview = _isUnderReview(eligibilityStatus);
    final statusColor = getEligibilityStatusColor(eligibilityStatus);
    final label = underReview ? 'View Status' : 'Check Eligibility';
    final chipText = statusColor == p.success
        ? p.successDark
        : statusColor == p.warning
        ? p.warningText
        : statusColor;
    final chipBg = statusColor == p.success
        ? p.successBg
        : statusColor == p.warning
        ? p.warningBg
        : p.accentBg;

    // Countdown to the next eligible date, when it is known.
    final next = isEligibilityLoading ? null : parseLongDate(nextEligibleDate);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final daysLeft = next?.difference(todayDate).inDays;
    final last = DateTime.tryParse(
      _digitalId?.donations.lastDonationDate ?? '',
    );
    double? progress;
    if (next != null && last != null && daysLeft != null && daysLeft > 0) {
      final span = next.difference(last).inDays;
      if (span > 0) progress = todayDate.difference(last).inDays / span;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: homeCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accentBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  color: p.primaryText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HomeSectionTitle('Donation Eligibility'),
                    const SizedBox(height: 6),
                    if (isEligibilityLoading)
                      const SkeletonPulse(
                        child: SkeletonBox(width: 84, height: 22, radius: 11),
                      )
                    else
                      HomeStatusChip(
                        label: formatEligibilityStatus(eligibilityStatus),
                        color: chipText,
                        background: chipBg,
                        dot: underReview
                            ? _PulsingDot(color: statusColor, size: 8)
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.infoBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: p.info,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Next Eligible',
                            style: TextStyle(fontSize: 11, color: p.muted),
                          ),
                          const SizedBox(height: 2),
                          if (isEligibilityLoading)
                            const SkeletonPulse(
                              child: SkeletonBox(width: 120, height: 14),
                            )
                          else
                            Text(
                              nextEligibleDate,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.foreground,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (daysLeft != null && daysLeft > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        daysLeft == 1 ? '1 day to go' : '$daysLeft days to go',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.primaryText,
                        ),
                      ),
                    ],
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  SlimProgressBar(
                    value: progress,
                    color: AppColors.primary,
                    trackColor: p.border,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlowPulse(
            enabled: label == 'Check Eligibility',
            sheen: true,
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => widget.onNavigateToTab(2),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(label),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: p.border,
                  disabledForegroundColor: p.muted,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: homeCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: context.palette.foreground,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final date = formatDate(appt["appointment_date"] ?? "");
    final time = formatTime(appt["appointment_time"] ?? "");
    final center = appt["donation_center"] ?? "N/A";
    final status = appt["status"] ?? "N/A";
    final statusColor = getStatusColor(status);
    final statusBg = getStatusBg(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: homeCardDecoration(context),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.palette.accentBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              color: context.palette.primaryText,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: context.palette.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Faint droplet watermark for the Digital ID mini card (Section 3.2).
class _MiniCardDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, w * 0.12, h * 0.42, w * 0.12, h * 0.66)
      ..cubicTo(w * 0.12, h * 0.87, w * 0.28, h, w * 0.5, h)
      ..cubicTo(w * 0.72, h, w * 0.88, h * 0.87, w * 0.88, h * 0.66)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniCardDropPainter oldDelegate) => false;
}

// One-time light sweep across the Digital ID mini card when it first appears.
class _LightSweep extends StatefulWidget {
  const _LightSweep();

  @override
  State<_LightSweep> createState() => _LightSweepState();
}

class _LightSweepState extends State<_LightSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _position;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _position = Tween<double>(
      begin: -0.4,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, child) => Align(
          alignment: Alignment(_position.value * 2 - 1, 0),
          child: FractionallySizedBox(
            widthFactor: 0.3,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .18),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Small pulsing dot for the Blood Requests card's urgent banner — mirrors
// UrgencyChip's critical-urgency pulse in blood_request_widgets.dart.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({this.color = Colors.white, this.size = 10});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Steady (no ticker) with animations removed.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl
        ..stop()
        ..value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, child) =>
        Opacity(opacity: 0.35 + (_ctrl.value * 0.65), child: child),
    child: Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    ),
  );
}
