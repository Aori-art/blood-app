import 'package:flutter/material.dart';
import 'book.dart';
import 'check.dart';
import 'history.dart';
import 'alerts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // List of your 5 screens
  final List<Widget> _screens = [
    const HomeContent(),  // Your home page content
    const BookScreen(),
    const CheckScreen(),
    const HistoryScreen(),
    const AlertsScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Book'),
          BottomNavigationBarItem(icon: Icon(Icons.check_circle), label: 'Check'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
        ],
      ),
    );
  }
}

// Your original HomeContent widget (renamed from HomeScreen)
class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome Back,', style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 5),
                Text('Jane Doe', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(screenWidth * 0.05),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Your Blood Type'),
                          SizedBox(height: 5),
                          Text('O+', style: TextStyle(fontSize: 18, color: Color(0xFF750000), fontWeight: FontWeight.bold)),
                        ]),
                        Column(children: [
                          Text('Total Donations'),
                          SizedBox(height: 5),
                          Text('12', style: TextStyle(fontSize: 18, color: Color(0xFF750000), fontWeight: FontWeight.bold)),
                        ])
                      ],
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Donation Eligibility', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const Text('Next Eligible Date: December 1, 2026'),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF750000)),
                          onPressed: () {},
                          child: const Text('Check Eligibility'),
                        ),
                      ),
                    ]),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Row(children: [
                    Expanded(child: _actionCard('Book\nAppointment', 'Schedule your donation')),
                    SizedBox(width: screenWidth * 0.04),
                    Expanded(child: _actionCard('History', 'View past donations')),
                  ]),
                  SizedBox(height: screenHeight * 0.02),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Upcoming Appointments',
                      style: TextStyle(color: const Color(0xFF750000), fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('December 20, 2026', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 5),
                        Text('10:00 AM', style: TextStyle(color: Colors.red)),
                        SizedBox(height: 5),
                        Text('City Blood bank, 123 Health St.', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF750000), Color(0xFFFF4E4E)]),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Column(children: [
                      Text('Your Impact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10),
                      Text(
                        'Your 12 donations have potentially saved up to 36 lives!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ]),
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
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Column(children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}