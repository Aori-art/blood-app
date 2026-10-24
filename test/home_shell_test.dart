import 'dart:ui' show Tristate;

import 'package:blood/alerts.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/book.dart';
import 'package:blood/check.dart';
import 'package:blood/donation_history.dart';
import 'package:blood/home.dart';
import 'package:blood/home_nav.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/unread_notifications.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// Home's tabs as swipeable pages, the nav following them, HomeNav switching
/// tabs instead of pushing screens, and the Book tab freshening up.

class _Server {
  String eligibility = 'eligible';
  int eligibilityCalls = 0;

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('get_eligibility_status.php')) {
      eligibilityCalls++;
      return okJson({'status': eligibility, 'can_book': true});
    }
    if (r.url.path.endsWith('get_donation_history.php')) {
      return okJson({'status': 'success', 'data': <Object>[]});
    }
    return pumpableServer(r);
  }
}

class _Pushes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
  double scale = 1,
  bool reduceMotion = false,
  NavigatorObserver? observer,
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
  // The test font is wider than the real one (Roboto): overflow outside the
  // nav is not a bug here.
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
      navigatorObservers: [?observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await _frames(tester, 16);
}

Future<void> _close(WidgetTester tester) async {
  // Home starts the unread-count polling (a periodic timer): stop it so the
  // test ends with no timer pending.
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

Future<void> _with(_Server s, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(s.handle));

Finder _nav(Pattern label) => find.bySemanticsLabel(label);

bool _selected(WidgetTester tester, Pattern label) =>
    tester.getSemantics(_nav(label)).flagsCollection.isSelected ==
    Tristate.isTrue;

/// The Check button's size: 62 raised, 48 sunk into the bar (its tap area is
/// never under 48).
double _checkSize(WidgetTester tester) =>
    tester.getSize(_nav('Check eligibility')).width;

Future<void> _swipe(WidgetTester tester, double dx) async {
  // From the top of the screen (the headers), clear of anything that
  // scrolls sideways inside a tab.
  await tester.dragFrom(const Offset(180, 90), Offset(dx, 0));
  await _frames(tester, 12);
}

Finder _built(Type type) => find.byType(type, skipOffstage: false);

/// Presses the button labelled [text] (it may sit under the floating nav,
/// where a tap would land on the nav).
Future<void> _press(WidgetTester tester, String text) async {
  final button = find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  tester.widget<ButtonStyleButton>(button.first).onPressed!();
  await _frames(tester, 12);
}

/// The 48 px guideline for the nav (the bottom of the screen); the screens
/// above it have their own tests.
class _NavTapTargets extends MinimumTapTargetGuideline {
  const _NavTapTargets()
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

void main() {
  testWidgets('swiping moves between tabs; the nav and Check follow', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final s = _Server();
    await _with(s, () async {
      await _pump(tester, const HomeScreen());
      expect(_selected(tester, 'Home'), isTrue);
      expect(_checkSize(tester), closeTo(62, 0.5));

      await _swipe(tester, -300);
      expect(_selected(tester, 'Book an appointment'), isTrue);
      expect(_selected(tester, 'Home'), isFalse);
      expect(_built(BookScreen), findsOneWidget);
      expect(_checkSize(tester), closeTo(62, 0.5)); // still raised

      // On to Check: the button sinks into the bar, as for a tap.
      await _swipe(tester, -300);
      expect(_selected(tester, 'Check eligibility'), isTrue);
      expect(_checkSize(tester), closeTo(48, 0.5));

      // Back to Book: it rises again.
      await _swipe(tester, 300);
      expect(_selected(tester, 'Book an appointment'), isTrue);
      expect(_checkSize(tester), closeTo(62, 0.5));
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('a tap from Home to Alerts builds none of the tabs between', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _with(_Server(), () async {
      await _pump(tester, const HomeScreen());
      // The nav item (the Alerts screen's title is "Notifications" too).
      await tester.tap(_nav(RegExp(r'^Notifications(, [0-9]+ unread)?$')));
      await _frames(tester, 12);
      expect(_selected(tester, 'Home'), isFalse);
      expect(_built(AlertsScreen), findsOneWidget);
      expect(_built(BookScreen), findsNothing);
      expect(_built(CheckScreen), findsNothing);
      expect(_built(DonationHistoryScreen), findsNothing);
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('a tab keeps its scroll position across a round trip', (
    tester,
  ) async {
    await _with(_Server(), () async {
      await _pump(tester, const HomeScreen());
      final scroll = find
          .descendant(
            of: find.byType(HomeContent),
            matching: find.byType(Scrollable),
            skipOffstage: false,
          )
          .first;
      await tester.drag(scroll, const Offset(0, -300));
      await _frames(tester, 6);
      final offset = tester.state<ScrollableState>(scroll).position.pixels;
      expect(offset, greaterThan(100));

      await tester.dragFrom(const Offset(180, 300), const Offset(-300, 0));
      await _frames(tester, 12);
      expect(_built(BookScreen), findsOneWidget);
      await _swipe(tester, 300);
      expect(tester.state<ScrollableState>(scroll).position.pixels, offset);
      await _close(tester);
    });
  });

  group('HomeNav', () {
    testWidgets('the eligible result\'s Book button selects the Book tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final pushes = _Pushes();
      await _with(_Server(), () async {
        await _pump(tester, const HomeScreen(), observer: pushes);
        await tester.tap(_nav('Check eligibility'));
        await _frames(tester, 20);
        final before = pushes.pushed.length;
        await _press(tester, 'Book an Appointment');
        expect(pushes.pushed.length, before); // nothing pushed
        expect(_selected(tester, 'Book an appointment'), isTrue);
        expect(
          tester.widget<BookScreen>(_built(BookScreen)).showBackButton,
          isFalse,
        );
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('the empty history\'s Book button selects the Book tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final pushes = _Pushes();
      await _with(_Server(), () async {
        await _pump(tester, const HomeScreen(), observer: pushes);
        await tester.tap(_nav('Donation history'));
        await _frames(tester, 20);
        final before = pushes.pushed.length;
        await _press(tester, 'Book an Appointment');
        expect(pushes.pushed.length, before);
        expect(_selected(tester, 'Book an appointment'), isTrue);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('the Book gate\'s Take Eligibility Check selects Check', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final pushes = _Pushes();
      final s = _Server()..eligibility = 'not_checked';
      await _with(s, () async {
        await _pump(tester, const HomeScreen(), observer: pushes);
        await tester.tap(_nav('Book an appointment'));
        await _frames(tester, 20);
        final before = pushes.pushed.length;
        await _press(tester, 'Take Eligibility Check');
        expect(pushes.pushed.length, before);
        expect(_selected(tester, 'Check eligibility'), isTrue);
        expect(_built(CheckScreen), findsOneWidget);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('from a Check screen pushed over Home: pop it, then Book', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _with(_Server(), () async {
        await _pump(tester, const HomeScreen());
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(MaterialPageRoute(builder: (_) => const CheckScreen()));
        await _frames(tester, 20);
        expect(_built(CheckScreen), findsOneWidget);
        await _press(tester, 'Book an Appointment');
        expect(_built(CheckScreen), findsNothing); // popped
        expect(_selected(tester, 'Book an appointment'), isTrue);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('with no Home it falls back to pushing Book', (tester) async {
      await _with(_Server(), () async {
        await _pump(tester, const CheckScreen());
        expect(HomeNav.available, isFalse);
        await _press(tester, 'Book an Appointment');
        expect(
          tester.widget<BookScreen>(find.byType(BookScreen)).showBackButton,
          isTrue,
        );
        await _close(tester);
      });
    });

    testWidgets('a center asked for is used once', (tester) async {
      final handle = tester.ensureSemantics();
      await _with(_Server(), () async {
        await _pump(tester, const HomeScreen());
        expect(HomeNav.goTo(HomeTab.book, bookFacilityId: 1), isTrue);
        await _frames(tester, 20);
        expect(_selected(tester, 'Book an appointment'), isTrue);
        expect(HomeNav.pendingBookFacilityId.value, isNull);
        await _close(tester);
      });
      handle.dispose();
    });
  });

  testWidgets(
    'the Book tab freshens up when it comes back, at most every 5 s',
    (tester) async {
      final handle = tester.ensureSemantics();
      final s = _Server()..eligibility = 'not_checked';
      await _with(s, () async {
        await _pump(tester, const HomeScreen());
        await tester.tap(_nav('Book an appointment'));
        await _frames(tester, 20);
        expect(find.textContaining('Take Eligibility Check'), findsOneWidget);
        final first = s.eligibilityCalls;

        // A screening later, the server says eligible.
        await tester.tap(_nav('Home'));
        await _frames(tester, 10);
        s.eligibility = 'eligible';
        await tester.pump(const Duration(seconds: 6));

        await tester.tap(_nav('Book an appointment'));
        final skeleton = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_BookingSkeleton',
          skipOffstage: false,
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(skeleton, findsNothing); // the old view stays until then
        }
        expect(s.eligibilityCalls, first + 1);
        expect(find.textContaining('Take Eligibility Check'), findsNothing);
        expect(find.text('Select Date'), findsOneWidget);

        // Back again within 5 seconds: no new fetch.
        await tester.tap(_nav('Home'));
        await _frames(tester, 5);
        await tester.tap(_nav('Book an appointment'));
        await _frames(tester, 10);
        expect(s.eligibilityCalls, first + 1);
        await _close(tester);
      });
      handle.dispose();
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('the glass nav meets the guidelines '
          '(${dark ? 'dark' : 'light'}, text x$scale)', (tester) async {
        final handle = tester.ensureSemantics();
        await _with(_Server(), () async {
          await _pump(tester, const HomeScreen(), dark: dark, scale: scale);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(const _NavTapTargets()));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await _close(tester);
        });
        handle.dispose();
      });
    }
  }
}
