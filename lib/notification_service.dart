import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Bridges Firebase Cloud Messaging with local (in-app) notification display
/// and app navigation. MySQL (via get_notifications.php) remains the
/// authoritative notification inbox — this service only tells the rest of
/// the app "something changed" or "the user tapped a push".
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'edonate_notifications',
    'eDonate Notifications',
    description:
        'Notifications about your appointments, eligibility, and donations.',
    importance: Importance.high,
  );

  final StreamController<void> _onNotificationReceived =
      StreamController<void>.broadcast();
  final StreamController<void> _onAlertsTapped =
      StreamController<void>.broadcast();

  /// Fires whenever an FCM message arrives while the app is in the
  /// foreground — used by alerts.dart to refresh its list from MySQL.
  Stream<void> get onNotificationReceived => _onNotificationReceived.stream;

  /// Fires whenever the user taps a push notification (foreground local
  /// notification, background system tray, or terminated cold start).
  Stream<void> get onAlertsTapped => _onAlertsTapped.stream;

  bool _initialized = false;
  bool _openAlertsOnStart = false;

  /// Whether HomeScreen should open directly on the Alerts tab because the
  /// app was launched by tapping a push notification while terminated.
  bool get openAlertsOnStart => _openAlertsOnStart;

  void consumeOpenAlertsOnStart() {
    _openAlertsOnStart = false;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (_) {
        _onAlertsTapped.add(null);
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Foreground: FCM does not show a system notification by itself, so we
    // show one via flutter_local_notifications. Background/terminated
    // messages are shown automatically by the OS from the FCM payload, so
    // handling them here too would create duplicates.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _onAlertsTapped.add(null);
    });

    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _openAlertsOnStart = true;
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );

    _onNotificationReceived.add(null);
  }

  @visibleForTesting
  void dispose() {
    _onNotificationReceived.close();
    _onAlertsTapped.close();
  }
}
