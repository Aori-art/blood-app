// register1.dart
// Place at: lib/screens/register/register1.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blood/shared_design.dart';
import 'register2.dart';

// ─── Formatters ───────────────────────────────────────────────────────────────

class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final text = newValue.text.toLowerCase();
    return newValue.copyWith(
        text: text[0].toUpperCase() + text.substring(1));
  }
}

class MiddleInitialFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    String text = newValue.text.replaceAll('.', '');
    if (text.length > 1) text = text[0];
    text = '${text.toUpperCase()}.';
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstCtrl = TextEditingController();
  final _midCtrl   = TextEditingController();
  final _lastCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bdayCtrl  = TextEditingController();

  String? _gender;
  String? _suffix;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _midCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _bdayCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime(2004, 1, 1);
    if (_bdayCtrl.text.isNotEmpty) {
      try { initial = DateTime.parse(_bdayCtrl.text); } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kCrimson,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _bdayCtrl.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _goNext() {
    final first = _firstCtrl.text.trim();
    final last  = _lastCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final bday  = _bdayCtrl.text.trim();

    if (first.isEmpty || last.isEmpty || email.isEmpty ||
        phone.isEmpty || bday.isEmpty || _gender == null) {
      _snack('Please fill in all required fields.');
      return;
    }
    if (!phone.startsWith('09') || phone.length != 11) {
      _snack('Phone must be 11 digits starting with 09.');
      return;
    }

    final mid    = _midCtrl.text.trim();
    final suffix = _suffix ?? '';
    final fullName = [
      first,
      if (mid.isNotEmpty) mid,
      last,
      if (suffix.isNotEmpty) suffix,
    ].join(' ');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterStep2(
          fullName: fullName,
          firstName: first,
          middleInitial: mid,
          lastName: last,
          suffix: suffix,
          email: email,
          phone: phone,
          birthdate: bday,
          gender: _gender!,
        ),
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientScreen(
        child: Column(
          children: [
            RegisterHeader(
              step: 1,
              subtitle: 'Step 1 of 3 · Personal Information',
            ),
            Expanded(
              child: RegisterCard(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle('Basic Information'),
                      const SizedBox(height: 16),

                      FieldLabel('First Name'),
                      AppTextField(
                        controller: _firstCtrl,
                        hint: 'Juan',
                        prefixIcon: Icons.person_outline_rounded,
                        inputFormatters: [CapitalizeFirstLetterFormatter()],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel('Middle Initial'),
                                AppTextField(
                                  controller: _midCtrl,
                                  hint: 'D.',
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[a-zA-Z.]')),
                                    MiddleInitialFormatter(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel('Suffix'),
                                AppDropdown<String>(
                                  value: _suffix,
                                  hint: 'None',
                                  onChanged: (v) =>
                                      setState(() => _suffix = v),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '', child: Text('None')),
                                    DropdownMenuItem(
                                        value: 'Jr.', child: Text('Jr.')),
                                    DropdownMenuItem(
                                        value: 'Sr.', child: Text('Sr.')),
                                    DropdownMenuItem(
                                        value: 'II', child: Text('II')),
                                    DropdownMenuItem(
                                        value: 'III', child: Text('III')),
                                    DropdownMenuItem(
                                        value: 'IV', child: Text('IV')),
                                    DropdownMenuItem(
                                        value: 'V', child: Text('V')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Last Name'),
                      AppTextField(
                        controller: _lastCtrl,
                        hint: 'Dela Cruz',
                        prefixIcon: Icons.person_outline_rounded,
                        inputFormatters: [CapitalizeFirstLetterFormatter()],
                      ),
                      const SizedBox(height: 24),

                      SectionTitle('Contact & Identity'),
                      const SizedBox(height: 16),

                      FieldLabel('Email Address'),
                      AppTextField(
                        controller: _emailCtrl,
                        hint: 'your.email@gmail.com',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.mail_outline_rounded,
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Phone Number'),
                      AppTextField(
                        controller: _phoneCtrl,
                        hint: '09XXXXXXXXX',
                        keyboardType: TextInputType.phone,
                        prefixIcon: Icons.phone_outlined,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '11-digit number starting with 09',
                          style: TextStyle(
                              color: kTextMuted.withOpacity(0.7),
                              fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Date of Birth'),
                      AppTextField(
                        controller: _bdayCtrl,
                        hint: 'Select your birthdate',
                        readOnly: true,
                        prefixIcon: Icons.cake_outlined,
                        onTap: _pickDate,
                        suffix: const Icon(Icons.calendar_today_outlined,
                            color: kTextMuted, size: 18),
                      ),
                      const SizedBox(height: 14),

                      FieldLabel('Gender'),
                      AppDropdown<String>(
                        value: _gender,
                        hint: 'Select Gender',
                        onChanged: (v) => setState(() => _gender = v),
                        items: const [
                          DropdownMenuItem(
                              value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'Female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'Non-binary',
                              child: Text('Non-binary')),
                          DropdownMenuItem(
                              value: 'Prefer not to say',
                              child: Text('Prefer not to say')),
                        ],
                      ),
                      const SizedBox(height: 32),

                      PrimaryButton(label: 'Continue', onTap: _goNext),
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