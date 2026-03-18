import 'package:flutter/material.dart';
import 'register2.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Step1(),
    );
  }
}

class Step1 extends StatelessWidget {
  const Step1({super.key});

  @override
  Widget build(BuildContext context) {
    // Get screen size
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
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
          SizedBox(height: screenHeight * 0.02),
          const Text(
            'Step 1 of 3: Personal Information',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: screenHeight * 0.04),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05,
                  vertical: screenHeight * 0.03),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Full Name'),
                    _buildTextField('Juan Dela Cruz'),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Email Address'),
                    _buildTextField('your.email@gmail.com'),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Phone Number'),
                    _buildTextField('0912 345 6789'),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Date of Birth'),
                    _buildTextField('dd/mm/yyyy'),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Gender'),
                    _buildTextField('Male / Female'),
                    SizedBox(height: screenHeight * 0.04),
                    Center(
                      child: SizedBox(
                        width: screenWidth * 0.5,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF850000),
                          ),
                          onPressed: () {
                            // Navigate to RegisterStep2
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterStep2(),
                              ),
                            );
                          },
                          child: const Text("Next"),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildTextField(String hint) {
    return TextField(
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