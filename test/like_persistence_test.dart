import 'dart:async';
import 'dart:convert';

import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/newsfeed/category_nav_bar.dart';
import 'package:blood/newsfeed/like_store.dart';
import 'package:blood/newsfeed/post_parts.dart';
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

/// A like has to stay: the request is right, the heart survives every way the
/// feed rebuilds, failures say so, quick taps are sent in order, and a
/// refresh that arrives late never undoes a newer tap.

/// A server that remembers likes, and records what it is asked.
class _Server {
  _Server({this.image});

  final String? image;

  /// Post ids liked on the server.
  final liked = <int>{};
  final likeBodies = <Map<String, dynamic>>[];
  final likeHeaders = <Map<String, String>>[];
  int feedLoads = 0;

  /// Answers like requests with this status; 200 when null.
  int? failWith;

  /// The next like request waits for this before it is answered.
  Completer<void>? likeGate;

  /// The next feed request waits for this before it is answered.
  Completer<void>? feedGate;

  /// When set, the feed always answers with this (stale) state.
  bool staleFeed = false;

  int active = 0;
  int maxActive = 0;

  Map<String, dynamic> post(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final base = json['likes'] as int;
    final isLiked = staleFeed ? false : liked.contains(id);
    return {...json, 'liked': isLiked, 'likes': base + (isLiked ? 1 : 0)};
  }

  Future<http.Response> handle(http.Request r) async {
    final name = r.url.path.split('/').last;
    if (name == 'get_posts.php') {
      feedLoads++;
      final gate = feedGate;
      feedGate = null;
      final snapshot = [
        post(eventPostJson(image: image)),
        post(urgentPostJson()),
        post(milestonePostJson()),
        post(storyPostJson()),
      ];
      await gate?.future;
      return okJson({'success': true, 'posts': snapshot});
    }
    if (name == 'like_post.php') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      likeBodies.add(body);
      likeHeaders.add(r.headers);
      active++;
      if (active > maxActive) maxActive = active;
      final gate = likeGate;
      likeGate = null;
      await gate?.future;
      active--;
      if (failWith != null) return http.Response('error', failWith!);
      final id = body['post_id'] as int;
      if (body['liked'] == true) {
        liked.add(id);
      } else {
        liked.remove(id);
      }
      final base = id == 101 ? 2 : 0;
      return okJson({
        'success': true,
        'liked': liked.contains(id),
        'likes': base + (liked.contains(id) ? 1 : 0),
      });
    }
    return pumpableServer(r);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpFeed(WidgetTester tester, {bool dark = false}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
  });
  StreakController.instance.reset(forgetSeen: true);
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font is wider than the real one (Roboto): overflow is not a bug.
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
      home: const NewsfeedPage(),
    ),
  );
  await _frames(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _with(_Server s, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(s.handle));

Future<void> _tap(WidgetTester tester, Finder f, [int frames = 8]) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester, frames);
}

Future<void> _scrollDown(WidgetTester tester, [double by = 300]) async {
  await tester.drag(
    find.byType(CustomScrollView).hitTestable(),
    Offset(0, -by),
  );
  await _frames(tester);
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(
    find.byType(CustomScrollView).hitTestable(),
    const Offset(0, 3000),
  );
  await _frames(tester);
}

/// Pull down at the top of the feed (the screen's pull-to-refresh).
Future<void> _pullToRefresh(WidgetTester tester) async {
  await _scrollToTop(tester);
  await tester.fling(
    find.byType(CustomScrollView).hitTestable(),
    const Offset(0, 400),
    1000,
  );
  await _frames(tester, 20);
}

Finder _categoryItem(String label) => find.descendant(
  of: find.byType(CategoryNavBar),
  matching: find.text(label),
);

/// The filled red heart is on screen exactly once, in the palette's red.
void _expectHeartRed(WidgetTester tester, {required bool dark}) {
  final heart = find.byIcon(Icons.favorite_rounded);
  expect(heart, findsOneWidget);
  final palette = dark ? AppPalette.dark : AppPalette.light;
  expect(tester.widget<Icon>(heart).color, palette.primaryText);
}

void _expectNoHeart() =>
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);

void main() {
  group('PostLikeStore', () {
    test('a feed asked for before a tap cannot undo it', () async {
      final store = PostLikeStore(
        send: (id, liked) async =>
            LikeAnswer(liked: liked, likes: liked ? 3 : 2),
      );
      final info = store.watch(1, liked: false, likes: 2);
      final mark = store.mark; // the feed is asked for here
      store.setLiked(1, true);
      await Future<void>.delayed(Duration.zero);
      expect(info.value, const LikeInfo(liked: true, likes: 3));
      // ... and answers late, with the old state.
      store.merge([const PostSnapshot(id: 1, liked: false, likes: 2)], mark);
      expect(info.value, const LikeInfo(liked: true, likes: 3));
    });

    test('an untouched post takes what the server says', () {
      final store = PostLikeStore(
        send: (id, liked) async => const LikeAnswer(),
      );
      final info = store.watch(1, liked: false, likes: 2);
      store.merge([
        const PostSnapshot(id: 1, liked: true, likes: 9),
      ], store.mark);
      expect(info.value, const LikeInfo(liked: true, likes: 9));
    });

    test('the server\x27s answer is the truth', () async {
      final store = PostLikeStore(
        send: (id, liked) async => const LikeAnswer(liked: true, likes: 7),
      );
      final info = store.watch(1, liked: false, likes: 2);
      store.setLiked(1, true);
      expect(info.value, const LikeInfo(liked: true, likes: 3)); // at once
      await Future<void>.delayed(Duration.zero);
      expect(info.value, const LikeInfo(liked: true, likes: 7));
    });

    test('the comment count is shared and a late feed does not undo it', () {
      final store = PostLikeStore(
        send: (id, liked) async => const LikeAnswer(),
      );
      final a = store.watchComments(1); // two cards of the same post
      store.watch(1, liked: false, likes: 0, comments: 3);
      final b = store.watchComments(1);
      expect(a, same(b));
      final mark = store.mark;
      store.setComments(1, 4);
      expect(a.value, 4);
      store.merge([
        const PostSnapshot(id: 1, liked: false, likes: 0, comments: 3),
      ], mark);
      expect(b.value, 4);
      store.merge([
        const PostSnapshot(id: 1, liked: false, likes: 0, comments: 5),
      ], store.mark);
      expect(b.value, 5);
    });

    test('a flag and a count may come as 1, "1" or a string', () {
      final post = Post.fromJson({
        'id': 5,
        'liked': 1,
        'likes': '4',
        'comments': 2.0,
      });
      expect(post.liked, isTrue);
      expect(post.likes, 4);
      expect(post.comments, 2);
      expect(Post.fromJson({'id': 5, 'liked': '0'}).liked, isFalse);
      expect(Post.fromJson({'id': 5, 'liked': '1'}).liked, isTrue);
      expect(Post.fromJson({'id': 5, 'liked': false}).liked, isFalse);
      expect(Post.fromJson({'id': 5}).liked, isFalse);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets(
      'Like sends the right request and the heart turns red ($mode)',
      (tester) async {
        final s = _Server();
        await _with(s, () async {
          await _pumpFeed(tester, dark: dark);
          expect(find.text('Like 2'), findsOneWidget);
          _expectNoHeart();

          await _tap(tester, find.text('Like 2'));
          expect(s.likeBodies, [
            {'post_id': 101, 'donor_id': '7', 'liked': true},
          ]);
          expect(s.likeBodies.single['post_id'], isA<int>());
          expect(s.likeBodies.single['donor_id'], isA<String>());
          expect(
            s.likeHeaders.single['content-type'],
            contains('application/json'),
          );
          expect(find.text('Like 3'), findsOneWidget);
          _expectHeartRed(tester, dark: dark);
          await _close(tester);
        });
      },
    );

    testWidgets(
      'the like survives a category tap, All, and a refresh ($mode)',
      (tester) async {
        final s = _Server();
        await _with(s, () async {
          await _pumpFeed(tester, dark: dark);
          await _tap(tester, find.text('Like 2'));
          expect(find.text('Like 3'), findsOneWidget);

          // Select a category and go back to All.
          await _scrollDown(tester);
          await tester.tap(_categoryItem('Urgent'));
          await _frames(tester, 20);
          expect(
            find.text('Like 3'),
            findsNothing,
          ); // the event is filtered out
          await tester.tap(_categoryItem('All'));
          await _frames(tester, 20);
          await _scrollToTop(tester);
          expect(find.text('Like 3'), findsOneWidget);
          _expectHeartRed(tester, dark: dark);

          // Pull to refresh: the server says it is liked.
          final loads = s.feedLoads;
          await _pullToRefresh(tester);
          expect(s.feedLoads, greaterThan(loads));
          expect(find.text('Like 3'), findsOneWidget);
          _expectHeartRed(tester, dark: dark);
          await _close(tester);
        });
      },
    );

    testWidgets('a like that fails reverts the heart and says so ($mode)', (
      tester,
    ) async {
      final s = _Server()..failWith = 500;
      await _with(s, () async {
        await _pumpFeed(tester, dark: dark);
        await _tap(tester, find.text('Like 2'));
        expect(s.likeBodies, hasLength(1));
        expect(find.text('Like 2'), findsOneWidget);
        _expectNoHeart();
        expect(
          find.text("Couldn't save your like. Please try again."),
          findsOneWidget,
        );
        await _close(tester);
      });
    });
  }

  testWidgets('the heart is still red after scrolling away and back', (
    tester,
  ) async {
    final s = _Server();
    await _with(s, () async {
      await _pumpFeed(tester);
      await _tap(tester, find.text('Like 2'));
      expect(find.text('Like 3'), findsOneWidget);
      await _scrollDown(tester, 2500);
      expect(find.text('Like 3'), findsNothing); // the card is gone
      await _scrollToTop(tester);
      expect(find.text('Like 3'), findsOneWidget);
      _expectHeartRed(tester, dark: false);
      await _close(tester);
    });
  });

  testWidgets('like then unlike quickly: both sent, in order, one at a time', (
    tester,
  ) async {
    final s = _Server()..likeGate = Completer<void>();
    final gate = s.likeGate!;
    await _with(s, () async {
      await _pumpFeed(tester);
      await _tap(tester, find.text('Like 2'), 2);
      // The like is on its way; unlike before it was answered.
      expect(find.text('Like 3'), findsOneWidget);
      await _tap(tester, find.text('Like 3'), 2);
      expect(find.text('Like 2'), findsOneWidget);
      // The second waits for the first.
      expect(s.likeBodies.map((b) => b['liked']), [true]);

      gate.complete();
      await _frames(tester, 20);
      expect(s.likeBodies.map((b) => b['liked']), [true, false]);
      expect(s.maxActive, 1);
      expect(find.text('Like 2'), findsOneWidget);
      _expectNoHeart();
      expect(s.liked, isEmpty);
      await _close(tester);
    });
  });

  testWidgets('a refresh that arrives while a like is in flight keeps it', (
    tester,
  ) async {
    final s = _Server()..likeGate = Completer<void>();
    final gate = s.likeGate!;
    await _with(s, () async {
      await _pumpFeed(tester);
      await _tap(tester, find.text('Like 2'), 2);
      expect(find.text('Like 3'), findsOneWidget);

      // The server has not recorded the like yet, so the refresh is stale.
      s.staleFeed = true;
      await _pullToRefresh(tester);
      expect(find.text('Like 3'), findsOneWidget);
      _expectHeartRed(tester, dark: false);

      s.staleFeed = false;
      gate.complete();
      await _frames(tester, 20);
      expect(find.text('Like 3'), findsOneWidget);
      _expectHeartRed(tester, dark: false);
      await _close(tester);
    });
  });

  testWidgets('double tap on the photo likes once, and never unlikes', (
    tester,
  ) async {
    final s = _Server(image: 'https://example.com/poster.jpg');
    await _with(s, () async {
      await _pumpFeed(tester);
      final photo = find.byType(PostImage);
      await tester.ensureVisible(photo);
      await tester.pump();

      Future<void> doubleTap() async {
        await tester.tap(photo, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(photo, warnIfMissed: false);
        await _frames(tester, 12);
      }

      await doubleTap();
      expect(s.likeBodies.map((b) => b['liked']), [true]);
      expect(find.text('Like 3'), findsOneWidget);

      await doubleTap();
      expect(s.likeBodies, hasLength(1));
      expect(find.text('Like 3'), findsOneWidget);
      _expectHeartRed(tester, dark: false);
      await _close(tester);
    });
  });
}
