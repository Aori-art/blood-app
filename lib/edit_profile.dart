import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'profile_page_widgets.dart';
import 'shared_design.dart';

class _Location {
  final String code;
  final String name;
  const _Location(this.code, this.name);
  factory _Location.fromJson(Map json) =>
      _Location(json['code']?.toString() ?? '', json['name']?.toString() ?? '');
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final formKey = GlobalKey<FormState>();
  final first = TextEditingController(),
      middle = TextEditingController(),
      last = TextEditingController(),
      suffix = TextEditingController(),
      phone = TextEditingController(),
      street = TextEditingController();
  List<_Location> provinces = [], cities = [], barangays = [];
  String? donorId,
      provinceCode,
      provinceName,
      cityCode,
      cityName,
      barangayCode,
      barangayName;
  String email = 'N/A', bloodType = 'N/A', birthdate = 'N/A';
  String? nextEdit;
  bool loading = true,
      saving = false,
      online = true,
      canEdit = true,
      loadingProvinces = false,
      loadingCities = false,
      loadingBarangays = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    first.dispose();
    middle.dispose();
    last.dispose();
    suffix.dispose();
    phone.dispose();
    street.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    donorId = prefs.getString('donorId');
    if (donorId == null || donorId!.isEmpty) {
      if (mounted) setState(() => loading = false);
      return;
    }
    Map<String, dynamic>? cached;
    final raw = prefs.getString('cached_profile_' + donorId!);
    if (raw != null) {
      try {
        cached = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _fill(cached);
      } catch (_) {}
    }
    if (mounted) setState(() => loading = cached == null);
    try {
      final res = await http
          .get(
            Uri.parse(
              AppConfig.baseUrl + '/get_profile.php?donor_id=' + donorId!,
            ),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 &&
          body is Map &&
          body['status'] == 'success' &&
          body['data'] is Map) {
        final data = Map<String, dynamic>.from(body['data'] as Map);
        await prefs.setString('cached_profile_' + donorId!, jsonEncode(data));
        _fill(data);
      } else {
        online = false;
      }
    } catch (_) {
      online = false;
    }
    if (!mounted) return;
    setState(() => loading = false);
    _loadProvinces();
  }

  void _fill(Map<String, dynamic> data) {
    first.text = _text(data['first_name']);
    middle.text = _text(data['middle_initial']);
    last.text = _text(data['last_name']);
    suffix.text = _text(data['suffix']);
    phone.text = _text(data['phone'] ?? data['contact_number']);
    street.text = _text(data['street'] ?? data['street_address']);
    provinceCode = _nullable(data['province_code']);
    provinceName = _nullable(data['state'] ?? data['province']);
    cityCode = _nullable(data['city_code']);
    cityName = _nullable(data['city'] ?? data['municipality']);
    barangayCode = _nullable(data['barangay_code']);
    barangayName = _nullable(data['barangay']);
    email = _text(data['email']);
    bloodType = _text(data['blood_type']);
    birthdate = _text(data['birthdate']);
    canEdit =
        data['can_edit_profile'] != false &&
        data['can_edit_profile'] != 0 &&
        data['can_edit_profile'] != 'false';
    nextEdit = _nullable(data['next_profile_edit_at']);
  }

  String _text(dynamic value) => value == null ? '' : value.toString();
  String? _nullable(dynamic value) {
    final text = _text(value).trim();
    return text.isEmpty ? null : text;
  }

  void snack(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<_Location> _items(dynamic data) => data is List
      ? data
            .whereType<Map>()
            .map(_Location.fromJson)
            .where((x) => x.code.isNotEmpty && x.name.isNotEmpty)
            .toList()
      : [];

  Future<void> _loadProvinces() async {
    setState(() => loadingProvinces = true);
    try {
      final r = await http
          .get(Uri.parse(AppConfig.baseUrl + '/get_provinces.php'))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(r.body);
      if (mounted)
        setState(() {
          provinces = body is Map && body['status'] == 'success'
              ? _items(body['data'])
              : [];
          loadingProvinces = false;
        });
      if (provinceCode != null) _loadCities(provinceCode!, preserve: true);
    } catch (_) {
      if (mounted) setState(() => loadingProvinces = false);
    }
  }

  Future<void> _loadCities(String code, {bool preserve = false}) async {
    if (mounted)
      setState(() {
        loadingCities = true;
        if (!preserve) {
          cities = [];
          barangays = [];
          cityCode = cityName = barangayCode = barangayName = null;
        }
      });
    try {
      final uri = Uri.parse(
        AppConfig.baseUrl + '/get_cities.php',
      ).replace(queryParameters: {'province_code': code});
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(r.body);
      if (mounted)
        setState(() {
          cities = body is Map && body['status'] == 'success'
              ? _items(body['data'])
              : [];
          loadingCities = false;
        });
      if (cityCode != null)
        _loadBarangays(cityCode!, cityName ?? '', preserve: true);
    } catch (_) {
      if (mounted) setState(() => loadingCities = false);
    }
  }

  Future<void> _loadBarangays(
    String code,
    String name, {
    bool preserve = false,
  }) async {
    if (mounted)
      setState(() {
        loadingBarangays = true;
        if (!preserve) {
          barangays = [];
          barangayCode = barangayName = null;
        }
      });
    try {
      final uri = Uri.parse(
        AppConfig.baseUrl + '/get_barangays.php',
      ).replace(queryParameters: {'city_code': code, 'city_name': name});
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = jsonDecode(r.body);
      if (mounted)
        setState(() {
          barangays = body is Map && body['status'] == 'success'
              ? _items(body['data'])
              : [];
          loadingBarangays = false;
        });
    } catch (_) {
      if (mounted) setState(() => loadingBarangays = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!online) {
      snack('Internet connection is required to update your profile.');
      return;
    }
    if (!canEdit || saving || !(formKey.currentState?.validate() ?? false))
      return;
    if (provinceCode == null ||
        cityCode == null ||
        barangayCode == null ||
        provinceName == null ||
        cityName == null ||
        barangayName == null) {
      snack('Please complete your address.');
      return;
    }
    setState(() => saving = true);
    try {
      final data = {
        'donor_id': int.tryParse(donorId!) ?? donorId!,
        'first_name': first.text.trim(),
        'middle_initial': middle.text.trim(),
        'last_name': last.text.trim(),
        'suffix': suffix.text.trim(),
        'contact_number': phone.text.trim(),
        'street_address': street.text.trim(),
        'province': provinceName,
        'province_code': provinceCode,
        'municipality': cityName,
        'city_code': cityCode,
        'barangay': barangayName,
        'barangay_code': barangayCode,
      };
      final r = await http
          .post(
            Uri.parse(AppConfig.baseUrl + '/update_profile.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 12));
      dynamic body;
      try {
        body = jsonDecode(r.body);
      } catch (_) {
        body = {};
      }
      if (r.statusCode == 200 && body is Map && body['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        final updated = body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : <String, dynamic>{
                ...data,
                'phone': phone.text.trim(),
                'street': street.text.trim(),
                'state': provinceName,
                'city': cityName,
                'email': email,
                'blood_type': bloodType,
                'birthdate': birthdate,
                'full_name': [
                  first.text.trim(),
                  middle.text.trim(),
                  last.text.trim(),
                  suffix.text.trim(),
                ].where((x) => x.isNotEmpty).join(' '),
              };
        await prefs.setString(
          'cached_profile_' + donorId!,
          jsonEncode(updated),
        );
        await prefs.setString(
          'userName',
          updated['full_name']?.toString() ??
              [
                first.text.trim(),
                last.text.trim(),
              ].where((x) => x.isNotEmpty).join(' '),
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Profile updated'),
            content: const Text('Your profile information has been updated.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context, true);
      } else if (r.statusCode == 429) {
        final message = body is Map ? _text(body['message']).trim() : '';
        snack(
          message.isEmpty
              ? 'Profile was edited too recently. Please try again on your next available date.'
              : message,
        );
      } else {
        snack('Something went wrong. Please try again.');
      }
    } catch (_) {
      snack('Internet connection is required to update your profile.');
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !canEdit || !online;
    return ProfilePage(
      title: 'Edit Profile',
      subtitle: 'Update your personal information',
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: kCrimson),
              ),
            )
          : Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  profileInfoCard(
                    'Profile information can only be updated once every 7 days.',
                  ),
                  if (!canEdit) ...[
                    const SizedBox(height: 12),
                    profileInfoCard(
                      'Editing is currently unavailable. You can update your profile again' +
                          (nextEdit == null ? '.' : ' on ' + nextEdit! + '.'),
                      icon: Icons.lock_outline,
                    ),
                  ],
                  if (!online) ...[
                    const SizedBox(height: 12),
                    profileInfoCard(
                      'Saved information is shown below. Internet connection is required to update your profile.',
                      icon: Icons.cloud_off_outlined,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ProfileCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personal Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field('First Name', first, disabled: disabled),
                        _field(
                          'Middle Initial',
                          middle,
                          disabled: disabled,
                          max: 2,
                        ),
                        _field('Last Name', last, disabled: disabled),
                        _field('Suffix', suffix, disabled: disabled),
                        _field(
                          'Contact Number',
                          phone,
                          disabled: disabled,
                          type: TextInputType.phone,
                        ),
                        _field('Street Address', street, disabled: disabled),
                        const SizedBox(height: 4),
                        const Text(
                          'Province',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _dropdown(
                          provinces,
                          provinceCode,
                          loadingProvinces,
                          disabled,
                          'Select Province',
                          (v) {
                            if (v == null) return;
                            final item = provinces.firstWhere(
                              (x) => x.code == v,
                            );
                            setState(() {
                              provinceCode = item.code;
                              provinceName = item.name;
                              cityCode = cityName = barangayCode =
                                  barangayName = null;
                              cities = [];
                              barangays = [];
                            });
                            _loadCities(v);
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'City / Municipality',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _dropdown(
                          cities,
                          cityCode,
                          loadingCities,
                          disabled || provinceCode == null,
                          'Select City / Municipality',
                          (v) {
                            if (v == null) return;
                            final item = cities.firstWhere((x) => x.code == v);
                            setState(() {
                              cityCode = item.code;
                              cityName = item.name;
                              barangayCode = barangayName = null;
                              barangays = [];
                            });
                            _loadBarangays(item.code, item.name);
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Barangay',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _dropdown(
                          barangays,
                          barangayCode,
                          loadingBarangays,
                          disabled || cityCode == null,
                          'Select Barangay',
                          (v) {
                            if (v == null) return;
                            final item = barangays.firstWhere(
                              (x) => x.code == v,
                            );
                            setState(() {
                              barangayCode = item.code;
                              barangayName = item.name;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ProfileCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _readOnly('Donor ID', donorId ?? 'N/A'),
                        _readOnly('Blood Type', bloodType),
                        _readOnly('Date of Birth', birthdate),
                        _readOnly('Verified Email', email),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: canEdit ? 'Save Changes' : 'Changes Locked',
                    loading: saving,
                    onTap: disabled ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool disabled = false,
    TextInputType type = TextInputType.text,
    int? max,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: !disabled,
          keyboardType: type,
          maxLength: max,
          validator: (v) =>
              (v == null || v.trim().isEmpty) &&
                  label != 'Middle Initial' &&
                  label != 'Suffix'
              ? 'Please enter ' + label.toLowerCase() + '.'
              : null,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: kInputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _dropdown(
    List<_Location> items,
    String? value,
    bool isLoading,
    bool disabled,
    String hint,
    void Function(String?) changed,
  ) {
    final present = items.any((x) => x.code == value);
    return isLoading
        ? const SizedBox(
            height: 52,
            child: Center(child: CircularProgressIndicator(color: kCrimson)),
          )
        : AppDropdown<String>(
            value: present ? value : null,
            hint: hint,
            items: items
                .map(
                  (x) => DropdownMenuItem(
                    value: x.code,
                    child: Text(x.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: disabled ? null : changed,
          );
  }

  Widget _readOnly(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: kTextMuted, fontSize: 13),
          ),
        ),
        Text(
          value.isEmpty ? 'N/A' : value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    ),
  );
}
