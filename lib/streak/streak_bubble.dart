import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home.dart' show kBottomNavBarHeight;
import '../main.dart' show appNavigatorKey;
import '../shared_design.dart';
import 'blood_bag_mascot.dart';
import 'mascot_chatter.dart';
import 'milestone_celebration.dart';
import 'streak_controller.dart';
import 'streak_ladder_screen.dart';
import 'streak_particles.dart';

/// The assistive-touch style floating streak bubble. Mounted once, above the
/// Navigator, so it navigates and shows sheets through [appNavigatorKey].
class StreakBubbleOverlay extends StatefulWidget {
  const StreakBubbleOverlay({super.key});

  @override
  State<StreakBubbleOverlay> createState() => _StreakBubbleOverlayState();
}

class _StreakBubbleOverlayState extends State<StreakBubbleOverlay>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const double _size = 58;
  static const double _margin = 8;
  static const double _dragThreshold = 4;

  /// Length of the "new day" animation around the bubble.
  static const int _burstMs = 2500;

  final StreakController _c = StreakController.instance;
  final MascotChatter _chatter = MascotChatter();
  final math.Random _rand = math.Random();

  late final AnimationController _snap;
  late final AnimationController _burst;
  Animation<Offset>? _snapAnim;
  late final List<Particle> _burstParticles = generateParticles(
    seed: 11,
    count: 14,
    palette: const [kCrimson, Color(0xFFFF8FA3), Color(0xFFEF4444)],
    shapes: const [ParticleShape.drop, ParticleShape.heart, ParticleShape.drop],
    speedMin: 70,
    speedMax: 170,
    sizeMin: 5,
    sizeMax: 8,
    lifeMin: 1.3,
    lifeMax: 1.9,
    delayMax: 0.1,
  );

  Size _screen = Size.zero;
  EdgeInsets _safe = EdgeInsets.zero;

  // Drag state (raw pointer events: no 36 px pan slop before the bag moves).
  Offset _live = Offset.zero;
  Offset _downAt = Offset.zero;
  Offset _liveAtDown = Offset.zero;
  bool _dragging = false;
  bool _didDrag = false;
  Offset _look = Offset.zero;

  bool _idle = false;
  bool _celebrating = false;
  int _rollFrom = 0;
  Timer? _idleTimer;
  Timer? _celebrateTimer;
  int _seenReset = 0;

  // Mascot chat.
  Timer? _chatTimer;
  Timer? _chatHideTimer;
  String? _chatText;
  bool _chatShowing = false;
  bool _foreground = true;
  bool _wasVisible = false;
  bool _lastChatEnabled = true;

  // Full-screen celebrations.
  bool _celebrationOpen = false;
  bool _celebrationBusy = false;

  bool get _visible =>
      _c.loggedIn &&
      _c.data != null &&
      _c.showBubblePref &&
      _c.hiddenCount == 0;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _burstMs),
    );
    WidgetsBinding.instance.addObserver(this);
    _seenReset = _c.bubbleResetCount;
    _lastChatEnabled = _c.chatEnabled;
    _c.addListener(_onChanged);
    _wasVisible = _visible;
    if (_wasVisible) {
      _scheduleIdle();
      _scheduleChat(first: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onChanged);
    _idleTimer?.cancel();
    _celebrateTimer?.cancel();
    _chatTimer?.cancel();
    _chatHideTimer?.cancel();
    _snap.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _c.onAppResumed();
      if (_visible) _scheduleChat(first: true);
    } else {
      // Backgrounded: stop talking and don't start again until we're back.
      _foreground = false;
      _chatTimer?.cancel();
      _hideChat(reschedule: false);
    }
  }

  // ─── Reacting to the controller ─────────────────────────────────────────

  void _onChanged() {
    if (!mounted) return;
    if (_seenReset != _c.bubbleResetCount) {
      _seenReset = _c.bubbleResetCount;
      _snap.stop();
      _snapAnim = null;
      _dragging = false;
    }
    final visible = _visible;
    if (visible) {
      if (_c.celebrate) {
        _c.consumeCelebrate();
        _playCelebrate();
      } else if (_idleTimer == null && !_idle) {
        _scheduleIdle();
      }
    } else {
      _idleTimer?.cancel();
      _idleTimer = null;
      _idle = false;
    }

    // Chat: start when the bubble appears, stop when it goes away or the
    // setting is switched off.
    if (visible && !_wasVisible && _c.chatEnabled) {
      _scheduleChat(first: true);
    } else if (!visible && _wasVisible) {
      _chatTimer?.cancel();
      _hideChat(reschedule: false);
    }
    if (_c.chatEnabled != _lastChatEnabled) {
      _lastChatEnabled = _c.chatEnabled;
      if (_lastChatEnabled && visible) {
        _scheduleChat(first: true);
      } else {
        _chatTimer?.cancel();
        _hideChat(reschedule: false);
      }
    }
    _wasVisible = visible;

    setState(() {});
    _maybeShowCelebration();
  }

  // The "new day" animation: number roll, rings, +1, particles, jump.
  void _playCelebrate() {
    _celebrateTimer?.cancel();
    _wake();
    _hideChat(reschedule: false);
    _chatTimer?.cancel();
    _celebrating = true;
    _rollFrom = _c.celebrateFrom;
    HapticFeedback.lightImpact();
    _chatter.queueSpecial('Day {n}! You did it again!');
    if (_c.evolvedNow) {
      _chatter.queueSpecial('Look at me, I evolved into {stage}!');
    }
    if (!_reduceMotion) _burst.forward(from: 0);
    _celebrateTimer = Timer(const Duration(milliseconds: _burstMs), () {
      if (!mounted) return;
      setState(() => _celebrating = false);
      _scheduleIdle();
      // A queued special line comes out soon after the show.
      _chatTimer?.cancel();
      _chatTimer = Timer(const Duration(seconds: 3), _tryChat);
      _maybeShowCelebration();
    });
  }

  // ─── Idle fade (like AssistiveTouch) ────────────────────────────────────

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_dragging && !_celebrating) setState(() => _idle = true);
    });
  }

  void _wake() {
    _idleTimer?.cancel();
    if (_idle) setState(() => _idle = false);
  }

  // ─── Mascot chat ────────────────────────────────────────────────────────

  bool get _chatPossible =>
      _visible && _c.chatEnabled && _foreground && !_celebrationOpen;

  // First line ~6 s after the bubble appears, then every 40–90 s.
  void _scheduleChat({bool first = false}) {
    _chatTimer?.cancel();
    if (!_chatPossible) return;
    final delay = first
        ? const Duration(seconds: 6)
        : Duration(seconds: 40 + _rand.nextInt(51));
    _chatTimer = Timer(delay, _tryChat);
  }

  void _tryChat() {
    _chatTimer = null;
    if (!mounted || !_chatPossible) return;
    if (_dragging || _celebrating || _chatShowing || _c.hiddenCount > 0) {
      _chatTimer = Timer(const Duration(seconds: 10), _tryChat);
      return;
    }
    final data = _c.data;
    if (data == null) return;
    final text = _chatter.next(data);
    if (text == null) {
      _scheduleChat();
      return;
    }
    setState(() {
      _chatText = text;
      _chatShowing = true;
    });
    _chatHideTimer?.cancel();
    _chatHideTimer = Timer(const Duration(milliseconds: 4500), _hideChat);
  }

  void _hideChat({bool reschedule = true}) {
    _chatHideTimer?.cancel();
    if (_chatShowing && mounted) setState(() => _chatShowing = false);
    if (reschedule && mounted) _scheduleChat();
  }

  // ─── Position ───────────────────────────────────────────────────────────

  double _minY(EdgeInsets safe) => safe.top + _margin;

  double _maxY(Size screen, EdgeInsets safe) => math.max(
    _minY(safe),
    screen.height - safe.bottom - kBottomNavBarHeight - _margin - _size,
  );

  double _clampY(double y, Size screen, EdgeInsets safe) =>
      y.clamp(_minY(safe), _maxY(screen, safe));

  Offset _rest(Size screen, EdgeInsets safe) {
    final x = _c.bubbleSide == 'left'
        ? _margin
        : screen.width - _size - _margin;
    return Offset(x, _clampY(_c.bubbleDy * screen.height, screen, safe));
  }

  Offset _current(Size screen, EdgeInsets safe) {
    if (_dragging) return _live;
    final anim = _snapAnim;
    if (anim != null && _snap.isAnimating) {
      final v = anim.value;
      // easeOutBack overshoots; keep the bag on screen while it settles.
      return Offset(v.dx.clamp(0.0, screen.width - _size), v.dy);
    }
    return _rest(screen, safe);
  }

  void _pointerDown(PointerDownEvent e) {
    _wake();
    _didDrag = false;
    _downAt = e.position;
    _liveAtDown = _current(_screen, _safe);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_dragging) {
      if ((e.position - _downAt).distance < _dragThreshold) return;
      _snap.stop();
      _snapAnim = null;
      _dragging = true;
      _didDrag = true;
      // Never talk while being dragged.
      _hideChat();
    }
    final target = _liveAtDown + (e.position - _downAt);
    _live = Offset(
      target.dx.clamp(0.0, _screen.width - _size),
      _clampY(target.dy, _screen, _safe),
    );
    _look = Offset.lerp(
      _look,
      Offset(
        (e.delta.dx / 8).clamp(-1.0, 1.0),
        (e.delta.dy / 8).clamp(-1.0, 1.0),
      ),
      0.5,
    )!;
    setState(() {});
  }

  void _pointerUp(PointerEvent e) {
    if (_dragging) {
      _finishDrag();
    } else {
      _scheduleIdle();
    }
  }

  void _finishDrag() {
    final screen = _screen;
    final onRight = _live.dx + _size / 2 > screen.width / 2;
    final target = Offset(
      onRight ? screen.width - _size - _margin : _margin,
      _clampY(_live.dy, screen, _safe),
    );
    _dragging = false;
    _look = Offset.zero;
    _snapAnim = Tween<Offset>(
      begin: _live,
      end: target,
    ).animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutBack));
    _c.saveBubblePosition(
      onRight ? 'right' : 'left',
      target.dy / screen.height,
    );
    _snap.forward(from: 0);
    setState(() {});
    _scheduleIdle();
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  void _openLadder() {
    if (_didDrag) return;
    appNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const StreakLadderScreen()),
    );
  }

  Future<void> _showMenu() async {
    if (_didDrag) return;
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    HapticFeedback.mediumImpact();
    final hide = await showModalBottomSheet<bool>(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Floating streak',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(sheetCtx, true),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kInputFill,
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_off_rounded, color: kCrimson),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hide floating streak',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kTextPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'You can turn it back on in Streak Ladder > Settings.',
                              style: TextStyle(
                                fontSize: 12,
                                color: kTextMuted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (hide != true) return;
    await _c.setShowBubble(false);
    final nav = appNavigatorKey.currentContext;
    if (nav != null && nav.mounted) {
      ScaffoldMessenger.maybeOf(nav)?.showSnackBar(
        SnackBar(
          content: const Text('Turn it back on in Streak Ladder > Settings'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ─── Full-screen celebrations ───────────────────────────────────────────

  Offset _bubbleCenter() {
    final size = _screen == Size.zero ? MediaQuery.sizeOf(context) : _screen;
    final safe = _screen == Size.zero ? MediaQuery.paddingOf(context) : _safe;
    return _rest(size, safe) + const Offset(_size / 2, _size / 2);
  }

  // Shows queued celebrations one at a time, but never over a hidden or
  // sensitive screen — they wait in the queue until it's allowed.
  Future<void> _maybeShowCelebration() async {
    if (_celebrationBusy || !_c.hasCelebration || _celebrating) return;
    if (!_c.loggedIn || _c.hiddenCount > 0 || !_foreground) return;
    _celebrationBusy = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // Re-check: a sensitive screen may have opened while we waited.
      if (!mounted ||
          !_c.loggedIn ||
          _c.hiddenCount > 0 ||
          _celebrating ||
          !_foreground) {
        return;
      }
      final event = _c.takeCelebration();
      if (event == null) return;
      _chatTimer?.cancel();
      _hideChat(reschedule: false);
      final origin = _bubbleCenter();
      setState(() => _celebrationOpen = true);
      await showMilestoneCelebration(event: event, origin: origin);
    } finally {
      _celebrationBusy = false;
      if (mounted && _celebrationOpen) setState(() => _celebrationOpen = false);
    }
    if (!mounted) return;
    _chatTimer?.cancel();
    _chatTimer = Timer(
      _chatter.hasSpecial
          ? const Duration(seconds: 3)
          : const Duration(seconds: 30),
      _tryChat,
    );
    _maybeShowCelebration();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  // Two quick hops at the start of the "new day" animation.
  double _jumpOffset() {
    final u = _burst.value * _burstMs / 800;
    if (u >= 1) return 0;
    return -12 * math.sin(math.pi * ((u * 2) % 1.0));
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _celebrationOpen) {
      return const Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    // Outside any Scaffold, text would inherit Flutter's fallback style (a
    // yellow double underline), so give the overlay a transparent Material.
    // It paints nothing and doesn't catch touches.
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _screen = constraints.biggest;
            _safe = MediaQuery.paddingOf(context);
            return AnimatedBuilder(
              animation: Listenable.merge([_snap, _burst]),
              builder: (context, _) {
                final pos = _current(_screen, _safe);
                final onRight = pos.dx + _size / 2 > _screen.width / 2;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_celebrating && !_reduceMotion) _burstFx(pos),
                    _pill(pos, onRight),
                    _chatBubble(pos, onRight),
                    Positioned(
                      left: pos.dx,
                      top: pos.dy,
                      width: _size,
                      height: _size,
                      child: _bubble(),
                    ),
                    if (_celebrating && !_reduceMotion) _plusOne(pos),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Rings and particles around the bag (never blocks touches).
  Widget _burstFx(Offset pos) {
    const box = 200.0;
    return Positioned(
      left: pos.dx + _size / 2 - box / 2,
      top: pos.dy + _size / 2 - box / 2,
      width: box,
      height: box,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _BurstPainter(
              ms: _burst.value * _burstMs,
              particles: _burstParticles,
            ),
          ),
        ),
      ),
    );
  }

  // A "+1" that floats up from the bag and fades.
  Widget _plusOne(Offset pos) {
    final p = (_burst.value * _burstMs / 1300).clamp(0.0, 1.0);
    if (p >= 1) return const SizedBox.shrink();
    final rise = Curves.easeOutCubic.transform(p);
    final opacity = p < 0.55 ? 1.0 : 1 - (p - 0.55) / 0.45;
    return Positioned(
      left: pos.dx - 10,
      width: _size + 20,
      top: pos.dy - 14 - 40 * rise,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: const Center(
            child: Text(
              '+1',
              style: TextStyle(
                color: kCrimson,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: Colors.white, blurRadius: 4),
                  Shadow(color: Colors.white, blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(Offset pos, bool onRight) {
    final streak = _c.data?.current ?? 0;
    return Positioned(
      top: pos.dy + (_size - 28) / 2,
      left: onRight ? null : pos.dx + _size + 6,
      right: onRight ? _screen.width - pos.dx + 6 : null,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _celebrating ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kCrimson, kCrimsonDark]),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              'Day $streak streak!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The speech bubble beside the mascot, on the side facing the screen centre.
  Widget _chatBubble(Offset pos, bool onRight) {
    final text = _chatText;
    if (text == null) return const SizedBox.shrink();
    final size = MascotSpeechBubble.measure(text);
    final bagCenterY = pos.dy + _size / 2;
    final minTop = _safe.top + 8;
    final maxTop = math.max(
      minTop,
      _screen.height - _safe.bottom - 8 - size.height,
    );
    final top = (bagCenterY - size.height / 2).clamp(minTop, maxTop);
    final left = onRight
        ? math.max(8.0, pos.dx - 4 - size.width)
        : math.min(_screen.width - size.width - 8, pos.dx + _size + 4);
    return Positioned(
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        ignoring: !_chatShowing,
        child: AnimatedOpacity(
          opacity: _chatShowing ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedScale(
            scale: _chatShowing ? 1 : 0.85,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideChat,
              child: MascotSpeechBubble(
                text: text,
                tailOnRight: onRight,
                tailTop: bagCenterY - top,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble() {
    final streak = _c.data?.current ?? 0;
    final MascotMood mood = _dragging
        ? MascotMood.dragging
        : _celebrating
        ? MascotMood.celebrate
        : _chatShowing
        ? MascotMood.talking
        : (streak == 0 ? MascotMood.sleepy : MascotMood.idle);
    final rolling = _celebrating && !_reduceMotion;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openLadder,
        onLongPress: _showMenu,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _idle ? 0.6 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale: _idle ? 0.9 : 1,
            child: Transform.translate(
              offset: Offset(0, rolling ? _jumpOffset() : 0),
              child: BloodBagMascot(
                size: _size,
                streak: streak,
                mood: mood,
                look: _look,
                rollFrom: rolling ? _rollFrom : null,
                rollProgress: rolling
                    ? (_burst.value * _burstMs / 600).clamp(0.0, 1.0)
                    : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two expanding rings plus a burst of drops and hearts.
class _BurstPainter extends CustomPainter {
  final double ms;
  final List<Particle> particles;

  const _BurstPainter({required this.ms, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 2; i++) {
      final p = ((ms - i * 250) / 1100).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final e = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        center,
        29 + 56 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * (1 - e) + 1
          ..color = kCrimson.withValues(alpha: 0.5 * (1 - e)),
      );
    }
    ParticlePainter(
      particles: particles,
      mode: ParticleMode.burst,
      time: ms / 1000,
      origin: center,
      gravity: 240,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.ms != ms;
}
