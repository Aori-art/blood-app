import 'package:blood/app_theme.dart';
import 'package:blood/streak/dugtong.dart';
import 'package:blood/streak/dugtong_chatter.dart';
import 'package:blood/streak/streak_about_sheet.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/streak/streak_home_screen.dart';
import 'package:blood/streak/streak_ladder_screen.dart';
import 'package:blood/streak/streak_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_streak.dart';

/// The streak home: one screen that never scrolls, in both themes, on a
/// small, a normal and a large phone, at normal and large text.

Widget _host({required bool dark, double textScale = 1}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: const StreakHomeScreen(),
);

Future<void> _setUp(
  WidgetTester tester, {
  Size size = const Size(360, 780),
  StreakData? data,
  Map<String, Object> prefs = const {},
}) async {
  // No donor id: refresh() leaves the fake streak alone (no network).
  SharedPreferences.setMockInitialValues({...prefs});
  useFakeStreak(data ?? fakeStreak());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(() => useFakeStreak(null));
}

/// Frames (not one long jump), so entrances and route animations finish.
Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options'));
  await _settle(tester, 4);
}

void main() {
  const sizes = [Size(360, 640), Size(360, 780), Size(411, 890)];
  for (final dark in [false, true]) {
    for (final size in sizes) {
      for (final scale in [1.0, 1.3]) {
        final name =
            '${dark ? 'dark' : 'light'}, '
            '${size.width.toInt()}x${size.height.toInt()}, x$scale';
        testWidgets('fits one screen and meets the guidelines ($name)', (
          tester,
        ) async {
          await _setUp(tester, size: size);
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(_host(dark: dark, textScale: scale));
          await _settle(tester);
          // The worst case: the longest thing Dugtong can say.
          final longest = DugtongChatter.allTemplates.reduce(
            (a, b) => a.length >= b.length ? a : b,
          );
          tester
              .state<StreakHomeScreenState>(find.byType(StreakHomeScreen))
              .debugSay(longest);
          await _settle(tester, 25);
          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsNothing);
          expect(find.bySemanticsLabel('Current streak: 12 days'), findsOne);
          expect(find.bySemanticsLabel(RegExp(r'^Best streak, ')), findsOne);
          expect(find.bySemanticsLabel(RegExp(r'^Total days, ')), findsOne);
          expect(find.bySemanticsLabel(RegExp(r'^Streak Freeze, ')), findsOne);
          expect(
            find.textContaining('more days to Two Weeks Strong'),
            findsOne,
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
          await _tearDown(tester);
        });
      }
    }
  }

  group('menu', () {
    testWidgets('shows exactly the three options', (tester) async {
      await _setUp(tester);
      await tester.pumpWidget(_host(dark: false));
      await _settle(tester);
      await _openMenu(tester);
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      expect(find.text('About Dugtong'), findsOne);
      expect(find.text('Streak settings'), findsOne);
      expect(find.text('Streak ladder'), findsOne);
      await _tearDown(tester);
    });

    testWidgets('"Streak ladder" pushes the ladder page', (tester) async {
      await _setUp(tester);
      await tester.pumpWidget(_host(dark: false));
      await _settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Streak ladder'));
      await _settle(tester);
      expect(find.byType(StreakLadderScreen), findsOne);
      expect(find.text('THE LADDER'), findsOne);
      await _tearDown(tester);
    });

    testWidgets('"About Dugtong" opens the About sheet', (tester) async {
      await _setUp(tester);
      await tester.pumpWidget(_host(dark: true));
      await _settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('About Dugtong'));
      await _settle(tester);
      expect(find.text(kAboutDugtong), findsOne);
      expect(find.text("Dugtong's forms"), findsOne);
      expect(find.text('You'), findsOne);
      expect(tester.takeException(), isNull);
      await _tearDown(tester);
    });

    testWidgets('Streak settings: the switches persist, reset still works', (
      tester,
    ) async {
      await _setUp(
        tester,
        prefs: {'streak_bubble_dx': 'left', 'streak_bubble_dy': 0.8},
      );
      final c = StreakController.instance;
      c.showBubblePref = true;
      c.chatEnabled = true;
      c.bubbleSide = 'left';
      await tester.pumpWidget(_host(dark: false));
      await _settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Streak settings'));
      await _settle(tester);

      await tester.tap(find.text('Show floating streak'));
      await _settle(tester, 2);
      await tester.tap(find.text('Dugtong chat'));
      await _settle(tester, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('streak_bubble_enabled'), isFalse);
      expect(prefs.getBool('streak_chat_enabled'), isFalse);
      expect(c.showBubblePref, isFalse);
      expect(c.chatEnabled, isFalse);

      await tester.tap(find.text('Reset bubble position'));
      await _settle(tester, 3);
      expect(prefs.getString('streak_bubble_dx'), isNull);
      expect(prefs.getDouble('streak_bubble_dy'), isNull);
      expect(c.bubbleSide, 'right');
      expect(find.text('Bubble position reset.'), findsOne);
      await _tearDown(tester);
    });
  });

  group('edge cases', () {
    testWidgets('a streak of 0', (tester) async {
      await _setUp(tester, data: fakeStreak(current: 0, longest: 5));
      await tester.pumpWidget(_host(dark: false));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Start your streak'), findsOne);
      expect(find.bySemanticsLabel('Current streak: 0 days'), findsOne);
      final dugtong = tester.widget<Dugtong>(find.byType(Dugtong).first);
      expect(dugtong.mood, DugtongMood.sleepy);
      await _tearDown(tester);
    });

    testWidgets('a streak with no next reward', (tester) async {
      await _setUp(tester, data: fakeStreak(current: 400, equipped: 'gold'));
      await tester.pumpWidget(_host(dark: true));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text("You've climbed the whole ladder!"), findsOne);
      expect(find.byType(Scrollable), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('the share icon runs the share image with its card', (
      tester,
    ) async {
      await _setUp(tester);
      await tester.pumpWidget(_host(dark: false));
      await _settle(tester);
      expect(find.byTooltip('Share your streak'), findsOne);
      await tester.tap(find.byTooltip('Share your streak'));
      await tester.pump();
      await tester.pump();
      // The existing share function lays its card out off-screen.
      expect(find.byType(StreakShareCard), findsOne);
      expect(tester.takeException(), isNull);
      await _tearDown(tester);
    });

    testWidgets('with animations removed: no count-up, no typing, settles', (
      tester,
    ) async {
      await _setUp(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(_host(dark: false));
      await tester.pump();
      // The final number at once (no count-up from 0).
      expect(find.text('12'), findsWidgets);
      final state = tester.state<StreakHomeScreenState>(
        find.byType(StreakHomeScreen),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final line = state.currentLine;
      expect(line, isNotNull);
      // The whole line at once (no typewriter).
      expect(find.textContaining(line!, findRichText: true), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      await _tearDown(tester);
    });

    testWidgets('at most three tickers, and none after it closes', (
      tester,
    ) async {
      await _setUp(tester);
      await tester.pumpWidget(_host(dark: false));
      await tester.pump(const Duration(milliseconds: 100));
      // During the entrance: the scenery, Dugtong and the entrance itself.
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(3));
      await _settle(tester);
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
