import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:blood/config.dart';
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
  final TextEditingController streetController = TextEditingController();

  final List<String> bloodTypes = const [
    'O+',
    'O-',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
  ];

  List<dynamic> provinces = [];
  List<dynamic> cities = [];
  List<dynamic> barangays = [];

  String? selectedBloodType;

  String? selectedProvinceCode;
  String? selectedProvinceName;

  String? selectedCityCode;
  String? selectedCityName;

  String? selectedBarangayCode;
  String? selectedBarangayName;

  bool isLoadingProvinces = true;
  bool isLoadingCities = false;
  bool isLoadingBarangays = false;

  @override
  void initState() {
    super.initState();
    loadProvinces();
  }

  @override
  void dispose() {
    streetController.dispose();
    super.dispose();
  }

  Future<void> loadProvinces() async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_provinces.php"),
      );

      final data = jsonDecode(response.body);

      if (data["status"] == "success") {
        setState(() {
          provinces = data["data"];
          isLoadingProvinces = false;
        });
      } else {
        setState(() {
          isLoadingProvinces = false;
        });
      }
    } catch (e) {
      debugPrint("Load provinces error: $e");
      setState(() {
        isLoadingProvinces = false;
      });
    }
  }

  Future<void> loadCities(String provinceCode) async {
    setState(() {
      isLoadingCities = true;
      cities = [];
      barangays = [];
      selectedCityCode = null;
      selectedCityName = null;
      selectedBarangayCode = null;
      selectedBarangayName = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          "${AppConfig.baseUrl}/get_cities.php?province_code=$provinceCode",
        ),
      );

      final data = jsonDecode(response.body);

      if (data["status"] == "success") {
        setState(() {
          cities = data["data"];
          isLoadingCities = false;
        });
      } else {
        setState(() {
          isLoadingCities = false;
        });
      }
    } catch (e) {
      debugPrint("Load cities error: $e");
      setState(() {
        isLoadingCities = false;
      });
    }
  }

  Future<void> loadBarangays(String cityCode) async {
    setState(() {
      isLoadingBarangays = true;
      barangays = [];
      selectedBarangayCode = null;
      selectedBarangayName = null;
    });

    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_barangays.php?city_code=$cityCode"),
      );

      final data = jsonDecode(response.body);

      if (data["status"] == "success") {
        setState(() {
          barangays = data["data"];
          isLoadingBarangays = false;
        });
      } else {
        setState(() {
          isLoadingBarangays = false;
        });
      }
    } catch (e) {
      debugPrint("Load barangays error: $e");
      setState(() {
        isLoadingBarangays = false;
      });
    }
  }

  void goNext() {
    if (selectedBloodType == null ||
        selectedBloodType!.isEmpty ||
        streetController.text.trim().isEmpty ||
        selectedProvinceName == null ||
        selectedCityName == null ||
        selectedBarangayName == null) {
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
          bloodType: selectedBloodType!,
          streetAddress: streetController.text.trim(),
          barangay: selectedBarangayName!,
          municipality: selectedCityName!,
          province: selectedProvinceName!,
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

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<dynamic> items,
    required void Function(String?) onChanged,
    bool isEnabled = true,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFD9D9D9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      hint: Text(hint),
      items: items.map<DropdownMenuItem<String>>((item) {
        return DropdownMenuItem<String>(
          value: item["code"].toString(),
          child: Text(
            item["name"].toString(),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: isEnabled ? onChanged : null,
    );
  }

  Widget _buildBloodTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedBloodType,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFD9D9D9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      hint: const Text('Select Blood Type'),
      items: bloodTypes.map((bloodType) {
        return DropdownMenuItem<String>(
          value: bloodType,
          child: Text(bloodType),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          selectedBloodType = value;
        });
      },
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
                      _buildBloodTypeDropdown(),
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
                                _buildFieldLabel('Province'),
                                isLoadingProvinces
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    : _buildDropdown(
                                        hint: 'Select Province',
                                        value: selectedProvinceCode,
                                        items: provinces,
                                        onChanged: (value) {
                                          if (value == null) return;

                                          final selectedItem = provinces.firstWhere(
                                            (item) =>
                                                item["code"].toString() == value,
                                          );

                                          setState(() {
                                            selectedProvinceCode = value;
                                            selectedProvinceName =
                                                selectedItem["name"].toString();
                                          });

                                          loadCities(value);
                                        },
                                      ),
                              ],
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.05),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Municipality'),
                                isLoadingCities
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    : _buildDropdown(
                                        hint: 'Select Municipality',
                                        value: selectedCityCode,
                                        items: cities,
                                        isEnabled: selectedProvinceCode != null,
                                        onChanged: (value) {
                                          if (value == null) return;

                                          final selectedItem = cities.firstWhere(
                                            (item) =>
                                                item["code"].toString() == value,
                                          );

                                          setState(() {
                                            selectedCityCode = value;
                                            selectedCityName =
                                                selectedItem["name"].toString();
                                          });

                                          loadBarangays(value);
                                        },
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: screenHeight * 0.02),

                      _buildFieldLabel('Barangay'),
                      isLoadingBarangays
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _buildDropdown(
                              hint: 'Select Barangay',
                              value: selectedBarangayCode,
                              items: barangays,
                              isEnabled: selectedCityCode != null,
                              onChanged: (value) {
                                if (value == null) return;

                                final selectedItem = barangays.firstWhere(
                                  (item) => item["code"].toString() == value,
                                );

                                setState(() {
                                  selectedBarangayCode = value;
                                  selectedBarangayName =
                                      selectedItem["name"].toString();
                                });
                              },
                            ),

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
                                side: const BorderSide(
                                  color: Color(0xFF850000),
                                ),
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
                                foregroundColor: Colors.white,
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
}