// register2.dart
// Place at: lib/screens/register/register2.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:blood/config.dart';
import 'package:blood/shared_design.dart';
import 'register3.dart';

class RegisterStep2 extends StatefulWidget {
  final String fullName;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String suffix;
  final String email;
  final String phone;
  final String birthdate;
  final String gender;

  const RegisterStep2({
    super.key,
    required this.fullName,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.suffix,
    required this.email,
    required this.phone,
    required this.birthdate,
    required this.gender,
  });

  @override
  State<RegisterStep2> createState() => _RegisterStep2State();
}

class _RegisterStep2State extends State<RegisterStep2> {
  final _streetCtrl = TextEditingController();

  static const _bloodTypes = [
    'O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'
  ];

  List<dynamic> _provinces  = [];
  List<dynamic> _cities     = [];
  List<dynamic> _barangays  = [];

  String? _bloodType;
  String? _provinceCode, _provinceName;
  String? _cityCode, _cityName;
  String? _barangayCode, _barangayName;

  bool _loadingProvinces = true;
  bool _loadingCities    = false;
  bool _loadingBarangays = false;

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProvinces() async {
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.baseUrl}/get_provinces.php'));
      final data = jsonDecode(res.body);
      setState(() {
        if (data['status'] == 'success') _provinces = data['data'];
        _loadingProvinces = false;
      });
    } catch (_) {
      setState(() => _loadingProvinces = false);
    }
  }

  Future<void> _loadCities(String provinceCode) async {
    setState(() {
      _loadingCities = true;
      _cities = _barangays = [];
      _cityCode = _cityName = _barangayCode = _barangayName = null;
    });
    try {
      final res = await http.get(Uri.parse(
          '${AppConfig.baseUrl}/get_cities.php?province_code=$provinceCode'));
      final data = jsonDecode(res.body);
      setState(() {
        if (data['status'] == 'success') _cities = data['data'];
        _loadingCities = false;
      });
    } catch (_) {
      setState(() => _loadingCities = false);
    }
  }

  Future<void> _loadBarangays(String cityCode) async {
    setState(() {
      _loadingBarangays = true;
      _barangays = [];
      _barangayCode = _barangayName = null;
    });
    try {
      final res = await http.get(Uri.parse(
          '${AppConfig.baseUrl}/get_barangays.php?city_code=$cityCode'));
      final data = jsonDecode(res.body);
      setState(() {
        if (data['status'] == 'success') _barangays = data['data'];
        _loadingBarangays = false;
      });
    } catch (_) {
      setState(() => _loadingBarangays = false);
    }
  }

  void _goNext() {
    if (_bloodType == null ||
        _streetCtrl.text.trim().isEmpty ||
        _provinceName == null ||
        _cityName == null ||
        _barangayName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterStep3(
          fullName: widget.fullName,
          firstName: widget.firstName,
          middleInitial: widget.middleInitial,
          lastName: widget.lastName,
          suffix: widget.suffix,
          email: widget.email,
          phone: widget.phone,
          birthdate: widget.birthdate,
          gender: widget.gender,
          bloodType: _bloodType!,
          streetAddress: _streetCtrl.text.trim(),
          barangay: _barangayName!,
          municipality: _cityName!,
          province: _provinceName!,
        ),
      ),
    );
  }

  Widget _loadingBox() => Container(
        height: 52,
        decoration: BoxDecoration(
            color: kInputFill,
            borderRadius: BorderRadius.circular(14)),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: kCrimson),
          ),
        ),
      );

  Widget _locationDropdown({
    required bool loading,
    required String hint,
    required String? value,
    required List<dynamic> items,
    required bool enabled,
    required void Function(String?) onChanged,
  }) {
    if (loading) return _loadingBox();
    return AppDropdown<String>(
      value: value,
      hint: hint,
      onChanged: enabled ? onChanged : null,
      items: items.map<DropdownMenuItem<String>>((item) {
        return DropdownMenuItem<String>(
          value: item['code'].toString(),
          child: Text(item['name'].toString(),
              overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientScreen(
        child: Column(
          children: [
            RegisterHeader(
              step: 2,
              subtitle: 'Step 2 of 3 · Medical & Address',
            ),
            Expanded(
              child: RegisterCard(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle('Medical Info'),
                      const SizedBox(height: 16),

                      FieldLabel('Blood Type'),
                      AppDropdown<String>(
                        value: _bloodType,
                        hint: 'Select Blood Type',
                        onChanged: (v) => setState(() => _bloodType = v),
                        items: _bloodTypes
                            .map((t) => DropdownMenuItem(
                                value: t, child: Text(t)))
                            .toList(),
                      ),
                      const SizedBox(height: 24),

                      SectionTitle('Address'),
                      const SizedBox(height: 16),

                      FieldLabel('Street Address'),
                      AppTextField(
                        controller: _streetCtrl,
                        hint: '123 Main Street',
                        prefixIcon: Icons.home_outlined,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel('Province'),
                                _loadingProvinces
                                    ? _loadingBox()
                                    : _locationDropdown(
                                        loading: false,
                                        hint: 'Province',
                                        value: _provinceCode,
                                        items: _provinces,
                                        enabled: true,
                                        onChanged: (v) {
                                          if (v == null) return;
                                          final item =
                                              _provinces.firstWhere(
                                                  (e) =>
                                                      e['code'].toString() ==
                                                      v);
                                          setState(() {
                                            _provinceCode = v;
                                            _provinceName =
                                                item['name'].toString();
                                          });
                                          _loadCities(v);
                                        },
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel('Municipality'),
                                _locationDropdown(
                                  loading: _loadingCities,
                                  hint: 'Municipality',
                                  value: _cityCode,
                                  items: _cities,
                                  enabled: _provinceCode != null,
                                  onChanged: (v) {
                                    if (v == null) return;
                                    final item = _cities.firstWhere(
                                        (e) =>
                                            e['code'].toString() == v);
                                    setState(() {
                                      _cityCode = v;
                                      _cityName = item['name'].toString();
                                    });
                                    _loadBarangays(v);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Barangay'),
                      _locationDropdown(
                        loading: _loadingBarangays,
                        hint: 'Select Barangay',
                        value: _barangayCode,
                        items: _barangays,
                        enabled: _cityCode != null,
                        onChanged: (v) {
                          if (v == null) return;
                          final item = _barangays.firstWhere(
                              (e) => e['code'].toString() == v);
                          setState(() {
                            _barangayCode = v;
                            _barangayName = item['name'].toString();
                          });
                        },
                      ),

                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(
                            child: OutlineBtn(
                              label: 'Back',
                              onTap: () => Navigator.pop(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PrimaryButton(
                              label: 'Continue',
                              onTap: _goNext,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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