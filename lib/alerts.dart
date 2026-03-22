import 'package:flutter/material.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final alerts = [
      {
        "title": "Appointment Confirmed",
        "subtitle": "Your appointment on December 20, 2026 at 10:00 AM has been confirmed.",
        "date": "Today",
      },
      {
        "title": "Reminder: Blood Donation",
        "subtitle": "You are eligible to donate blood again. Book your appointment today!",
        "date": "Yesterday",
      },
      {
        "title": "Thank You!",
        "subtitle": "Thank you for your recent donation. You helped save lives!",
        "date": "September 15, 2025",
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: size.height * 0.02),
              color: const Color(0xFF850000),
              child: Column(
                children: const [
                  Text(
                    "Notification",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "2 unread",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // ALERT LIST
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    vertical: size.height * 0.02,
                    horizontal: size.width * 0.04),
                child: Column(
                  children: alerts.map((alert) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: size.height * 0.02),
                      child: Container(
                        padding: EdgeInsets.all(size.width * 0.04),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFF850000)),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 4,
                              color: Colors.black12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert["title"]!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              alert["subtitle"]!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF757575),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              alert["date"]!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF757575),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // MARK ALL READ BUTTON
            Padding(
              padding: EdgeInsets.symmetric(vertical: size.height * 0.01),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF850000)),
                ),
                onPressed: () {},
                child: const Text(
                  "Mark all as read",
                  style: TextStyle(color: Color(0xFF850000)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}