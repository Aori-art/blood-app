import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'register2.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController middleInitialController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController suffixController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController birthdateController = TextEditingController();

  String? selectedGender;

  @override
  void dispose() {
    firstNameController.dispose();
    middleInitialController.dispose();
    lastNameController.dispose();
    suffixController.dispose();
    emailController.dispose();
    phoneController.dispose();
    birthdateController.dispose();
    super.dispose();
  }

  void goNext() {
    final firstName = firstNameController.text.trim();
    final middleInitial = middleInitialController.text.trim();
    final lastName = lastNameController.text.trim();
    final suffix = suffixController.text.trim();
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final birthdate = birthdateController.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        birthdate.isEmpty ||
        selectedGender == null ||
        selectedGender!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all required fields.")),
      );
      return;
    }

    if (!phone.startsWith('09') || phone.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Phone number must be 11 digits and start with 09."),
        ),
      );
      return;
    }

    final fullName = [
      firstName,
      if (middleInitial.isNotEmpty) middleInitial,
      lastName,
      if (suffix.isNotEmpty) suffix,
    ].join(' ');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterStep2(
          fullName: fullName,
          email: email,
          phone: phone,
          birthdate: birthdate,
          gender: selectedGender!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Step1(
        firstNameController: firstNameController,
        middleInitialController: middleInitialController,
        lastNameController: lastNameController,
        suffixController: suffixController,
        emailController: emailController,
        phoneController: phoneController,
        birthdateController: birthdateController,
        selectedGender: selectedGender,
        onGenderChanged: (value) {
          setState(() {
            selectedGender = value;
          });
        },
        onNext: goNext,
      ),
    );
  }
}

class Step1 extends StatelessWidget {
  final TextEditingController firstNameController;
  final TextEditingController middleInitialController;
  final TextEditingController lastNameController;
  final TextEditingController suffixController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController birthdateController;
  final String? selectedGender;
  final ValueChanged<String?> onGenderChanged;
  final VoidCallback onNext;

  const Step1({
    super.key,
    required this.firstNameController,
    required this.middleInitialController,
    required this.lastNameController,
    required this.suffixController,
    required this.emailController,
    required this.phoneController,
    required this.birthdateController,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.onNext,
  });

  Future<void> _selectBirthdate(BuildContext context) async {
    DateTime initialDate = DateTime(2004, 1, 1);

    if (birthdateController.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(birthdateController.text);
      } catch (_) {}
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      final formattedDate =
          "${pickedDate.year.toString().padLeft(4, '0')}-"
          "${pickedDate.month.toString().padLeft(2, '0')}-"
          "${pickedDate.day.toString().padLeft(2, '0')}";

      birthdateController.text = formattedDate;
    }
  }

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
                    _buildFieldLabel('First Name'),
                    _buildTextField('Juan', firstNameController),
                    SizedBox(height: screenHeight * 0.02),

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('Middle Initial'),
                              _buildTextField('D.', middleInitialController),
                            ],
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.04),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('Suffix'),
                              _buildTextField('Jr. (optional)', suffixController),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: screenHeight * 0.02),

                    _buildFieldLabel('Last Name'),
                    _buildTextField('Dela Cruz', lastNameController),
                    SizedBox(height: screenHeight * 0.02),

                    _buildFieldLabel('Email Address'),
                    _buildTextField(
                      'your.email@gmail.com',
                      emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: screenHeight * 0.02),

                    _buildFieldLabel('Phone Number'),
                    _buildTextField(
                      '09XXXXXXXXX',
                      phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Note: Enter an 11-digit mobile number that starts with 09.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),

                    _buildFieldLabel('Date of Birth'),
                    _buildDateField(
                      context,
                      'Select your birthdate',
                      birthdateController,
                    ),
                    SizedBox(height: screenHeight * 0.02),

                    _buildFieldLabel('Gender'),
                    _buildGenderDropdown(),
                    SizedBox(height: screenHeight * 0.04),

                    Center(
                      child: SizedBox(
                        width: screenWidth * 0.5,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF850000),
                            foregroundColor: Colors.white,
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
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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

  Widget _buildDateField(
    BuildContext context,
    String hint,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _selectBirthdate(context),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFD9D9D9),
        suffixIcon: const Icon(Icons.calendar_today),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedGender,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: 'Select Gender',
        filled: true,
        fillColor: const Color(0xFFD9D9D9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      items: const [
        DropdownMenuItem(
          value: 'Male',
          child: Text('Male'),
        ),
        DropdownMenuItem(
          value: 'Female',
          child: Text('Female'),
        ),
        DropdownMenuItem(
          value: 'Non-binary',
          child: Text('Non-binary'),
        ),
        DropdownMenuItem(
          value: 'Prefer not to say',
          child: Text('Prefer not to say'),
        ),
      ],
      onChanged: onGenderChanged,
    );
  }
}