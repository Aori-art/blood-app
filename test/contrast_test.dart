import 'dart:convert';

import 'package:blood/app_colors.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/login.dart';
import 'package:blood/pin_screen.dart';
import 'package:blood/privacy_consent.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/screens/register/register1.dart';
import 'package:blood/screens/register/register2.dart';
import 'package:blood/screens/register/register3.dart';
import 'package:blood/splash_screen/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text on the red surfaces (headers, CTA cards, buttons, splash, login, PIN)
/// must stay readable. These tests pump screens that need no real network and
/// let flutter_test measure the painted text against what is behind it.

http.Response _json(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);

Future<http.Response> _server(http.Request request) async {
  if (request.url.path.endsWith('pin_api.php')) {
    return _json({
      'status': 'success',
      'has_pin': true,
      'is_verified': true,
      'first_name': 'Rey',
      'lock_seconds': 0,
    });
  }
  return _json({'status': 'success', 'success': true});
}

/// Pumps [screen], then checks every piece of text against the guideline.
Future<void> _meetsContrast(
  WidgetTester tester,
  Widget screen, {
  Duration settle = const Duration(milliseconds: 1600),
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
    ...prefs,
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font (Ahem) is wider than the real one, so rows can overflow here
  // without being a bug; only contrast is being checked.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  final semantics = tester.ensureSemantics();
  try {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: screen),
      );
      await tester.pump(settle);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      // Dispose, then let leftover timers (splash navigation...) run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => MockClient(_server));
  } finally {
    semantics.dispose();
    FlutterError.onError = previous;
  }
}

void main() {
  group('colors on red', () {
    test('white text on both ends of the red gradient is readable', () {
      for (final bg in AppColors.primaryGradient) {
        expect(contrastRatio(AppColors.onPrimary, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('secondary text on red stays legible as large text and icons', () {
      for (final bg in AppColors.primaryGradient) {
        expect(
          contrastRatio(AppColors.onPrimaryMuted, bg),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrastRatio(AppColors.onPrimarySoft, bg),
          greaterThanOrEqualTo(3),
        );
      }
    });

    test('red-on-red is caught', () {
      // The bug this guards against: a tint of the brand red used as text on
      // the brand red.
      expect(
        contrastRatio(AppColors.primaryBorder, AppColors.primary),
        lessThan(1.5),
      );
    });

    test('text on pale surfaces', () {
      for (final bg in [Colors.white, AppColors.mutedBg, AppColors.accentBg]) {
        expect(contrastRatio(AppColors.foreground, bg), greaterThanOrEqualTo(7));
        expect(contrastRatio(AppColors.muted, bg), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(AppColors.primary, bg), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('text contrast guideline', () {
    testWidgets('splash', (tester) async {
      await _meetsContrast(tester, const SplashScreen(isLoggedIn: false));
    });

    testWidgets('login', (tester) async {
      await _meetsContrast(tester, const LoginScreen());
    });

    testWidgets('register step 1', (tester) async {
      await _meetsContrast(tester, const RegisterScreen());
    });

    testWidgets('register step 2', (tester) async {
      await _meetsContrast(
        tester,
        const RegisterStep2(
          fullName: 'Rey Ashlee',
          firstName: 'Rey',
          middleInitial: '',
          lastName: 'Ashlee',
          suffix: '',
          email: 'rey@example.com',
          phone: '09171234567',
          birthdate: '2000-01-01',
          gender: 'Male',
        ),
      );
    });

    testWidgets('register step 3', (tester) async {
      await _meetsContrast(
        tester,
        const RegisterStep3(
          fullName: 'Rey Ashlee',
          firstName: 'Rey',
          middleInitial: '',
          lastName: 'Ashlee',
          suffix: '',
          email: 'rey@example.com',
          phone: '09171234567',
          birthdate: '2000-01-01',
          gender: 'Male',
          bloodType: 'O+',
          streetAddress: '1 Main St',
          province: 'Province',
          provinceCode: '1',
          municipality: 'City',
          cityCode: '1',
          barangay: 'Barangay',
          barangayCode: '1',
        ),
      );
    });

    testWidgets('privacy consent', (tester) async {
      await _meetsContrast(
        tester,
        PrivacyConsentScreen(nextBuilder: (_) => const SizedBox()),
        prefs: {kPrivacyConsentVersionKey: ''},
      );
    });

    testWidgets('PIN screen (unlock)', (tester) async {
      await _meetsContrast(tester, const PinScreen());
    });
  });
}
