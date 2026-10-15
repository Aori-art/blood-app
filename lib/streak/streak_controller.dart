import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

int _int(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _nullableString(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s.toLowerCase() == 'null') ? null : s;
}

/// Up to two initials from a display name, for avatar previews.
String streakInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// One rung of the ladder, or the "next milestone" / a newly unlocked reward.
class Milestone {
  final int days;
  final String type; // 'badge' | 'frame'
  final String key;
  final String label;
  final String description;
  final bool unlocked;
  final int? remaining;

  const Milestone({
    required this.days,
    required this.type,
    required this.key,
    required this.label,
    required this.description,
    this.unlocked = false,
    this.remaining,
  });

  bool get isFrame => type == 'frame';

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    days: _int(json['days']),
    type: _nullableString(json['type']) ?? 'badge',
    key: _nullableString(json['key']) ?? '',
    label: _nullableString(json['label']) ?? '',
    description: _nullableString(json['description']) ?? '',
    unlocked: json['unlocked'] == true,
    remaining: json['remaining'] == null ? null : _int(json['remaining']),
  );

  Map<String, dynamic> toJson() => {
    'days': days,
    'type': type,
    'key': key,
    'label': label,
    'description': description,
    'unlocked': unlocked,
    if (remaining != null) 'remaining': remaining,
  };
}

class StreakData {
  final int current;
  final int longest;
  final int totalCheckins;
  final String? lastCheckinDate;
  final bool freezeAvailable;
  final String? equippedFrame;
  final List<String> unlockedFrames;
  final Milestone? nextMilestone;
  final List<Milestone> ladder;

  const StreakData({
    required this.current,
    required this.longest,
    required this.totalCheckins,
    required this.lastCheckinDate,
    required this.freezeAvailable,
    required this.equippedFrame,
    required this.unlockedFrames,
    required this.nextMilestone,
    required this.ladder,
  });

  /// Parses the success body shared by all three endpoints. Returns null when
  /// the body has no usable `streak` object.
  static StreakData? fromBody(Map<String, dynamic> body) {
    final streak = body['streak'];
    if (streak is! Map) return null;
    final next = body['next_milestone'];
    final ladder = body['ladder'];
    final frames = body['unlocked_frames'];
    return StreakData(
      current: _int(streak['current']),
      longest: _int(streak['longest']),
      totalCheckins: _int(streak['total_checkins']),
      lastCheckinDate: _nullableString(streak['last_checkin_date']),
      freezeAvailable: streak['freeze_available'] == true,
      equippedFrame: _nullableString(body['equipped_frame']),
      unlockedFrames: frames is List
          ? frames.map((e) => e.toString()).toList()
          : const [],
      nextMilestone: next is Map
          ? Milestone.fromJson(Map<String, dynamic>.from(next))
          : null,
      ladder: ladder is List
          ? ladder
                .whereType<Map>()
                .map((e) => Milestone.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }

  /// Same shape as the server body, so the cache can be re-parsed with
  /// [fromBody].
  Map<String, dynamic> toJson() => {
    'success': true,
    'streak': {
      'current': current,
      'longest': longest,
      'total_checkins': totalCheckins,
      'last_checkin_date': lastCheckinDate,
      'freeze_available': freezeAvailable,
    },
    'equipped_frame': equippedFrame,
    'unlocked_frames': unlockedFrames,
    'next_milestone': nextMilestone?.toJson(),
    'ladder': ladder.map((m) => m.toJson()).toList(),
  };

  StreakData withFrame(String? frame) => StreakData(
    current: current,
    longest: longest,
    totalCheckins: totalCheckins,
    lastCheckinDate: lastCheckinDate,
    freezeAvailable: freezeAvailable,
    equippedFrame: frame,
    unlockedFrames: unlockedFrames,
    nextMilestone: nextMilestone,
    ladder: ladder,
  );
}

class StreakActionResult {
  final bool ok;
  final String? code;
  final String? message;
  const StreakActionResult({required this.ok, this.code, this.message});
}

/// App-wide streak state. All streak rules live on the server; this only
/// calls the endpoints, caches the last answer, and tells the UI what to show.
class StreakController extends ChangeNotifier {
  StreakController._();
  static final StreakController instance = StreakController._();

  static const _kBubbleEnabled = 'streak_bubble_enabled';
  static const _kBubbleDx = 'streak_bubble_dx';
  static const _kBubbleDy = 'streak_bubble_dy';
  static const _kCachePrefix = 'streak_cache_';
  static const double defaultBubbleDy = 0.35;
  static const Duration _resumeThrottle = Duration(minutes: 30);

  StreakData? data;
  bool showBubblePref = true;
  bool loggedIn = false;

  /// Screens where the bubble must not show hold this above zero.
  int hiddenCount = 0;

  /// One-shot: set when a new day was recorded, cleared by [consumeCelebrate].
  bool celebrate = false;

  /// Display-only facts about the latest check-in.
  bool freezeUsedNow = false;
  bool streakLostNow = false;
  int previousStreak = 0;

  /// 'left' | 'right', and the bubble's top as a fraction of screen height.
  String bubbleSide = 'right';
  double bubbleDy = defaultBubbleDy;

  /// Bumped when the saved position is cleared so the bubble re-snaps.
  int bubbleResetCount = 0;

  final List<Milestone> _rewardQueue = [];
  String? _dataDonorId;
  int _session = 0;
  bool _checkInBusy = false;
  DateTime? _lastCheckInAt;
  String? _lastCheckInDate;
  bool _notifyScheduled = false;

  String? get equippedFrame => loggedIn ? data?.equippedFrame : null;
  bool get hasReward => _rewardQueue.isNotEmpty;

  // ─── Setup ─────────────────────────────────────────────────────────────

  /// Loads the saved bubble settings and, for a signed-in donor, the cached
  /// streak so the bubble can appear before the network answers.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    showBubblePref = prefs.getBool(_kBubbleEnabled) ?? true;
    final side = prefs.getString(_kBubbleDx);
    bubbleSide = side == 'left' ? 'left' : 'right';
    bubbleDy = (prefs.getDouble(_kBubbleDy) ?? defaultBubbleDy).clamp(0.0, 1.0);
    final id = _signedInDonorId(prefs);
    loggedIn = id != null;
    if (id != null) _loadCache(prefs, id);
    notifyListeners();
  }

  // Same rule main.dart and the newsfeed use for "signed in".
  String? _signedInDonorId(SharedPreferences prefs) {
    final loggedInFlag = prefs.getBool('isLoggedIn') ?? false;
    final id = prefs.getString('donorId');
    if (loggedInFlag && id != null && id.isNotEmpty) return id;
    return null;
  }

  void _loadCache(SharedPreferences prefs, String id) {
    if (data != null && _dataDonorId == id) return;
    final raw = prefs.getString('$_kCachePrefix$id');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final parsed = StreakData.fromBody(Map<String, dynamic>.from(decoded));
        if (parsed != null) {
          data = parsed;
          _dataDonorId = id;
        }
      }
    } catch (_) {}
  }

  // ─── Server calls ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _request(
    String path,
    Map<String, String> fields, {
    required bool post,
  }) async {
    try {
      final base = Uri.parse('${AppConfig.baseUrl}/$path');
      final response = post
          ? await http
                .post(base, body: fields)
                .timeout(const Duration(seconds: 15))
          : await http
                .get(base.replace(queryParameters: fields))
                .timeout(const Duration(seconds: 15));
      // Errors come back as JSON with a non-200 status, so always parse.
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// Records today's check-in (idempotent on the server). Silent on failure.
  Future<void> checkIn() async {
    if (_checkInBusy) return;
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (id == null || session != _session) return;
    _checkInBusy = true;
    final now = DateTime.now();
    _lastCheckInAt = now;
    _lastCheckInDate = _dateKey(now);
    try {
      if (!loggedIn) {
        loggedIn = true;
        _loadCache(prefs, id);
        notifyListeners();
      }
      final body = await _request('streak_checkin.php', {
        'donor_id': id,
      }, post: true);
      if (body == null || body['success'] != true || session != _session) {
        return;
      }
      _apply(prefs, id, body, fromCheckIn: true);
    } finally {
      _checkInBusy = false;
    }
  }

  /// Called when the app returns to the foreground: at most once per 30
  /// minutes, unless the local date changed.
  Future<void> onAppResumed() async {
    final now = DateTime.now();
    final last = _lastCheckInAt;
    final due =
        last == null ||
        now.difference(last) >= _resumeThrottle ||
        _lastCheckInDate != _dateKey(now);
    if (due) await checkIn();
  }

  Future<bool> refresh() async {
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (id == null || session != _session) return false;
    final body = await _request('get_streak.php', {
      'donor_id': id,
    }, post: false);
    if (body == null || body['success'] != true || session != _session) {
      return false;
    }
    _apply(prefs, id, body, fromCheckIn: false);
    return true;
  }

  /// [key] null (or empty) removes the frame.
  Future<StreakActionResult> setFrame(String? key) async {
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (id == null || session != _session) {
      return const StreakActionResult(
        ok: false,
        message: 'Please sign in again.',
      );
    }
    final body = await _request('set_streak_frame.php', {
      'donor_id': id,
      'frame_key': key ?? '',
    }, post: true);
    if (body == null) {
      return const StreakActionResult(
        ok: false,
        code: 'NETWORK_ERROR',
        message: 'Unable to reach the server. Please check your connection.',
      );
    }
    if (body['success'] != true) {
      return StreakActionResult(
        ok: false,
        code: _nullableString(body['code']),
        message: _nullableString(body['message']),
      );
    }
    if (session != _session) return const StreakActionResult(ok: true);

    if (StreakData.fromBody(body) != null) {
      _apply(prefs, id, body, fromCheckIn: false);
    } else if (data != null) {
      final equipped = body.containsKey('equipped_frame')
          ? _nullableString(body['equipped_frame'])
          : _nullableString(key);
      data = data!.withFrame(equipped);
      unawaited(
        prefs.setString('$_kCachePrefix$id', jsonEncode(data!.toJson())),
      );
      notifyListeners();
    }
    return const StreakActionResult(ok: true);
  }

  void _apply(
    SharedPreferences prefs,
    String id,
    Map<String, dynamic> body, {
    required bool fromCheckIn,
  }) {
    final parsed = StreakData.fromBody(body);
    if (parsed == null) return;
    data = parsed;
    _dataDonorId = id;
    loggedIn = true;
    unawaited(
      prefs.setString('$_kCachePrefix$id', jsonEncode(parsed.toJson())),
    );

    if (fromCheckIn) {
      freezeUsedNow = body['freeze_used'] == true;
      streakLostNow = body['streak_lost'] == true;
      previousStreak = _int(body['previous_streak']);
      if (body['is_new_checkin'] == true) {
        celebrate = true;
        final unlocked = body['newly_unlocked'];
        if (unlocked is List) {
          for (final item in unlocked.whereType<Map>()) {
            final reward = Milestone.fromJson(Map<String, dynamic>.from(item));
            final queued = _rewardQueue.any(
              (m) => m.key == reward.key && m.days == reward.days,
            );
            if (!queued) _rewardQueue.add(reward);
          }
        }
      }
    }
    notifyListeners();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── One-shot UI state ─────────────────────────────────────────────────

  bool consumeCelebrate() {
    if (!celebrate) return false;
    celebrate = false;
    return true;
  }

  Milestone? takeReward() =>
      _rewardQueue.isEmpty ? null : _rewardQueue.removeAt(0);

  // ─── Where the bubble may show ─────────────────────────────────────────

  void pushHidden() {
    hiddenCount++;
    _notifyAfterFrame();
  }

  void popHidden() {
    if (hiddenCount > 0) hiddenCount--;
    _notifyAfterFrame();
  }

  // Hidden counters change during build/dispose, so listeners are told once
  // the frame is done.
  void _notifyAfterFrame() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  // ─── Bubble settings ───────────────────────────────────────────────────

  Future<void> setShowBubble(bool value) async {
    showBubblePref = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBubbleEnabled, value);
  }

  /// Remembers where the bubble rests. Does not notify — the bubble already
  /// shows it.
  Future<void> saveBubblePosition(String side, double dy) async {
    bubbleSide = side;
    bubbleDy = dy.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBubbleDx, bubbleSide);
    await prefs.setDouble(_kBubbleDy, bubbleDy);
  }

  Future<void> resetBubblePosition() async {
    bubbleSide = 'right';
    bubbleDy = defaultBubbleDy;
    bubbleResetCount++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBubbleDx);
    await prefs.remove(_kBubbleDy);
  }

  // ─── Sign-out ──────────────────────────────────────────────────────────

  /// Forget everything — call on logout and after account deletion.
  void reset() {
    _session++;
    data = null;
    _dataDonorId = null;
    loggedIn = false;
    celebrate = false;
    freezeUsedNow = false;
    streakLostNow = false;
    previousStreak = 0;
    _rewardQueue.clear();
    showBubblePref = true;
    bubbleSide = 'right';
    bubbleDy = defaultBubbleDy;
    bubbleResetCount++;
    _lastCheckInAt = null;
    _lastCheckInDate = null;
    notifyListeners();
    unawaited(_clearStoredStreak());
  }

  Future<void> _clearStoredStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('streak_')) await prefs.remove(key);
      }
    } catch (_) {}
  }
}
