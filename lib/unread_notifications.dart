import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'notification_service.dart';

/// How many notifications the signed-in donor has not read yet. It feeds the
/// badge on the Alerts icon of the bottom navigation bar.
///
/// The server is the source of truth: [refresh] asks it, and the Alerts screen
/// calls [set] whenever its own list changes so the badge never disagrees with
/// what the donor sees.
class UnreadNotifications with WidgetsBindingObserver {
  UnreadNotifications._();
  static final UnreadNotifications instance = UnreadNotifications._();

  static const Duration _pollEvery = Duration(seconds: 60);

  /// The number to show (0 = no badge).
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  Timer? _timer;
  StreamSubscription<void>? _pushSub;
  bool _started = false;
  bool _foreground = true;

  // Bumped by [set], [clear] and [stop]: an answer that was already on its way
  // when one of those happened is older than what the screen shows, so it is
  // dropped.
  int _version = 0;

  bool get isStarted => _started;

  /// Starts keeping the count fresh: now, every 60 s while the app is in the
  /// foreground, when the app comes back to the foreground, and whenever a push
  /// arrives. Calling it again only refreshes.
  void start() {
    if (_started) {
      unawaited(refresh());
      return;
    }
    _started = true;
    _foreground = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_pollEvery, (_) {
      if (_foreground) unawaited(refresh());
    });
    _pushSub = NotificationService.instance.onNotificationReceived.listen((_) {
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  /// Stops all polling and listening. The count is left as it is: call
  /// [clear] as well when the donor signs out.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _pushSub?.cancel();
    _pushSub = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _version++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_started) unawaited(refresh());
    } else {
      _foreground = false;
    }
  }

  /// Asks the server for the unread count. Errors are ignored: the badge just
  /// keeps its last value.
  Future<void> refresh() async {
    final version = _version;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('donorId');
      if (id == null || id.isEmpty) return;
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_unread_notification_count.php'
              '?donor_id=$id',
            ),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return;
      final n = body['unread_count'];
      final value = n is num ? n.toInt() : int.tryParse('$n');
      if (value == null || version != _version) return;
      _write(value);
    } catch (_) {
      // Offline or a server hiccup: keep showing the last known number.
    }
  }

  /// Shows exactly [n] (the Alerts screen knows its own list).
  void set(int n) {
    _version++;
    _write(n);
  }

  /// Back to 0 (sign out).
  void clear() {
    _version++;
    _write(0);
  }

  void _write(int n) {
    final value = n < 0 ? 0 : n;
    if (count.value != value) count.value = value;
  }
}
