import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/theme_controller.dart';
import 'package:blood/theme_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _switchKey = GlobalKey();

/// Wired like main.dart: boundary + reveal host in MaterialApp.builder.
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ThemeController.instance,
      ThemeTransition.running,
    ]),
    builder: (context, _) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeController.instance.isDark
          ? ThemeMode.dark
          : ThemeMode.light,
      themeAnimationDuration: ThemeTransition.running.value
          ? Duration.zero
          : const Duration(milliseconds: 250),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(key: ThemeTransition.boundaryKey, child: child),
          const ThemeRevealHost(),
        ],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: _switchKey,
              onPressed: () =>
                  ThemeTransition.toggle(context, originKey: _switchKey),
              child: Text(
                'toggle',
                style: TextStyle(color: context.palette.foreground),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Drives frames (and real async for toImage) until [f] is done.
Future<void> _drive(WidgetTester tester, Future<void> f) async {
  var done = false;
  f.whenComplete(() => done = true);
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'the reveal must always finish');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.load();
  });

  testWidgets('the reveal switches the theme and always cleans up', (
    tester,
  ) async {
    await tester.pumpWidget(const _App());
    final ctx = tester.element(find.text('toggle'));

    var sawOverlay = false;
    void watch() {
      if (ThemeTransition.state.value != null) sawOverlay = true;
    }

    ThemeTransition.state.addListener(watch);
    addTearDown(() => ThemeTransition.state.removeListener(watch));

    final f = ThemeTransition.toggle(ctx, originKey: _switchKey);
    expect(ThemeTransition.running.value, isTrue);
    // A second toggle while one runs is ignored.
    await ThemeTransition.toggle(ctx, originKey: _switchKey);
    await _drive(tester, f);

    expect(sawOverlay, isTrue);
    expect(ThemeController.instance.isDark, isTrue);
    expect(ThemeTransition.running.value, isFalse);
    expect(ThemeTransition.state.value, isNull);

    // And back to light the same way.
    await _drive(tester, ThemeTransition.toggle(ctx, originKey: _switchKey));
    expect(ThemeController.instance.isDark, isFalse);
    expect(ThemeTransition.state.value, isNull);
  });

  testWidgets('with animations removed it just switches (the plain fade)', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(const _App());
    final ctx = tester.element(find.text('toggle'));
    await ThemeTransition.toggle(ctx, originKey: _switchKey);
    expect(ThemeController.instance.isDark, isTrue);
    expect(ThemeTransition.state.value, isNull);
    expect(ThemeTransition.running.value, isFalse);
    await ThemeController.instance.setDark(false);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
