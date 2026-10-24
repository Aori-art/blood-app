import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_controller.dart' show kThemeModeKey;
import 'app_palette.dart';

// Bump this whenever the statement below changes in a way users must
// re-consent to — the splash gate compares it with the stored value.
const kPrivacyPolicyVersion = '2026-10-12-v2';

const kPrivacyConsentVersionKey = 'privacy_consent_version';
const kPrivacyConsentAtKey = 'privacy_consent_at';
const kPrivacyInstallIdKey = 'privacy_install_id';
const kPrivacyReceiptPendingKey = 'privacy_receipt_pending';

const List<String> _kConsentKeys = [
  kPrivacyConsentVersionKey,
  kPrivacyConsentAtKey,
  kPrivacyInstallIdKey,
  kPrivacyReceiptPendingKey,
  // The chosen light/dark mode is a device preference: it outlives logout.
  kThemeModeKey,
];

// Keys of this prefix hold which streak frames a donor has already seen
// celebrated (just frame keys), so a re-login doesn't replay them. Account
// deletion removes them afterwards (StreakController.reset(forgetSeen: true)).
const String _kSeenFramesPrefix = 'streak_seen_frames_';

// Replaces prefs.clear() everywhere a session ends (logout, account
// deletion) so the user isn't asked to re-consent on every sign-in.
Future<void> clearSessionKeepConsent(SharedPreferences prefs) async {
  final kept = <String, Object>{};
  for (final key in prefs.getKeys()) {
    if (!_kConsentKeys.contains(key) && !key.startsWith(_kSeenFramesPrefix)) {
      continue;
    }
    final value = prefs.get(key);
    if (value != null) kept[key] = value;
  }
  await prefs.clear();
  for (final entry in kept.entries) {
    final value = entry.value;
    if (value is String) {
      await prefs.setString(entry.key, value);
    } else if (value is bool) {
      await prefs.setBool(entry.key, value);
    } else if (value is List) {
      await prefs.setStringList(entry.key, value.cast<String>());
    }
  }
}

class _PrivacySection {
  final IconData icon;
  final String heading;
  final List<String> bullets;
  const _PrivacySection(this.icon, this.heading, this.bullets);
}

const String _kIntro =
    'Dugtong respects your privacy. This statement explains what personal '
    'information we collect, why we collect it, and how we protect it, in '
    'line with the Data Privacy Act of 2012 (Republic Act No. 10173).';

const List<_PrivacySection> _kSections = [
  _PrivacySection(Icons.list_alt_rounded, '1. What we collect', [
    'Your name, sex, date of birth, contact number, email address and home '
        'address.',
    'Your blood type and your answers to the eligibility screening '
        'questions (health-related information).',
    'Photos of the valid ID you upload for identity verification.',
    'Your appointments and donation records.',
    'A push-notification token from your phone, so we can send you alerts.',
  ]),
  _PrivacySection(Icons.volunteer_activism_outlined, '2. Why we collect it', [
    'To create and secure your account and verify your identity.',
    'To check whether you are eligible to donate and to schedule your '
        'appointments.',
    'To record your donations and keep your donation history.',
    'To send you verification codes, reminders and updates.',
  ]),
  _PrivacySection(Icons.visibility_outlined, '3. Who can see it', [
    'Only authorized Dugtong administrators and donation center staff, and '
        'only as needed for the purposes above.',
    'We do not sell or rent your information, and the app has no '
        'advertising or analytics trackers.',
    'Firebase (push notifications) and Gmail (email delivery) are used to '
        'deliver messages to you.',
    'If you comment on a post, your first name, last initial, profile photo '
        'and frame are visible to other users. You can hide your profile '
        'photo in comments at any time from the comment box or in Privacy & '
        'Security.',
  ]),
  _PrivacySection(Icons.lock_outline_rounded, '4. How we protect it', [
    'Your password is stored in encrypted (hashed) form and is never kept '
        'in plain text.',
    'Your email is verified with a one-time code.',
    'Your ID photos are used only for identity verification and are not '
        'shown publicly.',
    'No system is completely secure, so please keep your password private.',
  ]),
  _PrivacySection(Icons.tune_rounded, '5. Your choices', [
    'You can view and update your profile information in the app.',
    'You can turn push notifications on or off.',
    'You can delete your account and personal data at any time in Profile '
        '> Privacy & Security > Delete Account.',
  ]),
  _PrivacySection(
    Icons.delete_outline_rounded,
    '6. Keeping and deleting data',
    [
      'We keep your information while your account is active.',
      'When you delete your account, your personal information, ID photos, '
          'screening answers, appointments and notifications are permanently '
          'removed.',
      'Donation records may be kept without any information that identifies '
          'you, for blood-supply and safety records.',
    ],
  ),
];

// The full privacy statement, shared by the first-launch consent screen and
// the read-only copy under Profile > Privacy & Security. It never scrolls on
// its own — the host screen provides the scroll view.
class PrivacyStatementView extends StatelessWidget {
  // Fill of each section card, so the sections read against whichever
  // surface the host places them on. Null = the palette's alternate surface.
  final Color? sectionFill;

  const PrivacyStatementView({super.key, this.sectionFill});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _kIntro,
        style: TextStyle(
          fontSize: 13,
          color: context.palette.muted,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      for (final section in _kSections) ...[
        _sectionCard(context, section),
        const SizedBox(height: 12),
      ],
      Center(
        child: Text(
          'Policy version: $kPrivacyPolicyVersion',
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
      ),
    ],
  );

  Widget _sectionCard(BuildContext context, _PrivacySection section) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sectionFill ?? context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.palette.accentBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    section.icon,
                    size: 17,
                    color: context.palette.primaryText,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.heading,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.palette.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 7, right: 8),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: context.palette.primaryText,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        bullet,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
