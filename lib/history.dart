import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'config.dart';
import 'edit_profile.dart';
import 'help_support.dart';
import 'login.dart';
import 'notification_settings.dart';
import 'privacy_security.dart';
import 'shared_design.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Map<String, dynamic>? profile;
  String? notice;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool progress = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('donorId');
    if (id == null || id.isEmpty) {
      if (mounted)
        setState(() {
          loading = false;
          notice = 'Unable to load your profile. Please sign in again.';
        });
      return;
    }
    Map<String, dynamic>? cached;
    final saved = prefs.getString('cached_profile_' + id);
    if (saved != null) {
      try {
        cached = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      if (cached != null) profile = cached;
      loading = progress && cached == null;
      notice = null;
    });
    try {
      final response = await http
          .get(Uri.parse(AppConfig.baseUrl + '/get_profile.php?donor_id=' + id))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          body is Map &&
          body['status'] == 'success' &&
          body['data'] is Map) {
        final data = Map<String, dynamic>.from(body['data'] as Map);
        await prefs.setString('cached_profile_' + id, jsonEncode(data));
        if (mounted)
          setState(() {
            profile = data;
            loading = false;
            notice = null;
          });
        return;
      }
    } catch (_) {}
    if (mounted)
      setState(() {
        loading = false;
        notice = cached == null
            ? 'Unable to load your profile. Check your internet connection and try again.'
            : "You're offline — showing saved profile information.";
      });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('donorId');
    if (id != null && id.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(AppConfig.baseUrl + '/delete_fcm_token.php'),
              body: {'donor_id': id},
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Error removing FCM token on logout: ' + e.toString());
      }
    }
    await prefs.clear();
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
  }

  String safe(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? 'N/A' : v.toString().trim();
  String initials(String name) => name == 'N/A'
      ? 'U'
      : name
            .split(' ')
            .where((x) => x.isNotEmpty)
            .take(2)
            .map((x) => x[0])
            .join()
            .toUpperCase();
  String date(dynamic v, {bool monthOnly = false}) {
    try {
      final d = DateTime.parse(safe(v));
      const months = [
        '',
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
      return monthOnly
          ? months[d.month] + ' ' + d.year.toString()
          : months[d.month] + ' ' + d.day.toString() + ', ' + d.year.toString();
    } catch (_) {
      return 'N/A';
    }
  }

  String days(dynamic v) {
    try {
      final n = DateTime.now().difference(DateTime.parse(safe(v))).inDays;
      return n == 0
          ? 'Today'
          : n == 1
          ? '1 day'
          : n.toString() + ' days';
    } catch (_) {
      return 'N/A';
    }
  }

  String address() {
    final result = [
      profile?['street'],
      profile?['barangay'],
      profile?['city'],
      profile?['state'],
    ].map(safe).where((x) => x != 'N/A').join(', ');
    return result.isEmpty ? 'N/A' : result;
  }

  @override
  Widget build(BuildContext context) {
    final name = safe(profile?['full_name']);
    final total =
        int.tryParse((profile?['total_donations'] ?? 0).toString()) ?? 0;
    final active = days(profile?['date_registered']);
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: SafeArea(
              top: false,
              child: RefreshIndicator(
                color: kCrimson,
                onRefresh: () => _load(progress: false),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    children: [
                      if (notice != null) ...[
                        _notice(notice!),
                        const SizedBox(height: 16),
                      ],
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(color: kCrimson),
                        ),
                      FadeSlideIn(index: 0, child: _profileCard(name)),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        index: 1,
                        child: Row(
                          children: [
                            Expanded(
                              child: _stat(
                                Icons.water_drop,
                                total.toString(),
                                'Donations',
                                kCrimson,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                Icons.calendar_today,
                                active,
                                'Days Active',
                                const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                Icons.emoji_events,
                                (total * 3).toString(),
                                'Lives Helped',
                                const Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        index: 2,
                        child: _card('Personal Information', [
                          _info(
                            Icons.phone,
                            'Phone Number',
                            safe(profile?['phone']),
                          ),
                          _info(Icons.location_on, 'Address', address()),
                          _info(
                            Icons.cake,
                            'Date of Birth',
                            date(profile?['birthdate']),
                          ),
                          _info(
                            Icons.calendar_today,
                            'Member Since',
                            date(profile?['date_registered'], monthOnly: true),
                          ),
                          _info(Icons.timer, 'Days Active', active),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        index: 3,
                        child: _card('Donation Status', [
                          _info(
                            Icons.water_drop,
                            'Last Donation',
                            date(profile?['last_donation']),
                          ),
                          _info(
                            Icons.event_available,
                            'Next Eligible',
                            _next(),
                            color: Colors.green,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        index: 4,
                        child: _card(null, [
                          _menu(Icons.edit, 'Edit Profile', () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                            if (changed == true) _load(progress: false);
                          }),
                          _menu(
                            Icons.notifications,
                            'Notification Settings',
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const NotificationSettingsScreen(),
                              ),
                            ),
                          ),
                          _menu(
                            Icons.shield,
                            'Privacy & Security',
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacySecurityScreen(),
                              ),
                            ),
                          ),
                          _menu(
                            Icons.help_outline,
                            'Help & Support',
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HelpSupportScreen(),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: kCrimson),
                          label: const Text(
                            'Logout',
                            style: TextStyle(
                              color: kCrimson,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _next() {
    try {
      final d = DateTime.parse(safe(profile?['last_donation']));
      return date(DateTime(d.year, d.month + 3, d.day));
    } catch (_) {
      return 'N/A';
    }
  }

  Widget _header(BuildContext c) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.of(c).size.height * .06,
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
          onTap: () => Navigator.pop(c),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manage your account & donations',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  BoxDecoration _box({Gradient? gradient, Color? border}) => BoxDecoration(
    color: gradient == null ? Colors.white : null,
    gradient: gradient,
    borderRadius: BorderRadius.circular(16),
    border: border == null ? null : Border.all(color: border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(.05),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  );
  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      border: Border.all(color: const Color(0xFFFDE68A)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: Color(0xFFD97706)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
          ),
        ),
        TextButton(
          onPressed: () => _load(progress: false),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
  Widget _profileCard(String name) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: _box(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFF1F1), Color(0xFFFFE4E4)],
      ),
      border: const Color(0xFFFECACA),
    ),
    child: Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: kCrimson,
          child: Text(
            initials(name),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          safe(profile?['email']),
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: kCrimson,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            safe(profile?['blood_type']) + ' Blood Type',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _stat(IconData icon, String value, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: _box(),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
  Widget _card(String? title, List<Widget> content) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: _box(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
        ],
        ...content,
      ],
    ),
  );
  Widget _info(IconData icon, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: color ?? const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget _menu(IconData icon, String label, VoidCallback action) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: action,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
        ],
      ),
    ),
  );
}
