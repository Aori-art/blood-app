import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'config.dart';

class DonationHistoryScreen extends StatefulWidget {
  const DonationHistoryScreen({super.key});

  @override
  State<DonationHistoryScreen> createState() =>
      _DonationHistoryScreenState();
}

class _DonationHistoryScreenState extends State<DonationHistoryScreen> {
  List donations = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDonationHistory();
  }

  Future<void> fetchDonationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
            "${AppConfig.baseUrl}/get_donation_history.php?donor_id=$donorId"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] == "success") {
          setState(() {
            donations = data["data"];
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => isLoading = true);
    await fetchDonationHistory();
  }

  String formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return "${months[d.month - 1]} ${d.day}, ${d.year}";
    } catch (e) {
      return date;
    }
  }

  int getTotalUnits() {
    int total = 0;
    for (var d in donations) {
      total += int.tryParse(d["blood_units"].toString()) ?? 0;
    }
    return total;
  }

  Widget summaryItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.red),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget buildCard(Map item, int index) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.red.shade100,
                      child: const Icon(Icons.water_drop,
                          color: Colors.red),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Donation #${donations.length - index}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatDate(item["donation_date"] ?? ""),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      "${item["blood_units"] ?? 0} unit(s)",
                      style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item["remarks"] ?? "No remarks",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            const Divider(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "Completed",
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  "Helped save lives!",
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 🔥 HEADER (IMPROVED)
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              bottom: screenHeight * 0.03,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
              ),
            ),
            child: Column(
              children: const [
                Text(
                  "Donation History",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  "Your journey of saving lives",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // 🔥 CONTENT
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFDC2626),
                        ),
                      )
                    : donations.isEmpty
                        ? Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOut,
                              builder: (_, v, child) => Opacity(
                                opacity: v,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - v) * 12),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.water_drop_outlined,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "No donation history found.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              // 🔥 SUMMARY CARD
                              FadeSlideIn(
                                index: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  margin:
                                      const EdgeInsets.only(bottom: 15),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFEBEE),
                                        Color(0xFFFFCDD2)
                                      ],
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      summaryItem(
                                          Icons.water_drop,
                                          donations.length.toString(),
                                          "Donations"),
                                      summaryItem(
                                          Icons.trending_up,
                                          "${getTotalUnits()}",
                                          "Units"),
                                      summaryItem(
                                          Icons.calendar_today,
                                          "Active",
                                          "Status"),
                                    ],
                                  ),
                                ),
                              ),

                              // 🔥 LIST
                              Expanded(
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: donations.length,
                                  itemBuilder: (context, index) {
                                    return FadeSlideIn(
                                      index: index + 1,
                                      child: buildCard(
                                          donations[index], index),
                                    );
                                  },
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
}