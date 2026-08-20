import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'profile_page_widgets.dart';
import 'shared_design.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final key = GlobalKey<FormState>();
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  bool currentVisible = false,
      nextVisible = false,
      confirmVisible = false,
      saving = false;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  void snack(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (saving || !(key.currentState?.validate() ?? false)) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('donorId');
    if (id == null || id.isEmpty) {
      snack('Unable to find your account. Please sign in again.');
      return;
    }
    setState(() => saving = true);
    try {
      final r = await http
          .post(
            Uri.parse(AppConfig.baseUrl + '/change_password.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'donor_id': int.tryParse(id) ?? id,
              'current_password': current.text,
              'new_password': next.text,
            }),
          )
          .timeout(const Duration(seconds: 12));
      dynamic body;
      try {
        body = jsonDecode(r.body);
      } catch (_) {
        body = {};
      }
      if (r.statusCode == 200 && body is Map && body['status'] == 'success') {
        current.clear();
        next.clear();
        confirm.clear();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Password changed'),
            content: const Text('Your password has been updated successfully.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else if (r.statusCode == 401 ||
          (body is Map &&
              (body['code'] == 'invalid_current_password' ||
                  body['error'] == 'invalid_current_password'))) {
        snack('Your current password is incorrect.');
      } else {
        snack('Something went wrong. Please try again.');
      }
    } catch (_) {
      snack('Internet connection is required to change your password.');
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Change Password',
    subtitle: 'Keep your eDonate account secure',
    child: Form(
      key: key,
      child: Column(
        children: [
          ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Update Password',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _field(
                  'Current Password',
                  current,
                  currentVisible,
                  (v) => setState(() => currentVisible = v),
                ),
                _field(
                  'New Password',
                  next,
                  nextVisible,
                  (v) => setState(() => nextVisible = v),
                  validator: (v) {
                    if (v == null ||
                        v.length < 8 ||
                        !RegExp('[A-Za-z]').hasMatch(v) ||
                        !RegExp('[0-9]').hasMatch(v))
                      return 'Use at least 8 characters with a letter and a number.';
                    if (v == current.text)
                      return 'New password must be different.';
                    return null;
                  },
                ),
                _field(
                  'Confirm New Password',
                  confirm,
                  confirmVisible,
                  (v) => setState(() => confirmVisible = v),
                  validator: (v) =>
                      v != next.text ? 'Passwords do not match.' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Change Password',
            loading: saving,
            onTap: _save,
          ),
        ],
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller,
    bool visible,
    void Function(bool) changed, {
    String? Function(String?)? validator,
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
          obscureText: !visible,
          validator:
              validator ??
              (v) =>
                  v == null || v.isEmpty ? 'Please enter your password.' : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: kInputFill,
            suffixIcon: IconButton(
              tooltip: visible ? 'Hide password' : 'Show password',
              onPressed: () => changed(!visible),
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
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
}
