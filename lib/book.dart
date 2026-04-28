import 'package:flutter/material.dart';

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  DateTime? selectedDate;
  String? selectedCenter;
  String? selectedTime;

  final List<String> centers = [
    "Lipa City Hall"
  ];

  final List<String> timeSlots = [
    "8:00 AM - 9:00 AM",
    "9:00 AM - 10:00 AM",
    "10:00 AM - 11:00 AM",
    "1:00 PM - 2:00 PM",
    "2:00 PM - 3:00 PM",
  ];

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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

                    // ✅ DATE BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF850000)),
                        ),
                        onPressed: _pickDate,
                        child: Text(
                          selectedDate == null
                              ? "Select Date"
                              : "${selectedDate!.year}-${selectedDate!.month}-${selectedDate!.day}",
                          style: const TextStyle(
                            color: Color(0xFF850000),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text("Donation Center"),
                    const SizedBox(height: 8),

                    // ✅ DROPDOWN CENTER
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: DropdownButton<String>(
                        value: selectedCenter,
                        hint: const Text("Choose Donation Center"),
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: centers.map((center) {
                          return DropdownMenuItem(
                            value: center,
                            child: Text(center),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedCenter = value;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text("Time Slot"),
                    const SizedBox(height: 8),

                    // ✅ TIME SLOT DROPDOWN
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: DropdownButton<String>(
                        value: selectedTime,
                        hint: const Text("Choose Time Slot"),
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: timeSlots.map((time) {
                          return DropdownMenuItem(
                            value: time,
                            child: Text(time),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedTime = value;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ✅ CONFIRM BUTTON FIXED
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF850000),
                          foregroundColor: Colors.white, // FIX TEXT COLOR
                        ),
                        onPressed: () {
                          // TODO: Handle booking logic
                        },
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
}