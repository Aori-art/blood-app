import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null) return;

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
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => isLoading = false);
    }
  }

  String getInitials(String name) {
    List<String> parts = name.split(" ");
    if (parts.length >= 2) {
      return parts[0][0] + parts[1][0];
    }
    return parts[0][0];
  }

  String formatDate(String? date) {
    if (date == null || date.isEmpty) return "N/A";
    DateTime dt = DateTime.parse(date);
    return "${dt.month}/${dt.day}/${dt.year}";
  }

  String getNextEligible(String? lastDonation) {
    if (lastDonation == null) return "N/A";
    DateTime last = DateTime.parse(lastDonation);
    DateTime next = DateTime(last.year, last.month + 3, last.day);
    return formatDate(next.toString());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = userData?["full_name"] ?? "N/A";
    final bloodType = userData?["blood_type"] ?? "N/A";
    final totalDonations = userData?["total_donations"] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: size.height * 0.02,
              ),
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
                                Text(name, style: const TextStyle(color: Colors.grey)),
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
                                const Text("Personal Information", style: TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: size.height * 0.01),

                                _infoRow("Full Name", name),
                                _infoRow("Email", userData?["email"] ?? ""),
                                _infoRow("Phone", userData?["phone"] ?? ""),
                                _infoRow("Birthdate", formatDate(userData?["birthdate"])),
                                _infoRow("Blood Type", bloodType),

                                SizedBox(height: size.height * 0.02),

                                const Text("Address Information", style: TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(height: size.height * 0.01),

                                _infoRow("Street", userData?["street"] ?? ""),
                                _infoRow("Barangay", userData?["barangay"] ?? ""),
                                _infoRow("City", userData?["city"] ?? ""),
                                _infoRow("Province", userData?["state"] ?? ""),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: size.height * 0.03),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(size.width * 0.04),
                      decoration: _cardStyle(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Donation Status",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF850000),
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: size.height * 0.02),

                          _infoRow("Last Donation", formatDate(userData?["last_donation"])),
                          _infoRow("Next Eligible", getNextEligible(userData?["last_donation"]), valueColor: Colors.green),
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

  Widget _infoRow(String label, String value, {Color valueColor = Colors.grey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
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
          Text(
            value,
            style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}