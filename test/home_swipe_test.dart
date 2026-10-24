import 'dart:ui' show Tristate;

import 'package:blood/app_theme.dart';
import 'package:blood/alerts.dart';
import 'package:blood/book.dart';
import 'package:blood/check.dart';
import 'package:blood/donation_history.dart';
import 'package:blood/home.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/interactive_dugtong.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// Swiping between Home's five tabs with real gestures: from every kind of
/// place on the screen, on every tab, both ways.

// The History tab shows its milestones row only when there are donations.
bool _withDonations = false;

// What the eligibility endpoint says (an eligible result celebrates, with a
// buzz of its own, which would blur the count of the nav's).
String _eligibility = 'eligible';

Future<http.Response> _server(http.Request r) async {
  if (r.url.path.endsWith('get_donation_history.php')) {
    if (_withDonations) {
      final screen = pumpableScreens.firstWhere(
        (s) => s.name == 'donation history (with donations)',
      );
      return okJson(screen.responses['get_donation_history.php']!);
    }
    return okJson({'status': 'success', 'data': <Object>[]});
  }
  if (r.url.path.endsWith('get_eligibility_status.php')) {
    return okJson({'status': _eligibility});
  }
  return pumpableServer(r);
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
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
    (call) async => null,
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
      home: const HomeScreen(),
    ),
  );
  await _frames(tester, 16);
}

Future<void> _close(WidgetTester tester) async {
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

Future<void> _with(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(_server));

TabController _controller(WidgetTester tester) =>
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!;

const _navLabels = <Pattern>[
  'Home',
  'Book an appointment',
  'Check eligibility',
  'Donation history',
];

Pattern _label(int i) =>
    i < 4 ? _navLabels[i] : RegExp(r'^Notifications(, [0-9]+ unread)?$');

bool _navSelected(WidgetTester tester, int i) =>
    tester
        .getSemantics(find.bySemanticsLabel(_label(i)))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

Type _pageType(int i) => const [
  HomeContent,
  BookScreen,
  CheckScreen,
  DonationHistoryScreen,
  AlertsScreen,
][i];

/// What receives a touch at [point]: printed so a failure can be read.
String _hitPath(WidgetTester tester, Offset point) {
  final result = HitTestResult();
  tester.binding.hitTestInView(result, point, tester.view.viewId);
  return result.path.map((e) => e.target.runtimeType).take(40).join(' > ');
}

/// A quick horizontal flick: [direction] -1 is leftward (to the next tab).
Future<void> _flick(
  WidgetTester tester,
  Offset start,
  int direction, {
  int steps = 6,
  double stepDx = 40,
  int stepMs = 16,
  // A real finger's first move event is small: this many px, before the rest.
  double firstDx = 0,
}) async {
  final g = await tester.startGesture(start);
  var t = Duration.zero;
  if (firstDx != 0) {
    t += Duration(milliseconds: stepMs);
    await g.moveBy(Offset(direction * firstDx, 0), timeStamp: t);
    await tester.pump(Duration(milliseconds: stepMs));
  }
  for (var i = 0; i < steps; i++) {
    t += Duration(milliseconds: stepMs);
    // The time stamp matters: without it the gesture has no velocity.
    await g.moveBy(Offset(direction * stepDx, 0), timeStamp: t);
    await tester.pump(Duration(milliseconds: stepMs));
  }
  await g.up(timeStamp: t);
}

/// The places to start a swipe: blank space, over a card, the header, and
/// just above the nav.
const _starts = <String, Offset>{
  'middle': Offset(180, 320),
  'upper card': Offset(180, 230),
  'header': Offset(180, 90),
  'above the nav': Offset(100, 540),
};

void main() {
  for (final entry in _starts.entries) {
    testWidgets('a fast flick from the ${entry.key} moves on every tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        final failures = <String>[];
        // Forward through the five tabs, then back again.
        for (var step = 0; step < 8; step++) {
          final forward = step < 4;
          final from = forward ? step : 8 - step;
          final to = forward ? from + 1 : from - 1;
          var start = entry.value;
          // Dugtong on the Check tab is a toy that keeps its own drags (it
          // takes the touch on purpose): start beside it instead.
          final toys = find.byType(InteractiveDugtong).hitTestable();
          if (toys.evaluate().isNotEmpty &&
              tester.getRect(toys.first).inflate(8).contains(start)) {
            start = Offset(30, start.dy);
          }
          final path = _hitPath(tester, start);
          await _flick(tester, start, forward ? -1 : 1);
          await _frames(tester, 25);
          final index = _controller(tester).index;
          final shown = find.byType(_pageType(to)).hitTestable().evaluate();
          if (index != to || !_navSelected(tester, to) || shown.isEmpty) {
            failures.add(
              'tab $from ${forward ? "->" : "<-"} expected $to: '
              'index $index, nav ${_navSelected(tester, to)}, '
              'page shown ${shown.isNotEmpty}; hit path at the start: $path',
            );
            break;
          }
        }
        // ignore: avoid_print
        print('${entry.key}: ${_hitPath(tester, entry.value)}');
        expect(failures, isEmpty, reason: failures.join('\n'));
        await _close(tester);
      });
      handle.dispose();
    });
  }

  testWidgets('a short fast flick moves on; a short slow drag snaps back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _with(() async {
      await _pump(tester);
      // 110 px in about 100 ms: well under half a page, but fast.
      await _flick(tester, const Offset(180, 320), -1, steps: 5, stepDx: 22);
      await _frames(tester, 25);
      expect(_controller(tester).index, 1, reason: 'a fast flick moves on');

      // 110 px in about 1.5 s: slow and short, it snaps back.
      await _flick(
        tester,
        const Offset(180, 320),
        -1,
        steps: 5,
        stepDx: 22,
        stepMs: 300,
      );
      await _frames(tester, 25);
      expect(_controller(tester).index, 1, reason: 'a slow short drag stays');
      expect(_navSelected(tester, 1), isTrue);
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('a swipe right after a tap on the nav still pages', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _with(() async {
      await _pump(tester);
      await tester.tap(find.bySemanticsLabel('Donation history'));
      await _frames(tester, 5); // the tap's glide has just ended
      // Swipe back at once.
      await _flick(tester, const Offset(100, 540), 1);
      await _frames(tester, 25);
      expect(_controller(tester).index, 2);
      expect(_navSelected(tester, 2), isTrue);
      await _flick(tester, const Offset(100, 540), -1);
      await _frames(tester, 25);
      expect(_controller(tester).index, 3);
      expect(_navSelected(tester, 3), isTrue);
      await _close(tester);
    });
    handle.dispose();
  });

  group('widgets that take sideways drags', () {
    testWidgets('Alerts: right pages back to History; left still deletes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Notifications')));
        await _frames(tester, 25);
        expect(_controller(tester).index, 4);
        final note = find.text('Notification 1');
        final at = tester.getCenter(note);

        // Left on a notification: its own swipe-to-delete (a confirmation).
        await _flick(tester, at, -1);
        await _frames(tester, 25);
        expect(_controller(tester).index, 4, reason: 'left deletes, not pages');
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.byType(TextButton).first);
        await _frames(tester, 15);

        // Right on a notification: back to History.
        await _flick(tester, tester.getCenter(find.text('Notification 2')), 1);
        await _frames(tester, 25);
        expect(_controller(tester).index, 3);
        expect(_navSelected(tester, 3), isTrue);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('Book: the date strip scrolls; at its start right pages', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        await _pump(tester);
        await tester.tap(find.bySemanticsLabel('Book an appointment'));
        await _frames(tester, 25);
        final strip = find.descendant(
          of: find.byType(BookScreen),
          matching: find.byType(ListView),
        );
        final stripList = strip.evaluate().firstWhere(
          (e) => (e.widget as ListView).scrollDirection == Axis.horizontal,
        );
        final scrollable = find.descendant(
          of: find.byWidget(stripList.widget),
          matching: find.byType(Scrollable),
        );
        final at = tester.getCenter(find.byWidget(stripList.widget));
        double offset() =>
            tester.state<ScrollableState>(scrollable).position.pixels;

        // Left on the strip: it scrolls; the pager stays on Book.
        await _flick(tester, at, -1, steps: 4, stepDx: 25);
        await _frames(tester, 20);
        expect(offset(), greaterThan(20));
        expect(_controller(tester).index, 1);

        // Back to its start with a drag the strip can follow.
        await _flick(tester, at, 1, steps: 4, stepDx: 40, firstDx: 8);
        await _frames(tester, 20);
        expect(offset(), 0);
        expect(_controller(tester).index, 1);

        // At its start, right: the pager takes it, back to Home.
        await _flick(tester, at, 1, firstDx: 8);
        await _frames(tester, 25);
        expect(_controller(tester).index, 0);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('History: milestones scroll; at the start right pages', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(() async {
        _withDonations = true;
        addTearDown(() => _withDonations = false);
        await _pump(tester);
        await tester.tap(find.bySemanticsLabel('Donation history'));
        await _frames(tester, 25);
        final row = find
            .descendant(
              of: find.byType(DonationHistoryScreen),
              matching: find.byType(SingleChildScrollView),
            )
            .evaluate()
            .map((e) => e.widget as SingleChildScrollView)
            .firstWhere((w) => w.scrollDirection == Axis.horizontal);
        final rowFinder = find.byWidget(row);
        final at = tester.getCenter(rowFinder);
        expect(_controller(tester).index, 3);

        // At the start, right: the pager takes it, back to Check.
        await _flick(tester, at, 1, firstDx: 8);
        await _frames(tester, 25);
        expect(_controller(tester).index, 2);
        await _close(tester);
      });
      handle.dispose();
    });
  });

  testWidgets('the Check button changes once per swipe, not twice', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final haptics = <String>[];
    _eligibility = 'not_checked';
    addTearDown(() => _eligibility = 'eligible');
    await _with(() async {
      await _pump(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate')
            haptics.add('${call.arguments}');
          return null;
        },
      );
      await _flick(tester, const Offset(180, 90), -1, steps: 5, stepDx: 30);
      await _frames(tester, 25);
      await _flick(tester, const Offset(180, 90), -1, steps: 5, stepDx: 30);
      await _frames(tester, 25);
      // Home -> Book -> Check: arriving on Check is one medium impact (the
      // sink), and the button is sunk.
      expect(_controller(tester).index, 2);
      expect(haptics.where((h) => h.contains('mediumImpact')), hasLength(1));
      expect(
        tester.getSize(find.bySemanticsLabel('Check eligibility')).width,
        closeTo(48, 0.5),
      );
      await _flick(tester, const Offset(180, 90), 1, steps: 5, stepDx: 30);
      await _frames(tester, 25);
      expect(_controller(tester).index, 1);
      expect(
        tester.getSize(find.bySemanticsLabel('Check eligibility')).width,
        closeTo(62, 0.5),
      );
      // Leaving Check did not buzz again.
      expect(haptics.where((h) => h.contains('mediumImpact')), hasLength(1));
      await _close(tester);
    });
    handle.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'swiping works in ${dark ? 'dark' : 'light'}, and with animations off',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _with(() async {
          await _pump(tester, dark: dark, reduceMotion: !dark);
          await _flick(
            tester,
            const Offset(180, 320),
            -1,
            steps: 5,
            stepDx: 30,
          );
          await _frames(tester, 25);
          expect(_controller(tester).index, 1);
          expect(_navSelected(tester, 1), isTrue);
          await _flick(tester, const Offset(180, 320), 1, steps: 5, stepDx: 30);
          await _frames(tester, 25);
          expect(_controller(tester).index, 0);
          await _close(tester);
        });
        handle.dispose();
      },
    );
  }
}
