import 'package:flutter/material.dart';

class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key});

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

            // Header
            const Text(
              'Verification',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: screenHeight * 0.02),

            const Text(
              'Enter Verification Code',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),

            SizedBox(height: screenHeight * 0.01),

            const Text(
              "We've sent a 6-digit code to your email.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),

            SizedBox(height: screenHeight * 0.04),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.06,
                  vertical: screenHeight * 0.03,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Enter the 6-digit code',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: screenHeight * 0.03),

                    // OTP Boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: screenWidth * 0.12,
                          child: TextField(
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: const Color(0xFFFFF7C5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: screenHeight * 0.03),

                    const Text(
                      "Didn't receive the code?",
                      style: TextStyle(fontSize: 12),
                    ),

                    TextButton(
                      onPressed: () {
                        // TODO: Resend OTP logic
                      },
                      child: const Text(
                        'Resend OTP',
                        style: TextStyle(color: Color(0xFF850000)),
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.02),

                    // Verify Button
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF850000),
                        ),
                        onPressed: () {
                          // TODO: Verify OTP
                        },
                        child: const Text('Verify OTP'),
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.03),

                    // Security Notice
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Security Notice\nThis code is valid for 10 minutes. Never share this code with anyone.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Back Button
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF850000),
                          side: const BorderSide(color: Color(0xFF850000)),
                        ),
                        onPressed: () {
                          Navigator.pop(context); // ✅ Back works
                        },
                        child: const Text('Back'),
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