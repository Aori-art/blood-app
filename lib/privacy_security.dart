import 'package:flutter/material.dart';

import 'change_password.dart';
import 'data_privacy.dart';
import 'profile_page_widgets.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});
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
