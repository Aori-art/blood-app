import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'media_url.dart';
import 'streak/streak_controller.dart';

/// The signed-in donor's own photo (donors.profile_photo_path, from
/// get_my_avatar.php) and the frame the server reports, shared by every place
/// that draws "my avatar" (see MyAvatar in my_avatar.dart).
///
/// The photo path is cached in preferences ('my_avatar_path') so it shows
/// straight away on the next start, then the server is asked.
class MyAvatarController extends ChangeNotifier with WidgetsBindingObserver {
  MyAvatarController._();
  static final MyAvatarController instance = MyAvatarController._();

  static const String _kPath = 'my_avatar_path';

  /// After coming back to the app, ask again at most this often.
  static const Duration resumeThrottle = Duration(minutes: 5);

  /// The server-relative (or absolute) photo path, null without a photo.
  String? avatarPath;

  /// The frame the server last said is still valid for this donor.
  String? frame;

  /// The donor's name (prefs 'userName').
  String name = '';

  // Bumped by [reset]: an answer that was on its way is for a donor who is
  // gone.
  int _epoch = 0;
  DateTime? _lastFetch;
  bool _observing = false;

  /// The full photo URL, or null.
  String? get avatarUrl => resolveMediaUrl(avatarPath);

  /// The donor's initials (up to two letters), '?' without a name.
  String get initials => streakInitials(name);

  /// The frame to show: the streak's equipped frame (reactive, so equipping
  /// one updates every avatar at once). Only while the streak has not been
  /// loaded does the frame from the server's avatar answer stand in.
  String? get viewerFrame {
    final streak = StreakController.instance;
    if (streak.data != null) return streak.equippedFrame;
    return streak.equippedFrame ?? frame;
  }

  /// Shows the cached photo at once, then asks the server.
  Future<void> load() async {
    await loadCached();
    await _fetch();
  }

  /// Same as [load].
  Future<void> refresh() => load();

  /// Only the cached photo (no network), so a screen's first frame already
  /// has it; follow with [refresh].
  Future<void> loadCached() async {
    _observe();
    final epoch = _epoch;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _epoch) return;
    final cached = prefs.getString(_kPath);
    final userName = prefs.getString('userName') ?? '';
    final path = (cached == null || cached.isEmpty) ? null : cached;
    if (path != avatarPath || userName != name) {
      avatarPath = path;
      name = userName;
      notifyListeners();
    }
  }

  // Errors are ignored: what is shown stays as it was.
  Future<void> _fetch() async {
    final epoch = _epoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('donorId');
      if (id == null || id.isEmpty) return;
      _lastFetch = DateTime.now();
      final response = await http
          .get(Uri.parse('${AppConfig.baseUrl}/get_my_avatar.php?donor_id=$id'))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true || epoch != _epoch) return;
      final avatar = body['avatar']?.toString();
      final f = body['frame']?.toString();
      final newPath = (avatar == null || avatar.isEmpty) ? null : avatar;
      final newFrame = (f == null || f.isEmpty || f == 'null') ? null : f;
      if (newPath == null) {
        await prefs.remove(_kPath);
      } else {
        await prefs.setString(_kPath, newPath);
      }
      if (epoch != _epoch) return;
      final userName = prefs.getString('userName') ?? name;
      if (newPath != avatarPath || newFrame != frame || userName != name) {
        avatarPath = newPath;
        frame = newFrame;
        name = userName;
        notifyListeners();
      }
    } catch (_) {
      // Offline or a server hiccup: keep the cached photo.
    }
  }

  /// Forget the donor (sign out, account deletion), including the cached
  /// path, so the next donor never sees this one's photo.
  void reset() {
    _epoch++;
    avatarPath = null;
    frame = null;
    name = '';
    _lastFetch = null;
    notifyListeners();
    unawaited(
      SharedPreferences.getInstance().then((prefs) => prefs.remove(_kPath)),
    );
  }

  // ─── Coming back to the app ────────────────────────────────────────────

  void _observe() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastFetch;
    if (last != null && DateTime.now().difference(last) < resumeThrottle) {
      return;
    }
    unawaited(load());
  }
}
