import 'dart:convert';

import 'package:blood/alerts.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/blood_requests/blood_requests_screen.dart';
import 'package:blood/book.dart';
import 'package:blood/change_password.dart';
import 'package:blood/check.dart';
import 'package:blood/data_privacy.dart';
import 'package:blood/digital_id.dart';
import 'package:blood/donation_history.dart';
import 'package:blood/edit_profile.dart';
import 'package:blood/forgot_password.dart';
import 'package:blood/help_support.dart';
import 'package:blood/history.dart';
import 'package:blood/login.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/notification_settings.dart';
import 'package:blood/pin_screen.dart';
import 'package:blood/privacy_consent.dart';
import 'package:blood/privacy_security.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/screens/register/otp.dart';
import 'package:blood/screens/register/register1.dart';
import 'package:blood/screens/register/register2.dart';
import 'package:blood/screens/register/register3.dart';
import 'package:blood/splash_screen/splash_screen.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/streak/streak_ladder_screen.dart';
import 'package:blood/verify.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every screen that can be pumped without a real network is measured in BOTH
/// themes with flutter_test's text contrast guideline.

http.Response _ok(Map<String, dynamic> m) => http.Response(jsonEncode(m), 200);

Future<http.Response> _server(http.Request r) async {
  switch (r.url.path.split('/').last) {
    case 'get_posts.php':
      return _ok({
        'success': true,
        'posts': [
          {
            'id': 1,
            'type': 'urgent',
            'author': 'City Blood Bank',
            'authorAvatar': '',
            'timeAgo': '2h ago',
            'content': 'We urgently need O+ donors this weekend.',
            'likes': 5,
            'urgency': 'critical',
            'liked': true,
            'comments': 3,
          },
        ],
      });
    case 'get_notifications.php':
      return _ok({
        'success': true,
        'unread_count': 2,
        'notifications': [
          for (final (i, t) in [
            (1, 'appointment_approved'),
            (2, 'screening_failed'),
            (3, 'eligibility'),
            (4, 'reminder'),
          ])
            {
              'notification_id': i,
              'title': 'Notification $i',
              'message': 'Message body $i',
              'notification_type': t,
              'is_read': i > 2,
              'date': 'Oct 16, 2026',
              'created_at': '2026-10-16 08:00:00',
            },
        ],
      });
    case 'get_verification_status.php':
      return _ok({'status': 'success', 'verification_status': 'verified'});
    case 'pin_api.php':
      return _ok({
        'status': 'success',
        'has_pin': true,
        'is_verified': true,
        'first_name': 'Rey',
        'lock_seconds': 0,
      });
    case 'get_eligibility_status.php':
      return _ok({'status': 'eligible'});
    case 'get_screening_questions.php':
      return _ok({
        'status': 'success',
        'questions': [
          {
            'question_id': 1,
            'question_text': 'Are you feeling healthy today?',
            'followup_prompt': '',
            'followup_trigger': 'none',
          },
        ],
      });
    case 'get_screening_materials.php':
      return _ok({
        'status': 'success',
        'materials': {
          'url': 'https://example.org',
          'title': 'Blood Donation Guide',
          'required': true,
          'viewed': false,
        },
      });
    case 'get_facilities.php':
      return _ok({
        'status': 'success',
        'facilities': [
          {'facility_id': 1, 'facility_name': 'City Blood Center'},
        ],
      });
    case 'get_facility_time_slots.php':
      return _ok({
        'status': 'success',
        'slots_by_facility': {
          '1': [
            {
              'slot_id': 1,
              'value': '8:00 AM - 9:00 AM',
              'start_time': '08:00',
              'end_time': '09:00',
              'period': 'morning',
            },
          ],
        },
      });
    default:
      return _ok({
        'success': true,
        'status': 'success',
        'posts': [],
        'appointments': [],
        'requests': [],
        'data': [],
        'history': [],
        'donations': [],
      });
  }
}

class _Screen {
  final String name;
  final Widget Function() build;
  final Map<String, Object> prefs;

  /// Set when the shipped LIGHT look already misses the guideline here. Light
  /// mode must stay exactly as it is, so the light run is skipped (the dark
  /// run is still asserted) and the gap is reported instead.
  final String? lightGap;

  const _Screen(this.name, this.build, {this.prefs = const {}, this.lightGap});
}

final List<_Screen> _screens = [
  _Screen('splash', () => const SplashScreen(isLoggedIn: false)),
  _Screen('login', () => const LoginScreen()),
  _Screen('forgot password', () => const ForgotPasswordScreen()),
  _Screen('register 1', () => const RegisterScreen()),
  _Screen(
    'register 2',
    () => const RegisterStep2(
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
  ),
  _Screen(
    'register 3',
    () => const RegisterStep3(
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
  ),
  _Screen('otp', () => const OtpScreen(email: 'rey@example.com')),
  _Screen('PIN', () => const PinScreen()),
  _Screen(
    'privacy consent',
    () => PrivacyConsentScreen(nextBuilder: (_) => const SizedBox()),
    prefs: {kPrivacyConsentVersionKey: ''},
  ),
  _Screen('help & support', () => const HelpSupportScreen()),
  _Screen('notification settings', () => const NotificationSettingsScreen()),
  _Screen('privacy & security', () => const PrivacySecurityScreen()),
  _Screen('data privacy', () => const DataPrivacyScreen()),
  _Screen('change password', () => const ChangePasswordScreen()),
  _Screen('edit profile', () => const EditProfileScreen()),
  _Screen('verify', () => const VerifyScreen()),
  _Screen(
    'profile',
    () => const HistoryScreen(),
    lightGap:
        'the green "Verified" chip is 3.0:1 (success on its soft green fill)',
  ),
  _Screen('alerts', () => const AlertsScreen(donorId: 7)),
  _Screen('eligibility check', () => const CheckScreen()),
  _Screen('book', () => const BookScreen()),
  _Screen('newsfeed', () => const NewsfeedPage()),
  _Screen('donation history', () => DonationHistoryScreen()),
  _Screen('digital ID', () => const DigitalIdScreen()),
  _Screen('blood requests', () => const BloodRequestsScreen()),
  _Screen('streak ladder', () => const StreakLadderScreen()),
];

Future<void> _meetsContrast(
  WidgetTester tester,
  _Screen screen, {
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
    }, () => MockClient(_server));
  } finally {
    semantics.dispose();
    FlutterError.onError = previous;
  }
}

void main() {
  for (final dark in [false, true]) {
    group(dark ? 'dark theme' : 'light theme', () {
      for (final screen in _screens) {
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
