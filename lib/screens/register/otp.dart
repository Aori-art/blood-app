// otp.dart
// Place at: lib/screens/register/otp.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:blood/config.dart';
import 'package:blood/login.dart';
import 'package:blood/shared_design.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  String get _otpCode => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.88, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_otpCode.length != 6) {
      _snack('Please enter the 6-digit OTP.');
      return;
    }
    setState(() => _verifying = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/verify_otp.php'),
        body: {'email': widget.email, 'otp': _otpCode},
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (data['status'] == 'success') {
        _snack(data['message'] ?? 'OTP verified!');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        _snack(data['message'] ?? 'Invalid OTP.');
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      if (mounted) _snack('Connection error: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/resend_otp.php'),
        body: {'email': widget.email},
      );
      final data = jsonDecode(res.body);
      if (mounted) _snack(data['message'] ?? 'OTP resent.');
    } catch (e) {
      if (mounted) _snack('Connection error: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _otpBox(int index) {
    final filled = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: kTextPrimary),
        onChanged: (val) {
          if (val.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (val.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: filled ? kCrimson.withOpacity(0.08) : kInputFill,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: filled ? kCrimson : Colors.transparent,
                  width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kCrimson, width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filledCount = _controllers.where((c) => c.text.isNotEmpty).length;

    return Scaffold(
      body: GradientScreen(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.of(context).size.height * 0.06,
                  24,
                  24),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.mark_email_read_outlined,
                          color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Check your email',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    "We've sent a 6-digit code to",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.email,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // ── Card ───────────────────────────────────────────────────
            Expanded(
              child: RegisterCard(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    children: [
                      // Progress dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (i) {
                          final active = i < filledCount;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: active ? 10 : 8,
                            height: active ? 10 : 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: active
                                  ? kCrimson
                                  : kCrimson.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),

                      // OTP boxes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, _otpBox),
                      ),
                      const SizedBox(height: 32),

                      PrimaryButton(
                        label: 'Verify Code',
                        loading: _verifying,
                        onTap: _verify,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Didn't receive it?  ",
                              style: TextStyle(
                                  color: kTextMuted, fontSize: 13)),
                          GestureDetector(
                            onTap: _resending ? null : _resend,
                            child: Text(
                              _resending ? 'Sending...' : 'Resend OTP',
                              style: const TextStyle(
                                  color: kCrimson,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Security notice
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.amber.withOpacity(0.3),
                              width: 1),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.shield_outlined,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This code is valid for 10 minutes. Never share this code with anyone.',
                                style: TextStyle(
                                    color: kTextMuted,
                                    fontSize: 11,
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      OutlineBtn(
                          label: 'Back',
                          onTap: () => Navigator.pop(context)),
                      const SizedBox(height: 8),
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