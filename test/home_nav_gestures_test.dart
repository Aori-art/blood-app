import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:blood/app_colors.dart';
import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/home.dart';
import 'package:blood/home_nav.dart';
import 'package:blood/home_nav_glass.dart';
import 'package:blood/home_nav_visibility.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_bubble.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_streak.dart';
import 'support/pumpable_screens.dart';

/// The Home nav's gestures: dragging a finger along it moves between the tabs
/// (the pages and the lens follow), and swiping it down hides it behind a
/// small handle that brings it back.

Future<http.Response> _server(http.Request r) async {
  if (r.url.path.endsWith('get_donation_history.php')) {
    return okJson({'status': 'success', 'data': <Object>[]});
  }
  if (r.url.path.endsWith('get_eligibility_status.php')) {
    // Not an eligible result: that one celebrates with a buzz of its own.
    return okJson({'status': 'not_checked'});
  }
  return pumpableServer(r);
}

final _haptics = <String>[];

int _clicks() => _haptics.where((h) => h.contains('selectionClick')).length;

int _impacts(String kind) => _haptics.where((h) => h.contains(kind)).length;

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  bool reduceMotion = false,
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
    'userEmail': 'rey@example.com',
  });
  StreakController.instance.reset(forgetSeen: true);
  HomeNavVisibility.instance.reset();
  _haptics.clear();
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        _haptics.add('${call.arguments}');
      }
      return null;
    },
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') ||
        text.contains('MissingPlugin') ||
        text.contains('No Firebase App')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  );
  await _frames(tester, 16);
  _haptics.clear();
}

Future<void> _close(WidgetTester tester) async {
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

Future<void> _with(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(_server));

TabController _tabs(WidgetTester tester) =>
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!;

double _position(WidgetTester tester) => _tabs(tester).animation!.value;

// The nav on a 360 x 640 screen: 16 px in from each side, its bar 64 px tall
// and 10 px above the bottom edge.
const double _slot = 328 / 5;
double _slotX(num i) => 16 + _slot * (i + 0.5);
const double _barY = 640 - 10 - 32;

/// Drags a finger along the bar from slot [from] to slot [to] in [steps]
/// moves, calling [each] after every move. Leaves the finger down.
Future<TestGesture> _scrub(
  WidgetTester tester,
  double from,
  double to, {
  int steps = 40,
  int stepMs = 16,
  void Function(double fingerX)? each,
}) async {
  var x = _slotX(from);
  final g = await tester.startGesture(Offset(x, _barY));
  var t = Duration.zero;
  final dx = (_slotX(to) - x) / steps;
  for (var i = 0; i < steps; i++) {
    t += Duration(milliseconds: stepMs);
    x += dx;
    await g.moveBy(Offset(dx, 0), timeStamp: t);
    await tester.pump(Duration(milliseconds: stepMs));
    each?.call(x);
  }
  return g;
}

bool _navSelected(WidgetTester tester, Pattern label) =>
    tester
        .getSemantics(find.bySemanticsLabel(label))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

/// The Check button's size: 62 raised, 48 sunk into the bar.
double _checkSize(WidgetTester tester) =>
    tester.getSize(find.bySemanticsLabel('Check eligibility')).width;

/// 1 = the nav is shown, 0 = it is hidden.
double get _shown => HomeNavVisibility.instance.progress.value;

Finder get _handle => find.byType(GlassHandle);

double _lensTop(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('nav-lens'))).top;

/// Moves a finger from [start] by [by] in [steps] moves, calling [each]
/// after every move, and lifts it: still (no fling) unless [flick].
Future<void> _drag(
  WidgetTester tester,
  Offset start,
  Offset by, {
  int steps = 20,
  int stepMs = 40,
  bool flick = false,
  void Function()? each,
}) async {
  final g = await tester.startGesture(start);
  var t = Duration.zero;
  for (var i = 0; i < steps; i++) {
    t += Duration(milliseconds: stepMs);
    await g.moveBy(by / steps.toDouble(), timeStamp: t);
    await tester.pump(Duration(milliseconds: stepMs));
    each?.call();
  }
  if (flick) {
    await g.up(timeStamp: t);
  } else {
    await tester.pump(const Duration(milliseconds: 200));
    await g.up(timeStamp: t + const Duration(seconds: 1));
  }
}

/// Swipes the nav down, slowly, from the Home item.
Future<void> _hide(WidgetTester tester) async {
  await _drag(tester, Offset(_slotX(0), _barY), const Offset(0, 80));
  await _frames(tester, 6);
  expect(_shown, 0);
}

/// The 48 px guideline for the bottom of the screen (the handle); the
/// screens above have their own tests.
class _BottomTapTargets extends MinimumTapTargetGuideline {
  const _BottomTapTargets()
    : super(size: const Size(48, 48), link: 'https://m3.material.io');

  @override
  bool shouldSkipNode(SemanticsNode node) {
    var rect = node.rect;
    SemanticsNode? n = node;
    while (n != null) {
      final t = n.transform;
      if (t != null) rect = MatrixUtils.transformRect(t, rect);
      n = n.parent;
    }
    return rect.bottom < 640 - 120 || super.shouldSkipNode(node);
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('dragging along the bar', () {
    testWidgets('the pages and the lens follow the finger, a tick per tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        final lens = find.byKey(const ValueKey('nav-lens'));
        final tracked = <String>[];
        var stretched = false;
        final g = await _scrub(
          tester,
          0,
          4,
          each: (x) {
            final expected = ((x - 16) / _slot - 0.5).clamp(0.0, 4.0);
            final actual = _position(tester);
            // After the touch slop the pages are where the finger is.
            if (x > _slotX(0) + 24 && (actual - expected).abs() > 0.02) {
              tracked.add('finger $expected, pages $actual');
            }
            if (lens.evaluate().isNotEmpty &&
                tester.getSize(lens).width > NavLensGeometry.restWidth + 2) {
              stretched = true;
            }
          },
        );
        expect(tracked, isEmpty, reason: tracked.take(5).join('\n'));
        expect(stretched, isTrue, reason: 'the lens stretches between tabs');
        // Home -> Book -> Check -> History -> Alerts: four ticks.
        expect(_clicks(), 4);
        await g.up();
        await _frames(tester, 10);
        expect(_position(tester), 4);
        expect(_tabs(tester).index, 4);
        // (The Alerts screen's title is "Notifications" too: check Home is not.)
        expect(_navSelected(tester, 'Home'), isFalse);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('release settles on the nearest tab, or on with a flick', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        // Slowly to just past Book (1.3): back to Book.
        var g = await _scrub(tester, 0, 1.3, steps: 30, stepMs: 40);
        await tester.pump(const Duration(milliseconds: 200));
        await g.up(timeStamp: const Duration(seconds: 2));
        await _frames(tester, 10);
        expect(_tabs(tester).index, 1);

        // Quickly from Book to 2.3: a flick, on to History.
        g = await _scrub(tester, 1, 2.3, steps: 6, stepMs: 12);
        await g.up(timeStamp: const Duration(milliseconds: 72));
        await _frames(tester, 10);
        expect(_tabs(tester).index, 3);
        await _close(tester);
      });
    });

    testWidgets('releasing over Check selects Check, like a tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        expect(_checkSize(tester), closeTo(62, 0.5));
        final g = await _scrub(tester, 0, 2, steps: 30, stepMs: 40);
        await tester.pump(const Duration(milliseconds: 200));
        await g.up(timeStamp: const Duration(seconds: 2));
        await _frames(tester, 12);
        expect(_tabs(tester).index, 2);
        expect(_navSelected(tester, 'Check eligibility'), isTrue);
        expect(_checkSize(tester), closeTo(48, 0.5)); // sunk, once
        expect(_impacts('mediumImpact'), 1);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('a drag that starts on the Check button scrubs too', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        // From the raised button (above the bar) toward History.
        final g = await tester.startGesture(Offset(_slotX(2), _barY - 30));
        var t = Duration.zero;
        for (var i = 0; i < 20; i++) {
          t += const Duration(milliseconds: 40);
          await g.moveBy(Offset(_slot / 20, 0), timeStamp: t);
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pump(const Duration(milliseconds: 200));
        await g.up(timeStamp: t + const Duration(seconds: 1));
        await _frames(tester, 12);
        expect(_tabs(tester).index, 3);
        await _close(tester);
      });
    });

    testWidgets('taps on every item and on Check still work', (tester) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        for (final (i, label) in [
          (1, 'Book an appointment'),
          (2, 'Check eligibility'),
          (3, 'Donation history'),
          (0, 'Home'),
        ]) {
          await tester.tap(find.bySemanticsLabel(label));
          await _frames(tester, 8);
          expect(_tabs(tester).index, i, reason: label);
          expect(_navSelected(tester, label), isTrue);
        }
        // Into Check and out again: one medium buzz (the sink), no more.
        expect(_impacts('mediumImpact'), 1);
        expect(_checkSize(tester), closeTo(62, 0.5));
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('with animations off it scrubs, and settles with a jump', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester, reduceMotion: true);
        final g = await _scrub(tester, 0, 3.2, steps: 30, stepMs: 40);
        expect(_position(tester), closeTo(3.2, 0.05));
        await tester.pump(const Duration(milliseconds: 200));
        await g.up(timeStamp: const Duration(seconds: 2));
        await tester.pump();
        await tester.pump();
        expect(_position(tester), 3);
        await _frames(tester, 4);
        expect(_tabs(tester).index, 3);
        await _close(tester);
      });
    });
  });

  group('swiping the bar down', () {
    testWidgets('it follows the finger, hides, and the handle brings it back', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        expect(_handle.hitTestable(), findsNothing);
        final top = _lensTop(tester);
        var moved = 0.0;
        await _drag(
          tester,
          Offset(_slotX(0), _barY),
          const Offset(0, 80),
          each: () => moved = math.max(moved, _lensTop(tester) - top),
        );
        // 80 px, 18 of them to start the drag: the nav follows the other 62,
        // with resistance after 24 (24 + 38 / 2 = 43).
        expect(moved, closeTo(43, 3));
        await _frames(tester, 6);
        expect(_shown, 0);
        expect(HomeNavVisibility.instance.hidden, isTrue);
        expect(_impacts('lightImpact'), 1);
        expect(_handle.hitTestable(), findsOneWidget);
        // Hidden, the nav says nothing; the handle does.
        expect(find.semantics.byLabel('Check eligibility'), findsNothing);
        expect(find.semantics.byLabel('Show navigation bar'), findsOne);

        await tester.tap(_handle);
        await _frames(tester, 6);
        expect(_shown, 1);
        expect(_lensTop(tester), top);
        expect(_impacts('lightImpact'), 2);
        expect(_handle.hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Show navigation bar'), findsNothing);

        // Back, it works as before (a tap is not taken for a swipe down).
        await tester.tapAt(Offset(_slotX(1), _barY));
        await _frames(tester, 8);
        expect(_tabs(tester).index, 1);
        expect(_shown, 1);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('dragging the handle up brings the nav up with the finger', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        await _hide(tester);
        var followed = 0.0;
        await _drag(
          tester,
          tester.getCenter(_handle),
          const Offset(0, -50),
          steps: 10,
          each: () => followed = math.max(followed, _shown),
        );
        // 32 px after the slop, of the 144 the nav travels.
        expect(followed, closeTo(32 / 144, 0.03));
        await _frames(tester, 6);
        expect(_shown, 1);
        expect(_impacts('lightImpact'), 2);
        await _close(tester);
      });
    });

    testWidgets('a short slow drag springs back; a quick flick hides', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        final top = _lensTop(tester);
        // 26 px: 8 past the slop.
        await _drag(
          tester,
          Offset(_slotX(0), _barY),
          const Offset(0, 26),
          steps: 13,
        );
        await _frames(tester, 4);
        expect(_shown, 1);
        expect(_lensTop(tester), top);
        expect(_impacts('lightImpact'), 0);

        // 36 px in 60 ms: only 12 past the slop, but 600 px/s.
        await _drag(
          tester,
          Offset(_slotX(0), _barY),
          const Offset(0, 36),
          steps: 6,
          stepMs: 10,
          flick: true,
        );
        await _frames(tester, 6);
        expect(_shown, 0);
        expect(_impacts('lightImpact'), 1);
        await _close(tester);
      });
    });

    testWidgets('a drag down from the Check button hides it too', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        await _drag(
          tester,
          Offset(_slotX(2), _barY - 30),
          const Offset(0, 80),
        );
        await _frames(tester, 6);
        expect(_shown, 0);
        // Not a tap on Check: still Home, nothing sank.
        expect(_tabs(tester).index, 0);
        expect(_impacts('mediumImpact'), 0);
        await _close(tester);
      });
    });

    testWidgets('each drag keeps to the axis it starts on', (tester) async {
      await _with(() async {
        await _pump(tester);
        // Mostly sideways: it moves the pages and never the nav.
        await _drag(
          tester,
          Offset(_slotX(0), _barY),
          const Offset(60, 15),
          steps: 10,
          each: () => expect(_shown, 1),
        );
        await _frames(tester, 8);
        expect(_tabs(tester).index, 1);
        expect(_shown, 1);
        expect(_impacts('lightImpact'), 0);

        // Mostly down: it moves the nav and never the pages.
        await _drag(
          tester,
          Offset(_slotX(1), _barY),
          const Offset(12, 80),
          each: () => expect(_position(tester), 1),
        );
        await _frames(tester, 8);
        expect(_shown, 0);
        expect(_tabs(tester).index, 1);
        await _close(tester);
      });
    });

    testWidgets('the pages still swipe while the nav is hidden', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        await _hide(tester);
        await tester.flingFrom(
          const Offset(300, 520),
          const Offset(-200, 0),
          1000,
        );
        await _frames(tester, 8);
        expect(_tabs(tester).index, 1);
        expect(_shown, 0);
        await _close(tester);
      });
    });
  });

  testWidgets('HomeNav.goTo while hidden brings the nav back first', (
    tester,
  ) async {
    await _with(() async {
      await _pump(tester);
      await _hide(tester);
      expect(HomeNav.goTo(HomeTab.history), isTrue);
      // (A ticker's first frame is its start.)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_shown, greaterThan(0));
      await _frames(tester, 8);
      expect(_shown, 1);
      expect(_tabs(tester).index, 3);
      expect(_impacts('lightImpact'), 2);
      await _close(tester);
      // Not kept: every other screen (and the next Home) has the nav back.
      expect(_shown, 1);
    });
  });

  group('the room kept for the nav', () {
    const navRoom =
        FloatingNavMetrics.barHeight + FloatingNavMetrics.bottomMargin;
    // What FloatingNavMetrics.bottomPadding always was (no inset in tests).
    const oldPadding = navRoom + 24;

    testWidgets('the same as before while shown, the handle\'s while hidden', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester);
        final context = tester.element(find.byType(TabBarView));
        final scroll = find.descendant(
          of: find.byType(HomeContent),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView && w.scrollDirection == Axis.vertical,
          ),
        );
        double homePadding() =>
            (tester.widget<SingleChildScrollView>(scroll.first).padding!
                    as EdgeInsets)
                .bottom;
        double book() =>
            HomeNavScope.reserveOf(context, shown: kBottomNavBarHeight);
        double alerts() => HomeNavScope.reserveOf(context, shown: navRoom);
        double dugtong() => HomeNavVisibility.instance.reserve(
          kBottomNavBarHeight,
          HomeNavVisibility.handleReserve,
        );

        expect(FloatingNavMetrics.bottomPadding(context), oldPadding);
        expect(homePadding(), oldPadding);
        expect(book(), kBottomNavBarHeight); // Book's sticky bar
        expect(alerts(), navRoom); // Alerts' delete-all button
        expect(dugtong(), kBottomNavBarHeight); // the bubble's lowest place

        await _hide(tester);
        const handle = HomeNavVisibility.handleReserve;
        expect(FloatingNavMetrics.bottomPadding(context), handle + 24);
        expect(homePadding(), handle + 24);
        expect(book(), handle);
        expect(alerts(), handle);
        expect(dugtong(), handle);

        await tester.tap(_handle);
        await _frames(tester, 6);
        expect(FloatingNavMetrics.bottomPadding(context), oldPadding);
        expect(homePadding(), oldPadding);
        await _close(tester);
      });
    });

    testWidgets('screens outside Home always keep the full room', (
      tester,
    ) async {
      HomeNavVisibility.instance.progress.value = 0;
      addTearDown(HomeNavVisibility.instance.reset);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(FloatingNavMetrics.bottomPadding(context), oldPadding);
      expect(
        HomeNavScope.reserveOf(context, shown: kBottomNavBarHeight),
        kBottomNavBarHeight,
      );
    });

    testWidgets('Dugtong\'s bubble may go lower while the nav is hidden', (
      tester,
    ) async {
      await _with(() async {
        SharedPreferences.setMockInitialValues({});
        useFakeStreak(fakeStreak());
        final c = StreakController.instance;
        c.bubbleSide = 'right';
        c.bubbleDy = 1; // as low as it may go
        HomeNavVisibility.instance.reset();
        addTearDown(HomeNavVisibility.instance.reset);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Stack(
              fit: StackFit.expand,
              children: [child!, const StreakBubbleOverlay()],
            ),
            home: const Scaffold(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final bubble = find.descendant(
          of: find.byType(StreakBubbleOverlay),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width == 58,
          ),
        );
        double top() => tester.getTopLeft(bubble).dy;
        // Above the nav (and an 8 px margin), as always.
        expect(top(), 640 - kBottomNavBarHeight - 8 - 58);
        HomeNavVisibility.instance.progress.value = 0;
        await tester.pump();
        expect(top(), 640 - HomeNavVisibility.handleReserve - 8 - 58);
        HomeNavVisibility.instance.progress.value = 1;
        await tester.pump();
        expect(top(), 640 - kBottomNavBarHeight - 8 - 58);
        useFakeStreak(null);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 70));
      });
    });
  });

  group('accessibility', () {
    testWidgets('with animations off the nav cross-fades, it does not slide', (
      tester,
    ) async {
      await _with(() async {
        await _pump(tester, reduceMotion: true);
        final top = _lensTop(tester);
        await _drag(
          tester,
          Offset(_slotX(0), _barY),
          const Offset(0, 80),
          each: () => expect(_lensTop(tester), top),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 130));
        expect(_shown, 0);
        expect(_lensTop(tester), top);
        expect(_handle.hitTestable(), findsOneWidget);

        await tester.tap(_handle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        // Half way through the 120 ms fade: both half there, in place.
        expect(_shown, closeTo(0.5, 0.1));
        expect(_lensTop(tester), top);
        await tester.pump(const Duration(milliseconds: 70));
        expect(_shown, 1);
        await _close(tester);
      });
    });

    testWidgets('a screen reader hides it with an action; the handle is a '
        'labelled button', (tester) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        final id = CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Hide navigation bar'),
        );
        SemanticsNode? nav = tester.getSemantics(find.bySemanticsLabel('Home'));
        while (nav != null &&
            !(nav.getSemanticsData().customSemanticsActionIds?.contains(id) ??
                false)) {
          nav = nav.parent;
        }
        expect(nav, isNotNull, reason: 'the nav offers "Hide navigation bar"');
        nav!.owner!.performAction(nav.id, SemanticsAction.customAction, id);
        await _frames(tester, 6);
        expect(_shown, 0);

        final label = find.bySemanticsLabel('Show navigation bar');
        expect(
          tester.getSemantics(label),
          containsSemantics(
            label: 'Show navigation bar',
            isButton: true,
            hasTapAction: true,
          ),
        );
        final size = tester.getSize(label);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        final node = tester.getSemantics(label);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await _frames(tester, 6);
        expect(_shown, 1);
        expect(find.semantics.byLabel('Show navigation bar'), findsNothing);
        await _close(tester);
      });
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('the handle meets the guidelines '
          '(${dark ? 'dark' : 'light'}, text x1.3)', (tester) async {
        final handle = tester.ensureSemantics();
        await _with(() async {
          await _pump(tester, dark: dark, scale: 1.3);
          await _hide(tester);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(const _BottomTapTargets()));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          // The arrow on its glass (the thinnest tint, 0.80, with no blur),
          // whatever is behind it: 3:1 at least, as for any icon.
          final p = tester.element(_handle).palette;
          final arrow = tester
              .widget<Icon>(
                find.descendant(of: _handle, matching: find.byType(Icon)),
              )
              .color!;
          expect(arrow, p.primaryText);
          for (final behind in [
            Colors.white,
            Colors.black,
            AppColors.primary,
            p.surface,
            p.surfaceAlt,
          ]) {
            final glass = Color.alphaBlend(
              p.surface.withValues(alpha: 0.80),
              behind,
            );
            expect(
              _contrast(arrow, glass),
              greaterThanOrEqualTo(3),
              reason: 'over $behind',
            );
          }
          await _close(tester);
        });
        handle.dispose();
      });
    }
  });
}
