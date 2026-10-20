import 'package:blood/app_theme.dart';
import 'package:blood/widgets/glow_pulse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool dark, required Widget child}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

Widget _button(Key key) => SizedBox(
  key: key,
  width: 200,
  height: 52,
  child: ElevatedButton(onPressed: () {}, child: const Text('Book')),
);

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'builds and keeps the child size (${dark ? 'dark' : 'light'})',
      (tester) async {
        const plainKey = Key('plain');
        const glowKey = Key('glow');
        await tester.pumpWidget(_host(dark: dark, child: _button(plainKey)));
        final plain = tester.getSize(find.byKey(plainKey));

        var taps = 0;
        await tester.pumpWidget(
          _host(
            dark: dark,
            child: GlowPulse(
              sheen: true,
              child: SizedBox(
                key: glowKey,
                width: 200,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('Book'),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1200));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(glowKey)), plain);
        expect(tester.getSize(find.byType(GlowPulse)), plain);
        await tester.tap(find.text('Book'));
        expect(taps, 1, reason: 'the glow never blocks touches');
      },
    );
  }

  testWidgets('is inert (no ticker) when disabled', (tester) async {
    await tester.pumpWidget(
      _host(
        dark: false,
        child: GlowPulse(
          enabled: false,
          sheen: true,
          child: _button(const Key('b')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a static halo, no ticker, with animations removed', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      _host(
        dark: true,
        child: GlowPulse(sheen: true, child: _button(const Key('b'))),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
