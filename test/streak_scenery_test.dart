import 'package:blood/app_theme.dart';
import 'package:blood/streak/streak_scenery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool dark, VoidCallback? onTap}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  home: Scaffold(
    body: SizedBox(
      width: 360,
      height: 420,
      child: StreakScenery(
        height: 230,
        litWindows: 30,
        parallax: 200,
        onSunMoonTap: onTap,
        child: const SizedBox(width: 360, height: 420),
      ),
    ),
  ),
);

void main() {
  for (final dark in [false, true]) {
    testWidgets('paints and animates (${dark ? 'night' : 'day'})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_host(dark: dark, onTap: () => taps++));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
      expect(find.text(dark ? 'Clear night' : 'Sunny day'), findsOneWidget);
      final label = dark ? 'Switch to light mode' : 'Switch to dark mode';
      expect(find.bySemanticsLabel(label), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(label));
      expect(taps, 1);
      handle.dispose();
    });
  }

  testWidgets('with animations removed it paints a static frame', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(_host(dark: false));
    await tester.pumpWidget(_host(dark: true));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    // No ticker keeps running (pumped once more, without a theme change).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(dark: true));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
  });

  Widget fullScreen({required bool dark, Offset drag = Offset.zero}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 780,
            child: StreakScenery(
              groundFraction: 0.7,
              litWindows: 12,
              drag: drag,
              celestial: const Offset(306, 98),
              captionAt: const Offset(16, 54),
              onSunMoonTap: () {},
            ),
          ),
        ),
      );

  for (final dark in [false, true]) {
    testWidgets('full screen: sizes from its box (${dark ? 'night' : 'day'})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(fullScreen(dark: dark));
      await tester.pump(const Duration(seconds: 1));
      // Dugtong dragged far: the layers shift, nothing breaks.
      await tester.pumpWidget(
        fullScreen(dark: dark, drag: const Offset(-400, 300)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final caption = find.text(dark ? 'Clear night' : 'Sunny day');
      expect(tester.getTopLeft(caption).dy, lessThan(80));
      final label = dark ? 'Switch to light mode' : 'Switch to dark mode';
      expect(
        tester.getCenter(find.bySemanticsLabel(label)),
        const Offset(306, 98),
      );
      handle.dispose();
    });
  }

  testWidgets('full screen: one static frame with animations removed', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(fullScreen(dark: false));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
