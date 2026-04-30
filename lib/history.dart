import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../config.dart';
import '../login.dart';

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
      return "${d.month}/${d.day}/${d.year}";
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(child: Text(errorMessage!)),
      );
    }

    final name = safe(userData?["full_name"]);
    final bloodType = safe(userData?["blood_type"]);
    final totalDonations = userData?["total_donations"] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER WITH BACK BUTTON
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: size.height * 0.06,
                bottom: size.height * 0.025,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 10,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Text(
                        "My Profile",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(size.width * 0.04),
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // LEFT PANEL
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.all(size.width * 0.04),
                              decoration: _cardStyle(),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: size.width * 0.08,
                                    backgroundColor: const Color(0xFF850000),
                                    child: Text(
                                      getInitials(name),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  SizedBox(height: size.height * 0.01),
                                  Text(name,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.grey)),

                                  SizedBox(height: size.height * 0.01),

                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF850000),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "Blood Type: $bloodType",
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),

                                  SizedBox(height: size.height * 0.02),

                                  _statBox("Total Donation", totalDonations.toString(), const Color(0xFF850000)),
                                  SizedBox(height: size.height * 0.01),
                                  _statBox("Lives Saved", (totalDonations * 3).toString(), const Color(0xFF5E9831)),

                                  SizedBox(height: size.height * 0.02),

                                  // LOGOUT BUTTON
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF850000),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: _handleLogout,
                                      child: const Text(
                                        "Logout",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: size.width * 0.04),

                          // RIGHT PANEL - Stretched to match left container height
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: EdgeInsets.all(size.width * 0.04),
                              decoration: _cardStyle(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("Personal Information", style: TextStyle(fontWeight: FontWeight.bold)),
                                  _infoRow("Full Name", name),
                                  _infoRow("Email", safe(userData?["email"])),
                                  _infoRow("Phone", safe(userData?["phone"])),
                                  _infoRow("Birthdate", formatDate(userData?["birthdate"])),

                                  const SizedBox(height: 10),

                                  const Text("Address Information", style: TextStyle(fontWeight: FontWeight.bold)),
                                  _infoRow("Street", safe(userData?["street"])),
                                  _infoRow("Barangay", safe(userData?["barangay"])),
                                  _infoRow("City", safe(userData?["city"])),
                                  _infoRow("Province", safe(userData?["state"])),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.03),

                    // GRAPH
                    Container(
                      padding: EdgeInsets.all(size.width * 0.04),
                      decoration: _cardStyle(),
                      child: isChartLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              height: 200,
                              child: LineChart(
                                LineChartData(
                                  gridData: FlGridData(show: false),
                                  titlesData: FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: chartData,
                                      isCurved: true,
                                      color: const Color(0xFF850000),
                                      barWidth: 3,
                                      dotData: FlDotData(show: true),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),

                    SizedBox(height: size.height * 0.03),

                    // DONATION STATUS CARD
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(size.width * 0.04),
                      decoration: _cardStyle(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Donation Status",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF850000),
                                  fontSize: 16)),
                          SizedBox(height: size.height * 0.02),
                          _infoRowWithColor("Last Donation",
                              formatDate(userData?["last_donation"])),
                          _infoRowWithColor(
                            "Next Eligible",
                            getNextEligible(userData?["last_donation"]),
                            valueColor: Colors.green,
                          ),
                        ],
                      ),
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

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 4)),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _infoRowWithColor(String label, String value,
      {Color valueColor = Colors.grey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String title, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}