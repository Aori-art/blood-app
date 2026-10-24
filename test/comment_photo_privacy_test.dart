import 'dart:convert';

import 'package:blood/app_theme.dart';
import 'package:blood/my_avatar_controller.dart';
import 'package:blood/post_comments.dart';
import 'package:blood/privacy_security.dart';
import 'package:blood/privacy_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_streak.dart';
import 'support/pumpable_screens.dart';

/// Hiding my profile photo in comments: the controller, the comment box chip,
/// the Privacy & Security switch and how comments draw the avatars.

class _Server {
  bool hidden;
  bool failSave = false;
  final saves = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> comments;

  _Server({this.hidden = false, List<Map<String, dynamic>>? comments})
    : comments =
          comments ??
          [
            {
              'id': 1,
              'authorName': 'Rey A.',
              'avatar': null,
              'content': 'My comment',
              'timeAgo': '1m',
              'createdAt': '2026-10-23 10:00:00',
              'isMine': true,
              'photoHidden': true,
            },
            {
              'id': 2,
              'authorName': 'Sam T.',
              'avatar': null,
              'content': 'Another donor',
              'timeAgo': '2m',
              'createdAt': '2026-10-23 10:01:00',
              'isMine': false,
              'photoHidden': true,
            },
          ];

  Future<http.Response> handle(http.Request r) async {
    switch (r.url.path.split('/').last) {
      case 'get_my_avatar.php':
        return okJson({
          'success': true,
          'avatar': 'uploads/profile/7.jpg',
          'frame': null,
          'hide_photo_in_comments': hidden,
        });
      case 'set_comment_photo_privacy.php':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        saves.add(body);
        if (failSave) return http.Response('{"success":false}', 500);
        hidden = body['hide'] == true;
        return okJson({'success': true, 'hide_photo_in_comments': hidden});
      case 'get_post_comments.php':
        return okJson({
          'success': true,
          'total': comments.length,
          'hasMore': false,
          'comments': comments,
        });
    }
    return pumpableServer(r);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _setUp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  // Forget the previous test's donor first (reset also clears the cache, a
  // moment later), then seed this one's preferences.
  MyAvatarController.instance.reset();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
    ...prefs,
  });
  useFakeStreak(fakeStreak());
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() {
    useFakeStreak(null);
    MyAvatarController.instance.reset();
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font is much wider than the real one: overflow is not a bug here.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _openComments(WidgetTester tester, {required bool dark}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showPostComments(
                context,
                postId: 1,
                isLoggedIn: true,
                verificationStatus: 'verified',
                total: 2,
                onTotalChanged: (_) {},
              ),
              child: const Text('Open comments'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open comments'));
  await _frames(tester, 14);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Future<void> _with(_Server s, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(s.handle));

final _hiddenLabel = find.bySemanticsLabel(RegExp('Your photo is hidden'));

void main() {
  group('MyAvatarController', () {
    testWidgets('load() reads the choice from the server and caches it', (
      tester,
    ) async {
      await _setUp(tester);
      final s = _Server(hidden: true);
      await _with(s, () async {
        final me = MyAvatarController.instance;
        expect(me.hidePhotoInComments, isFalse);
        await me.load();
        expect(me.hidePhotoInComments, isTrue);
        expect(me.hideKnown, isTrue);
        expect(me.avatarPath, 'uploads/profile/7.jpg');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('hide_photo_in_comments'), isTrue);
      });
    });

    testWidgets('the cached choice is there before the network answers', (
      tester,
    ) async {
      await _setUp(tester, prefs: {'hide_photo_in_comments': true});
      await MyAvatarController.instance.loadCached();
      expect(MyAvatarController.instance.hidePhotoInComments, isTrue);
    });

    testWidgets('setHidePhotoInComments posts the right body', (tester) async {
      await _setUp(tester);
      final s = _Server();
      await _with(s, () async {
        final me = MyAvatarController.instance;
        final future = me.setHidePhotoInComments(true);
        // Optimistic: it already shows before the answer.
        expect(me.hidePhotoInComments, isTrue);
        expect(await future, isTrue);
        expect(s.saves, [
          {'donor_id': 7, 'hide': true},
        ]);
        expect(me.hidePhotoInComments, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('hide_photo_in_comments'), isTrue);

        expect(await me.setHidePhotoInComments(false), isTrue);
        expect(s.saves.last, {'donor_id': 7, 'hide': false});
        expect(me.hidePhotoInComments, isFalse);
      });
    });

    testWidgets('a failure reverts the change and returns false', (
      tester,
    ) async {
      await _setUp(tester);
      final s = _Server()..failSave = true;
      await _with(s, () async {
        final me = MyAvatarController.instance;
        expect(await me.setHidePhotoInComments(true), isFalse);
        expect(me.hidePhotoInComments, isFalse);
        expect(me.hideKnown, isFalse);
      });
    });

    testWidgets('reset() forgets the choice and the cache', (tester) async {
      await _setUp(tester, prefs: {'hide_photo_in_comments': true});
      final me = MyAvatarController.instance;
      await me.loadCached();
      expect(me.hidePhotoInComments, isTrue);
      me.reset();
      expect(me.hidePhotoInComments, isFalse);
      expect(me.hideKnown, isFalse);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hide_photo_in_comments'), isFalse);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('the comment box ($mode)', () {
      testWidgets('the chip toggles the choice, with a confirmation', (
        tester,
      ) async {
        await _setUp(tester);
        final s = _Server(hidden: false);
        await _with(s, () async {
          await _openComments(tester, dark: dark);
          expect(find.text('Photo visible'), findsOneWidget);
          expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

          await tester.tap(find.text('Photo visible'));
          await _frames(tester, 6);
          expect(s.saves, [
            {'donor_id': 7, 'hide': true},
          ]);
          expect(find.text('Photo hidden'), findsOneWidget);
          expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);
          expect(
            find.text(
              'Others will see your initials instead of your photo in comments.',
            ),
            findsOneWidget,
          );
          expect(MyAvatarController.instance.hidePhotoInComments, isTrue);

          await tester.tap(find.text('Photo hidden'));
          await _frames(tester, 6);
          expect(find.text('Photo visible'), findsOneWidget);
          expect(
            find.text('Your photo is visible in comments again.'),
            findsOneWidget,
          );
          await _close(tester);
        });
      });

      testWidgets('a failure puts it back and says so', (tester) async {
        await _setUp(tester);
        final s = _Server(hidden: false)..failSave = true;
        await _with(s, () async {
          await _openComments(tester, dark: dark);
          await tester.tap(find.text('Photo visible'));
          await _frames(tester, 6);
          expect(find.text('Photo visible'), findsOneWidget);
          expect(find.text('Photo hidden'), findsNothing);
          expect(
            find.text("Couldn't save your choice. Please try again."),
            findsOneWidget,
          );
          await _close(tester);
        });
      });

      testWidgets('own comments show initials and the badge when hidden', (
        tester,
      ) async {
        await _setUp(tester);
        final s = _Server(hidden: true);
        final handle = tester.ensureSemantics();
        await _with(s, () async {
          await _openComments(tester, dark: dark);
          // Initials, not photos.
          expect(find.byType(Image), findsNothing);
          expect(find.text('R'), findsWidgets);
          // The composer's avatar and the donor's own comment: both badged.
          expect(_hiddenLabel, findsNWidgets(2));
          // Another donor with no photo: initials, no badge.
          expect(find.text('S'), findsOneWidget);

          // Showing the photo again drops the badges at once.
          await tester.tap(find.text('Photo hidden'));
          await _frames(tester, 6);
          expect(_hiddenLabel, findsNothing);
          await _close(tester);
        });
        handle.dispose();
      });

      testWidgets('meets the text and label guidelines', (tester) async {
        await _setUp(tester);
        final s = _Server(hidden: true);
        final handle = tester.ensureSemantics();
        await _with(s, () async {
          await _openComments(tester, dark: dark);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await _close(tester);
        });
        handle.dispose();
      });

      testWidgets('the chip has a 48 px touch target', (tester) async {
        await _setUp(tester);
        final s = _Server();
        await _with(s, () async {
          await _openComments(tester, dark: dark);
          final box = find.ancestor(
            of: find.text('Photo visible'),
            matching: find.byType(InkWell),
          );
          expect(tester.getSize(box.first).height, greaterThanOrEqualTo(48));
          await _close(tester);
        });
      });
    });

    group('Privacy & Security ($mode)', () {
      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: const PrivacySecurityScreen(),
          ),
        );
        await _frames(tester, 8);
      }

      testWidgets('the switch follows the server and saves', (tester) async {
        await _setUp(tester);
        final s = _Server(hidden: true);
        await _with(s, () async {
          await open(tester);
          expect(find.text('Hide my photo in comments'), findsOneWidget);
          expect(
            find.text('Others will see your initials in comments'),
            findsOneWidget,
          );
          Switch row() => tester.widget<Switch>(find.byType(Switch));
          expect(row().value, isTrue);

          await tester.tap(find.byType(Switch));
          await _frames(tester, 4);
          expect(s.saves.last, {'donor_id': 7, 'hide': false});
          expect(row().value, isFalse);

          // Tapping the row (not just the switch) works too.
          await tester.tap(find.text('Hide my photo in comments'));
          await _frames(tester, 4);
          expect(s.saves.last, {'donor_id': 7, 'hide': true});
          expect(row().value, isTrue);
          await _close(tester);
        });
      });

      testWidgets('a failure reverts the switch and says so', (tester) async {
        await _setUp(tester);
        final s = _Server(hidden: false)..failSave = true;
        await _with(s, () async {
          await open(tester);
          await tester.tap(find.byType(Switch));
          await _frames(tester, 4);
          expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
          expect(
            find.text("Couldn't save your choice. Please try again."),
            findsOneWidget,
          );
          await _close(tester);
        });
      });

      testWidgets('meets the text and label guidelines', (tester) async {
        await _setUp(tester);
        final s = _Server(hidden: true);
        final handle = tester.ensureSemantics();
        await _with(s, () async {
          await open(tester);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await _close(tester);
        });
        handle.dispose();
      });
    });
  }
}
