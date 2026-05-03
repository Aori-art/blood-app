// register3.dart
// Place at: lib/screens/register/register3.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:blood/config.dart';
import 'package:blood/shared_design.dart';
import 'otp.dart';

class RegisterStep3 extends StatefulWidget {
  final String fullName, firstName, middleInitial, lastName, suffix;
  final String email, phone, birthdate, gender;
  final String bloodType, streetAddress, barangay, municipality, province;

  const RegisterStep3({
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
    required this.bloodType,
    required this.streetAddress,
    required this.barangay,
    required this.municipality,
    required this.province,
  });

  @override
  State<RegisterStep3> createState() => _RegisterStep3State();
}

class _RegisterStep3State extends State<RegisterStep3> {
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading       = false;
  bool _passHidden    = true;
  bool _confirmHidden = true;

  @override
  void initState() {
    super.initState();
    _passCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _hasLength    => _passCtrl.text.length >= 8;
  bool get _hasUppercase => _passCtrl.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber    => _passCtrl.text.contains(RegExp(r'[0-9]'));

  Future<void> _submit() async {
    final pass    = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pass.isEmpty || confirm.isEmpty) {
      _snack('Please fill in both password fields.');
      return;
    }
    if (pass != confirm) {
      _snack('Passwords do not match.');
      return;
    }
    if (!_hasLength) {
      _snack('Password must be at least 8 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/register.php'),
        body: {
          'first_name':     widget.firstName,
          'middle_initial': widget.middleInitial,
          'last_name':      widget.lastName,
          'suffix':         widget.suffix,
          'email':          widget.email,
          'phone':          widget.phone,
          'birthdate':      widget.birthdate,
          'gender':         widget.gender,
          'blood_type':     widget.bloodType,
          'street_address': widget.streetAddress,
          'barangay':       widget.barangay,
          'municipality':   widget.municipality,
          'province':       widget.province,
          'password':       pass,
        },
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['status'] == 'success') {
        _snack(data['message'] ?? 'OTP sent to email.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => OtpScreen(email: widget.email)),
        );
      } else {
        _snack(data['message'] ?? 'Registration failed.');
      }
    } catch (e) {
      if (mounted) _snack('Connection error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCrimson,
      body: SafeArea(
        child: Column(
          children: [
            RegisterHeader(
              step: 3,
              subtitle: 'Step 3 of 3 · Set Password',
            ),
            Expanded(
              child: RegisterCard(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCrimson.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: kCrimson.withOpacity(0.15), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outlined,
                                color: kCrimson, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Almost done! Create a strong password for your account.',
                                style: TextStyle(
                                    color: kTextMuted,
                                    fontSize: 12,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      FieldLabel('Password'),
                      AppTextField(
                        controller: _passCtrl,
                        hint: 'Create a strong password',
                        obscure: _passHidden,
                        prefixIcon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _passHidden = !_passHidden),
                          icon: Icon(
                              _passHidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: kTextMuted,
                              size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Confirm Password'),
                      AppTextField(
                        controller: _confirmCtrl,
                        hint: 'Re-enter your password',
                        obscure: _confirmHidden,
                        prefixIcon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          onPressed: () => setState(
                              () => _confirmHidden = !_confirmHidden),
                          icon: Icon(
                              _confirmHidden
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: kTextMuted,
                              size: 20),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Live requirements card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kInputFill,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Password requirements',
                                style: TextStyle(
                                    color: kTextPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                            const SizedBox(height: 10),
                            _Req(
                                label: 'At least 8 characters',
                                met: _hasLength),
                            const SizedBox(height: 6),
                            _Req(
                                label: 'One uppercase letter',
                                met: _hasUppercase),
                            const SizedBox(height: 6),
                            _Req(label: 'One number', met: _hasNumber),
                          ],
                        ),
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
                              label: 'Confirm',
                              loading: _loading,
                              onTap: _submit,
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

// ─── Requirement row ──────────────────────────────────────────────────────────
class _Req extends StatelessWidget {
  final String label;
  final bool met;
  const _Req({required this.label, required this.met});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: met ? kCrimson : Colors.transparent,
              border: Border.all(
                  color: met ? kCrimson : kTextMuted.withOpacity(0.4),
                  width: 1.5),
              borderRadius: BorderRadius.circular(9),
            ),
            child: met
                ? const Icon(Icons.check, color: Colors.white, size: 12)
                : null,
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: met ? kTextPrimary : kTextMuted,
                  fontSize: 12,
                  fontWeight:
                      met ? FontWeight.w600 : FontWeight.w400)),
        ],
      );
}