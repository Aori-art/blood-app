import 'package:blood/app_theme.dart';
import 'package:blood/my_avatar.dart';
import 'package:blood/my_avatar_controller.dart';
import 'package:blood/streak/avatar_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_streak.dart';

/// The donor's own avatar: the photo when there is one, the initials when
/// there is none or it fails to load, and the equipped frame either way.

Widget _host({required bool dark, Widget? child}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  home: Scaffold(
    body: Center(
      child:
          child ??
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MyAvatar(radius: 44),
              SizedBox(width: 16),
              MyAvatar(radius: 22, onGradient: true, ringColor: Colors.white38),
            ],
          ),
    ),
  ),
);

void _me({String? path}) {
  final me = MyAvatarController.instance;
  me.avatarPath = path;
  me.name = 'Rey Ashlee';
  me.frame = null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useFakeStreak(fakeStreak(equipped: 'gold'));
  });
  tearDown(() {
    useFakeStreak(null);
    _me();
  });

  StreakAvatarFrame frameOf(WidgetTester tester) =>
      tester.widget<StreakAvatarFrame>(find.byType(StreakAvatarFrame).first);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('with a photo URL it builds the photo, in the frame ($mode)', (
      tester,
    ) async {
      _me(path: 'https://example.com/me.jpg');
      await tester.pumpWidget(_host(dark: dark));
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<ResizeImage>());
      final provider = (image.image as ResizeImage).imageProvider;
      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).url, 'https://example.com/me.jpg');
      expect(frameOf(tester).frameKey, 'gold');
      expect(
        find.bySemanticsLabel('Rey Ashlee, profile picture'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a relative path becomes a full URL ($mode)', (tester) async {
      _me(path: 'uploads/profile/7.jpg');
      await tester.pumpWidget(_host(dark: dark));
      final image = tester.widget<Image>(find.byType(Image).first);
      final url =
          ((image.image as ResizeImage).imageProvider as NetworkImage).url;
      expect(url, startsWith('http'));
      expect(url, endsWith('/uploads/profile/7.jpg'));
    });

    testWidgets('without a photo it shows the initials, in the frame ($mode)', (
      tester,
    ) async {
      _me();
      await tester.pumpWidget(_host(dark: dark));
      expect(find.byType(Image), findsNothing);
      expect(find.text('RA'), findsOneWidget); // the crimson circle
      expect(find.text('R'), findsOneWidget); // on the red header
      expect(frameOf(tester).frameKey, 'gold');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a photo that fails to load falls back to the initials ($mode)',
      (tester) async {
        // Every network image fails in a widget test (HTTP 400): a broken link.
        _me(path: 'https://example.com/broken.jpg');
        await tester.pumpWidget(_host(dark: dark));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(find.text('RA'), findsOneWidget);
        expect(find.text('R'), findsOneWidget);
        expect(frameOf(tester).frameKey, 'gold');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('no frame equipped: the plain ring on the red header', (
    tester,
  ) async {
    useFakeStreak(fakeStreak());
    _me();
    await tester.pumpWidget(
      _host(
        dark: false,
        child: const MyAvatar(
          radius: 22,
          onGradient: true,
          ringColor: Colors.white38,
        ),
      ),
    );
    // The avatar plus the 3 px gap and 2 px ring on each side.
    expect(tester.getSize(find.byType(MyAvatar)), const Size(54, 54));
    expect(find.text('R'), findsOneWidget);
  });

  testWidgets('reset forgets the donor (and the cached path)', (tester) async {
    SharedPreferences.setMockInitialValues({'my_avatar_path': 'a.jpg'});
    final me = MyAvatarController.instance;
    await me.loadCached();
    expect(me.avatarPath, 'a.jpg');
    me.reset();
    expect(me.avatarPath, isNull);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('my_avatar_path'), isNull);
  });
}
