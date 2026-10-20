import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'login.dart';
import 'streak/streak_screen.dart';
import 'app_palette.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  bool isLoading = false;
  bool _sent = false;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    emailController.dispose();
    _emailFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> sendResetRequest() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      _showSnack('Please enter your email address.', isError: true);
      return;
    }

    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showSnack('Please enter a valid email address.', isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/forgot_password.php"),
        body: {"email": email},
      );

      if (response.statusCode != 200) throw Exception("Server error");

      final data = jsonDecode(response.body);
      if (!mounted) return;

      final isSuccess = data["status"] == "success";
      final message = data["message"] ?? "Request sent";

      if (isSuccess) {
        setState(() => _sent = true);
      } else {
        _showSnack(message, isError: true);
      }
    } catch (e) {
      debugPrint("Forgot password error: $e");
      if (!mounted) return;
      _showSnack('Connection error. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: isError ? AppColors.primary : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'forgot_password', hideBubble: true, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          // ── HEADER ────────────────────────────────────────────
          _buildHeader(size),

          // ── BODY ──────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    size.width * 0.06,
                    28,
                    size.width * 0.06,
                    32,
                  ),
                  child: _sent ? _buildSuccessState() : _buildForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Size size) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: size.height * 0.06,
        left: 20,
        right: 20,
        bottom: 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -20, right: -10,
            child: _DecorativeCircle(size: 120, opacity: 0.10),
          ),
          Positioned(
            bottom: -30, right: 60,
            child: _DecorativeCircle(size: 80, opacity: 0.08),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(height: 20),
              // Blood drop icon
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: _BloodDropMini(),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Forgot Password?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'No worries — we\'ll send a reset link\nto your registered email.',
                style: TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.orangeBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.orangeBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: context.palette.orange, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enter your email and we\'ll send reset instructions. Check your spam folder if you don\'t see it.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.warningText,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Email label
        Text(
          'Email Address',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.palette.foreground,
          ),
        ),
        const SizedBox(height: 8),

        // Email field
        Focus(
          onFocusChange: (_) => setState(() {}),
          child: TextField(
            controller: emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(fontSize: 14, color: context.palette.foreground),
            decoration: InputDecoration(
              hintText: 'your.email@gmail.com',
              hintStyle: TextStyle(color: context.palette.muted, fontSize: 14),
              filled: true,
              fillColor: _emailFocus.hasFocus
                  ? context.palette.surface
                  : context.palette.surfaceAlt,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: _emailFocus.hasFocus
                      ? context.palette.primaryText
                      : context.palette.muted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.palette.primaryText, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Send button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : sendResetRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              disabledBackgroundColor: Colors.transparent,
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: isLoading
                    ? LinearGradient(
                        colors: [context.palette.hint, context.palette.hint])
                    : const LinearGradient(
                        colors: AppColors.primaryGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: isLoading
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Send Reset Link',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Back to login
        Center(
          child: GestureDetector(
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded,
                    size: 15, color: context.palette.muted),
                SizedBox(width: 5),
                Text(
                  'Back to Login',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        const SizedBox(height: 20),

        // Animated success icon
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, v, child) =>
              Transform.scale(scale: v, child: child),
          child: Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: context.palette.successBg,
              shape: BoxShape.circle,
              border: Border.all(color: context.palette.successBorder, width: 2),
              boxShadow: [
                BoxShadow(
                  color: context.palette.success.withOpacity(0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.mark_email_read_rounded,
                color: context.palette.success, size: 42),
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Check your inbox!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We\'ve sent a reset link to\n${emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: context.palette.muted,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 28),

        // Steps
        _stepRow(Icons.inbox_rounded, context.palette.info,
            'Open the email from eDonate'),
        const SizedBox(height: 12),
        _stepRow(Icons.link_rounded, context.palette.purple,
            'Tap the reset link inside'),
        const SizedBox(height: 12),
        _stepRow(Icons.lock_reset_rounded, context.palette.primaryText,
            'Set your new password'),

        const SizedBox(height: 32),

        // Spam note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.warningBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.warningBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: context.palette.warning, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Didn't receive it? Check your spam or junk folder, or wait a minute and try again.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.warningText,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Back to login
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            icon: Icon(Icons.login_rounded,
                size: 18, color: context.palette.primaryText),
            label: Text(
              'Back to Login',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: context.palette.primaryText,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: context.palette.primaryText, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Try again
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            emailController.clear();
          }),
          child: Text(
            'Try a different email',
            style: TextStyle(
              fontSize: 13,
              color: context.palette.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepRow(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _DecorativeCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withOpacity(opacity), width: 1.5),
      ),
    );
  }
}

class _BloodDropMini extends StatelessWidget {
  const _BloodDropMini();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 28),
      painter: _BloodDropPainter(),
    );
  }
}

class _BloodDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path();
    final cx = size.width / 2;
    path.moveTo(cx, 0);
    path.cubicTo(cx + size.width * 0.6, size.height * 0.35,
        cx + size.width * 0.6, size.height * 0.7, cx, size.height);
    path.cubicTo(cx - size.width * 0.6, size.height * 0.7,
        cx - size.width * 0.6, size.height * 0.35, cx, 0);
    path.close();
    canvas.drawPath(path, paint);
    final shine = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - size.width * 0.12, size.height * 0.42),
        width: size.width * 0.22,
        height: size.height * 0.18,
      ),
      shine,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}