import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'alerts.dart';
import 'anim.dart';
import 'book.dart';
import 'check.dart';
import 'config.dart';
import 'history.dart';
import 'login.dart';
import 'newsfeed.dart';
import 'donation_history.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _donorId = 0;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _loadDonorId();
    _screens = [
      const HomeContent(),
      const BookScreen(),
      const CheckScreen(),
      DonationHistoryScreen(),
      const SizedBox(child: Center(child: CircularProgressIndicator())),
    ];
  }

  Future<void> _loadDonorId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorIdString = prefs.getString('donorId');
    final id = int.tryParse(donorIdString ?? '0') ?? 0;

    if (mounted) {
      setState(() {
        _donorId = id;
        _screens = [
          const HomeContent(),
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

  void _onItemTapped(int index) {
    if (index == 2) return; // handled by FAB
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      floatingActionButton: _CenterFAB(
        isActive: _selectedIndex == 2,
        onTap: () => setState(() => _selectedIndex = 2),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _CustomNavBar(
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

// ── CUSTOM BOTTOM NAV ─────────────────────────────────────────────────────────

class _CustomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _CustomNavBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCheckActive = selectedIndex == 2;

    return BottomAppBar(
      shape: isCheckActive ? null : const CircularNotchedRectangle(),
      notchMargin: isCheckActive ? 0 : 8,
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SizedBox(
        height: 62,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: isCheckActive ? 0 : 56,
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
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: isSelected
            ? BoxDecoration(
                color: const Color(0xFFFFF1F1),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterFAB extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _CenterFAB({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: isActive ? const Offset(0, 0.55) : Offset.zero,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: isActive ? 72 : 62,
          height: isActive ? 54 : 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isActive ? 14 : 31),
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
              _BloodDropIcon(isActive: isActive),
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
      ),
    );
  }
}

class _BloodDropIcon extends StatelessWidget {
  final bool isActive;
  const _BloodDropIcon({required this.isActive});

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

    final path = Path();
    final cx = size.width / 2;

    path.moveTo(cx, 0);
    path.cubicTo(
      cx + size.width * 0.6,
      size.height * 0.35,
      cx + size.width * 0.6,
      size.height * 0.7,
      cx,
      size.height,
    );
    path.cubicTo(
      cx - size.width * 0.6,
      size.height * 0.7,
      cx - size.width * 0.6,
      size.height * 0.35,
      cx,
      0,
    );
    path.close();

    canvas.drawPath(path, paint);

    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - size.width * 0.12, size.height * 0.42),
        width: size.width * 0.22,
        height: size.height * 0.18,
      ),
      shinePaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── HOME CONTENT ──────────────────────────────────────────────────────────────

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

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
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_eligibility.php?donor_id=$donorId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["status"] == "success") {
          if (mounted) {
            setState(() {
              nextEligibleDate = formatDate(
                data["next_eligible_date"]?.toString() ?? "",
              );
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
      case 'approved':
        return const Color(0xFF16A34A);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFDC2626);
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
                    _FeedBackButton(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NewsfeedPage()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                                  : eligibilityStatus,
                              Icons.circle,
                              getEligibilityStatusColor(eligibilityStatus),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CheckScreen(),
                                    ),
                                  );
                                },
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
                              context: context,
                              icon: Icons.calendar_month_rounded,
                              iconColor: const Color(0xFF2563EB),
                              iconBg: const Color(0xFFEFF6FF),
                              title: 'Book Appointment',
                              subtitle: 'Schedule your donation',
                              destination: const BookScreen(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _actionCard(
                              context: context,
                              icon: Icons.history_rounded,
                              iconColor: const Color(0xFF9333EA),
                              iconBg: const Color(0xFFFAF5FF),
                              title: 'Donation History',
                              subtitle: 'View past donations',
                              destination: DonationHistoryScreen(),
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
                          if (!isAppointmentsLoading &&
                              appointments.isNotEmpty)
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DonationHistoryScreen(),
                                ),
                              ),
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
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return PressableScale(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ),
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

// ── Frosted-glass "back to feed" button ─────────────────────────────────────
class _FeedBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FeedBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.16),
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withOpacity(0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Feed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
