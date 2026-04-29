import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? errorMessage;

  // ✅ NEW: chart state
  List<FlSpot> chartData = [];
  bool isChartLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
    fetchDonationHistory(); // ✅ NEW
  }

  Future<void> fetchUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    debugPrint("DONOR ID FROM PREFS: $donorId");

    if (donorId == null || donorId.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = "No donor ID found. Please log in again.";
      });
      return;
    }

    try {
      final uri = Uri.parse("${AppConfig.baseUrl}/get_profile.php?donor_id=$donorId");
      debugPrint("FETCHING: $uri");

      final response = await http.get(uri);

      debugPrint("STATUS CODE: ${response.statusCode}");
      debugPrint("RAW RESPONSE: ${response.body}");

      if (response.statusCode != 200) {
        setState(() {
          isLoading = false;
          errorMessage = "Server error: ${response.statusCode}";
        });
        return;
      }

      final data = jsonDecode(response.body);

      if (data["status"] == "success" && data["data"] != null) {
        setState(() {
          userData = data["data"];
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = data["message"] ?? "Failed to load profile.";
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      setState(() {
        isLoading = false;
        errorMessage = "An error occurred: $e";
      });
    }
  }

  // ✅ NEW: fetch donation history for graph
  Future<void> fetchDonationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      setState(() => isChartLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_donations_history.php?donor_id=$donorId"),
      );

      if (response.statusCode == 200) {
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
      } else {
        setState(() => isChartLoading = false);
      }
    } catch (e) {
      setState(() => isChartLoading = false);
    }
  }

  String safe(dynamic value) {
    if (value == null) return "N/A";
    final str = value.toString().trim();
    return str.isEmpty ? "N/A" : str;
  }

  String getInitials(String name) {
    if (name.isEmpty || name == "N/A") return "U";
    List<String> parts = name.trim().split(" ");
    String first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : "";
    String second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : "";
    return (first + second).toUpperCase();
  }

  String formatDate(String? date) {
    if (date == null || date.trim().isEmpty) return "N/A";
    try {
      DateTime dt = DateTime.parse(date);
      return "${dt.month}/${dt.day}/${dt.year}";
    } catch (e) {
      return "N/A";
    }
  }

  String getNextEligible(String? lastDonation) {
    if (lastDonation == null || lastDonation.trim().isEmpty) return "N/A";
    try {
      DateTime last = DateTime.parse(lastDonation);
      DateTime next = DateTime(last.year, last.month + 3, last.day);
      return formatDate(next.toIso8601String());
    } catch (e) {
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
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
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: size.height * 0.02),
              color: const Color(0xFF850000),
              child: const Center(
                child: Text(
                  "Donation History",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(size.width * 0.04),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF850000),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    "Blood Type: $bloodType",
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                SizedBox(height: size.height * 0.02),
                                _statBox("Total Donation",
                                    totalDonations.toString(),
                                    const Color(0xFF850000)),
                                SizedBox(height: size.height * 0.01),
                                _statBox(
                                    "Lives Saved",
                                    (totalDonations * 3).toString(),
                                    const Color(0xFF5E9831)),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(width: size.width * 0.04),

                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: EdgeInsets.all(size.width * 0.04),
                            decoration: _cardStyle(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Personal Information",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: size.height * 0.01),
                                _infoRow("Full Name", name),
                                _infoRow("Email", safe(userData?["email"])),
                                _infoRow("Phone", safe(userData?["phone"])),
                                _infoRow("Birthdate",
                                    formatDate(userData?["birthdate"])),
                                _infoRow("Blood Type", bloodType),
                                SizedBox(height: size.height * 0.02),
                                const Text("Address Information",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: size.height * 0.01),
                                _infoRow("Street", safe(userData?["street"])),
                                _infoRow(
                                    "Barangay", safe(userData?["barangay"])),
                                _infoRow("City", safe(userData?["city"])),
                                _infoRow("Province", safe(userData?["state"])),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: size.height * 0.03),

                    // ✅ NEW GRAPH SECTION
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(size.width * 0.04),
                      decoration: _cardStyle(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Donation Trend",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF850000),
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: size.height * 0.02),

                          if (isChartLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (chartData.isEmpty)
                            const Center(
                              child: Text(
                                "No donation history yet.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            SizedBox(
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
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: const Color(0xFF850000)
                                            .withOpacity(0.1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.03),

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
                          _infoRow("Last Donation",
                              formatDate(userData?["last_donation"])),
                          _infoRow(
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
        BoxShadow(
          blurRadius: 4,
          color: Colors.black12,
          offset: Offset(0, 4),
        )
      ],
    );
  }

  Widget _infoRow(String label, String value,
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
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
                fontSize: 18, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}