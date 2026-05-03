// login.dart
// Place at: lib/login.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'home.dart';
import 'screens/register/register1.dart';
import 'forgot_password.dart';

// ─── Design tokens (inline so no cross-lib import needed) ─────────────────────
const Color _kCrimson     = Color(0xFFAE0000);
const Color _kSurface     = Color(0xFFFAF7F7);
const Color _kInputFill   = Color(0xFFF0E8E8);
const Color _kTextPrimary = Color(0xFF1A0A0A);
const Color _kTextMuted   = Color(0xFF7A5C5C);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  bool _loading    = false;
  bool _passHidden = true;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _loadEmail();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) _emailCtrl.text = prefs.getString('lastUsedEmail') ?? '';
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text.trim();

    if (email.isEmpty) {
      _snack('Please enter your email.');
      return;
    }
    if (pass.isEmpty) {
      _snack('Please enter your password.');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/login.php'),
        body: {'email': email, 'password': pass},
      );
      if (res.statusCode != 200) throw Exception('Server error');
      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (data['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('lastUsedEmail', email);
        await prefs.setString('userEmail', email);
        if (data['user_name'] != null)
          await prefs.setString('userName', data['user_name']);
        if (data['donor_id'] != null)
          await prefs.setString('donorId', data['donor_id'].toString());
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        _snack(data['message'] ?? 'Login failed.');
      }
    } catch (e) {
      if (mounted) _snack('Connection error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _inputDeco(String hint,
      {IconData? prefix, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: _kTextMuted.withOpacity(0.6), fontSize: 14),
        filled: true,
        fillColor: _kInputFill,
        prefixIcon:
            prefix != null ? Icon(prefix, color: _kTextMuted, size: 18) : null,
        suffixIcon: suffix,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kCrimson, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: _kCrimson,
      body: SafeArea(
        child: Column(
          children: [
            // ── Hero ───────────────────────────────────────────────────
            SizedBox(
              height: h * 0.30,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.bloodtype_rounded,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 14),
                    const Text('eDonate',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('Blood Donation App',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 13,
                            letterSpacing: 1.2)),
                  ],
                ),
              ),
            ),

            // ── Card ───────────────────────────────────────────────────
            Expanded(
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: _kSurface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(28, 36, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Welcome back!',
                              style: TextStyle(
                                  color: _kTextPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Sign in to continue saving lives',
                              style: TextStyle(
                                  color: _kTextMuted, fontSize: 14)),
                          const SizedBox(height: 32),

                          // Email
                          const Text('Email Address',
                              style: TextStyle(
                                  color: _kTextPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                                color: _kTextPrimary, fontSize: 14),
                            decoration: _inputDeco(
                                'your.email@gmail.com',
                                prefix: Icons.mail_outline_rounded),
                          ),
                          const SizedBox(height: 16),

                          // Password
                          const Text('Password',
                              style: TextStyle(
                                  color: _kTextPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _passHidden,
                            style: const TextStyle(
                                color: _kTextPrimary, fontSize: 14),
                            decoration: _inputDeco(
                              'Enter your password',
                              prefix: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                onPressed: () => setState(
                                    () => _passHidden = !_passHidden),
                                icon: Icon(
                                    _passHidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: _kTextMuted,
                                    size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen())),
                              child: const Text('Forgot Password?',
                                  style: TextStyle(
                                      color: _kCrimson,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Sign in button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kCrimson,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                              ),
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white))
                                  : const Text('Sign In',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                            ),
                          ),
                          const SizedBox(height: 24),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('New to eDonate? ',
                                  style: TextStyle(
                                      color: _kTextMuted, fontSize: 13)),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const RegisterScreen())),
                                child: const Text('Create Account',
                                    style: TextStyle(
                                        color: _kCrimson,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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