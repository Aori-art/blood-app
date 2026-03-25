import 'package:flutter/material.dart';
import 'register2.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController birthdateController = TextEditingController();
  final TextEditingController genderController = TextEditingController();

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    birthdateController.dispose();
    genderController.dispose();
    super.dispose();
  }

  void goNext() {
    if (fullNameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        birthdateController.text.trim().isEmpty ||
        genderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterStep2(
          fullName: fullNameController.text.trim(),
          email: emailController.text.trim(),
          phone: phoneController.text.trim(),
          birthdate: birthdateController.text.trim(),
          gender: genderController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Step1(
        fullNameController: fullNameController,
        emailController: emailController,
        phoneController: phoneController,
        birthdateController: birthdateController,
        genderController: genderController,
        onNext: goNext,
      ),
    );
  }
}

class Step1 extends StatelessWidget {
  final TextEditingController fullNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController birthdateController;
  final TextEditingController genderController;
  final VoidCallback onNext;

  const Step1({
    super.key,
    required this.fullNameController,
    required this.emailController,
    required this.phoneController,
    required this.birthdateController,
    required this.genderController,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
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
                    _buildFieldLabel('Full Name'),
                    _buildTextField('Juan Dela Cruz', fullNameController),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Email Address'),
                    _buildTextField('your.email@gmail.com', emailController),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Phone Number'),
                    _buildTextField('0912 345 6789', phoneController),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Date of Birth'),
                    _buildTextField('yyyy-mm-dd', birthdateController),
                    SizedBox(height: screenHeight * 0.02),
                    _buildFieldLabel('Gender'),
                    _buildTextField('Male / Female', genderController),
                    SizedBox(height: screenHeight * 0.04),
                    Center(
                      child: SizedBox(
                        width: screenWidth * 0.5,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF850000),
                          ),
                          onPressed: onNext,
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
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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