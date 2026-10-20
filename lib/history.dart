import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'streak/streak_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'config.dart';
import 'edit_profile.dart';
import 'help_support.dart';
import 'login.dart';
import 'notification_settings.dart';
import 'pin_screen.dart'; // PIN: logout reset
import 'privacy_security.dart';
import 'privacy_statement.dart';
import 'shared_design.dart';
import 'streak/avatar_frame.dart';
import 'streak/frame_picker.dart';
import 'streak/streak_controller.dart';
import 'unread_notifications.dart';
import 'donor_avatar.dart';
import 'streak/streak_ladder_screen.dart';
import 'theme_controller.dart';
import 'theme_transition.dart';
import 'verify.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Map<String, dynamic>? profile;
  String? notice;
  bool loading = true;
  String?
  verificationStatus; // 'unverified' | 'pending' | 'verified' | 'rejected'

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
    await Future.wait([
      _fetchProfileFromServer(prefs, id, cached),
      _fetchVerificationStatus(id),
    ]);
  }

  Future<void> _fetchProfileFromServer(
    SharedPreferences prefs,
    String id,
    Map<String, dynamic>? cached,
  ) async {
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

  // Leaves verificationStatus untouched on failure (null on first load,
  // or whatever it was last known to be) — this screen should never claim
  // a status it doesn't actually know.
  Future<void> _fetchVerificationStatus(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_verification_status.php?donor_id=$id',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['status'] == 'success') {
          setState(
            () => verificationStatus = body['verification_status']?.toString(),
          );
        }
      }
    } catch (_) {}
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
    await clearSessionKeepConsent(prefs);
    StreakController.instance.onLoggedOut();
    UnreadNotifications.instance
      ..stop()
      ..clear();
    MyAvatar.instance.clear();
    AppSession.homeInStack = false; // PIN: next Home visit asks for the PIN
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
  Widget build(BuildContext context) =>
      StreakScreen(id: 'profile', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final name = safe(profile?['full_name']);
    final total =
        int.tryParse((profile?['total_donations'] ?? 0).toString()) ?? 0;
    final active = days(profile?['date_registered']);
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: SafeArea(
              top: false,
              child: RefreshIndicator(
                color: context.palette.primaryText,
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
                        Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(color: context.palette.primaryText),
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
                                context.palette.primaryText,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                Icons.calendar_today,
                                active,
                                'Days Active',
                                context.palette.info,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                Icons.emoji_events,
                                (total * 3).toString(),
                                'Lives Helped',
                                context.palette.warning,
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
                            color: context.palette.success,
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
                            Icons.local_fire_department_rounded,
                            'Daily Streak',
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StreakLadderScreen(),
                              ),
                            ),
                          ),
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
                                builder: (_) => PrivacySecurityScreen(
                                  showChangePin:
                                      verificationStatus == 'verified',
                                ),
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
                          _darkModeRow(),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          icon: Icon(Icons.logout, color: context.palette.primaryText),
                          label: Text(
                            'Logout',
                            style: TextStyle(
                              color: context.palette.primaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(color: context.palette.primaryBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
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

  Widget _header(BuildContext c) => EdonateHeader(
    title: 'My Profile',
    subtitle: 'Manage your account & donations',
    leading: HeaderIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back',
      onTap: () => Navigator.pop(c),
    ),
  );
  BoxDecoration _box({Gradient? gradient, Color? border}) => BoxDecoration(
    color: gradient == null ? context.palette.surface : null,
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
      color: context.palette.warningBg,
      border: Border.all(color: context.palette.warningBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_outlined, color: context.palette.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: context.palette.warningText),
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
      gradient: LinearGradient(
        colors: [context.palette.accentBg, context.palette.accentBg],
      ),
      border: context.palette.primaryBorder,
    ),
    child: Column(
      children: [
        ListenableBuilder(
          listenable: StreakController.instance,
          builder: (context, _) => StreakAvatarFrame(
            frameKey: StreakController.instance.equippedFrame,
            radius: 44,
            child: CircleAvatar(
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
          ),
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) => GestureDetector(
            onTap: () =>
                showFrameCatalogSheet(context, initials: initials(name)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: context.palette.accentBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.palette.primaryBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: context.palette.primaryText),
                  SizedBox(width: 5),
                  Text(
                    'Edit Frame',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.palette.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          safe(profile?['email']),
          style: TextStyle(fontSize: 13, color: context.palette.muted),
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
        const SizedBox(height: 8),
        _verificationBadge(),
      ],
    ),
  );

  Widget _verificationBadge() {
    late Color fg;
    late Color bg;
    late String label;
    late IconData icon;

    switch (verificationStatus) {
      case 'verified':
        fg = context.palette.success;
        bg = context.palette.successSoft;
        label = 'Verified';
        icon = Icons.verified_user_rounded;
        break;
      case 'pending':
        fg = context.palette.warning;
        bg = context.palette.warningBg;
        label = 'Verification Pending';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'rejected':
        fg = context.palette.primaryText;
        bg = context.palette.accentBg;
        label = 'Verification Rejected';
        icon = Icons.gpp_bad_outlined;
        break;
      case 'unverified':
        fg = context.palette.primaryText;
        bg = context.palette.accentBg;
        label = 'Not Verified';
        icon = Icons.shield_outlined;
        break;
      default:
        fg = context.palette.muted;
        bg = context.palette.surfaceAlt;
        label = 'Checking...';
        icon = Icons.hourglass_empty_rounded;
    }

    final isVerified = verificationStatus == 'verified';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: isVerified
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerifyScreen()),
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              style: TextStyle(fontSize: 10, color: context.palette.muted),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.foreground,
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
            Icon(icon, size: 18, color: context.palette.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: color ?? context.palette.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  /// The Dark mode switch. It lives next to the other settings rows; toggling
  /// it changes the whole app at once (the theme fades between the modes).
  final GlobalKey _darkSwitchKey = GlobalKey();

  Widget _darkModeRow() => ListenableBuilder(
    listenable: ThemeController.instance,
    builder: (context, _) {
      final dark = ThemeController.instance.isDark;
      final p = context.palette;
      // The new theme grows out of the switch as a circle (theme_transition).
      void toggle(bool value) {
        if (value == dark) return;
        ThemeTransition.toggle(context, originKey: _darkSwitchKey);
      }

      return Semantics(
        container: true,
        label: 'Dark mode',
        toggled: dark,
        onTap: () => toggle(!dark),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => toggle(!dark),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.accentBg,
                  ),
                  // Sun and moon morph into each other: a half turn plus a pop.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => RotationTransition(
                      turns: Tween<double>(begin: 0.5, end: 1).animate(animation),
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      dark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      key: ValueKey(dark),
                      size: 18,
                      color: p.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dark mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: p.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Easier on the eyes in low light',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: _darkSwitchKey,
                  value: dark,
                  onChanged: toggle,
                  thumbColor: WidgetStateProperty.all(Colors.white),
                  thumbIcon: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Icon(
                            Icons.dark_mode_rounded,
                            size: 14,
                            color: AppColors.primary,
                          )
                        : Icon(
                            Icons.light_mode_rounded,
                            size: 14,
                            color: p.muted,
                          ),
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.primary
                        : p.border,
                  ),
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.primary
                        : p.border,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _menu(
    IconData icon,
    String label,
    VoidCallback action, {
    String? subtitle,
  }) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: action,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.palette.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: context.palette.foreground,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: context.palette.muted),
        ],
      ),
    ),
  );
}
