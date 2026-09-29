import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'home.dart';
import 'login.dart';

// ─────────────────────────────────────────────────────────────────────────────
// eDonate PIN — a 4-digit PIN (like GCash's MPIN) that protects Home.
//
//  • Newsfeed "Go to Home"  → PinScreen()                → unlock, or create
//                                                           a PIN the first time
//  • Profile "Change PIN"   → PinScreen(purpose: change) → current → new → confirm
//
// The PIN lives on the server (hashed) — see pin_api.php. Nothing about the
// PIN is stored on the phone.
// ─────────────────────────────────────────────────────────────────────────────

/// Remembers whether a PIN-unlocked Home screen is currently open, so the
/// newsfeed can simply go back to it instead of asking for the PIN again.
class AppSession {
  AppSession._();
  static bool homeInStack = false;
}

enum PinPurpose { enterHome, change }

enum _PinStage { loading, blocked, unlock, current, create, confirm, success }

class PinApi {
  PinApi._();

  static Future<Map<String, dynamic>> call(
    String action,
    String donorId, {
    String? pin,
    String? currentPin,
    String? password,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/pin_api.php'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'action': action,
            'donor_id': int.tryParse(donorId) ?? donorId,
            if (pin != null) 'pin': pin,
            if (currentPin != null) 'current_pin': currentPin,
            if (password != null) 'password': password,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(response.body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Unexpected response');
  }
}

/// 0000, 1111, 1234, 4321, 6789, 9876 ... (the server checks this too).
bool isWeakPin(String pin) {
  if (RegExp(r'^(\d)\1{3}$').hasMatch(pin)) return true;
  return '0123456789'.contains(pin) || '9876543210'.contains(pin);
}

// Brand colors
const Color _crimson = Color(0xFFDC2626);
const Color _crimsonDeep = Color(0xFF7F1D1D);
const Color _crimsonMid = Color(0xFFB91C1C);
const Color _blush = Color(0xFFFECACA);

// The eDonate logo at the top of the PIN screen. Both files go in
// assets/images/ (declared under flutter → assets in pubspec.yaml).
//   edonate_logo_white.png → white wordmark, globe lines cut out so the
//                            crimson background shows through them
//   edonate_logo.png       → original red colors
const String _kLogoWhiteAsset = 'assets/images/edonate_logo_white.png';
const String _kLogoColorAsset = 'assets/images/edonate_logo.png';
const double _kLogoAspect = 4.15; // width ÷ height of both logo files

// false → white logo directly on the crimson background (GCash style).
// true  → original red logo on a white rounded card.
const bool _kLogoOnCard = false;

class PinScreen extends StatefulWidget {
  final PinPurpose purpose;

  const PinScreen({super.key, this.purpose = PinPurpose.enterHome});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with TickerProviderStateMixin {
  static const int _pinLength = 4;

  late final AnimationController _shake;
  late final AnimationController _pulse;

  _PinStage _stage = _PinStage.loading;
  _PinStage _stageBeforeReset = _PinStage.unlock;
  bool _hadPin = false;

  String _donorId = '';
  String _firstName = '';

  String _entered = '';
  String? _firstPin;
  String? _currentPin;
  String? _resetPassword;

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  String _successTitle = 'Welcome back!';

  String _blockedTitle = '';
  String _blockedMessage = '';
  bool _blockedCanRetry = false;

  int _lockSeconds = 0;
  Timer? _lockTimer;

  bool get _locked => _lockSeconds > 0;

  bool get _acceptsInput =>
      _stage == _PinStage.unlock ||
      _stage == _PinStage.current ||
      _stage == _PinStage.create ||
      _stage == _PinStage.confirm;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _load();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _shake.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ── Loading & state ────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _stage = _PinStage.loading;
      _message = null;
      _entered = '';
    });

    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId') ?? '';
    final savedName = (prefs.getString('userName') ?? '').trim();
    _donorId = donorId;
    _firstName = savedName.isEmpty ? '' : savedName.split(RegExp(r'\s+')).first;

    if (donorId.isEmpty) {
      _block(
        'Please sign in again',
        "We couldn't find your account on this device.",
      );
      return;
    }

    try {
      final d = await PinApi.call('status', donorId);
      if (!mounted) return;
      if (d['status'] != 'success') {
        _block(
          "Can't continue",
          d['message']?.toString() ?? 'Something went wrong. Please try again.',
          retry: true,
        );
        return;
      }

      final hasPin = d['has_pin'] == true;
      final verified = d['is_verified'] == true;
      final serverName = d['first_name']?.toString().trim() ?? '';
      if (_firstName.isEmpty && serverName.isNotEmpty) {
        _firstName = serverName.split(RegExp(r'\s+')).first;
      }

      if (!hasPin && !verified) {
        _block(
          'Verify your identity first',
          'You can create your eDonate PIN once your ID has been verified.',
        );
        return;
      }

      setState(() {
        _hadPin = hasPin;
        if (widget.purpose == PinPurpose.change) {
          _stage = hasPin ? _PinStage.current : _PinStage.create;
        } else {
          _stage = hasPin ? _PinStage.unlock : _PinStage.create;
        }
      });
      _startLock((d['lock_seconds'] as num?)?.toInt() ?? 0);
    } catch (_) {
      if (!mounted) return;
      _block(
        'No connection',
        "We couldn't reach eDonate. Check your internet and try again.",
        retry: true,
      );
    }
  }

  void _block(String title, String message, {bool retry = false}) {
    if (!mounted) return;
    setState(() {
      _stage = _PinStage.blocked;
      _blockedTitle = title;
      _blockedMessage = message;
      _blockedCanRetry = retry;
      _busy = false;
      _entered = '';
    });
  }

  void _startLock(int seconds) {
    _lockTimer?.cancel();
    if (seconds <= 0) {
      if (_lockSeconds != 0 && mounted) setState(() => _lockSeconds = 0);
      return;
    }
    setState(() {
      _lockSeconds = seconds;
      _entered = '';
    });
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockSeconds -= 1;
        if (_lockSeconds <= 0) {
          _lockSeconds = 0;
          timer.cancel();
          _message = 'You can try again now.';
          _messageIsError = false;
        }
      });
    });
  }

  String _formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Keypad input ───────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_busy || _locked || !_acceptsInput) return;
    if (_entered.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      if (_messageIsError) _message = null;
    });
    if (_entered.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 140), _onComplete);
    }
  }

  void _onBackspace() {
    if (_busy || _entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _onClear() {
    if (_busy || _entered.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _entered = '');
  }

  Future<void> _onComplete() async {
    if (!mounted || _entered.length != _pinLength) return;
    final pin = _entered;

    switch (_stage) {
      case _PinStage.unlock:
        await _verify(pin, thenUnlock: true);
        break;
      case _PinStage.current:
        await _verify(pin, thenUnlock: false);
        break;
      case _PinStage.create:
        if (isWeakPin(pin)) {
          _fail(
            'That PIN is too easy to guess. Avoid repeated or consecutive digits.',
          );
          return;
        }
        setState(() {
          _firstPin = pin;
          _entered = '';
          _stage = _PinStage.confirm;
          _message = null;
        });
        break;
      case _PinStage.confirm:
        if (pin != _firstPin) {
          setState(() {
            _stage = _PinStage.create;
            _firstPin = null;
          });
          _fail("PINs didn't match. Please try again.");
          return;
        }
        await _savePin(pin);
        break;
      default:
        break;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _entered = '';
      _message = message;
      _messageIsError = true;
    });
  }

  void _startBusy() {
    setState(() => _busy = true);
    _pulse.repeat(reverse: true);
  }

  void _stopBusy() {
    _pulse.stop();
    _pulse.value = 0;
    if (mounted) setState(() => _busy = false);
  }

  // ── Server calls ───────────────────────────────────────────────────────

  Future<void> _verify(String pin, {required bool thenUnlock}) async {
    _startBusy();
    try {
      final d = await PinApi.call('verify', _donorId, pin: pin);
      if (!mounted) return;
      _stopBusy();
      if (d['status'] == 'success') {
        if (thenUnlock) {
          _successTitle = _firstName.isEmpty
              ? 'Welcome back!'
              : 'Welcome back, $_firstName!';
          await _finish();
        } else {
          setState(() {
            _currentPin = pin;
            _entered = '';
            _stage = _PinStage.create;
            _message = null;
          });
        }
        return;
      }
      _handleError(d);
    } catch (_) {
      if (!mounted) return;
      _stopBusy();
      _fail("Couldn't connect. Check your internet and try again.");
    }
  }

  Future<void> _savePin(String pin) async {
    _startBusy();
    try {
      final Map<String, dynamic> d;
      if (_resetPassword != null) {
        d = await PinApi.call(
          'reset',
          _donorId,
          password: _resetPassword,
          pin: pin,
        );
      } else {
        d = await PinApi.call('set', _donorId, pin: pin, currentPin: _currentPin);
      }
      if (!mounted) return;
      _stopBusy();

      if (d['status'] == 'success') {
        final wasReset = _resetPassword != null;
        _resetPassword = null;
        if (widget.purpose == PinPurpose.change) {
          _successTitle = 'PIN updated!';
        } else if (wasReset) {
          _successTitle = 'New PIN saved!';
        } else if (_hadPin) {
          _successTitle = 'PIN updated!';
        } else {
          _successTitle = 'PIN created!';
        }
        await _finish();
        return;
      }

      final code = d['code']?.toString();
      if (code == 'WEAK_PIN' || code == 'NEW_SAME' || code == 'INVALID_PIN') {
        setState(() {
          _stage = _PinStage.create;
          _firstPin = null;
        });
        _handleError(d);
        return;
      }
      if (code == 'WRONG_PIN' && _currentPin != null) {
        setState(() {
          _stage = _PinStage.current;
          _currentPin = null;
          _firstPin = null;
        });
        _handleError(d);
        return;
      }
      if (code == 'WRONG_PASSWORD') {
        setState(() {
          _stage = _stageBeforeReset;
          _resetPassword = null;
          _firstPin = null;
        });
        _handleError(d);
        return;
      }
      setState(() {
        _stage = _PinStage.create;
        _firstPin = null;
      });
      _handleError(d);
    } catch (_) {
      if (!mounted) return;
      _stopBusy();
      setState(() {
        _stage = _PinStage.create;
        _firstPin = null;
      });
      _fail("Couldn't connect. Check your internet and try again.");
    }
  }

  void _handleError(Map<String, dynamic> d) {
    final code = d['code']?.toString();
    final message =
        d['message']?.toString() ?? 'Something went wrong. Please try again.';

    switch (code) {
      case 'LOCKED':
        _fail(message);
        _startLock((d['lock_seconds'] as num?)?.toInt() ?? 300);
        break;
      case 'NO_PIN':
        setState(() {
          _hadPin = false;
          _stage = _PinStage.create;
          _entered = '';
          _message = 'Please create your eDonate PIN.';
          _messageIsError = false;
        });
        break;
      case 'NOT_VERIFIED':
      case 'INACTIVE':
      case 'INVALID_DONOR':
        _block("Can't continue", message);
        break;
      default:
        _fail(message);
    }
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = _PinStage.success;
      _entered = '';
      _message = null;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    if (widget.purpose == PinPurpose.change) {
      Navigator.of(context).pop(true);
      return;
    }
    AppSession.homeInStack = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ── Forgot PIN / Switch account ────────────────────────────────────────

  Future<void> _forgotPin() async {
    if (_busy || _donorId.isEmpty) return;
    final outcome = await showModalBottomSheet<_ResetOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForgotPinSheet(donorId: _donorId),
    );
    if (outcome == null || !mounted) return;

    if (outcome.lockSeconds > 0) {
      _fail(outcome.message ?? 'Too many incorrect attempts.');
      _startLock(outcome.lockSeconds);
      return;
    }
    if (outcome.noPin) {
      setState(() {
        _hadPin = false;
        _stage = _PinStage.create;
        _entered = '';
        _message = 'Create your eDonate PIN.';
        _messageIsError = false;
      });
      return;
    }
    if (outcome.password != null) {
      setState(() {
        _stageBeforeReset = _stage;
        _resetPassword = outcome.password;
        _currentPin = null;
        _firstPin = null;
        _entered = '';
        _stage = _PinStage.create;
        _message = 'Password confirmed. Create your new PIN.';
        _messageIsError = false;
      });
    }
  }

  Future<void> _switchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Switch account?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: const Text(
          "You'll be signed out of eDonate on this device.",
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _crimson,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('donorId');
    if (id != null && id.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('${AppConfig.baseUrl}/delete_fcm_token.php'),
              body: {'donor_id': id},
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await prefs.clear();
    AppSession.homeInStack = false;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Texts ──────────────────────────────────────────────────────────────

  String get _title => switch (_stage) {
    _PinStage.loading => 'Checking your account…',
    _PinStage.blocked => _blockedTitle,
    _PinStage.unlock => 'Enter your eDonate PIN',
    _PinStage.current => 'Enter your current PIN',
    _PinStage.create =>
      _resetPassword != null
          ? 'Create a new PIN'
          : widget.purpose == PinPurpose.change
          ? 'Create your new PIN'
          : 'Create your eDonate PIN',
    _PinStage.confirm => 'Confirm your PIN',
    _PinStage.success => _successTitle,
  };

  String? get _stepLabel {
    final changeWithCurrent = widget.purpose == PinPurpose.change && _hadPin;
    switch (_stage) {
      case _PinStage.current:
        return 'Step 1 of 3';
      case _PinStage.create:
        return changeWithCurrent && _resetPassword == null
            ? 'Step 2 of 3'
            : 'Step 1 of 2';
      case _PinStage.confirm:
        return changeWithCurrent && _resetPassword == null
            ? 'Step 3 of 3'
            : 'Step 2 of 2';
      default:
        return null;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: MediaQuery(
        data: mq.copyWith(
          textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15),
        ),
        child: Scaffold(
          backgroundColor: _crimsonMid,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_crimson, _crimsonMid, _crimsonDeep],
                stops: [0, 0.55, 1],
              ),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _BackdropPainter()),
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => _content(constraints),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Everything is sized from the space actually available, so the screen
  // always fits without scrolling: the keypad takes up to ~58% of the room
  // left after the top bar and bottom link, and the header (logo, greeting,
  // title, dots) uses the rest — shrinking slightly on very small phones.
  Widget _content(BoxConstraints c) {
    final height = c.maxHeight;
    final width = c.maxWidth;
    const reserved = 112.0; // top bar + bottom link + bottom spacing
    final usable = math.max(0.0, height - reserved);
    final keySize = math
        .min((width - 96) / 3, usable * 0.115)
        .clamp(48.0, 76.0)
        .toDouble();
    final gap = (keySize * 0.26).clamp(9.0, 20.0).toDouble();
    final contentWidth = math.max(200.0, width - 48);
    final logoWidth = math
        .min(contentWidth * 0.7, usable * 0.38)
        .clamp(170.0, 290.0)
        .toDouble();
    final showKeypad = _stage != _PinStage.blocked;

    return Column(
      children: [
        _topBar(),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: contentWidth,
                child: _stage == _PinStage.blocked
                    ? _blockedView(logoWidth)
                    : _headerSection(logoWidth),
              ),
            ),
          ),
        ),
        if (showKeypad) _keypad(keySize, gap),
        _bottomLink(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _topBar() {
    final step = _stepLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Row(
        children: [
          Tooltip(
            message: 'Back',
            child: Material(
              color: Colors.white.withValues(alpha: .14),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy ? null : () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: step == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(step),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      step,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerSection(double logoWidth) {
    final showGreeting = _stage == _PinStage.unlock;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EDonateLogo(width: logoWidth),
        SizedBox(height: logoWidth * 0.12),
        if (showGreeting) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _firstName.isEmpty ? 'Welcome back' : 'Hi, $_firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _busy ? null : _switchAccount,
                child: Text(
                  'Switch account',
                  style: TextStyle(
                    color: _blush,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: _blush.withValues(alpha: .7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _title,
            key: ValueKey('t_$_stage$_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(height: 50, child: Center(child: _indicator())),
        const SizedBox(height: 6),
        _messageArea(),
      ],
    );
  }

  Widget _indicator() {
    if (_stage == _PinStage.loading) {
      return const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
    }
    if (_stage == _PinStage.success) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: .35),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF16A34A),
            size: 32,
          ),
        ),
      );
    }
    return _dots();
  }

  Widget _dots() {
    return AnimatedBuilder(
      animation: Listenable.merge([_shake, _pulse]),
      builder: (context, _) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 6) * 14 * (1 - t);
        final opacity = _busy ? 0.45 + 0.55 * (1 - _pulse.value) : 1.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_pinLength, (i) {
                final filled = i < _entered.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: filled ? 17 : 15,
                  height: filled ? 17 : 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: filled ? 1 : .8),
                      width: 2,
                    ),
                    boxShadow: filled
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: .4),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _messageArea() {
    Widget child;
    if (_locked) {
      child = Container(
        key: const ValueKey('locked'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock_rounded, color: _blush, size: 16),
            const SizedBox(width: 8),
            Text(
              'Too many attempts. Try again in ${_formatCountdown(_lockSeconds)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (_message != null) {
      child = ConstrainedBox(
        key: ValueKey('m_$_message'),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _messageIsError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: _messageIsError ? _blush : Colors.white70,
              size: 15,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _messageIsError ? _blush : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      child = const SizedBox(key: ValueKey('none'), height: 18);
    }
    return SizedBox(
      height: 40,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
    );
  }

  Widget _blockedView(double logoWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EDonateLogo(width: logoWidth),
        const SizedBox(height: 26),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _blockedTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            _blockedMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_blockedCanRetry)
          SizedBox(
            width: 200,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _crimson,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text(
            'Go Back',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _keypad(double size, double gap) {
    final visible = _acceptsInput || _stage == _PinStage.loading;
    final enabled = _acceptsInput && !_busy && !_locked;

    Widget digit(String d) => _KeyButton(
      size: size,
      enabled: enabled,
      semanticLabel: d,
      onTap: () => _onDigit(d),
      child: Text(
        d,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.37,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    Widget row(Widget a, Widget b, Widget c) => Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          a,
          SizedBox(width: gap * 1.5),
          b,
          SizedBox(width: gap * 1.5),
          c,
        ],
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: !visible ? 0 : (enabled ? 1 : .45),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(digit('1'), digit('2'), digit('3')),
            row(digit('4'), digit('5'), digit('6')),
            row(digit('7'), digit('8'), digit('9')),
            row(
              SizedBox(width: size, height: size),
              digit('0'),
              _KeyButton(
                size: size,
                enabled: enabled && _entered.isNotEmpty,
                filled: false,
                semanticLabel: 'Delete',
                onTap: _onBackspace,
                onLongPress: _onClear,
                child: Icon(
                  Icons.backspace_outlined,
                  color: Colors.white.withValues(
                    alpha: _entered.isNotEmpty ? 1 : .45,
                  ),
                  size: size * 0.33,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomLink() {
    final canForget =
        (_stage == _PinStage.unlock || _stage == _PinStage.current) && _hadPin;
    if (canForget) {
      return TextButton(
        onPressed: _busy ? null : _forgotPin,
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        child: const Text(
          'Forgot PIN?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (_stage == _PinStage.create || _stage == _PinStage.confirm) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: .7),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Never share your PIN with anyone, including eDonate staff.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 48);
  }
}

// ── Keypad button ────────────────────────────────────────────────────────────

class _KeyButton extends StatefulWidget {
  final double size;
  final bool enabled;
  final bool filled;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _KeyButton({
    required this.size,
    required this.enabled,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.filled = true,
    this.onLongPress,
  });

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled
        ? Colors.white.withValues(alpha: _down ? .32 : .14)
        : (_down ? Colors.white.withValues(alpha: .14) : Colors.transparent);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _setDown(true) : null,
        onTapUp: widget.enabled ? (_) => _setDown(false) : null,
        onTapCancel: () => _setDown(false),
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: widget.filled
                  ? Border.all(color: Colors.white.withValues(alpha: .10))
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── eDonate logo ────────────────────────────────────────────────────────────

class _EDonateLogo extends StatelessWidget {
  final double width;
  const _EDonateLogo({required this.width});

  @override
  Widget build(BuildContext context) {
    final onCard = _kLogoOnCard;
    final imageWidth = onCard ? width * 0.84 : width;
    final image = Image.asset(
      onCard ? _kLogoColorAsset : _kLogoWhiteAsset,
      width: imageWidth,
      height: imageWidth / _kLogoAspect,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      // If the asset is missing, fall back to the name so the screen still works.
      errorBuilder: (_, __, ___) => SizedBox(
        width: imageWidth,
        height: imageWidth / _kLogoAspect,
        child: FittedBox(
          child: Text(
            'eDonate',
            style: TextStyle(
              color: onCard ? _crimson : Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );

    if (!onCard) return image;

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(vertical: width * 0.06),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.08),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: image,
    );
  }
}

Path _dropPath(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w * 0.5, 0)
    ..cubicTo(w * 0.5, 0, w * 0.12, h * 0.42, w * 0.12, h * 0.66)
    ..cubicTo(w * 0.12, h * 0.87, w * 0.28, h, w * 0.5, h)
    ..cubicTo(w * 0.72, h, w * 0.88, h * 0.87, w * 0.88, h * 0.66)
    ..cubicTo(w * 0.88, h * 0.42, w * 0.5, 0, w * 0.5, 0)
    ..close();
}

/// Soft decorative shapes behind the content.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = Colors.white.withValues(alpha: .05);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.08), 120, soft);
    canvas.drawCircle(
      Offset(size.width * 1.05, size.height * 0.32),
      90,
      Paint()..color = Colors.white.withValues(alpha: .04),
    );

    final dropSize = Size(size.width * 0.55, size.width * 0.66);
    canvas.save();
    canvas.translate(
      size.width - dropSize.width * 0.62,
      size.height - dropSize.height * 0.72,
    );
    canvas.drawPath(
      _dropPath(dropSize),
      Paint()..color = Colors.white.withValues(alpha: .05),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

// ── Forgot PIN sheet ─────────────────────────────────────────────────────────

class _ResetOutcome {
  final String? password;
  final int lockSeconds;
  final String? message;
  final bool noPin;

  const _ResetOutcome({
    this.password,
    this.lockSeconds = 0,
    this.message,
    this.noPin = false,
  });
}

class _ForgotPinSheet extends StatefulWidget {
  final String donorId;
  const _ForgotPinSheet({required this.donorId});

  @override
  State<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends State<_ForgotPinSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your account password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await PinApi.call(
        'reset',
        widget.donorId,
        password: password,
      );
      if (!mounted) return;
      if (d['status'] == 'success') {
        Navigator.of(context).pop(_ResetOutcome(password: password));
        return;
      }
      final code = d['code']?.toString();
      final message = d['message']?.toString() ?? 'Something went wrong.';
      if (code == 'LOCKED') {
        Navigator.of(context).pop(
          _ResetOutcome(
            lockSeconds: (d['lock_seconds'] as num?)?.toInt() ?? 300,
            message: message,
          ),
        );
        return;
      }
      if (code == 'NO_PIN') {
        Navigator.of(context).pop(const _ResetOutcome(noPin: true));
        return;
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't connect. Check your internet and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        child: SafeArea(
          top: false,
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
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF1F1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: _crimson,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forgot your PIN?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Enter your eDonate account password to create a new PIN.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF6B7280),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                enabled: !_busy,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continue(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF9CA3AF),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _crimson, width: 1.5),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 15,
                              color: _crimson,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _crimson,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _crimson,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFF87171),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}