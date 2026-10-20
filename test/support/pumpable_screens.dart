// Screens that can be pumped without a real network, with a mock server.
// Shared by the theme tests.
import 'dart:convert';

import 'package:blood/alerts.dart';
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
import 'package:blood/streak/streak_ladder_screen.dart';
import 'package:blood/verify.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

http.Response okJson(Map<String, dynamic> m) =>
    http.Response(jsonEncode(m), 200);

Future<http.Response> pumpableServer(http.Request r) async {
  switch (r.url.path.split('/').last) {
    case 'get_posts.php':
      return okJson({
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
      return okJson({
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
      return okJson({'status': 'success', 'verification_status': 'verified'});
    case 'pin_api.php':
      return okJson({
        'status': 'success',
        'has_pin': true,
        'is_verified': true,
        'first_name': 'Rey',
        'lock_seconds': 0,
      });
    case 'get_eligibility_status.php':
      return okJson({'status': 'eligible'});
    case 'get_screening_questions.php':
      return okJson({
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
      return okJson({
        'status': 'success',
        'materials': {
          'url': 'https://example.org',
          'title': 'Blood Donation Guide',
          'required': true,
          'viewed': false,
        },
      });
    case 'get_facilities.php':
      return okJson({
        'status': 'success',
        'facilities': [
          {'facility_id': 1, 'facility_name': 'City Blood Center'},
        ],
      });
    case 'get_facility_time_slots.php':
      return okJson({
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
      return okJson({
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

class PumpableScreen {
  final String name;
  final Widget Function() build;
  final Map<String, Object> prefs;

  /// Set when the shipped LIGHT look already misses the guideline here. Light
  /// mode must stay exactly as it is, so the light run is skipped (the dark
  /// run is still asserted) and the gap is reported instead.
  final String? lightGap;

  const PumpableScreen(
    this.name,
    this.build, {
    this.prefs = const {},
    this.lightGap,
  });
}

final List<PumpableScreen> pumpableScreens = [
  PumpableScreen('splash', () => const SplashScreen(isLoggedIn: false)),
  PumpableScreen('login', () => const LoginScreen()),
  PumpableScreen('forgot password', () => const ForgotPasswordScreen()),
  PumpableScreen('register 1', () => const RegisterScreen()),
  PumpableScreen(
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
  PumpableScreen(
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
  PumpableScreen('otp', () => const OtpScreen(email: 'rey@example.com')),
  PumpableScreen('PIN', () => const PinScreen()),
  PumpableScreen(
    'privacy consent',
    () => PrivacyConsentScreen(nextBuilder: (_) => const SizedBox()),
    prefs: {kPrivacyConsentVersionKey: ''},
  ),
  PumpableScreen('help & support', () => const HelpSupportScreen()),
  PumpableScreen(
    'notification settings',
    () => const NotificationSettingsScreen(),
  ),
  PumpableScreen('privacy & security', () => const PrivacySecurityScreen()),
  PumpableScreen('data privacy', () => const DataPrivacyScreen()),
  PumpableScreen('change password', () => const ChangePasswordScreen()),
  PumpableScreen('edit profile', () => const EditProfileScreen()),
  PumpableScreen('verify', () => const VerifyScreen()),
  PumpableScreen(
    'profile',
    () => const HistoryScreen(),
    lightGap:
        'the green "Verified" chip is 3.0:1 (success on its soft green fill)',
  ),
  PumpableScreen('alerts', () => const AlertsScreen(donorId: 7)),
  PumpableScreen('eligibility check', () => const CheckScreen()),
  PumpableScreen('book', () => const BookScreen()),
  PumpableScreen('newsfeed', () => const NewsfeedPage()),
  PumpableScreen('donation history', () => DonationHistoryScreen()),
  PumpableScreen('digital ID', () => const DigitalIdScreen()),
  PumpableScreen('blood requests', () => const BloodRequestsScreen()),
  PumpableScreen('streak ladder', () => const StreakLadderScreen()),
];
