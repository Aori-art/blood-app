import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import 'anim.dart';
import 'config.dart';
import 'login.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? errorMessage;

  List<FlSpot> chartData = [];
  bool isChartLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
    fetchDonationHistory();
  }

  Future<void> fetchUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = "No donor ID found.";
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_profile.php?donor_id=$donorId"),
      );
      final data = jsonDecode(response.body);
      if (data["status"] == "success") {
        setState(() {
          userData = data["data"];
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = "Failed to load profile.";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Error: $e";
      });
    }
  }

  Future<void> fetchDonationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null) {
      setState(() => isChartLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_donations_history.php?donor_id=$donorId"),
      );
      final data = jsonDecode(response.body);
      if (data["status"] == "success") {
        List list = data["data"];
        List<FlSpot> spots = [];
        for (int i = 0; i < list.length; i++) {
          spots.add(FlSpot(i.toDouble(), list[i]["count"].toDouble()));
        }
        setState(() {
          chartData = spots;
          isChartLoading = false;
        });
      } else {
        setState(() => isChartLoading = false);
      }
    } catch (e) {
      setState(() => isChartLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
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

    if (shouldLogout != true) return;

    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    // A shared device must not keep receiving the previous donor's push
    // notifications, so disassociate the FCM token before clearing session.
    if (donorId != null && donorId.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('${AppConfig.baseUrl}/delete_fcm_token.php'),
          body: {'donor_id': donorId},
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Error removing FCM token on logout: $e');
      }
    }

    await prefs.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  String safe(dynamic value) {
    if (value == null) return "N/A";
    final str = value.toString().trim();
    return str.isEmpty ? "N/A" : str;
  }

  String getInitials(String name) {
    if (name.isEmpty || name == "N/A") return "U";
    List<String> parts = name.trim().split(" ");
    return parts.map((e) => e[0]).take(2).join().toUpperCase();
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) return "N/A";
    try {
      final d = DateTime.parse(date);
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return "${months[d.month]} ${d.day}, ${d.year}";
    } catch (_) {
      return "N/A";
    }
  }

  String formatMonthYear(String? date) {
    if (date == null || date.isEmpty) return "N/A";
    try {
      final d = DateTime.parse(date);
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return "${months[d.month]} ${d.year}";
    } catch (_) {
      return "N/A";
    }
  }

  String getMemberSince(String? registeredDate) {
    if (registeredDate == null || registeredDate.isEmpty) return "N/A";
    try {
      final d = DateTime.parse(registeredDate);
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return "${months[d.month]} ${d.year}";
    } catch (_) {
      return "N/A";
    }
  }

  String getDaysSinceRegistration(String? registeredDate) {
    if (registeredDate == null || registeredDate.isEmpty) return "N/A";
    try {
      final registered = DateTime.parse(registeredDate);
      final now = DateTime.now();
      final difference = now.difference(registered);
      final days = difference.inDays;
      
      if (days == 0) return "Today";
      if (days == 1) return "1 day";
      return "$days days";
    } catch (_) {
      return "N/A";
    }
  }

  String getNextEligible(String? lastDonation) {
    if (lastDonation == null || lastDonation.isEmpty) return "N/A";
    try {
      final last = DateTime.parse(lastDonation);
      final next = DateTime(last.year, last.month + 3, last.day);
      return formatDate(next.toIso8601String());
    } catch (_) {
      return "N/A";
    }
  }

  String getFullAddress() {
    String street = safe(userData?["street"]);
    String barangay = safe(userData?["barangay"]);
    String city = safe(userData?["city"]);
    String province = safe(userData?["state"]);

    List parts = [street, barangay, city, province];
    parts = parts.where((e) => e != "N/A").toList();

    if (parts.isEmpty) return "N/A";
    return parts.join(", ");
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(child: Text(errorMessage!)),
      );
    }

    final name = safe(userData?["full_name"]);
    final email = safe(userData?["email"]);
    final bloodType = safe(userData?["blood_type"]);
    final totalDonations = userData?["total_donations"] ?? 0;
    final livesSaved = totalDonations * 3;
    final memberSince = getMemberSince(userData?["date_registered"]);
    final daysSinceRegistration = getDaysSinceRegistration(userData?["date_registered"]);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Color(0xFFDC2626), size: 18),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    // PROFILE HEADER CARD
                    FadeSlideIn(
                      index: 0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF1F1), Color(0xFFFFE4E4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Avatar
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: const Color(0xFFDC2626),
                                child: Text(
                                  getInitials(name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                              email,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 16),
                            // Badges
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _badge(
                                  label: "$bloodType Blood Type",
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                _badge(
                                  label: "🏆 Gold Donor",
                                  backgroundColor: const Color(0xFFF59E0B),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // STATS ROW
                    FadeSlideIn(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.water_drop,
                              iconColor: const Color(0xFFDC2626),
                              value: totalDonations.toString(),
                              label: "Donations",
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              icon: Icons.calendar_today,
                              iconColor: const Color(0xFF2563EB),
                              value: daysSinceRegistration,
                              label: "Days Active",
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              icon: Icons.emoji_events,
                              iconColor: const Color(0xFFD97706),
                              value: livesSaved.toString(),
                              label: "Lives Helped",
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // PERSONAL INFORMATION CARD
                    FadeSlideIn(
                      index: 2,
                      child: _sectionCard(
                        title: "Personal Information",
                        child: Column(
                          children: [
                            _infoTile(Icons.phone, "Phone Number", safe(userData?["phone"])),
                            _divider(),
                            _infoTile(Icons.location_on, "Address", getFullAddress()),
                            _divider(),
                            _infoTile(Icons.cake, "Date of Birth", formatDate(userData?["birthdate"])),
                            _divider(),
                            _infoTile(Icons.calendar_today, "Member Since", memberSince),
                            _divider(),
                            _infoTile(Icons.timer, "Days Active", daysSinceRegistration),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // DONATION STATUS CARD
                    FadeSlideIn(
                      index: 3,
                      child: _sectionCard(
                        title: "Donation Status",
                        child: Column(
                          children: [
                            _infoTile(Icons.water_drop, "Last Donation",
                                formatDate(userData?["last_donation"])),
                            _divider(),
                            _infoTile(
                              Icons.event_available,
                              "Next Eligible",
                              getNextEligible(userData?["last_donation"]),
                              valueColor: Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // DONATION HISTORY CHART
                    FadeSlideIn(
                      index: 4,
                      child: _sectionCard(
                        title: "Donation History",
                        child: SizedBox(
                          height: 180,
                          child: isChartLoading
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)))
                              : chartData.isEmpty
                                  ? const Center(
                                      child: Text("No donation data available.",
                                          style: TextStyle(color: Colors.grey)),
                                    )
                                  : LineChart(
                                      LineChartData(
                                        gridData: FlGridData(show: false),
                                        titlesData: FlTitlesData(show: false),
                                        borderData: FlBorderData(show: false),
                                        lineBarsData: [
                                          LineChartBarData(
                                            spots: chartData,
                                            isCurved: true,
                                            color: const Color(0xFFDC2626),
                                            barWidth: 3,
                                            dotData: FlDotData(show: true),
                                            belowBarData: BarAreaData(
                                              show: true,
                                              color: const Color(0xFFDC2626).withOpacity(0.1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // MENU ITEMS CARD
                    FadeSlideIn(
                      index: 5,
                      child: _sectionCard(
                        title: null,
                        child: Column(
                          children: [
                            _menuItem(Icons.edit, "Edit Profile"),
                            _divider(),
                            _menuItem(Icons.notifications, "Notification Settings"),
                            _divider(),
                            _menuItem(Icons.shield, "Privacy & Security"),
                            _divider(),
                            _menuItem(Icons.help_outline, "Help & Support"),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // LOGOUT BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout, color: Color(0xFFDC2626), size: 20),
                        label: const Text(
                          "Logout",
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Version 1.0.0",
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge({required String label, required Color backgroundColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String? title, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, title != null ? 8 : 8, 16, 8),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
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
                Text(label,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: valueColor ?? const Color(0xFF111827),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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

  Widget _divider() {
    return const Divider(height: 1, color: Color(0xFFF3F4F6));
  }
}