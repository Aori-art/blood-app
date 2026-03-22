import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
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

            // BODY (keep all existing content)
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
                                  child: const Text(
                                    "JD",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                SizedBox(height: size.height * 0.01),
                                const Text(
                                  "Jane Doe",
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: size.height * 0.01),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF850000),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    "Blood Type: O+",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                SizedBox(height: size.height * 0.02),

                                _statBox("Total Donation", "12",
                                    const Color(0xFF850000)),
                                SizedBox(height: size.height * 0.01),
                                _statBox("Lives Saved", "36",
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
                                const Text(
                                  "Personal Information",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: size.height * 0.01),

                                _infoRow("Full Name", "Jane Doe"),
                                _infoRow(
                                    "Email", "jane.doe@gmail.com"),
                                _infoRow("Phone", "09123456789"),
                                _infoRow("Birthdate",
                                    "January 1, 1001"),
                                _infoRow("Blood Type", "O+"),

                                SizedBox(height: size.height * 0.02),

                                const Text(
                                  "Address Information",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),

                                SizedBox(height: size.height * 0.01),

                                _infoRow("Street", "123 Main Street"),
                                _infoRow("City", "Lipa"),
                                _infoRow("State", "YN"),
                                _infoRow("Zip Code", "10101"),
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

                          _infoRow("Last Donation", "10/05/2026"),
                          _infoRow("Next Eligible", "12/01/2026",
                              valueColor: Colors.green),
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
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
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