import 'package:flutter/material.dart';
import 'register2.dart';

class RegisterStep3 extends StatelessWidget {
  const RegisterStep3({super.key});

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
              'Step 3 of 3: Set Password',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            SizedBox(height: screenHeight * 0.03),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.05,
                    vertical: screenHeight * 0.03),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Password'),
                      _buildTextField('Create Password'),
                      SizedBox(height: screenHeight * 0.02),
                      _buildFieldLabel('Confirm Password'),
                      _buildTextField('Confirm Password'),
                      SizedBox(height: screenHeight * 0.04),
                      Text(
                        'Password must contain:',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 5),
                      _buildRequirement('At least 8 characters'),
                      _buildRequirement('One uppercase letter'),
                      _buildRequirement('One number'),
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
                                side:
                                    const BorderSide(color: Color(0xFF850000)),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                              },
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
                              onPressed: () {
                                // TODO: Complete Registration
                                // e.g., submit form or navigate to home screen
                              },
                              child: const Text('Complete Registration'),
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
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildTextField(String hint) {
    return TextField(
      obscureText: true,
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

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 3),
      child: Row(
        children: [
          const Icon(Icons.check, size: 14, color: Colors.grey),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}