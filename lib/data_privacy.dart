import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_statement.dart';
import 'profile_page_widgets.dart';
import 'shared_design.dart';
import 'streak/streak_screen.dart';

class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  String? _acceptedOn;

  @override
  void initState() {
    super.initState();
    _loadAcceptedDate();
  }

  // Only shown for the version being displayed — an older acceptance would
  // make "this version" untrue.
  Future<void> _loadAcceptedDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(kPrivacyConsentVersionKey) != kPrivacyPolicyVersion) {
        return;
      }
      final at = DateTime.tryParse(prefs.getString(kPrivacyConsentAtKey) ?? '');
      if (at == null || !mounted) return;
      setState(() => _acceptedOn = _formatDate(at.toLocal()));
    } catch (_) {}
  }

  String _formatDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'privacy_security', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) => ProfilePage(
    title: 'Data Privacy',
    subtitle: 'How eDonate handles your information',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PrivacyStatementView(sectionFill: Colors.white),
        if (_acceptedOn != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You accepted this version on $_acceptedOn',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: kTextPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
