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

/// With animations removed (the system "remove animations" setting) the
/// polished screens settle: glows are static, numbers don't count, and no
/// ticker keeps running.
const _screens = {
  'home',
  'profile',
  'donation history',
  'donation history (with donations)',
  'eligibility check',
  'splash',
  'book',
};

void main() {
  for (final screen in pumpableScreens.where(
    (s) => _screens.contains(s.name),
  )) {
    for (final dark in [false, true]) {
      testWidgets('${screen.name} settles (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
          'isLoggedIn': true,
          'donorId': '7',
          'userName': 'Rey Ashlee',
          'userEmail': 'rey@example.com',
          ...screen.prefs,
        });
        StreakController.instance.reset(forgetSeen: true);
        tester.view.physicalSize = const Size(360, 780);
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
          // The test font is wider than the real one.
          if (text.contains('overflowed') ||
              text.contains('MissingPlugin') ||
              text.contains('No Firebase App')) {
            return;
          }
          previous?.call(details);
        };
        try {
          await http.runWithClient(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: screen.build(),
              ),
            );
            await tester.pump(const Duration(seconds: 3));
            await tester.pump(const Duration(seconds: 3));
            // The splash hands over to the feed in that second step; its fade
            // needs a frame or two more.
            await tester.pump(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
            expect(tester.binding.transientCallbackCount, 0);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 10));
          }, () => MockClient(screen.server));
        } finally {
          FlutterError.onError = previous;
        }
      });
    }
  }
}
