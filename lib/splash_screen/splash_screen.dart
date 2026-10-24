import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:blood/app_colors.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blood/newsfeed.dart';
import 'package:blood/privacy_consent.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_screen.dart';
import '../widgets/dugtong_wordmark.dart';

class SplashScreen extends StatefulWidget {
  final bool isLoggedIn;

  const SplashScreen({super.key, required this.isLoggedIn});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _lockupController;
  late final AnimationController _textController;
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  late final AnimationController _ringsController;

  // The lockup: the icon pops in, "Dug" and "tong" slide in from the sides
  // and meet ("dugtong" means to connect), then the tagline fades in.
  late final DugtongReveal _reveal;

  // The line at the bottom
  late final Animation<double> _subtitleFade;

  // With animations removed the splash is its last frame, still.
  bool _reduce = false;

  // Pulse glow behind logo
  late final Animation<double> _pulse;

  // Animated progress bar
  late final Animation<double> _progress;

  // Rotating decorative rings
  late final Animation<double> _rings;

  @override
  void initState() {
    super.initState();

    _lockupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // Lockup, on a 1000 ms clock: the icon pops in (0.7 → 1 with a small
    // overshoot) in 500 ms; the two halves of the name start at 250 ms and
    // take 450 ms; the tagline fades in from 700 ms.
    Animation<double> part(double from, double to, Curve curve) =>
        CurvedAnimation(
          parent: _lockupController,
          curve: Interval(from, to, curve: curve),
        );
    _reveal = DugtongReveal(
      icon: part(0.0, 0.5, Curves.easeOutBack),
      dug: part(0.25, 0.70, Curves.easeOutCubic),
      tong: part(0.25, 0.70, Curves.easeOutCubic),
      tagline: part(0.70, 1.0, Curves.easeOut),
    );

    // The line at the bottom
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Pulse
    _pulse = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Progress bar
    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Rings rotation
    _rings = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(parent: _ringsController, curve: Curves.linear));

    // Sequence: lockup → progress → bottom line
    _lockupController.forward();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_reduce) _textController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_reduce) _progressController.forward();
    });

    getFCMToken();

    Timer(const Duration(milliseconds: 3200), () async {
      if (!mounted) return;

      // Privacy gate: anyone who hasn't accepted the current statement version
      // sees the consent screen first. If preferences can't be read we assume
      // no consent rather than skipping the gate.
      var consented = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        consented =
            prefs.getString(kPrivacyConsentVersionKey) == kPrivacyPolicyVersion;
      } catch (_) {}
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          // Signed in and signed out both land on the newsfeed now — it already
          // supports a signed-out state with its own sign-in CTA.
          pageBuilder: (_, animation, __) => consented
              ? const NewsfeedPage()
              : PrivacyConsentScreen(nextBuilder: (_) => const NewsfeedPage()),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
      if (consented) unawaited(retryPendingPrivacyReceipt());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      // The final frame, no motion.
      for (final c in [
        _lockupController,
        _textController,
        _progressController,
      ]) {
        c.value = 1;
      }
      _pulseController.stop();
      _pulseController.value = 0.5;
      _ringsController.stop();
      _ringsController.value = 0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
      _ringsController.repeat();
    }
  }

  void getFCMToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      debugPrint("FCM TOKEN: $token");
    } catch (e) {
      debugPrint("Failed to get FCM token: $e");
    }
  }

  @override
  void dispose() {
    _lockupController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _ringsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreakScreen(
    id: 'splash',
    hideBubble: true,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryGradient,
          ),
        ),
        child: Stack(
          children: [
            // ── DECORATIVE BACKGROUND ────────────────────────────
            _BackgroundOrbs(size: size),

            // ── ROTATING RINGS ───────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _rings,
                builder: (_, __) =>
                    Transform.rotate(angle: _rings.value, child: _DecoRings()),
              ),
            ),

            // ── MAIN CONTENT ─────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // The lockup: icon, name and tagline, with a soft pulse
                  // behind the icon.
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: (96 - 170) / 2,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => Transform.scale(
                            scale: _pulse.value,
                            child: Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(
                                  0.07 * _pulse.value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DugtongLockup(
                        iconSize: 96,
                        axis: Axis.vertical,
                        onGradient: true,
                        tagline: true,
                        reveal: _reduce ? DugtongReveal.done : _reveal,
                      ),
                    ],
                  ),

                  const Spacer(flex: 3),

                  // ── BOTTOM SECTION ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
                    child: Column(
                      children: [
                        // Progress bar
                        AnimatedBuilder(
                          animation: _progress,
                          builder: (_, __) => Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: SizedBox(
                                  height: 3,
                                  child: LinearProgressIndicator(
                                    value: _progress.value,
                                    backgroundColor: Colors.white.withOpacity(
                                      0.15,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Bottom tagline
                        FadeTransition(
                          opacity: _subtitleFade,
                          child: const Text(
                            'Every drop counts. Every life matters.',
                            style: TextStyle(
                              color: AppColors.onPrimaryMuted,
                              fontSize: 12,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── BACKGROUND ORBS ───────────────────────────────────────────────────────────

class _BackgroundOrbs extends StatelessWidget {
  final Size size;
  const _BackgroundOrbs({required this.size});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top-left orb
        Positioned(
          top: -size.height * 0.10,
          left: -size.width * 0.15,
          child: Container(
            width: size.width * 0.65,
            height: size.width * 0.65,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        // Bottom-right orb
        Positioned(
          bottom: -size.height * 0.08,
          right: -size.width * 0.20,
          child: Container(
            width: size.width * 0.75,
            height: size.width * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.08),
            ),
          ),
        ),
        // Mid accent
        Positioned(
          top: size.height * 0.60,
          left: -size.width * 0.05,
          child: Container(
            width: size.width * 0.35,
            height: size.width * 0.35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.04),
            ),
          ),
        ),
      ],
    );
  }
}

// ── DECORATIVE ROTATING RINGS ─────────────────────────────────────────────────

class _DecoRings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 320,
      child: CustomPaint(painter: _RingsPainter()),
    );
  }
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final configs = [
      (radius: 130.0, opacity: 0.06, dashLen: 8.0, gapLen: 12.0),
      (radius: 148.0, opacity: 0.04, dashLen: 4.0, gapLen: 8.0),
      (radius: 158.0, opacity: 0.03, dashLen: 2.0, gapLen: 14.0),
    ];

    for (final c in configs) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(c.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final circumference = 2 * math.pi * c.radius;
      final total = c.dashLen + c.gapLen;
      final count = (circumference / total).floor();

      for (int i = 0; i < count; i++) {
        final startAngle = (i * total / circumference) * 2 * math.pi;
        final sweepAngle = (c.dashLen / circumference) * 2 * math.pi;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: c.radius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
