import 'package:blood/app_theme.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/newsfeed/category_nav_bar.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';
import 'support/sample_posts.dart';

/// The floating category bar and "Go to Home" take turns at the bottom of the
/// newsfeed; tapping a category filters the list and keeps the bar there.

/// What the screen is given: the posts, and the look of the run.
class _Run {
  _Run(this.posts);

  final List<Map<String, dynamic>> posts;
  final overflows = <String>[];
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpFeed(
  WidgetTester tester,
  _Run run, {
  bool dark = false,
  double scale = 1,
  bool reduceMotion = false,
  Size size = const Size(360, 640),
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
  });
  StreakController.instance.reset(forgetSeen: true);
  tester.view.physicalSize = size;
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
  // The test font is much wider than the real one (Roboto), so overflow in
  // the post cards is not a bug here. Overflow in the bar itself is one: it
  // is recorded and checked by the tests.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      if (details.toString().contains('category_nav_bar.dart')) {
        run.overflows.add(text);
      }
      return;
    }
    if (text.contains('MissingPlugin') || text.contains('No Firebase App')) {
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
      home: const NewsfeedPage(),
    ),
  );
  await _frames(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _with(_Run run, Future<void> Function() body) =>
    http.runWithClient(
      body,
      () => MockClient((r) async {
        if (r.url.path.endsWith('get_posts.php')) {
          return okJson({'success': true, 'posts': run.posts});
        }
        return pumpableServer(r);
      }),
    );

Finder get _bar => find.byType(CategoryNavBar);
Finder _item(String label) =>
    find.descendant(of: _bar, matching: find.text(label));

/// "Go to Home" is on screen: its button is opaque (it fades out when away).
bool _goHomeShown(WidgetTester tester) {
  final opacity = find.ancestor(
    of: find.text('Go to Home'),
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity).opacity == 1;
}

/// The bar is on screen: built (it builds nothing while away) and opaque.
bool _barShown(WidgetTester tester) {
  if (find
      .descendant(of: _bar, matching: find.byType(Opacity))
      .evaluate()
      .isEmpty) {
    return false;
  }
  final o = tester.widget<Opacity>(
    find.descendant(of: _bar, matching: find.byType(Opacity)),
  );
  return o.opacity == 1;
}

/// Never both at once.
void _neverTogether(WidgetTester tester) {
  expect(
    _goHomeShown(tester) && _barShown(tester),
    isFalse,
    reason: 'the bar and Go to Home are both on screen',
  );
}

Future<void> _scrollDown(WidgetTester tester, [double by = 300]) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, -by));
  await _frames(tester);
}

Future<void> _scrollUp(WidgetTester tester, [double by = 120]) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, by));
  await _frames(tester);
}

int _cards(WidgetTester tester) => find.byType(PostCard).evaluate().length;

void main() {
  testWidgets('the bar and Go to Home take turns as the feed scrolls', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);

      // At the top: Go to Home only.
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);

      // Scrolling down: the bar replaces it.
      await _scrollDown(tester);
      expect(_goHomeShown(tester), isFalse);
      expect(_barShown(tester), isTrue);
      _neverTogether(tester);

      // Scrolling back up (backwards): Go to Home returns, the bar leaves.
      await _scrollUp(tester);
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);
      _neverTogether(tester);

      // Down and up again: same.
      await _scrollDown(tester);
      expect(_barShown(tester), isTrue);
      await _scrollUp(tester, 2000);
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('the bar has the categories that exist, in order', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      final labels = [
        for (final e
            in find
                .descendant(of: _bar, matching: find.byType(Text))
                .evaluate())
          (e.widget as Text).data,
      ];
      expect(labels, ['All', 'Events', 'Urgent', 'Stories', 'Updates']);
      await _close(tester);
    });
  });

  testWidgets('a category filters the list; the bar stays; Show-all reminder', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      expect(_barShown(tester), isTrue);

      await tester.tap(_item('Urgent'));
      await _frames(tester, 20);
      // Only the urgent post is left (1 of the 6).
      expect(find.text('City Blood Bank'), findsOneWidget);
      expect(find.text('Capstone'), findsNothing);
      expect(_cards(tester), 1);
      // The bar stays, Go to Home stays away.
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      _neverTogether(tester);

      // A later scroll up swaps them.
      await _scrollUp(tester);
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('a short filtered list keeps the bar and hides Go to Home', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      // Tall enough that the Urgent post alone fits without scrolling.
      await _pumpFeed(tester, run, size: const Size(360, 1500));
      await _scrollDown(tester, 200);
      expect(_barShown(tester), isTrue);

      await tester.tap(_item('Urgent'));
      await _frames(tester, 20);
      expect(_cards(tester), 1);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.maxScrollExtent, lessThanOrEqualTo(0));
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);

      // Back to All: that list scrolls again, and the bar stays (the donor
      // tapped it); Go to Home comes back only by scrolling up.
      await tester.tap(_item('All'));
      await _frames(tester, 20);
      // Cards build lazily, so look for posts of several kinds, not a count.
      expect(find.text('City Blood Bank'), findsOneWidget);
      expect(find.text('Capstone'), findsWidgets);
      expect(_cards(tester), greaterThan(1));
      await _close(tester);
    });
  });

  testWidgets('with All selected and a list that cannot scroll: Go to Home', (
    tester,
  ) async {
    final run = _Run([urgentPostJson(), storyPostJson(content: 'Short.')]);
    await _with(run, () async {
      await _pumpFeed(tester, run, size: const Size(360, 1500));
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('with one category the bar never appears', (tester) async {
    final run = _Run([for (var i = 0; i < 6; i++) storyPostJson(id: 200 + i)]);
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      expect(_barShown(tester), isFalse);
      expect(find.bySemanticsLabel('Post categories'), findsNothing);
      // Go to Home behaves as it always did: away while scrolling down.
      expect(_goHomeShown(tester), isFalse);
      await _scrollUp(tester);
      expect(_goHomeShown(tester), isTrue);
      await _close(tester);
    });
  });

  testWidgets('no bar while the feed is empty', (tester) async {
    final run = _Run(const []);
    await _with(run, () async {
      await _pumpFeed(tester, run);
      expect(_barShown(tester), isFalse);
      expect(_goHomeShown(tester), isTrue);
      await _close(tester);
    });
  });

  testWidgets('the bar slides in; with animations off it only fades', (
    tester,
  ) async {
    double slideOf(WidgetTester t) => t
        .widget<Transform>(
          find.descendant(of: _bar, matching: find.byType(Transform)).first,
        )
        .transform
        .getTranslation()
        .y;

    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      // Part-way in: still below its place.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(slideOf(tester), greaterThan(0));
      await _frames(tester);
      expect(slideOf(tester), 0);
      await _close(tester);
    });

    final still = _Run(samplePostsJson());
    await _with(still, () async {
      await _pumpFeed(tester, still, reduceMotion: true);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));
      // A cross-fade: in place from the first frame.
      expect(
        find.descendant(of: _bar, matching: find.byType(Transform)),
        findsWidgets,
      );
      expect(slideOf(tester), 0);
      await _frames(tester);
      expect(_barShown(tester), isTrue);
      await _close(tester);
    });
  });

  testWidgets(
    'the reminder row shows the category and Show all returns to All',
    (tester) async {
      final run = _Run(samplePostsJson());
      await _with(run, () async {
        await _pumpFeed(tester, run);
        expect(find.textContaining('Showing'), findsNothing);
        await _scrollDown(tester);

        await tester.tap(_item('Events'));
        await _frames(tester, 20);
        expect(find.text('Showing Events - 2 posts'), findsOneWidget);
        expect(find.text('Show all'), findsOneWidget);

        await tester.tap(_item('Updates'));
        await _frames(tester, 20);
        expect(find.text('Showing Updates - 1 post'), findsOneWidget);

        await tester.tap(find.text('Show all'));
        await _frames(tester, 20);
        expect(find.textContaining('Showing'), findsNothing);
        expect(find.text('City Blood Bank'), findsOneWidget);
        // The bar stays, as after any category tap.
        expect(_barShown(tester), isTrue);
        await _close(tester);
      });
    },
  );

  testWidgets('a category change is announced', (tester) async {
    final handle = tester.ensureSemantics();
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final m = message as Map;
            if (m['type'] == 'announce') {
              announced.add((m['data'] as Map)['message'] as String);
            }
            return null;
          });
      await _scrollDown(tester);
      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      expect(announced, ['Showing Events, 2 posts']);
      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      // The same category again says nothing new.
      expect(announced, hasLength(1));
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('the bar is a labelled group of selectable buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      // Away: nothing of it is exposed.
      expect(find.bySemanticsLabel('Post categories'), findsNothing);
      await _scrollDown(tester);
      expect(find.bySemanticsLabel('Post categories'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('All, 6 posts')),
        containsSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Events, 2 posts')),
        containsSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Urgent, 1 post'), findsOneWidget);
      expect(find.bySemanticsLabel('Stories, 2 posts'), findsOneWidget);
      expect(find.bySemanticsLabel('Updates, 1 post'), findsOneWidget);
      await _close(tester);
    });
    handle.dispose();
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'the bar meets the guidelines (${dark ? 'dark' : 'light'}, text x$scale)',
        (tester) async {
          final handle = tester.ensureSemantics();
          final run = _Run(samplePostsJson());
          await _with(run, () async {
            await _pumpFeed(tester, run, dark: dark, scale: scale);
            // Far enough that the welcome cards (the verified card's small close
            // button is an existing 18 px target) are off screen.
            await _scrollDown(tester, 700);
            expect(_barShown(tester), isTrue);
            expect(run.overflows, isEmpty, reason: run.overflows.join(' | '));
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await _close(tester);
          });
          handle.dispose();
        },
      );
    }
  }
}
