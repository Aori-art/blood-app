import 'package:blood/app_theme.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/newsfeed/feed_chrome.dart';
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

/// The feed around the posts: filter chips, the footer, empty and error.

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpFeed(WidgetTester tester, Object postsResponse) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
  });
  StreakController.instance.reset(forgetSeen: true);
  tester.view.physicalSize = const Size(390, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
    MaterialApp(theme: AppTheme.light, home: const NewsfeedPage()),
  );
  await _frames(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _with(Object postsResponse, Future<void> Function() body) =>
    http.runWithClient(
      body,
      () => MockClient((r) async {
        if (r.url.path.endsWith('get_posts.php')) {
          return postsResponse is Map<String, dynamic>
              ? okJson(postsResponse)
              : http.Response('oops', 500);
        }
        return pumpableServer(r);
      }),
    );

int _cards(WidgetTester tester) => find.byType(PostCard).evaluate().length;

void main() {
  test('filter groups follow the post types', () {
    expect(FeedFilter.available(['story']), isEmpty);
    expect(FeedFilter.available(['story', 'story']), isEmpty);
    expect(FeedFilter.available(['milestone', 'event']), [
      FeedFilter.all,
      FeedFilter.events,
      FeedFilter.updates,
    ]);
    expect(FeedFilter.urgent.matches('urgent'), isTrue);
    expect(FeedFilter.stories.matches('event'), isFalse);
    expect(FeedFilter.all.matches('milestone'), isTrue);
  });

  testWidgets('the chips filter the list and All brings everything back', (
    tester,
  ) async {
    final posts = {'success': true, 'posts': samplePostsJson()};
    await _with(posts, () async {
      await _pumpFeed(tester, posts);
      expect(_cards(tester), 6);
      expect(find.text("You're all caught up"), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Urgent posts'));
      await _frames(tester);
      expect(_cards(tester), 1);
      expect(find.text('City Blood Bank'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Events posts'));
      await _frames(tester);
      expect(_cards(tester), 2);

      await tester.tap(find.bySemanticsLabel('All posts'));
      await _frames(tester);
      expect(_cards(tester), 6);
      await _close(tester);
    });
  });

  testWidgets('no chips when every post is the same kind', (tester) async {
    final posts = {
      'success': true,
      'posts': [storyPostJson(), storyPostJson(id: 2)],
    };
    await _with(posts, () async {
      await _pumpFeed(tester, posts);
      expect(find.byType(FeedFilterBar), findsNothing);
      expect(_cards(tester), 2);
      await _close(tester);
    });
  });

  testWidgets('empty feed and failed feed', (tester) async {
    final empty = {'success': true, 'posts': <Object>[]};
    await _with(empty, () async {
      await _pumpFeed(tester, empty);
      expect(find.text('No posts yet. Check back soon!'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await _close(tester);
    });
    await _with('fail', () async {
      await _pumpFeed(tester, 'fail');
      expect(find.text("Couldn't load the feed."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await _close(tester);
    });
  });
}
