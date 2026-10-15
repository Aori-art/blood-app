import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home.dart' show kBottomNavBarHeight;
import '../main.dart' show appNavigatorKey;
import '../shared_design.dart';
import 'avatar_frame.dart';
import 'blood_bag_mascot.dart';
import 'streak_controller.dart';
import 'streak_ladder_screen.dart';

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

  final StreakController _c = StreakController.instance;

  late final AnimationController _snap;
  late final AnimationController _bounce;
  Animation<Offset>? _snapAnim;

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
  Timer? _idleTimer;
  Timer? _celebrateTimer;
  int _seenReset = 0;
  bool _rewardBusy = false;

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
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addObserver(this);
    _seenReset = _c.bubbleResetCount;
    _c.addListener(_onChanged);
    if (_visible) _scheduleIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onChanged);
    _idleTimer?.cancel();
    _celebrateTimer?.cancel();
    _snap.dispose();
    _bounce.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.onAppResumed();
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
    if (_visible) {
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
    setState(() {});
    _maybeShowReward();
  }

  void _playCelebrate() {
    _celebrateTimer?.cancel();
    _wake();
    _celebrating = true;
    if (!_reduceMotion) _bounce.forward(from: 0);
    _celebrateTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _celebrating = false);
      _scheduleIdle();
      _maybeShowReward();
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

  // Shows queued rewards, but never over a hidden/sensitive screen.
  Future<void> _maybeShowReward() async {
    if (_rewardBusy || !_c.hasReward || _celebrating) return;
    if (!_c.loggedIn || _c.hiddenCount > 0) return;
    _rewardBusy = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final prefs = await SharedPreferences.getInstance();
      final initials = streakInitials(prefs.getString('userName') ?? '');
      // Re-check: a sensitive screen may have opened while we waited.
      if (!mounted || !_c.loggedIn || _c.hiddenCount > 0 || _celebrating) {
        return;
      }
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final reward = _c.takeReward();
      if (reward == null) return;
      await showDialog<void>(
        context: ctx,
        builder: (_) => _RewardDialog(reward: reward, initials: initials),
      );
    } finally {
      _rewardBusy = false;
    }
    if (mounted) _maybeShowReward();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  double _bounceOffset() {
    final v = _bounce.value;
    return -12 * math.sin(math.pi * ((v * 2) % 1.0));
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
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
              animation: _snap,
              builder: (context, _) {
                final pos = _current(_screen, _safe);
                final onRight = pos.dx + _size / 2 > _screen.width / 2;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _pill(pos, onRight),
                    Positioned(
                      left: pos.dx,
                      top: pos.dy,
                      width: _size,
                      height: _size,
                      child: _bubble(),
                    ),
                  ],
                );
              },
            );
          },
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

  Widget _bubble() {
    final streak = _c.data?.current ?? 0;
    final mood = _dragging
        ? MascotMood.dragging
        : _celebrating
        ? MascotMood.celebrate
        : (streak == 0 ? MascotMood.sleepy : MascotMood.idle);
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
            child: AnimatedBuilder(
              animation: _bounce,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _bounceOffset()),
                child: child,
              ),
              child: BloodBagMascot(
                size: _size,
                streak: streak,
                mood: mood,
                look: _look,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Reward unlocked!" popup. Frames can be equipped right away.
class _RewardDialog extends StatefulWidget {
  final Milestone reward;
  final String initials;

  const _RewardDialog({required this.reward, required this.initials});

  @override
  State<_RewardDialog> createState() => _RewardDialogState();
}

class _RewardDialogState extends State<_RewardDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _equip() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await StreakController.instance.setFrame(widget.reward.key);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = result.message ?? "Couldn't equip it right now. Try again.";
      });
    }
  }

  Widget _preview() {
    final reward = widget.reward;
    if (reward.isFrame) {
      return StreakAvatarFrame(
        frameKey: reward.key,
        radius: 34,
        child: CircleAvatar(
          radius: 34,
          backgroundColor: kCrimson,
          child: Text(
            widget.initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    final (icon, color) = badgeVisualFor(reward.key, reward.days);
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .14),
      ),
      child: Icon(icon, size: 40, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.reward;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _preview(),
            const SizedBox(height: 16),
            const Text(
              'Reward unlocked!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reward.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: kCrimson,
              ),
            ),
            if (reward.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                reward.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: kTextMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: kCrimson),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: reward.isFrame
            ? [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Later',
                    style: TextStyle(color: kTextMuted),
                  ),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _equip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCrimson,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Equip now'),
                ),
              ]
            : [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCrimson,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Great!'),
                ),
              ],
      ),
    );
  }
}
