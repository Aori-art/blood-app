import 'package:blood/app_theme.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/newsfeed/category_nav_bar.dart';
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
    expect(FeedCategory.available(['story']), isEmpty);
    expect(FeedCategory.available(['story', 'story']), isEmpty);
    expect(FeedCategory.available(['milestone', 'event']), [
      FeedCategory.all,
      FeedCategory.events,
      FeedCategory.updates,
    ]);
    expect(FeedCategory.urgent.matches('urgent'), isTrue);
    expect(FeedCategory.stories.matches('event'), isFalse);
    expect(FeedCategory.all.matches('milestone'), isTrue);
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
