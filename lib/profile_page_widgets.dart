import 'package:flutter/material.dart';

import 'anim.dart';
import 'shared_design.dart';

class ProfilePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const ProfilePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).size.height * .06,
            20,
            20,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: kHeaderGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: FadeSlideIn(index: 0, child: child),
            ),
          ),
        ),
      ],
    ),
  );
}

class ProfileCard extends StatelessWidget {
  final Widget child;
  const ProfileCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6B7280), size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kTextPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTextMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              (onTap == null
                  ? const SizedBox()
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    )),
        ],
      ),
    ),
  );
}

Widget profileInfoCard(String text, {IconData icon = Icons.info_outline}) =>
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kCrimson),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
