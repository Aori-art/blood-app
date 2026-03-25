import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:blood/config.dart';
import 'package:blood/login.dart';

class OtpScreen extends StatefulWidget {
  final String email;

  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> controllers =
      List.generate(6, (_) => TextEditingController());

  bool isVerifying = false;
  bool isResending = false;

  String get otpCode => controllers.map((c) => c.text).join();

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> verifyOtp() async {
    if (otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the 6-digit OTP.")),
      );
      return;
    }

    setState(() {
      isVerifying = true;
    });

    try {
      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/verify_otp.php"),
        body: {
          "email": widget.email,
          "otp": otpCode,
        },
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (data["status"] == "success") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["message"] ?? "OTP verified successfully.")),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["message"] ?? "Invalid OTP.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isVerifying = false;
        });
      }
    }
  }

  Future<void> resendOtp() async {
    setState(() {
      isResending = true;
    });

    try {
      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/resend_otp.php"),
        body: {
          "email": widget.email,
        },
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data["message"] ?? "OTP resend response received.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isResending = false;
        });
      }
    }
  }

  Widget _otpBox(int index, double screenWidth) {
    return SizedBox(
      width: screenWidth * 0.12,
      child: TextField(
        controller: controllers[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).nextFocus();
          }
        },
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
            Text(
              "We've sent a 6-digit code to ${widget.email}.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Enter the 6-digit code',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) => _otpBox(index, screenWidth)),
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    const Text(
                      "Didn't receive the code?",
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: isResending ? null : resendOtp,
                      child: Text(
                        isResending ? 'Resending...' : 'Resend OTP',
                        style: const TextStyle(color: Color(0xFF850000)),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF850000),
                        ),
                        onPressed: isVerifying ? null : verifyOtp,
                        child: isVerifying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify OTP'),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.03),
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
                    SizedBox(
                      width: double.infinity,
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