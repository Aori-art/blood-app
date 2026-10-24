import 'package:blood/app_colors.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/splash_screen/splash_screen.dart';
import 'package:blood/widgets/dugtong_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// The Dugtong name and lockup, on a surface and on the red gradient.

Widget _page({required bool dark, double scale = 1, double width = 328}) {
  Widget onGradient(Widget child) => Container(
    width: width,
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: AppColors.primaryGradient),
    ),
    child: child,
  );
  return MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DugtongLockup(iconSize: 36, tagline: true),
                    SizedBox(height: 12),
                    DugtongWordmark(size: 22),
                    SizedBox(height: 12),
                    DugtongWordmark(size: 18, tagline: true),
                  ],
                ),
              ),
            ),
            onGradient(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DugtongLockup(iconSize: 36, onGradient: true, tagline: true),
                  SizedBox(height: 12),
                  DugtongLockup(
                    iconSize: 64,
                    wordmarkSize: 30,
                    axis: Axis.vertical,
                    onGradient: true,
                    tagline: false,
                  ),
                  SizedBox(height: 12),
                  DugtongWordmark(size: 22, onGradient: true),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final scale in [1.0, 1.3]) {
      testWidgets('wordmark and lockup ($mode, text x$scale)', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_page(dark: dark, scale: scale));
        await tester.pump(const Duration(milliseconds: 100));

        // No overflow, and the contrast guideline holds.
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Every wordmark and lockup is one "Dugtong" for a screen reader;
        // the tagline and the logo inside are not read separately.
        final labelled = find.bySemanticsLabel('Dugtong');
        expect(labelled, findsWidgets);
        expect(find.bySemanticsLabel('BLOOD DONATION NETWORK'), findsNothing);
        expect(find.bySemanticsLabel('Dugtong logo'), findsNothing);
        for (final type in [DugtongWordmark, DugtongLockup]) {
          for (final e in find.byType(type).evaluate()) {
            expect(
              tester.getSemantics(find.byWidget(e.widget)).label,
              'Dugtong',
            );
          }
        }
        handle.dispose();
      });
    }
  }

  testWidgets(
    'the name is "Dug" in the brand red and "tong" in the text color',
    (tester) async {
      await tester.pumpWidget(_page(dark: false));
      final text = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(DugtongWordmark).first,
              matching: find.byType(Text),
            )
            .first,
      );
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((s) => s.text), ['Dug', 'tong']);
      expect(
        spans.every((s) => s.style!.fontWeight == FontWeight.w900),
        isTrue,
      );
      expect(spans[0].style!.color, isNot(spans[1].style!.color));
    },
  );

  testWidgets(
    'the splash shows the finished lockup at once without animations',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
      });
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
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
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const SplashScreen(isLoggedIn: false),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.binding.transientCallbackCount, 0);
        // Name and tagline are fully there (not fading or sliding).
        final tagline = tester.widget<FadeTransition>(
          find.ancestor(
            of: find.text('BLOOD DONATION NETWORK'),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(tagline.opacity.value, 1);
        expect(find.text('Dug'), findsOneWidget);
        expect(find.text('tong'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }, () => MockClient(pumpableServer));
    },
  );
}
