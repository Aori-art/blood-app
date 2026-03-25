import 'package:flutter/material.dart';
import 'register3.dart';

class RegisterStep2 extends StatefulWidget {
  final String fullName;
  final String email;
  final String phone;
  final String birthdate;
  final String gender;

  const RegisterStep2({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.birthdate,
    required this.gender,
  });

  @override
  State<RegisterStep2> createState() => _RegisterStep2State();
}

class _RegisterStep2State extends State<RegisterStep2> {
  final TextEditingController bloodTypeController = TextEditingController();
  final TextEditingController streetController = TextEditingController();
  final TextEditingController barangayController = TextEditingController();
  final TextEditingController municipalityController = TextEditingController();
  final TextEditingController provinceController = TextEditingController();

  @override
  void dispose() {
    bloodTypeController.dispose();
    streetController.dispose();
    barangayController.dispose();
    municipalityController.dispose();
    provinceController.dispose();
    super.dispose();
  }

  void goNext() {
    if (bloodTypeController.text.trim().isEmpty ||
        streetController.text.trim().isEmpty ||
        barangayController.text.trim().isEmpty ||
        municipalityController.text.trim().isEmpty ||
        provinceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterStep3(
          fullName: widget.fullName,
          email: widget.email,
          phone: widget.phone,
          birthdate: widget.birthdate,
          gender: widget.gender,
          bloodType: bloodTypeController.text.trim(),
          streetAddress: streetController.text.trim(),
          barangay: barangayController.text.trim(),
          municipality: municipalityController.text.trim(),
          province: provinceController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        color: const Color(0xFFAE0000),
        child: Column(
          children: [
            SizedBox(height: screenHeight * 0.08),
            const Text(
              'eDonate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            const Text(
              'Blood Donation App',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: screenHeight * 0.02),
            const Text(
              'Step 2 of 3: Medical and Address',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            SizedBox(height: screenHeight * 0.03),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05,
                  vertical: screenHeight * 0.03,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Blood Type'),
                      _buildTextField('O+, A+, B+, AB+', bloodTypeController),
                      SizedBox(height: screenHeight * 0.02),
                      _buildFieldLabel('Street Address'),
                      _buildTextField('123 Main Street', streetController),
                      SizedBox(height: screenHeight * 0.02),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Barangay'),
                                _buildTextField('Balintawak', barangayController),
                              ],
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.05),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Municipality'),
                                _buildTextField('Lipa', municipalityController),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      _buildFieldLabel('Province'),
                      _buildTextField('Batangas', provinceController),
                      SizedBox(height: screenHeight * 0.04),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: screenWidth * 0.35,
                            height: 45,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF850000),
                                side: const BorderSide(color: Color(0xFF850000)),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Back'),
                            ),
                          ),
                          SizedBox(
                            width: screenWidth * 0.35,
                            height: 45,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF850000),
                              ),
                              onPressed: goNext,
                              child: const Text('Next'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.02),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFD9D9D9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }
}