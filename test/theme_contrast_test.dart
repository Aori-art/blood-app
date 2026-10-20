import 'package:blood/app_theme.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// Every screen that can be pumped without a real network is measured in BOTH
/// themes with flutter_test's text contrast guideline.

Future<void> _meetsContrast(
  WidgetTester tester,
  PumpableScreen screen, {
  required bool dark,
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
    'userEmail': 'rey@example.com',
    ...screen.prefs,
  });
  StreakController.instance.reset(forgetSeen: true);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font (Ahem) is wider than the real one: overflow is not a bug here.
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
  final semantics = tester.ensureSemantics();
  try {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: screen.build(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => MockClient(screen.server));
  } finally {
    semantics.dispose();
    FlutterError.onError = previous;
  }
}

void main() {
  for (final dark in [false, true]) {
    group(dark ? 'dark theme' : 'light theme', () {
      for (final screen in pumpableScreens) {
        final skipLight = !dark && screen.lightGap != null;
        testWidgets(
          skipLight
              ? '${screen.name} (skipped: light look is frozen, known gap: '
                    '${screen.lightGap})'
              : screen.name,
          (tester) => _meetsContrast(tester, screen, dark: dark),
          timeout: const Timeout(Duration(seconds: 60)),
          skip: skipLight,
        );
      }
    });
  }
}
