import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_page_widgets.dart';
import 'shared_design.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _contactSupport(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    final donorId = prefs.getString('donorId')?.trim();
    final formattedDonorId = _formatDonorId(donorId);
    final messageBody =
        '''Hello eDonate Support,

I need help regarding:

[Please describe your concern here]

Donor ID: $formattedDonorId

Thank you.''';
    final uri = Uri(
      scheme: 'mailto',
      path: 'oedonate@gmail.com',
      queryParameters: {
        'subject': 'eDonate Support Request',
        'body': messageBody,
      },
    );

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) _showEmailFallback(context);
    } catch (_) {
      if (context.mounted) _showEmailFallback(context);
    }
  }

  String _formatDonorId(String? donorId) {
    if (donorId == null || donorId.isEmpty) return 'Not available';
    final numericId = int.tryParse(donorId);
    return numericId == null
        ? donorId
        : 'D${numericId.toString().padLeft(4, '0')}';
  }

  Future<void> _showEmailFallback(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Unable to Open Email App'),
      content: const Text(
        "We couldn't open an email application on this device. You can "
        'contact eDonate directly at:\n\noedonate@gmail.com',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: 'oedonate@gmail.com'),
            );
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Support email copied to clipboard.'),
              ),
            );
          },
          child: const Text('COPY EMAIL'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Help & Support',
    subtitle: "We're here to help",
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('QUICK HELP'),
        ProfileCard(
          child: Column(
            children: [
              _faq(
                "Why can't I book an appointment?",
                'Your eligibility status may need to be eligible, and an existing appointment can affect booking.',
              ),
              _faq(
                "Why didn't I receive a push notification?",
                'Check Notification Settings in eDonate, check phone notification permission, ensure internet is available, and reopen the application if necessary.',
              ),
              _faq('How often can I edit my profile?', 'Once every 7 days.'),
              _faq(
                'How do I change my password?',
                'Profile → Privacy & Security → Change Password.',
              ),
              _faq(
                'My eligibility status looks incorrect. What should I do?',
                'Review your screening information and contact eDonate support if assistance is required.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Label('CONTACT SUPPORT'),
        ProfileCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.support_agent_rounded, color: kCrimson),
                  SizedBox(width: 10),
                  Text(
                    'Contact Support',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Need assistance? Send our support team an email.',
                style: TextStyle(fontSize: 12, color: kTextMuted),
              ),
              const SizedBox(height: 3),
              const Text(
                'oedonate@gmail.com',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _contactSupport(context),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Contact Support'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCrimson,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        profileInfoCard(
          'For your security, never send passwords through email.',
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 16),
        ProfileCard(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'App Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('eDonate Donor App', style: TextStyle(color: kTextMuted)),
              Text('oedonate@gmail.com', style: TextStyle(color: kTextMuted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _faq(String question, String answer) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    title: Text(
      question,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          answer,
          style: const TextStyle(fontSize: 13, color: kTextMuted, height: 1.4),
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: .8,
        color: kTextMuted,
      ),
    ),
  );
}
