import 'dart:convert';

import 'package:blood/app_theme.dart';
import 'package:blood/book.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/privacy_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';
import 'support/sample_posts.dart';

/// The redesigned post card: every kind of post in both themes, and the
/// like, double tap, Read more and Donate Now behaviors.

class _Server {
  final likes = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('like_post.php')) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      likes.add(body);
      return okJson({'success': true, 'likes': body['liked'] == true ? 3 : 2});
    }
    return pumpableServer(r);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpCards(
  WidgetTester tester,
  List<Map<String, dynamic>> posts, {
  bool dark = false,
  double scale = 1,
  bool canDonate = true,
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
  });
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font is much wider than the real one (Roboto): overflow is not a
  // bug here (the layout is checked with real fonts separately).
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed') || text.contains('MissingPlugin')) return;
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
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final json in posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: PostCard(
                    post: Post.fromJson(json),
                    canDonate: canDonate,
                    isLoggedIn: true,
                    verificationStatus: 'verified',
                  ),
                ),
            ],
          ),
        ),
      ),
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

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester, 4);
}

Future<void> _guidelines(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

final _variants = <String, Map<String, dynamic>>{
  'event without image': eventPostJson(),
  'event with image': eventPostJson(image: 'https://example.com/poster.jpg'),
  'long story': storyPostJson(),
  'urgent': urgentPostJson(),
  'milestone': milestonePostJson(),
  'short story': storyPostJson(content: '❤️ Thank you, donors!'),
  'plain post': plainPostJson(),
};

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final scale in [1.0, 1.3]) {
      for (final MapEntry(key: name, value: json) in _variants.entries) {
        testWidgets('$name looks right ($mode, text x$scale)', (tester) async {
          final handle = tester.ensureSemantics();
          await _with(_Server(), () async {
            await _pumpCards(tester, [json], dark: dark, scale: scale);
            expect(find.byType(PostCard), findsOneWidget);
            await _guidelines(tester);
            await _close(tester);
          });
          handle.dispose();
        });
      }
    }
  }

  testWidgets('the event reads as title, details, status and note', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _with(_Server(), () async {
      await _pumpCards(tester, [eventPostJson()]);
      expect(find.text('Capstone'), findsOneWidget);
      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Mon, October 12, 2026'), findsOneWidget);
      expect(find.text('90 donors'), findsOneWidget);
      expect(find.textContaining('Only eligible donors'), findsOneWidget);
      // The emoji lines are gone; the raw text is not shown as is.
      expect(find.textContaining('📅'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Official event by Dugtong, 1 week ago, Capstone, '
          'Mon, October 12, 2026, Open',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Like, 2 likes'), findsOneWidget);
      expect(find.bySemanticsLabel('Comment, 3 comments'), findsOneWidget);
      expect(find.bySemanticsLabel('Share'), findsOneWidget);
      await _close(tester);
    });
    handle.dispose();
  });

  testWidgets('Like toggles, sends the like and shows the count', (
    tester,
  ) async {
    final s = _Server();
    await _with(s, () async {
      await _pumpCards(tester, [eventPostJson()]);
      expect(find.text('Like 2'), findsOneWidget);

      await _tap(tester, find.text('Like 2'));
      expect(find.text('Like 3'), findsOneWidget);
      expect(s.likes.single, {'post_id': 101, 'donor_id': '7', 'liked': true});

      await _tap(tester, find.text('Like 3'));
      expect(find.text('Like 2'), findsOneWidget);
      expect(s.likes.last['liked'], false);
      await _close(tester);
    });
  });

  testWidgets('a double tap on the photo likes, and never unlikes', (
    tester,
  ) async {
    final s = _Server();
    await _with(s, () async {
      await _pumpCards(tester, [
        eventPostJson(image: 'https://example.com/poster.jpg'),
      ]);
      final photo = find.bySemanticsLabel('Post photo. Opens full screen');
      await tester.ensureVisible(photo);
      await tester.pump();

      Future<void> doubleTap() async {
        await tester.tap(photo, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(photo, warnIfMissed: false);
        await _frames(tester, 10);
      }

      await doubleTap();
      expect(s.likes, hasLength(1));
      expect(s.likes.single['liked'], true);
      expect(find.text('Like 3'), findsOneWidget);

      // Already liked: a second double tap leaves it liked.
      await doubleTap();
      expect(s.likes, hasLength(1));
      expect(find.text('Like 3'), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('Read more opens the whole text and Show less folds it', (
    tester,
  ) async {
    await _with(_Server(), () async {
      await _pumpCards(tester, [storyPostJson()]);
      Text body() => tester.widget<Text>(
        find.textContaining('Last Saturday our volunteers'),
      );
      expect(body().maxLines, 6);

      await _tap(tester, find.text('Read more'));
      expect(body().maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);

      await _tap(tester, find.text('Show less'));
      expect(body().maxLines, 6);
      await _close(tester);
    });
  });

  testWidgets('a short post has no Read more', (tester) async {
    await _with(_Server(), () async {
      await _pumpCards(tester, [plainPostJson()]);
      expect(find.text('Read more'), findsNothing);
      await _close(tester);
    });
  });

  testWidgets('Donate Now opens Book with the post facility', (tester) async {
    await _with(_Server(), () async {
      await _pumpCards(tester, [urgentPostJson()]);
      await _tap(tester, find.text('Donate Now'));
      await _frames(tester, 6);
      final book = tester.widget<BookScreen>(find.byType(BookScreen));
      expect(book.preselectedFacilityId, 4);
      expect(book.showBackButton, isTrue);
      await _close(tester);
    });
  });

  testWidgets('Donate Now only shows when the donor may donate', (
    tester,
  ) async {
    await _with(_Server(), () async {
      // Not a verified donor.
      await _pumpCards(tester, [eventPostJson()], canDonate: false);
      expect(find.text('Donate Now'), findsNothing);
      await _close(tester);

      // The event is closed.
      await _pumpCards(tester, [eventPostJson(donationOpen: false)]);
      expect(find.text('Donate Now'), findsNothing);
      expect(find.text('Closed'), findsOneWidget);
      await _close(tester);

      // Not a donation post.
      await _pumpCards(tester, [storyPostJson()]);
      expect(find.text('Donate Now'), findsNothing);
      await _close(tester);
    });
  });

  testWidgets('the menu copies the post text', (tester) async {
    String? copied;
    await _with(_Server(), () async {
      await _pumpCards(tester, [plainPostJson()]);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await _tap(tester, find.byTooltip('More options'));
      await _tap(tester, find.text('Copy text'));
      expect(copied, 'Drop by our booth at the mall this weekend!');
      expect(find.text('Copied'), findsOneWidget);
      await _close(tester);
    });
  });
}
