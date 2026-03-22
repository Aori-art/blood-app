import 'package:flutter/material.dart';

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: const Color(0xFF850000),
              child: const Center(
                child: Text(
                  'Book Appointment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Schedule Your Donation',
                      style: TextStyle(
                        color: Color(0xFF850000),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select your preferred date, time and location',
                      style: TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    // DATE BOX
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6E6E6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text("Calendar UI here (simplified)"),
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text("Donation Center"),
                    const SizedBox(height: 8),
                    _inputBox("Choose Donation Center"),

                    const SizedBox(height: 20),

                    const Text("Time Slot"),
                    const SizedBox(height: 8),
                    _inputBox("Choose Time Slot"),

                    const SizedBox(height: 30),

                    // BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF850000),
                        ),
                        onPressed: () {},
                        child: const Text("Confirm Booking"),
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

  Widget _inputBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }
}