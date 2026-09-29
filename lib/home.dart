import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'alerts.dart';
import 'anim.dart';
import 'blood_requests/blood_request_api.dart';
import 'blood_requests/blood_request_detail_screen.dart';
import 'blood_requests/blood_request_models.dart';
import 'blood_requests/blood_request_widgets.dart';
import 'blood_requests/blood_requests_screen.dart';
import 'blood_requests/request_blood_screen.dart';
import 'book.dart';
import 'check.dart';
import 'config.dart';
import 'digital_id.dart';
import 'digital_id_service.dart';
import 'history.dart';
import 'newsfeed.dart';
import 'donation_history.dart';
import 'notification_service.dart';
import 'shared_design.dart';
import 'verify.dart';

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
      backgroundColor: const Color(0xFFF9FAFB),
      body: _screens[_selectedIndex],
      bottomNavigationBar: Material(
        type: MaterialType.transparency,
        child: _CustomNavBar(
          selectedIndex: _selectedIndex,
          onTap: _selectTab,
          onCheckTap: () => _selectTab(2),
        ),
      ),
    );
  }
}

// ── CUSTOM BOTTOM NAV ─────────────────────────────────────────────────────────

// Total footprint of _CustomNavBar's floating pill, including the portion
// of the center FAB that pokes above it — excludes the device safe-area
// inset, which the bar's own SafeArea adds separately. Tabs hosted inside
// HomeScreen that scroll under this bar should add at least this much
// bottom padding so their last item isn't tucked behind it.
const double kBottomNavBarHeight =
    _CustomNavBar._barHeight + (_CustomNavBar._checkSize / 2) + 8;

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
  static const double _stackHeight = kBottomNavBarHeight;

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
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 6),
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
    return Tooltip(
      message: label,
      child: Material(
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
                  const SizedBox(height: 5),
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

  BloodRequestSummary? _brSummary;
  bool _brLoading = true;
  bool _brError = false;

  DigitalIdData? _digitalId;
  bool _digitalIdLoaded = false;
  bool _digitalIdMasked = false;

  @override
  void initState() {
    super.initState();
    loadUserName();
    loadProfileData();
    loadEligibilityData();
    loadAppointments();
    loadBloodRequestSummary();
    loadDigitalId();
  }

  Future<void> loadDigitalId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) {
      if (mounted) setState(() => _digitalIdLoaded = true);
      return;
    }
    try {
      final masked = await DigitalIdService.isMasked(donorId);
      final data = await DigitalIdService.fetch(donorId);
      if (!mounted) return;
      setState(() {
        _digitalId = data;
        _digitalIdMasked = masked;
        _digitalIdLoaded = true;
      });
    } catch (_) {
      // Keep whatever was last known — this card should never show an
      // error state, it just quietly doesn't update.
      if (mounted) setState(() => _digitalIdLoaded = true);
    }
  }

  Future<void> _openDigitalId() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DigitalIdScreen()),
    );
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) return;
    final masked = await DigitalIdService.isMasked(donorId);
    if (mounted) setState(() => _digitalIdMasked = masked);
  }

  Future<void> _refreshHomeData() async {
    if (mounted) {
      setState(() {
        isProfileLoading = true;
        isEligibilityLoading = true;
        isAppointmentsLoading = true;
        _brLoading = true;
      });
    }

    await Future.wait([
      loadUserName(),
      loadProfileData(),
      loadEligibilityData(),
      loadAppointments(),
      loadBloodRequestSummary(),
    ]);
  }

  Future<void> loadBloodRequestSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) {
      if (mounted)
        setState(() {
          _brLoading = false;
          _brError = true;
        });
      return;
    }
    try {
      final summary = await BloodRequestApi.fetchSummary(donorId);
      if (!mounted) return;
      setState(() {
        _brSummary = summary;
        _brLoading = false;
        _brError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _brLoading = false;
        _brError = true;
      });
    }
  }

  Future<void> _openBloodRequestsHub({int tab = 0}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BloodRequestsScreen(initialTab: tab)),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _openBloodRequestDetail(int requestId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BloodRequestDetailScreen(requestId: requestId),
      ),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _openRequestBlood() async {
    final summary = _brSummary;
    if (summary != null && !summary.canRequest) {
      await _showRequestBlockedSheet(summary.requestBlock);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
    );
    if (mounted) await loadBloodRequestSummary();
  }

  Future<void> _showRequestBlockedSheet(VolunteerBlock? block) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Text(
              'Unable to Request Blood',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              block?.message ?? 'You cannot create a request right now.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (block?.action == 'verify')
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VerifyScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Verify Now',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

  Widget _headerInitial(String firstName) => Text(
    firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
    style: const TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  );

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  // ── Digital Donor ID card ────────────────────────────────────────────────

  Widget _digitalIdCard() {
    final data = _digitalId;
    if (data == null) return const SizedBox.shrink();
    final donor = data.donor;
    final code = _digitalIdMasked ? data.card.codeMasked : data.card.code;

    return PressableScale(
      onTap: _openDigitalId,
      child: Container(
        clipBehavior: Clip.antiAlias,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7F1D1D), Color(0xFFDC2626), Color(0xFFEF4444)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: .3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -14,
              child: CustomPaint(
                size: const Size(90, 108),
                painter: _MiniCardDropPainter(),
              ),
            ),
            const _LightSweep(),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: donor.photoUrl != null
                        ? Image.network(
                            donor.photoUrl!,
                            fit: BoxFit.cover,
                            width: 44,
                            height: 44,
                            errorBuilder: (_, _, _) =>
                                _initialsCircle(donor.fullName),
                          )
                        : _initialsCircle(donor.fullName),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DIGITAL DONOR ID',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        donor.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    donor.bloodType ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialsCircle(String name) => Container(
    color: Colors.white,
    alignment: Alignment.center,
    child: Text(
      _initialsFor(name),
      style: const TextStyle(
        color: Color(0xFFDC2626),
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
  );

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // ── Blood Requests card ─────────────────────────────────────────────────

  Widget _bloodRequestsCardShell(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
      ],
    ),
    child: child,
  );

  Widget _brHeaderRow() => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.bloodtype_rounded,
          color: Color(0xFFDC2626),
          size: 20,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Blood Requests',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              'Request blood or help a patient in need',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
      TextButton(
        onPressed: () => _openBloodRequestsHub(),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFDC2626),
          padding: EdgeInsets.zero,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'View all',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Icon(Icons.chevron_right_rounded, size: 16),
          ],
        ),
      ),
    ],
  );

  Widget _brUrgentBanner(BloodRequestSummary summary) {
    final n = summary.urgentMatchingCount;
    final top = summary.topUrgent;
    return PressableScale(
      onTap: top != null
          ? () => _openBloodRequestDetail(top.requestId)
          : () => _openBloodRequestsHub(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const _PulsingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 1
                        ? '1 urgent request needs your blood type'
                        : '$n urgent requests need your blood type',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (top != null)
                    Text(
                      [
                        top.facilityName,
                        top.timeLeftLabel,
                      ].where((e) => e != null && e.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _brRequestTile() => PressableScale(
    onTap: _openRequestBlood,
    child: Container(
      height: 118,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: .3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Blood',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'For you or a loved one',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _brHelpTile(BloodRequestSummary summary) => PressableScale(
    onTap: () => _openBloodRequestsHub(),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 118,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7F7),
            border: Border.all(color: const Color(0xFFFECACA), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Help a Patient',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.matchingCount > 0
                        ? '${summary.matchingCount} match your type'
                        : summary.openCount > 0
                        ? '${summary.openCount} open request${summary.openCount == 1 ? '' : 's'}'
                        : 'No requests right now',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (summary.openCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                '${summary.openCount}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _brYourRequestSection(BloodRequestSummary summary) {
    final r = summary.myActiveRequest!;
    return GestureDetector(
      onTap: () => _openBloodRequestDetail(r.requestId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'YOUR REQUEST',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8,
                ),
              ),
              if (summary.myActiveCount > 1) ...[
                const SizedBox(width: 6),
                Text(
                  '+${summary.myActiveCount - 1} more',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BloodDropBadge(bloodType: r.bloodType, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.reference,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    RequestStatusChip(status: r.status, label: r.statusLabel),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${r.volunteersCount}/${r.requiredDonors} donors',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    DonorProgressBar(
                      volunteers: r.volunteersCount,
                      required: r.requiredDonors,
                      showLabel: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brYourCommitmentSection(BloodRequestSummary summary) {
    final r = summary.myCommitment!;
    return GestureDetector(
      onTap: () => _openBloodRequestDetail(r.requestId),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          border: Border.all(color: const Color(0xFFBBF7D0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              size: 18,
              color: Color(0xFF16A34A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "You're donating for ${r.reference}",
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                  Text(
                    [
                      r.facility?.name,
                      r.neededBy != null
                          ? 'needed by ${brShortDate(r.neededBy)}'
                          : null,
                    ].where((e) => e != null && e.isNotEmpty).join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF15803D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF16A34A)),
          ],
        ),
      ),
    );
  }

  Widget _brHeaderRowSkeleton() => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'Blood Requests',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ),
    ],
  );

  Widget _brSkeletonTile() => Container(
    height: 118,
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(14),
    ),
  );

  Widget _brLoadingBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brHeaderRowSkeleton(),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(child: _brSkeletonTile()),
          const SizedBox(width: 12),
          Expanded(child: _brSkeletonTile()),
        ],
      ),
    ],
  );

  Widget _brErrorBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _brHeaderRowSkeleton(),
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 16,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          const Text(
            "Couldn't load blood requests",
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
          const Spacer(),
          TextButton(
            onPressed: loadBloodRequestSummary,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _bloodRequestsCard() {
    if (_brLoading) return _bloodRequestsCardShell(_brLoadingBody());
    final summary = _brSummary;
    if (_brError || summary == null)
      return _bloodRequestsCardShell(_brErrorBody());

    return _bloodRequestsCardShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brHeaderRow(),
          if (summary.urgentMatchingCount > 0) ...[
            const SizedBox(height: 14),
            _brUrgentBanner(summary),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _brRequestTile()),
              const SizedBox(width: 12),
              Expanded(child: _brHelpTile(summary)),
            ],
          ),
          if (summary.myActiveRequest != null) ...[
            const Divider(height: 28, color: Color(0xFFF3F4F6)),
            _brYourRequestSection(summary),
          ],
          if (summary.myCommitment != null) ...[
            const SizedBox(height: 10),
            _brYourCommitmentSection(summary),
          ],
        ],
      ),
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
                          child: _digitalId?.donor.photoUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    _digitalId!.donor.photoUrl!,
                                    fit: BoxFit.cover,
                                    width: 44,
                                    height: 44,
                                    errorBuilder: (_, _, _) =>
                                        _headerInitial(firstName),
                                  ),
                                )
                              : _headerInitial(firstName),
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
                    if (_digitalIdLoaded && _digitalId != null) ...[
                      FadeSlideIn(index: 1, child: _digitalIdCard()),
                      const SizedBox(height: 16),
                    ],
                    FadeSlideIn(
                      index: 2,
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
                    FadeSlideIn(index: 3, child: _bloodRequestsCard()),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 4,
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
                      index: 5,
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
                        index: 6,
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
                          index: 6,
                          child: _appointmentCard(appt),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      index: 7,
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
                      index: 8,
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

// Faint droplet watermark for the Digital ID mini card (Section 3.2).
class _MiniCardDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, w * 0.12, h * 0.42, w * 0.12, h * 0.66)
      ..cubicTo(w * 0.12, h * 0.87, w * 0.28, h, w * 0.5, h)
      ..cubicTo(w * 0.72, h, w * 0.88, h * 0.87, w * 0.88, h * 0.66)
      ..cubicTo(w * 0.88, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniCardDropPainter oldDelegate) => false;
}

// One-time light sweep across the Digital ID mini card when it first appears.
class _LightSweep extends StatefulWidget {
  const _LightSweep();

  @override
  State<_LightSweep> createState() => _LightSweepState();
}

class _LightSweepState extends State<_LightSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _position;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _position = Tween<double>(
      begin: -0.4,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, child) => Align(
          alignment: Alignment(_position.value * 2 - 1, 0),
          child: FractionallySizedBox(
            widthFactor: 0.3,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .18),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Small pulsing dot for the Blood Requests card's urgent banner — mirrors
// UrgencyChip's critical-urgency pulse in blood_request_widgets.dart.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, child) =>
        Opacity(opacity: 0.35 + (_ctrl.value * 0.65), child: child),
    child: Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
    ),
  );
}
