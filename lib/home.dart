import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'alerts.dart';
import 'book.dart';
import 'check.dart';
import 'config.dart';
import 'history.dart';
import 'login.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeContent(),
    BookScreen(),
    CheckScreen(),
    HistoryScreen(),
    AlertsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF850000),
        unselectedItemColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Book',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle),
            label: 'Check',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  String userName = "User";
  String bloodType = "Loading...";
  int totalDonations = 0;
  String nextEligibleDate = "Loading...";
  String eligibilityStatus = "Loading...";
  bool isProfileLoading = true;
  bool isEligibilityLoading = true;

  @override
  void initState() {
    super.initState();
    loadUserName();
    loadProfileData();
    loadEligibilityData();
  }

  Future<void> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('userName') ?? 'User';

    if (mounted) {
      setState(() {
        userName = name;
      });
    }
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          bloodType = "N/A";
          totalDonations = 0;
          isProfileLoading = false;
        });
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_profile.php?donor_id=$donorId"),
      );

      debugPrint("Profile status: ${response.statusCode}");
      debugPrint("Profile body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] == "success") {
          if (mounted) {
            setState(() {
              bloodType = (data["blood_type"] ?? "N/A").toString();
              totalDonations =
                  int.tryParse(data["total_donations"].toString()) ?? 0;
              isProfileLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              bloodType = "N/A";
              totalDonations = 0;
              isProfileLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            bloodType = "N/A";
            totalDonations = 0;
            isProfileLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Profile error: $e");

      if (mounted) {
        setState(() {
          bloodType = "N/A";
          totalDonations = 0;
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

      debugPrint("Eligibility status: ${response.statusCode}");
      debugPrint("Eligibility body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] == "success") {
          if (mounted) {
            setState(() {
              nextEligibleDate =
                  formatDate(data["next_eligible_date"]?.toString() ?? "");
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
      } else {
        if (mounted) {
          setState(() {
            nextEligibleDate = "N/A";
            eligibilityStatus = "Unknown";
            isEligibilityLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Eligibility error: $e");

      if (mounted) {
        setState(() {
          nextEligibleDate = "N/A";
          eligibilityStatus = "Unknown";
          isEligibilityLoading = false;
        });
      }
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
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _handleMenuSelection(BuildContext context, String value) async {
    switch (value) {
      case 'profile':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile clicked')),
        );
        break;

      case 'settings':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings clicked')),
        );
        break;

      case 'logout':
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        if (!context.mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        break;
    }
  }

  Widget _actionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return SizedBox(
      height: 115,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => destination),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              left: screenWidth * 0.05,
              right: screenWidth * 0.05,
              bottom: screenHeight * 0.02,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome Back,',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                  ),
                  onSelected: (value) async {
                    await _handleMenuSelection(context, value);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'profile',
                      child: Text('Profile'),
                    ),
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Text('Logout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(screenWidth * 0.05),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black26),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your Blood Type'),
                              const SizedBox(height: 5),
                              Text(
                                isProfileLoading ? 'Loading...' : bloodType,
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF750000),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Total Donations'),
                              const SizedBox(height: 5),
                              Text(
                                isProfileLoading
                                    ? '...'
                                    : totalDonations.toString(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF750000),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black26),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Donation Eligibility',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Next Eligible Date: ${isEligibilityLoading ? "Loading..." : nextEligibleDate}',
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Status: ${isEligibilityLoading ? "Loading..." : eligibilityStatus}',
                            style: const TextStyle(
                              color: Color(0xFF750000),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF750000),
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const CheckScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Check Eligibility',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    Row(
                      children: [
                        Expanded(
                          child: _actionCard(
                            context: context,
                            title: 'Book\nAppointment',
                            subtitle: 'Schedule your donation',
                            destination: const BookScreen(),
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.04),
                        Expanded(
                          child: _actionCard(
                            context: context,
                            title: 'History',
                            subtitle: 'View past donations',
                            destination: const HistoryScreen(),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Upcoming Appointments',
                        style: TextStyle(
                          color: const Color(0xFF750000),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black26),
                        ],
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'December 20, 2026',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 5),
                          Text(
                            '10:00 AM',
                            style: TextStyle(color: Colors.red),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'City Blood bank, 123 Health St.',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Your Impact',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your $totalDonations donations have potentially saved up to ${totalDonations * 3} lives!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Thank you for being a hero in your community. Every donation makes a difference.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.green, fontSize: 11),
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