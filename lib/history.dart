import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'streak/streak_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'config.dart';
import 'digital_id.dart';
import 'edit_profile.dart';
import 'help_support.dart';
import 'login.dart';
import 'notification_settings.dart';
import 'pin_screen.dart'; // PIN: logout reset
import 'privacy_security.dart';
import 'privacy_statement.dart';
import 'shared_design.dart';
import 'skeleton.dart';
import 'streak/frame_picker.dart';
import 'streak/streak_controller.dart';
import 'unread_notifications.dart';
import 'my_avatar.dart';
import 'my_avatar_controller.dart';
import 'streak/streak_routes.dart';
import 'theme_controller.dart';
import 'theme_transition.dart';
import 'verify.dart';
import 'widgets/image_viewer.dart';
import 'widgets/count_up_text.dart';

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
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.palette.accentBg,
          ),
          child: Icon(Icons.logout, color: context.palette.primaryText),
        ),
        title: Text(
          'Logout',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.palette.foreground,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.muted,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.primaryText,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
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
    MyAvatarController.instance.reset();
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
    final showSkeleton = loading && profile == null;
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: context.palette.primaryText,
          backgroundColor: context.palette.surface,
          onRefresh: () => Future.wait([
            _load(progress: false),
            MyAvatarController.instance.refresh(),
          ]),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                _bannerAndProfile(context, name, skeleton: showSkeleton),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (notice != null) ...[
                        _notice(notice!),
                        const SizedBox(height: 16),
                      ],
                      if (showSkeleton)
                        _skeleton()
                      else ...[
                        FadeSlideIn(
                          index: 1,
                          child: Row(
                            children: [
                              Expanded(
                                child: _stat(
                                  Icons.water_drop,
                                  'Donations',
                                  context.palette.primaryText,
                                  context.palette.accentBg,
                                  number: total,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _stat(
                                  Icons.calendar_today,
                                  'Days Active',
                                  context.palette.info,
                                  context.palette.infoBg,
                                  text: active,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _stat(
                                  Icons.emoji_events,
                                  'Lives Helped',
                                  context.palette.warning,
                                  context.palette.warningBg,
                                  number: total * 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _section(2, 'Personal Information', [
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
                        _section(3, 'Donation Status', [
                          _info(
                            Icons.water_drop,
                            'Last Donation',
                            date(profile?['last_donation']),
                          ),
                          _info(
                            Icons.event_available,
                            'Next Eligible',
                            _next(),
                            color: context.palette.successDark,
                          ),
                        ]),
                      ],
                      _section(4, 'Account', [
                        _menu(
                          Icons.edit,
                          'Edit Profile',
                          () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                            if (changed == true) _load(progress: false);
                            // A new photo may have been chosen there.
                            unawaited(MyAvatarController.instance.refresh());
                          },
                          subtitle: 'Update your personal details',
                          tint: context.palette.info,
                          tintBg: context.palette.infoBg,
                        ),
                        _menu(
                          Icons.badge_rounded,
                          'Digital Donor ID',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DigitalIdScreen(),
                            ),
                          ),
                          subtitle: 'Your donor card and QR code',
                          tint: context.palette.primaryText,
                          tintBg: context.palette.accentBg,
                        ),
                      ]),
                      _section(5, 'Preferences', [
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
                          subtitle: 'Choose what you hear about',
                          tint: context.palette.warning,
                          tintBg: context.palette.warningBg,
                        ),
                        _darkModeRow(),
                        _menu(
                          Icons.shield,
                          'Privacy & Security',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PrivacySecurityScreen(
                                showChangePin: verificationStatus == 'verified',
                              ),
                            ),
                          ),
                          subtitle: 'PIN, password and your data',
                          tint: context.palette.success,
                          tintBg: context.palette.successBg,
                        ),
                      ]),
                      _section(6, 'Support', [
                        _menu(
                          Icons.help_outline,
                          'Help & Support',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HelpSupportScreen(),
                            ),
                          ),
                          subtitle: 'FAQs and ways to reach us',
                          tint: context.palette.purple,
                          tintBg: context.palette.purpleBg,
                        ),
                      ]),
                      const SizedBox(height: 24),
                      FadeSlideIn(
                        index: 7,
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _logout,
                            icon: Icon(
                              Icons.logout,
                              color: context.palette.primaryText,
                            ),
                            label: Text(
                              'Logout',
                              style: TextStyle(
                                color: context.palette.primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: context.palette.surface,
                              foregroundColor: context.palette.primaryText,
                              side: BorderSide(
                                color: context.palette.primaryBorder,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Version 1.0.0',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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

  // ── Banner and profile card ─────────────────────────────────────────────

  static const double _avatarRadius = 44;

  /// The gradient banner with the framed avatar overlapping its bottom edge,
  /// over the card with the name, email, blood type, verification and streak.
  Widget _bannerAndProfile(
    BuildContext context,
    String name, {
    required bool skeleton,
  }) {
    final top = math.max(
      MediaQuery.paddingOf(context).top + 8,
      MediaQuery.sizeOf(context).height * 0.06,
    );
    final bannerHeight = top + 168;
    // The card starts this far above the banner's bottom edge.
    const overlap = 44.0;
    const avatarBox = _avatarRadius * 2 + 16;
    return Stack(
      children: [
        Container(
          height: bannerHeight,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            child: Stack(
              children: [
                Positioned(right: -50, top: -40, child: _ring(170, .09)),
                Positioned(left: -40, bottom: -60, child: _ring(140, .06)),
                Positioned(right: 70, bottom: 10, child: _ring(46, .07)),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, top, 20, 0),
                  child: Row(
                    children: [
                      HeaderIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Profile',
                              style: TextStyle(
                                color: AppColors.onPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Manage your account & donations',
                              style: TextStyle(
                                color: AppColors.onPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, bannerHeight - overlap, 16, 0),
          child: FadeSlideIn(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, avatarBox / 2 + 12, 20, 20),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.palette.border),
                boxShadow: context.palette.shadow,
              ),
              child: skeleton
                  ? const SkeletonPulse(
                      child: Column(
                        children: [
                          SkeletonBox(width: 96, height: 26, radius: 13),
                          SizedBox(height: 16),
                          SkeletonBox(width: 170, height: 20),
                          SizedBox(height: 8),
                          SkeletonBox(width: 140, height: 12),
                          SizedBox(height: 16),
                          SkeletonBox(width: 200, height: 26, radius: 13),
                        ],
                      ),
                    )
                  : _profileDetails(name),
            ),
          ),
        ),
        // The framed avatar, half on the banner and half on the card.
        Positioned(
          top: bannerHeight - overlap - avatarBox / 2,
          left: 0,
          right: 0,
          child: Center(
            // The photo, its frame ring and the white disc around them all
            // open the photo full screen.
            child: Semantics(
              button: true,
              label: 'View profile photo',
              excludeSemantics: true,
              onTap: () => _openPhoto(name),
              child: PressableScale(
                onTap: () => _openPhoto(name),
                child: Container(
                  width: avatarBox,
                  height: avatarBox,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: context.palette.isDark ? .35 : .12,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  // The donor's own photo and frame (initials without a photo).
                  child: const MyAvatar(
                    radius: _avatarRadius,
                    heroTag: 'profile_photo_0',
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the donor's photo full screen (it grows out of the round avatar).
  /// Without a photo there is nothing to show: a short note instead.
  void _openPhoto(String name) {
    final url = MyAvatarController.instance.avatarUrl;
    if (url == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("You haven't added a profile photo yet."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    HapticFeedback.selectionClick();
    final me = MyAvatarController.instance.name;
    openImageViewer(
      context,
      imageUrls: [url],
      initialIndex: 0,
      heroTagPrefix: 'profile_photo',
      title: name != 'N/A' ? name : (me.isNotEmpty ? me : null),
      fromCircle: true,
    );
  }

  Widget _ring(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.onPrimary.withValues(alpha: alpha),
    ),
  );

  Widget _profileDetails(String name) => Column(
    children: [
      Builder(
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () =>
                showFrameCatalogSheet(context, initials: initials(name)),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: context.palette.accentBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.palette.primaryBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: context.palette.primaryText,
                  ),
                  const SizedBox(width: 5),
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
      ),
      const SizedBox(height: 14),
      Text(
        name,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: context.palette.foreground,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        safe(profile?['email']),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      ),
      const SizedBox(height: 14),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kCrimson,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.water_drop_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  '${safe(profile?['blood_type'])} Blood Type',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _verificationBadge(),
          _streakChip(),
        ],
      ),
    ],
  );

  /// The current streak (from what StreakController already has); opens the
  /// streak home.
  Widget _streakChip() => ListenableBuilder(
    listenable: StreakController.instance,
    builder: (context, _) {
      final current = StreakController.instance.data?.current;
      final p = context.palette;
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, streakHomeRoute()),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: p.orangeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.orangeBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: p.orange,
                ),
                const SizedBox(width: 5),
                Text(
                  current == null
                      ? 'Daily Streak'
                      : current == 1
                      ? '1-day streak'
                      : '$current-day streak',
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 15, color: p.muted),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _skeleton() => SkeletonPulse(
    child: Column(
      children: [
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 96, radius: 20)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 96, radius: 20)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 96, radius: 20)),
          ],
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < 2; i++) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 120, height: 10),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              children: [
                for (var r = 0; r < 3; r++)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SkeletonBox(width: 36, height: 36, radius: 10),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 80, height: 10),
                              SizedBox(height: 6),
                              SkeletonBox(width: 150, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
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

  Widget _verificationBadge() {
    late Color fg;
    late Color iconColor;
    late Color bg;
    late String label;
    late IconData icon;

    switch (verificationStatus) {
      case 'verified':
        fg = context.palette.successDark;
        iconColor = context.palette.success;
        bg = context.palette.successSoft;
        label = 'Verified';
        icon = Icons.verified_user_rounded;
        break;
      case 'pending':
        fg = context.palette.warningText;
        iconColor = context.palette.warning;
        bg = context.palette.warningBg;
        label = 'Verification Pending';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'rejected':
        fg = iconColor = context.palette.primaryText;
        bg = context.palette.accentBg;
        label = 'Verification Rejected';
        icon = Icons.gpp_bad_outlined;
        break;
      case 'unverified':
        fg = iconColor = context.palette.primaryText;
        bg = context.palette.accentBg;
        label = 'Not Verified';
        icon = Icons.shield_outlined;
        break;
      default:
        fg = iconColor = context.palette.muted;
        bg = context.palette.surfaceAlt;
        label = 'Checking...';
        icon = Icons.hourglass_empty_rounded;
    }

    final isVerified = verificationStatus == 'verified';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isVerified
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VerifyScreen()),
              ),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
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
      ),
    );
  }

  Widget _stat(
    IconData icon,
    String label,
    Color color,
    Color bg, {
    int? number,
    String? text,
  }) {
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
      color: context.palette.foreground,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.border),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: number != null
                  ? CountUpText(number, style: style)
                  : Text(text ?? 'N/A', style: style),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// A small uppercase label over a grouped surface card; rows are split by
  /// hairline dividers.
  Widget _section(int index, String title, List<Widget> rows) => FadeSlideIn(
    index: index,
    child: Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: context.palette.muted,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.border),
              boxShadow: context.palette.shadow,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 64,
                        color: context.palette.border,
                      ),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _iconTile(IconData icon, Color color, Color bg) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: color),
  );

  Widget _info(IconData icon, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            _iconTile(icon, context.palette.muted, context.palette.surfaceAlt),
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
                      fontWeight: FontWeight.w600,
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
  /// it changes the whole app at once (the new theme grows out of the switch).
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
          onTap: () => toggle(!dark),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
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
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: p.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Easier on the eyes in low light',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
    Color? tint,
    Color? tintBg,
  }) => InkWell(
    onTap: action,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          _iconTile(
            icon,
            tint ?? context.palette.muted,
            tintBg ?? context.palette.surfaceAlt,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.palette.foreground,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
