import 'dart:ui' show Tristate;

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

  List<Map<String, dynamic>> posts;
  final overflows = <String>[];

  /// What the server says about the donor's ID.
  String verification = 'verified';
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
  // The feed opened from another page, so "back" has somewhere to go.
  bool below = false,
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
      home: below
          ? Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NewsfeedPage()),
                    ),
                    child: const Text('open the feed'),
                  ),
                ),
              ),
            )
          : const NewsfeedPage(),
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
        if (r.url.path.endsWith('get_verification_status.php')) {
          return okJson({
            'status': 'success',
            'verification_status': run.verification,
          });
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
  await tester.drag(
    find.byType(CustomScrollView).hitTestable(),
    Offset(0, -by),
  );
  await _frames(tester);
}

Future<void> _scrollUp(WidgetTester tester, [double by = 120]) async {
  await tester.drag(find.byType(CustomScrollView).hitTestable(), Offset(0, by));
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

      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      // The Events page: its posts, not the others.
      expect(find.text('Capstone'), findsWidgets);
      expect(find.text('City Blood Bank'), findsNothing);
      // The bar stays, Go to Home stays away.
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      _neverTogether(tester);

      // The first vertical scroll on the new page, then up: they swap.
      await _scrollDown(tester, 200);
      expect(_barShown(tester), isTrue);
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
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView).hitTestable(),
              matching: find.byType(Scrollable),
            ),
          )
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
      await tester.drag(
        find.byType(CustomScrollView).hitTestable(),
        const Offset(0, -300),
      );
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
      await tester.drag(
        find.byType(CustomScrollView).hitTestable(),
        const Offset(0, -300),
      );
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

  testWidgets('a category tap puts the first post right under the header', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      final top = tester
          .getTopLeft(find.byType(RefreshIndicator).hitTestable())
          .dy;
      final first = tester
          .getTopLeft(find.byType(PostCard).hitTestable().first)
          .dy;
      expect(first - top, closeTo(8, 1));
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      await _close(tester);
    });
  });

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

  // ── Swipeable pages and the glass bar ─────────────────────────────────

  Finder pageScroll(String name) =>
      find.byKey(ValueKey('feed-scroll-$name'), skipOffstage: false);

  double pageOffset(WidgetTester tester, String name) => tester
      .state<ScrollableState>(
        find.descendant(
          of: pageScroll(name),
          matching: find.byType(Scrollable),
          skipOffstage: false,
        ),
      )
      .position
      .pixels;

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await _frames(tester, 20);
  }

  Future<void> swipeRight(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await _frames(tester, 20);
  }

  /// Whether the bar item [label] is the selected one.
  bool selectedItem(WidgetTester tester, String label, int posts) {
    final node = tester.getSemantics(
      find.bySemanticsLabel('$label, ${postsLabel(posts)}'),
    );
    return node.flagsCollection.isSelected == Tristate.isTrue;
  }

  testWidgets('swiping changes the category, reveals the bar, then the rules', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final run = _Run(samplePostsJson());
    final haptics = <String>[];
    final announced = <String>[];
    await _with(run, () async {
      await _pumpFeed(tester, run);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
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

      // At the top: Go to Home only.
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);

      await swipeLeft(tester);
      // The Events page: its posts, the bar revealed, Go to Home away.
      expect(find.text('Capstone'), findsWidgets);
      expect(find.text('City Blood Bank'), findsNothing);
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      expect(selectedItem(tester, 'Events', 2), isTrue);
      expect(selectedItem(tester, 'All', 6), isFalse);
      expect(haptics.where((h) => h.contains('selectionClick')), hasLength(1));
      expect(announced, ['Showing Events, 2 posts']);
      // Each page is labelled for a screen reader.
      expect(
        find.bySemanticsLabel('Events posts, page 2 of 5'),
        findsOneWidget,
      );

      // The bar stays until a vertical scroll; then the normal swap rules.
      await _scrollDown(tester, 200);
      expect(_barShown(tester), isTrue);
      await _scrollUp(tester);
      expect(_goHomeShown(tester), isTrue);
      expect(_barShown(tester), isFalse);

      // Swiping back selects All again.
      await swipeRight(tester);
      expect(selectedItem(tester, 'All', 6), isTrue);
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('a far tap lands on its page without building the middle ones', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      await tester.tap(_item('Updates'));
      await _frames(tester, 20);
      expect(find.text('Dugtong'), findsWidgets); // the milestone's poster
      expect(find.text('1,000 donations this year!'), findsOneWidget);
      // Events and Urgent were never built (only the page next to the target
      // was, by the jump before the animation).
      expect(pageScroll('events'), findsNothing);
      expect(pageScroll('urgent'), findsNothing);
      expect(pageScroll('updates'), findsOneWidget);
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('tapping the selected category scrolls its page to the top', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      await _scrollDown(tester, 500);
      expect(pageOffset(tester, 'events'), greaterThan(100));

      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      expect(pageOffset(tester, 'events'), 0);
      // The bar stays: the donor tapped it.
      expect(_barShown(tester), isTrue);
      expect(_goHomeShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('each page keeps its scroll position', (tester) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester, 500);
      final before = pageOffset(tester, 'all');
      expect(before, greaterThan(300));

      await swipeLeft(tester); // Events
      await _scrollDown(tester, 250);
      final events = pageOffset(tester, 'events');
      expect(events, greaterThan(100));

      await swipeRight(tester); // back to All
      expect(pageOffset(tester, 'all'), before);
      await swipeLeft(tester);
      expect(pageOffset(tester, 'events'), events);
      await _close(tester);
    });
  });

  testWidgets('one category: one page, no swiping, no bar', (tester) async {
    final run = _Run([for (var i = 0; i < 6; i++) storyPostJson(id: 200 + i)]);
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _frames(tester);
      expect(pageScroll('all'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await _scrollDown(tester);
      expect(_barShown(tester), isFalse);
      await _close(tester);
    });
  });

  testWidgets('a reload that removes the category falls back to All', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      await tester.tap(_item('Events'));
      await _frames(tester, 20);
      expect(selectedItem(tester, 'Events', 2), isTrue);

      // The events are gone on the server; pull to refresh on that page.
      run.posts = [
        urgentPostJson(),
        milestonePostJson(),
        storyPostJson(),
        plainPostJson(),
      ];
      await tester.fling(
        find.byType(CustomScrollView).hitTestable(),
        const Offset(0, 400),
        1000,
      );
      await _frames(tester, 30);
      await tester.pump(const Duration(milliseconds: 100));
      // The page is All again, shown, and Events is not in the bar.
      expect(selectedItem(tester, 'All', 4), isTrue);
      expect(find.text('City Blood Bank'), findsOneWidget);
      expect(_item('Events'), findsNothing);
      await _close(tester);
    });
  });

  testWidgets('a reload that shifts the pages keeps the page you are on', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      await tester.tap(_item('Stories'));
      await _frames(tester, 20);
      expect(selectedItem(tester, 'Stories', 2), isTrue);

      // The urgent post is gone: Stories moves from page 3 to page 2.
      run.posts = [
        for (final p in samplePostsJson())
          if (p['type'] != 'urgent') p,
      ];
      await tester.fling(
        find.byType(CustomScrollView).hitTestable(),
        const Offset(0, 400),
        1000,
      );
      await _frames(tester, 30);
      expect(selectedItem(tester, 'Stories', 2), isTrue);
      expect(find.text('Maria Santos'), findsWidgets);
      await _close(tester);
    });
  });

  testWidgets('the glass lens follows the page, stretches between, rests', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      final lens = find.byKey(const ValueKey('glass-lens'));
      final allX = tester.getCenter(_item('All')).dx;
      final eventsX = tester.getCenter(_item('Events')).dx;

      // At rest: centered on the item, not stretched.
      final rest = tester.getRect(lens);
      expect(rest.center.dx, closeTo(allX, 1));
      expect(rest.width, lessThanOrEqualTo(76.01));

      // Half way through a swipe: between the two items, stretched.
      final g = await tester.startGesture(const Offset(300, 200));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final page = tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .page!;
      expect(page, inExclusiveRange(0.2, 0.8));
      final mid = tester.getRect(lens);
      expect(mid.center.dx, greaterThan(allX));
      expect(mid.center.dx, lessThan(eventsX));
      expect(mid.width, greaterThan(rest.width * 1.05));
      expect(mid.height, lessThan(rest.height));

      // Far enough past half way to settle on Events.
      for (var i = 0; i < 2; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await _frames(tester, 20);
      final done = tester.getRect(lens);
      expect(done.center.dx, closeTo(eventsX, 1));
      expect(done.width, closeTo(rest.width, 0.5));
      await _close(tester);
    });
  });

  testWidgets('dragging a finger along the bar moves the pages and the lens', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run);
      await _scrollDown(tester);
      final lens = find.byKey(const ValueKey('glass-lens'));
      final allX = tester.getCenter(_item('All')).dx;
      final urgentX = tester.getCenter(_item('Urgent')).dx;
      final y = tester.getCenter(_item('All')).dy;

      final g = await tester.startGesture(Offset(allX, y));
      for (var i = 0; i < 4; i++) {
        await g.moveBy(Offset((urgentX - allX) / 4 / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Half way along: the lens is between All and Urgent, with the finger.
      final lensX = tester.getRect(lens).center.dx;
      expect(lensX, inExclusiveRange(allX + 5, urgentX - 5));

      for (var i = 0; i < 4; i++) {
        await g.moveBy(Offset((urgentX - allX) / 4 / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await _frames(tester, 20);
      // Settled on Urgent: its page, its item selected, the lens on it.
      expect(find.text('City Blood Bank'), findsOneWidget);
      expect(selectedItem(tester, 'Urgent', 1), isTrue);
      expect(tester.getRect(lens).center.dx, closeTo(urgentX, 1));
      expect(_barShown(tester), isTrue);
      await _close(tester);
    });
  });

  testWidgets('with animations off the lens never stretches', (tester) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run, reduceMotion: true);
      await _scrollDown(tester);
      final lens = find.byKey(const ValueKey('glass-lens'));
      final rest = tester.getRect(lens);
      final g = await tester.startGesture(const Offset(300, 200));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Swiping still works: the lens moved with the page, at its own size.
      final mid = tester.getRect(lens);
      expect(mid.center.dx, greaterThan(rest.center.dx));
      expect(mid.width, closeTo(rest.width, 0.5));
      expect(mid.height, closeTo(rest.height, 0.5));
      await g.up();
      await _frames(tester, 10);

      // A tap jumps: the far page is there at once, none in between.
      await tester.tap(_item('Updates'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(pageScroll('updates'), findsOneWidget);
      expect(pageScroll('stories'), findsNothing);
      expect(pageScroll('urgent'), findsNothing);
      await _close(tester);
    });
  });

  testWidgets('back goes to All first; from All it pops as before', (
    tester,
  ) async {
    final run = _Run(samplePostsJson());
    await _with(run, () async {
      await _pumpFeed(tester, run, below: true);
      await tester.tap(find.text('open the feed'));
      await _frames(tester, 8);
      await _scrollDown(tester);
      await tester.tap(_item('Urgent'));
      await _frames(tester, 20);
      expect(selectedItem(tester, 'Urgent', 1), isTrue);

      // Back from a category: All, and still on the feed.
      await tester.binding.handlePopRoute();
      await _frames(tester, 20);
      expect(selectedItem(tester, 'All', 6), isTrue);
      expect(find.text('open the feed'), findsNothing);

      // Back from All: leaves the feed.
      await tester.binding.handlePopRoute();
      await _frames(tester, 10);
      expect(find.text('open the feed'), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('the Verify banner goes to All, then scrolls to the card', (
    tester,
  ) async {
    final run = _Run(samplePostsJson())..verification = 'unverified';
    await _with(run, () async {
      await _pumpFeed(tester, run);
      // Go to a category page; scroll there and back up so the banner shows.
      await swipeLeft(tester);
      await _scrollDown(tester, 200);
      await _scrollUp(tester);
      final banner = find.text('Verify your ID to unlock the rest of the app');
      expect(banner, findsOneWidget);
      // On the Events page (its posts; the bar is away while the banner shows).
      expect(find.text('Capstone'), findsWidgets);
      expect(find.text('City Blood Bank'), findsNothing);

      await tester.tap(banner);
      await _frames(tester, 30);
      // The All page, at the top with the verify card.
      expect(
        find.byKey(const ValueKey('feed-scroll-all')).hitTestable(),
        findsOneWidget,
      );
      expect(pageOffset(tester, 'all'), 0);
      expect(
        find.byKey(const ValueKey('feed-scroll-events')).hitTestable(),
        findsNothing,
      );
      await _close(tester);
    });
  });
}
