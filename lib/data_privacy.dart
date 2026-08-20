import 'package:flutter/material.dart';

import 'profile_page_widgets.dart';

class DataPrivacyScreen extends StatelessWidget {
  const DataPrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Data Privacy',
    subtitle: 'How eDonate handles your information',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          'Information We Collect',
          'eDonate may process identity and account details, contact information, blood type, eligibility and screening responses, appointment information, donation records, and device notification registration information.',
        ),
        _section(
          'Why We Use Your Information',
          'Your information supports donor accounts, eligibility pre-screening, appointment scheduling, donation records, notifications, donor support, and operation and improvement of the blood donation service.',
        ),
        _section(
          'Sensitive Information',
          'Blood type, health screening responses, and donation information require additional care because they may be sensitive personal information.',
        ),
        _section(
          'How Information Is Protected',
          'The system is designed to use reasonable administrative and technical safeguards, including authenticated account access, hashed passwords, HTTPS for production communication, restricted server credentials, and access limited according to system roles.',
        ),
        _section(
          'Sharing',
          '''Information should only be shared when necessary for authorized blood-donation operations, system administration, legal obligations, or with your consent where required.

eDonate does not sell donor personal information.''',
        ),
        _section(
          'Retention',
          'Records may be retained as necessary for donor services, operational records, safety, and applicable institutional or legal requirements.',
        ),
        _section(
          'Your Rights',
          'You may request appropriate access, correction, or assistance regarding your personal information.',
        ),
        _section(
          'Philippine Data Privacy',
          'eDonate is designed to follow applicable Philippine data protection principles, including the Data Privacy Act of 2012 (Republic Act No. 10173), in the handling of personal and sensitive personal information.',
        ),
        _section(
          'Contact',
          'For privacy questions, contact edonate73@gmail.com.',
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Last updated: August 2026',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    ),
  );

  Widget _section(String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4B5563),
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
