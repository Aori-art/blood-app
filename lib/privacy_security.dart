import 'package:flutter/material.dart';

import 'change_password.dart';
import 'data_privacy.dart';
import 'pin_screen.dart';
import 'profile_page_widgets.dart';

class PrivacySecurityScreen extends StatefulWidget {
  final bool showChangePin;

  const PrivacySecurityScreen({super.key, this.showChangePin = false});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  // PIN: opens the PIN screen in "change" mode (current → new → confirm).
  Future<void> _changePin() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinScreen(purpose: PinPurpose.change),
      ),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Your PIN was updated.')),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Privacy & Security',
    subtitle: 'Manage your account security and privacy',
    child: ProfileCard(
      child: Column(
        children: [
          SettingsRow(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your account password.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          // PIN: only verified donors have (or can create) a PIN.
          if (widget.showChangePin) ...[
            const Divider(),
            SettingsRow(
              icon: Icons.password_rounded,
              title: 'Change PIN',
              subtitle: 'Update the 4-digit PIN you use to open eDonate.',
              onTap: _changePin,
            ),
          ],
          const Divider(),
          SettingsRow(
            icon: Icons.privacy_tip_outlined,
            title: 'Data Privacy',
            subtitle: 'Learn how eDonate handles your information.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataPrivacyScreen()),
            ),
          ),
        ],
      ),
    ),
  );
}
