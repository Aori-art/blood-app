import 'dart:ui' show Tristate;

import 'package:blood/app_theme.dart';
import 'package:blood/home.dart';
import 'package:blood/home_nav.dart';
import 'package:blood/home_nav_glass.dart';
import 'package:blood/home_nav_visibility.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
