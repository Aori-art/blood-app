import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'dugtong_stage_art.dart';

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

/// One entry of the server's `frames` list: every frame that exists, with how
/// to unlock it. The picker renders this list, never a hardcoded one.
class FrameInfo {
  final String key;
  final String label;
  final String description;

  /// 'streak' (reach [unlockDays]) or 'verified' (get the ID verified).
  final String unlockType;
  final int? unlockDays;
  final bool unlocked;

  const FrameInfo({
    required this.key,
    required this.label,
    required this.description,
    required this.unlockType,
    required this.unlockDays,
    required this.unlocked,
  });

  bool get isVerifiedFrame => unlockType == 'verified';

  FrameInfo asUnlocked() => FrameInfo(
    key: key,
    label: label,
    description: description,
    unlockType: unlockType,
    unlockDays: unlockDays,
    unlocked: true,
  );

  factory FrameInfo.fromJson(Map<String, dynamic> json) {
    final unlock = json['unlock'];
    String type = 'streak';
    int? days;
    if (unlock is Map) {
      type = _nullableString(unlock['type']) ?? 'streak';
      if (unlock['days'] != null) days = _int(unlock['days']);
    }
    return FrameInfo(
      key: _nullableString(json['key']) ?? '',
      label: _nullableString(json['label']) ?? '',
      description: _nullableString(json['description']) ?? '',
      unlockType: type,
      unlockDays: days,
      unlocked: json['unlocked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'description': description,
    'unlock': {'type': unlockType, if (unlockDays != null) 'days': unlockDays},
    'unlocked': unlocked,
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
  final bool isVerified;
  final List<FrameInfo> frames;

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
    this.isVerified = false,
    this.frames = const [],
  });

  FrameInfo? frameByKey(String key) {
    for (final f in frames) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Parses the success body shared by all three endpoints. Returns null when
  /// the body has no usable `streak` object.
  static StreakData? fromBody(Map<String, dynamic> body) {
    final streak = body['streak'];
    if (streak is! Map) return null;
    final next = body['next_milestone'];
    final ladder = body['ladder'];
    final frames = body['unlocked_frames'];
    final frameList = body['frames'];
    final isVerified = body['is_verified'] == true;

    // The server's `frames` list is the truth about locked/unlocked; a donor
    // the server calls verified always has the Verified Donor frame.
    final infos = frameList is List
        ? frameList
              .whereType<Map>()
              .map((e) => FrameInfo.fromJson(Map<String, dynamic>.from(e)))
              .where((f) => f.key.isNotEmpty)
              .map((f) => isVerified && f.isVerifiedFrame ? f.asUnlocked() : f)
              .toList()
        : <FrameInfo>[];
    final byKey = {for (final f in infos) f.key: f};
    final unlockedFrames = <String>[
      if (frames is List)
        for (final e in frames)
          if (byKey[e.toString()]?.unlocked ?? true) e.toString(),
    ];
    for (final f in infos) {
      if (f.unlocked && !unlockedFrames.contains(f.key)) {
        unlockedFrames.add(f.key);
      }
    }
    if (isVerified && !unlockedFrames.contains('verified')) {
      unlockedFrames.add('verified');
    }
    return StreakData(
      current: _int(streak['current']),
      longest: _int(streak['longest']),
      totalCheckins: _int(streak['total_checkins']),
      lastCheckinDate: _nullableString(streak['last_checkin_date']),
      freezeAvailable: streak['freeze_available'] == true,
      equippedFrame: _nullableString(body['equipped_frame']),
      unlockedFrames: unlockedFrames,
      nextMilestone: next is Map
          ? Milestone.fromJson(Map<String, dynamic>.from(next))
          : null,
      ladder: ladder is List
          ? ladder
                .whereType<Map>()
                .map((e) => Milestone.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      isVerified: isVerified,
      frames: infos,
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
    'is_verified': isVerified,
    'frames': frames.map((f) => f.toJson()).toList(),
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
    isVerified: isVerified,
    frames: frames,
  );
}

class StreakActionResult {
  final bool ok;
  final String? code;
  final String? message;
  const StreakActionResult({required this.ok, this.code, this.message});
}

enum CelebrationKind { frame, badge, evolution, count }

/// One full-screen celebration, played as phases in order:
///   A. the count splash ([hasCount]: 2 -> 3, 6 -> 7, ...),
///   B. Dugtong evolving ([evolved]),
///   C. the reward reveal ([hasReward]: a new badge or frame).
/// Any phase that does not apply is skipped.
class StreakCelebration {
  final CelebrationKind kind;

  /// Frame key or badge key (empty when there is no reward).
  final String key;
  final String label;
  final String description;

  /// Streak when it happened.
  final int streak;
  final DugtongStage oldStage;
  final DugtongStage newStage;

  /// Set when phase A plays: the number rolls from [countFrom] to [countTo].
  final int? countFrom;
  final int? countTo;

  const StreakCelebration({
    required this.kind,
    required this.key,
    required this.label,
    required this.description,
    required this.streak,
    required this.oldStage,
    required this.newStage,
    this.countFrom,
    this.countTo,
  });

  String get id => switch (kind) {
    CelebrationKind.badge => 'badge:$key',
    CelebrationKind.frame => 'frame:$key',
    CelebrationKind.evolution => 'evolution:$key',
    CelebrationKind.count => 'count:$streak',
  };

  bool get hasCount => countFrom != null && countTo != null;
  bool get hasReward =>
      kind == CelebrationKind.frame || kind == CelebrationKind.badge;
  bool get isVerifiedFrame =>
      kind == CelebrationKind.frame && key == 'verified';
  bool get evolved => newStage.index > oldStage.index;
}

/// App-wide streak state. All streak rules live on the server; this only
/// calls the endpoints, caches the last answer, and tells the UI what to show.
class StreakController extends ChangeNotifier {
  StreakController._();
  static final StreakController instance = StreakController._();

  static const _kBubbleEnabled = 'streak_bubble_enabled';
  static const _kBubbleDx = 'streak_bubble_dx';
  static const _kBubbleDy = 'streak_bubble_dy';
  static const _kChatEnabled = 'streak_chat_enabled';
  static const _kCachePrefix = 'streak_cache_';
  static const _kSeenPrefix = 'streak_seen_frames_';
  static const double defaultBubbleDy = 0.35;
  static const Duration _resumeThrottle = Duration(minutes: 30);

  /// When a check-in can't be counted (offline, server hiccup) it is tried
  /// again after these delays, so the bubble doesn't stay missing until the
  /// next app start.
  static const List<Duration> _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
  ];

  /// Ladder days that get the full-screen count splash.
  static const Set<int> countMilestones = {3, 7, 14, 30, 60, 100, 200, 365};

  StreakData? data;
  bool showBubblePref = true;
  bool chatEnabled = true;
  bool loggedIn = false;

  // Where the donor is right now (see StreakScreen). An unwrapped route is
  // 'generic' and never hides the bubble.
  String _screenId = 'generic';
  bool _screenHidden = false;
  Object? _screenToken;

  /// One-shot: set when a new day was recorded, cleared by [consumeCelebrate].
  bool celebrate = false;

  /// The number rolls from [celebrateFrom] to [celebrateTo] on a new day.
  int celebrateFrom = 0;
  int celebrateTo = 0;

  /// Whether the latest check-in moved Dugtong to a new stage.
  bool evolvedNow = false;

  /// Display-only facts about the latest check-in.
  bool freezeUsedNow = false;
  bool streakLostNow = false;
  int previousStreak = 0;

  /// 'left' | 'right', and the bubble's top as a fraction of screen height.
  String bubbleSide = 'right';
  double bubbleDy = defaultBubbleDy;

  /// Bumped when the saved position is cleared so the bubble re-snaps.
  int bubbleResetCount = 0;

  final List<StreakCelebration> _celebrations = [];
  Set<String>? _seenFrames;
  String? _seenDonor;
  String? _dataDonorId;
  int _session = 0;
  int _applySeq = 0;
  bool _checkInBusy = false;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  DateTime? _lastCheckInAt;
  String? _lastCheckInDate;
  bool _notifyScheduled = false;

  String? get equippedFrame => loggedIn ? data?.equippedFrame : null;

  /// The server's name for a frame (e.g. "Gold Frame"), or null when the key
  /// is not in the list this donor received.
  String? frameLabel(String key) {
    final label = data?.frameByKey(key)?.label;
    return (label == null || label.isEmpty) ? null : label;
  }
  bool get hasCelebration => _celebrations.isNotEmpty;

  /// Id of the screen the donor is on ('generic' when it isn't a StreakScreen).
  String get currentScreenId => _screenId;

  /// True while a screen that keeps the bubble off is current.
  bool get currentScreenHidden => _screenHidden;

  /// Screens shown before the donor is inside the app.
  static const Set<String> preAppScreens = {
    'login',
    'register',
    'otp',
    'forgot_password',
    'splash',
    'consent',
  };

  /// Full-screen celebrations wait until the donor is signed in and past the
  /// login / registration / OTP screens.
  bool get celebrationAllowed => loggedIn && !preAppScreens.contains(_screenId);

  // ─── Setup ─────────────────────────────────────────────────────────────

  /// Loads the saved bubble settings and, for a signed-in donor, the cached
  /// streak so the bubble can appear before the network answers.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    showBubblePref = prefs.getBool(_kBubbleEnabled) ?? true;
    chatEnabled = prefs.getBool(_kChatEnabled) ?? true;
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

  /// Called right after a successful login (before navigating away from the
  /// login screen) and at app start when the saved session says the donor is
  /// signed in. Loads the cached streak, then counts today.
  Future<void> onLoggedIn() async {
    final session = _session;
    // Flip the flag at once so listeners react without waiting for storage.
    if (!loggedIn) {
      loggedIn = true;
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (session != _session) return;
    if (id == null) {
      loggedIn = false;
      notifyListeners();
      return;
    }
    if (_dataDonorId != null && _dataDonorId != id) {
      data = null;
      _dataDonorId = null;
      _celebrations.clear();
      _seenFrames = null;
      _seenDonor = null;
    }
    _loadCache(prefs, id);
    _retryAttempt = 0;
    notifyListeners();
    await checkIn();
  }

  /// Called on logout and after account deletion: hides the bubble and
  /// forgets the donor (see [reset]).
  void onLoggedOut({bool forgetSeen = false}) => reset(forgetSeen: forgetSeen);

  /// Records today's check-in (idempotent on the server). Returns whether the
  /// server answered. Silent on failure, but it tries again soon (see
  /// [_retryDelays]) instead of waiting for the next app start.
  Future<bool> checkIn() async {
    if (_checkInBusy) return false;
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (id == null || session != _session || _checkInBusy) return false;
    _checkInBusy = true;
    try {
      if (!loggedIn) {
        loggedIn = true;
        _loadCache(prefs, id);
        notifyListeners();
      }
      final body = await _request('streak_checkin.php', {
        'donor_id': id,
      }, post: true);
      if (session != _session) return false;
      if (body == null || body['success'] != true) {
        // Today could not be counted. Show what the server already knows (so
        // the bubble can appear) and try the check-in again shortly.
        if (data == null) unawaited(refresh());
        _scheduleRetry();
        return false;
      }
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
      final now = DateTime.now();
      _lastCheckInAt = now;
      _lastCheckInDate = _dateKey(now);
      _apply(prefs, id, body, fromCheckIn: true);
      return true;
    } finally {
      _checkInBusy = false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_retryAttempt >= _retryDelays.length) return;
    final delay = _retryDelays[_retryAttempt++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(checkIn());
    });
  }

  /// Called when the app returns to the foreground. The streak (and the
  /// frames, including Verified Donor) is always refreshed; today's check-in
  /// is repeated at most once per 30 minutes unless the date changed or
  /// nothing was ever loaded.
  Future<void> onAppResumed() async {
    final prefs = await SharedPreferences.getInstance();
    if (_signedInDonorId(prefs) == null) return;
    if (!loggedIn) {
      await onLoggedIn();
      return;
    }
    final now = DateTime.now();
    final last = _lastCheckInAt;
    final due =
        last == null ||
        data == null ||
        now.difference(last) >= _resumeThrottle ||
        _lastCheckInDate != _dateKey(now);
    await Future.wait([if (due) checkIn(), refresh()]);
  }

  /// Fetches the current streak and frames without recording a check-in. It
  /// always asks the server: locked or unlocked is never decided from the
  /// cache. Returns whether the server answered.
  Future<bool> refresh() async {
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    final id = _signedInDonorId(prefs);
    if (id == null || session != _session) return false;
    final seq = _applySeq;
    final body = await _request('get_streak.php', {
      'donor_id': id,
    }, post: false);
    if (body == null || body['success'] != true || session != _session) {
      return false;
    }
    // A check-in answered while this was in flight; its data is newer.
    if (_applySeq != seq) return true;
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

    // What Dugtong looked like before this payload (for evolution).
    final previous = (_dataDonorId == id) ? data : null;
    final isNewDay = fromCheckIn && body['is_new_checkin'] == true;
    final lost = fromCheckIn && body['streak_lost'] == true;

    _applySeq++;
    data = parsed;
    _dataDonorId = id;
    loggedIn = true;
    unawaited(
      prefs.setString('$_kCachePrefix$id', jsonEncode(parsed.toJson())),
    );

    final newlyUnlocked = <Milestone>[];
    if (fromCheckIn) {
      freezeUsedNow = body['freeze_used'] == true;
      streakLostNow = lost;
      previousStreak = _int(body['previous_streak']);
      final unlocked = body['newly_unlocked'];
      if (isNewDay && unlocked is List) {
        for (final item in unlocked.whereType<Map>()) {
          newlyUnlocked.add(
            Milestone.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      if (isNewDay) {
        // Ladder days get the full-screen count splash instead of the small
        // animation around the bubble.
        celebrate = !countMilestones.contains(parsed.current);
        celebrateTo = parsed.current;
        celebrateFrom = parsed.current > 0 ? parsed.current - 1 : 0;
      }
    }

    _queueCelebrations(
      prefs,
      id,
      parsed,
      newlyUnlocked: newlyUnlocked,
      previous: previous,
      isNewDay: isNewDay,
      lost: lost,
    );
    notifyListeners();
  }

  // ─── Celebrations ──────────────────────────────────────────────────────

  Set<String> _loadSeen(SharedPreferences prefs, String id) {
    if (_seenFrames != null && _seenDonor == id) return _seenFrames!;
    final stored = prefs.getStringList('$_kSeenPrefix$id');
    _seenDonor = id;
    _seenFrames = stored?.toSet();
    return _seenFrames ?? <String>{};
  }

  void _queueCelebrations(
    SharedPreferences prefs,
    String id,
    StreakData parsed, {
    required List<Milestone> newlyUnlocked,
    required StreakData? previous,
    required bool isNewDay,
    required bool lost,
  }) {
    _loadSeen(prefs, id);
    final newlyKeys = {for (final m in newlyUnlocked) m.key};

    // First load for this donor: everything already unlocked counts as seen
    // (so a reinstall doesn't replay old celebrations), except the Verified
    // frame and whatever was unlocked just now.
    if (_seenFrames == null) {
      _seenFrames = parsed.unlockedFrames
          .where((k) => k != 'verified' && !newlyKeys.contains(k))
          .toSet();
      unawaited(prefs.setStringList('$_kSeenPrefix$id', _seenFrames!.toList()));
    }
    final seen = _seenFrames!;

    // Evolution: compare Dugtong before and after this check-in.
    final newStage = dugtongStageFor(parsed.current);
    var oldStage = newStage;
    if (isNewDay) {
      final oldCurrent =
          previous?.current ??
          (lost
              ? previousStreak
              : (parsed.current > 0 ? parsed.current - 1 : 0));
      oldStage = dugtongStageFor(oldCurrent);
    }
    var evolutionPending = newStage.index > oldStage.index;
    evolvedNow = evolutionPending;

    // Ladder day (3, 7, 14, ...): the count splash plays on every one of them,
    // reward or not.
    var countPending = isNewDay && countMilestones.contains(parsed.current);
    final countFrom = parsed.current > 0 ? parsed.current - 1 : 0;

    final fresh = <StreakCelebration>[];
    void add(StreakCelebration c) {
      if (fresh.any((e) => e.id == c.id)) return;
      if (_celebrations.any((e) => e.id == c.id)) return;
      fresh.add(c);
    }

    StreakCelebration make(
      CelebrationKind kind,
      String key,
      String label,
      String description,
    ) {
      // The count splash and the evolution play once, with the first reward
      // of the check-in (the Verified frame never carries them).
      final carries = (evolutionPending || countPending) && key != 'verified';
      final withCount = carries && countPending;
      final withEvolution = carries && evolutionPending;
      if (carries) {
        evolutionPending = false;
        countPending = false;
      }
      return StreakCelebration(
        kind: kind,
        key: key,
        label: label,
        description: description,
        streak: parsed.current,
        oldStage: (withEvolution || withCount) ? oldStage : newStage,
        newStage: newStage,
        countFrom: withCount ? countFrom : null,
        countTo: withCount ? parsed.current : null,
      );
    }

    for (final m in newlyUnlocked) {
      add(
        make(
          m.isFrame ? CelebrationKind.frame : CelebrationKind.badge,
          m.key,
          m.label.isNotEmpty ? m.label : m.key,
          m.description,
        ),
      );
    }
    for (final key in parsed.unlockedFrames) {
      if (seen.contains(key)) continue;
      final info = parsed.frameByKey(key);
      add(
        make(
          CelebrationKind.frame,
          key,
          (info?.label.isNotEmpty ?? false) ? info!.label : key,
          info?.description ?? '',
        ),
      );
    }
    if (evolutionPending || countPending) {
      // No reward to ride along with.
      add(
        StreakCelebration(
          kind: evolutionPending
              ? CelebrationKind.evolution
              : CelebrationKind.count,
          key: evolutionPending ? newStage.name : '',
          label: newStage.stageName,
          description: 'Dugtong evolved!',
          streak: parsed.current,
          oldStage: oldStage,
          newStage: newStage,
          countFrom: countPending ? countFrom : null,
          countTo: countPending ? parsed.current : null,
        ),
      );
    }
    _celebrations.addAll(fresh);
  }

  /// The next celebration to show, or null. Takes it off the queue, and a
  /// frame counts as seen from here on so it never plays twice.
  StreakCelebration? takeCelebration() {
    if (_celebrations.isEmpty) return null;
    final next = _celebrations.removeAt(0);
    if (next.kind == CelebrationKind.frame) markFrameSeen(next.key);
    return next;
  }

  /// Called once a frame's celebration has been shown, so it never repeats.
  void markFrameSeen(String key) {
    final id = _seenDonor;
    final seen = _seenFrames;
    if (id == null || seen == null || !seen.add(key)) return;
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_kSeenPrefix$id', seen.toList());
    }());
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── One-shot UI state ─────────────────────────────────────────────────

  bool consumeCelebrate() {
    if (!celebrate) return false;
    celebrate = false;
    return true;
  }

  // ─── Where the donor is ────────────────────────────────────────────────────────────────────────────────────────

  /// A screen became current. [token] identifies the screen instance so that a
  /// screen leaving late can never clear the one that replaced it.
  void screenEntered(Object token, String id, {bool hidden = false}) {
    if (_screenToken == token && _screenId == id && _screenHidden == hidden) {
      return;
    }
    _screenToken = token;
    _screenId = id;
    _screenHidden = hidden;
    _notifyAfterFrame();
  }

  /// A screen stopped being current (covered, popped or disposed). Does
  /// nothing if another screen has already taken over.
  void screenLeft(Object token) {
    if (_screenToken != token) return;
    _screenToken = null;
    _screenId = 'generic';
    _screenHidden = false;
    _notifyAfterFrame();
  }

  // Screens change during build/dispose, so listeners are told once the frame
  // is done.
  void _notifyAfterFrame() {
    if (_notifyScheduled) return;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
    // Only now: if scheduling had thrown, a stuck flag would swallow every
    // later change.
    _notifyScheduled = true;
    binding.ensureVisualUpdate();
  }

  // ─── Bubble settings ───────────────────────────────────────────────────

  Future<void> setShowBubble(bool value) async {
    showBubblePref = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBubbleEnabled, value);
  }

  Future<void> setChatEnabled(bool value) async {
    chatEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kChatEnabled, value);
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

  /// Forget everything — call on logout and after account deletion. The seen
  /// frames are kept (so a re-login doesn't replay old celebrations) unless
  /// [forgetSeen] is true, as it is when the account is deleted.
  void reset({bool forgetSeen = false}) {
    _session++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _checkInBusy = false;
    data = null;
    _dataDonorId = null;
    loggedIn = false;
    celebrate = false;
    celebrateFrom = 0;
    celebrateTo = 0;
    evolvedNow = false;
    freezeUsedNow = false;
    streakLostNow = false;
    previousStreak = 0;
    _celebrations.clear();
    _seenFrames = null;
    _seenDonor = null;
    showBubblePref = true;
    chatEnabled = true;
    bubbleSide = 'right';
    bubbleDy = defaultBubbleDy;
    bubbleResetCount++;
    _lastCheckInAt = null;
    _lastCheckInDate = null;
    notifyListeners();
    unawaited(_clearStoredStreak(forgetSeen: forgetSeen));
  }

  Future<void> _clearStoredStreak({required bool forgetSeen}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (!key.startsWith('streak_')) continue;
        if (!forgetSeen && key.startsWith(_kSeenPrefix)) continue;
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
