import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'alerts.dart';
import 'anim.dart';
import 'book.dart';
import 'check.dart';
import 'config.dart';
import 'history.dart';
import 'newsfeed.dart';
import 'donation_history.dart';
import 'notification_service.dart';
import 'shared_design.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _donorId = 0;

  late List<Widget> _screens;
  StreamSubscription<void>? _alertsTapSub;

  @override
  void initState() {
    super.initState();
    _loadDonorId();
    _screens = [
      HomeContent(onNavigateToTab: _selectTab),
      const BookScreen(),
      const CheckScreen(),
      DonationHistoryScreen(),
      const SizedBox(child: Center(child: CircularProgressIndicator())),
    ];

    if (NotificationService.instance.openAlertsOnStart) {
      _selectedIndex = 4;
      NotificationService.instance.consumeOpenAlertsOnStart();
    }

    _alertsTapSub = NotificationService.instance.onAlertsTapped.listen((_) {
      if (mounted) _selectTab(4);
    });
  }

  @override
  void dispose() {
    _alertsTapSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDonorId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorIdString = prefs.getString('donorId');
    final id = int.tryParse(donorIdString ?? '0') ?? 0;

    if (mounted) {
      setState(() {
        _donorId = id;
        _screens = [
          HomeContent(onNavigateToTab: _selectTab),
          const BookScreen(),
          const CheckScreen(),
          DonationHistoryScreen(),
          AlertsScreen(donorId: _donorId),
        ];
      });
    }

    if (id > 0) {
      await _saveFcmTokenToServer(id);
    } else {
      debugPrint("FCM token not saved: donorId is missing.");
    }
  }

  Future<void> _saveFcmTokenToServer(int donorId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) {
        debugPrint("FCM token is null or empty.");
        return;
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/save_fcm_token.php'),
            body: {'donor_id': donorId.toString(), 'fcm_token': token},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("Save FCM token response: ${response.body}");
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: _CustomNavBar(
        selectedIndex: _selectedIndex,
        onTap: _selectTab,
        onCheckTap: () => _selectTab(2),
      ),
    );
  }
}

// ── CUSTOM BOTTOM NAV ─────────────────────────────────────────────────────────

class _CustomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCheckTap;

  const _CustomNavBar({
    required this.selectedIndex,
    required this.onTap,
    required this.onCheckTap,
  });

  // Fixed, device-independent sizing — no hardcoded `bottom:` offsets or
  // Transform.translate; SafeArea handles the system nav-bar/gesture inset.
  // 72px comfortably fits _NavItem's icon+label+indicator column without
  // overflowing (icon 22 + label ~13 + indicator 3 + spacing + padding ≈ 68).
  static const double _barHeight = 72;
  static const double _checkSize = 62;
  static const double _stackHeight = _barHeight + (_checkSize / 2) + 8;

  @override
  Widget build(BuildContext context) {
    final isCheckActive = selectedIndex == 2;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: SizedBox(
          height: _stackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Rounded floating pill
              Container(
                height: _barHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavItem(
                        icon: Icons.home_rounded,
                        label: 'Home',
                        index: 0,
                        selectedIndex: selectedIndex,
                        onTap: onTap,
                      ),
                      _NavItem(
                        icon: Icons.calendar_month_rounded,
                        label: 'Book',
                        index: 1,
                        selectedIndex: selectedIndex,
                        onTap: onTap,
                      ),
                      _NavItem(
                        icon: Icons.history_rounded,
                        label: 'History',
                        index: 3,
                        selectedIndex: selectedIndex,
                        onTap: onTap,
                      ),
                      _NavItem(
                        icon: Icons.notifications_rounded,
                        label: 'Alerts',
                        index: 4,
                        selectedIndex: selectedIndex,
                        onTap: onTap,
                      ),
                    ],
                  ),
                ),
              ),

              // Floating Check button — overlaps the top edge of the pill
              // (its own vertical center sits on the pill's top edge, same
              // ratio the old FloatingActionButtonLocation.centerDocked used).
              Positioned(
                bottom: _barHeight - (_checkSize / 2),
                child: _CenterFAB(isActive: isCheckActive, onTap: onCheckTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(index);
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: const Color(0xFFDC2626).withOpacity(0.12),
        highlightColor: const Color(0xFFDC2626).withOpacity(0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFFFFE4E4), Color(0xFFFFF1F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: isSelected ? 1.18 : 1.0),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF9CA3AF),
                  ),
                  child: Text(label),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  height: 3,
                  width: isSelected ? 14 : 0,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterFAB extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _CenterFAB({required this.isActive, required this.onTap});

  @override
  State<_CenterFAB> createState() => _CenterFABState();
}

class _CenterFABState extends State<_CenterFAB>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isActive) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _CenterFAB oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.stop();
      _pulseController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(31),
          gradient: LinearGradient(
            colors: isActive
                ? [const Color(0xFF750000), const Color(0xFFFF4E4E)]
                : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: isActive
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withOpacity(0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                // While active, the drop bobs up/down and squashes &
                // stretches like it's beating/dripping in place.
                final t = isActive ? _pulseController.value : 0.0;
                final bob = -4.0 * t;
                final stretch = 1.0 + 0.14 * t;
                final squash = 1.0 - 0.10 * t;
                return Transform.translate(
                  offset: Offset(0, bob),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(squash, stretch, 1),
                    child: child,
                  ),
                );
              },
              child: const _BloodDropIcon(),
            ),
            const SizedBox(height: 2),
            Text(
              'Check',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BloodDropIcon extends StatelessWidget {
  const _BloodDropIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(20, 26), painter: _BloodDropPainter());
  }
}

class _BloodDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Classic droplet: sharp point at the top, flaring out into a
    // fully rounded bulb at the bottom (not a symmetric oval).
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, w * 0.12, h * 0.42, w * 0.12, h * 0.66)
      ..cubicTo(w * 0.12, h * 0.87, w * 0.28, h, w * 0.5, h)
      ..cubicTo(w * 0.72, h, w * 0.88, h * 0.87, w * 0.88, h * 0.66)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();

    canvas.drawPath(path, paint);

    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.38, h * 0.62),
        width: w * 0.2,
        height: h * 0.16,
      ),
      shinePaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── HOME CONTENT ──────────────────────────────────────────────────────────────

class HomeContent extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const HomeContent({super.key, required this.onNavigateToTab});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  String userName = "User";
  String bloodType = "—";
  int totalDonations = 0;
  String nextEligibleDate = "Loading...";
  String eligibilityStatus = "Loading...";
  bool isProfileLoading = true;
  bool isEligibilityLoading = true;

  List<Map<String, dynamic>> appointments = [];
  bool isAppointmentsLoading = true;

  @override
  void initState() {
    super.initState();
    loadUserName();
    loadProfileData();
    loadEligibilityData();
    loadAppointments();
  }

  Future<void> _refreshHomeData() async {
    if (mounted) {
      setState(() {
        isProfileLoading = true;
        isEligibilityLoading = true;
        isAppointmentsLoading = true;
      });
    }

    await Future.wait([
      loadUserName(),
      loadProfileData(),
      loadEligibilityData(),
      loadAppointments(),
    ]);
  }

  Future<void> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => userName = prefs.getString('userName') ?? 'User');
    }
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          bloodType = "N/A";
          isProfileLoading = false;
        });
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_profile.php?donor_id=$donorId"),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded["status"] == "success" && decoded["data"] != null) {
          final d = decoded["data"];
          if (mounted) {
            setState(() {
              bloodType = (d["blood_type"] ?? "N/A").toString();
              totalDonations =
                  int.tryParse(d["total_donations"].toString()) ?? 0;
              isProfileLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              bloodType = "N/A";
              isProfileLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          bloodType = "N/A";
          isProfileLoading = false;
        });
      }
    }
  }

  Future<void> loadEligibilityData() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          nextEligibleDate = "N/A";
          eligibilityStatus = "Unknown";
          isEligibilityLoading = false;
        });
      }
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              "${AppConfig.baseUrl}/get_eligibility.php?donor_id=$donorId",
            ),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["status"] == "success") {
          if (mounted) {
            setState(() {
              nextEligibleDate =
                  data["next_eligible_date"] == null ||
                      data["next_eligible_date"].toString().trim().isEmpty
                  ? "N/A"
                  : formatDate(data["next_eligible_date"].toString());
              eligibilityStatus = (data["eligibility"] ?? "Unknown").toString();
              isEligibilityLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              nextEligibleDate = "N/A";
              eligibilityStatus = "Unknown";
              isEligibilityLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          nextEligibleDate = "N/A";
          eligibilityStatus = "Unknown";
          isEligibilityLoading = false;
        });
      }
    }
  }

  Future<void> loadAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) setState(() => isAppointmentsLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "${AppConfig.baseUrl}/get_appointments.php?donor_id=$donorId",
        ),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded["status"] == "success" && decoded["data"] != null) {
          if (mounted) {
            setState(() {
              final list = List<Map<String, dynamic>>.from(decoded["data"]);
              appointments = list.isNotEmpty ? [list.first] : [];
              isAppointmentsLoading = false;
            });
          }
        } else {
          if (mounted) setState(() => isAppointmentsLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => isAppointmentsLoading = false);
    }
  }

  String formatDate(String dateString) {
    if (dateString.isEmpty) return "N/A";
    try {
      final date = DateTime.parse(dateString);
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
      return "${months[date.month - 1]} ${date.day}, ${date.year}";
    } catch (_) {
      return dateString;
    }
  }

  String formatTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return "N/A";
    try {
      final parts = timeString.split(":");
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? "PM" : "AM";
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return "$hour:${minute.toString().padLeft(2, '0')} $period";
    } catch (_) {
      return timeString;
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'cancelled':
        return const Color(0xFFDC2626);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'approved':
      case 'completed':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  Color getStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'cancelled':
        return const Color(0xFFFFF1F1);
      case 'pending':
        return const Color(0xFFFFFBEB);
      case 'approved':
      case 'completed':
        return const Color(0xFFF0FDF4);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color getEligibilityStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'eligible':
        return const Color(0xFF16A34A);
      case 'pending':
      case 'for_review':
      case 'temporary_deferred':
      case 'not_checked':
        return const Color(0xFFF59E0B);
      case 'not_eligible':
      default:
        return const Color(0xFFDC2626);
    }
  }

  // Maps raw backend eligibility_status.status values to donor-facing text
  // so the UI never shows a raw snake_case value like "not_eligible".
  String formatEligibilityStatus(String status) {
    switch (status.toLowerCase()) {
      case 'eligible':
        return 'Eligible';
      case 'not_eligible':
        return 'Not Eligible';
      case 'pending':
      case 'for_review':
        return 'Pending Review';
      case 'temporary_deferred':
        return 'Temporarily Deferred';
      case 'not_checked':
        return 'Not Checked';
      case 'unknown':
        return 'Unknown';
      default:
        return status
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final firstName = userName.split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              left: 20,
              right: 20,
              bottom: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greetingText(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            firstName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Thank you for saving lives',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    HeaderIconButton(
                      icon: Icons.dynamic_feed_rounded,
                      tooltip: 'Newsfeed',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NewsfeedPage()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PressableScale(
                      onTap: _navigateToHistory,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white24,
                          child: Text(
                            firstName.isNotEmpty
                                ? firstName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFDC2626),
              onRefresh: _refreshHomeData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  screenWidth * 0.05,
                  20,
                  screenWidth * 0.05,
                  20,
                ),
                child: Column(
                  children: [
                    FadeSlideIn(
                      index: 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              label: 'Blood Type',
                              value: isProfileLoading ? '...' : bloodType,
                              icon: Icons.water_drop_rounded,
                              iconColor: const Color(0xFFDC2626),
                              iconBg: const Color(0xFFFFF1F1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              label: 'Donations',
                              value: isProfileLoading
                                  ? '...'
                                  : totalDonations.toString(),
                              icon: Icons.favorite_rounded,
                              iconColor: const Color(0xFFEC4899),
                              iconBg: const Color(0xFFFDF2F8),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              label: 'Lives Saved',
                              value: isProfileLoading
                                  ? '...'
                                  : '${totalDonations * 3}',
                              icon: Icons.people_rounded,
                              iconColor: const Color(0xFF16A34A),
                              iconBg: const Color(0xFFF0FDF4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 1,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.verified_user_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Donation Eligibility',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _eligibilityRow(
                              'Next Eligible',
                              isEligibilityLoading
                                  ? 'Loading...'
                                  : nextEligibleDate,
                              Icons.calendar_today_rounded,
                              const Color(0xFF2563EB),
                            ),
                            const SizedBox(height: 8),
                            _eligibilityRow(
                              'Status',
                              isEligibilityLoading
                                  ? 'Loading...'
                                  : formatEligibilityStatus(eligibilityStatus),
                              Icons.circle,
                              getEligibilityStatusColor(eligibilityStatus),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onNavigateToTab(2),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                                label: const Text('Check Eligibility'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 2,
                      child: Row(
                        children: [
                          Expanded(
                            child: _actionCard(
                              icon: Icons.calendar_month_rounded,
                              iconColor: const Color(0xFF2563EB),
                              iconBg: const Color(0xFFEFF6FF),
                              title: 'Book Appointment',
                              subtitle: 'Schedule your donation',
                              onTap: () => widget.onNavigateToTab(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _actionCard(
                              icon: Icons.history_rounded,
                              iconColor: const Color(0xFF9333EA),
                              iconBg: const Color(0xFFFAF5FF),
                              title: 'Donation History',
                              subtitle: 'View past donations',
                              onTap: () => widget.onNavigateToTab(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Upcoming Appointment',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF111827),
                            ),
                          ),
                          if (!isAppointmentsLoading && appointments.isNotEmpty)
                            GestureDetector(
                              onTap: () => widget.onNavigateToTab(3),
                              child: const Text(
                                'See all',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isAppointmentsLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFDC2626),
                        ),
                      )
                    else if (appointments.isEmpty)
                      FadeSlideIn(
                        index: 4,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                color: Colors.grey.shade300,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No upcoming appointments.',
                                style: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Book one to get started!',
                                style: TextStyle(
                                  color: Color(0xFFD1D5DB),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...appointments.map(
                        (appt) => FadeSlideIn(
                          index: 4,
                          child: _appointmentCard(appt),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 5,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your Impact',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$totalDonations donations · ${totalDonations * 3} lives potentially saved',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.emoji_events_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      index: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.volunteer_activism_rounded,
                              color: Color(0xFF16A34A),
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Thank you for being a hero in your community. Every donation makes a difference.',
                                style: TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _eligibilityRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appt) {
    final date = formatDate(appt["appointment_date"] ?? "");
    final time = formatTime(appt["appointment_time"] ?? "");
    final center = appt["donation_center"] ?? "N/A";
    final status = appt["status"] ?? "N/A";
    final statusColor = getStatusColor(status);
    final statusBg = getStatusBg(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFFDC2626),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
