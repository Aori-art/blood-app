import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
import 'splash_screen/splash_screen.dart';
import 'streak/streak_bubble.dart';
import 'streak/streak_controller.dart';
import 'streak/streak_screen.dart';

/// The floating streak bubble lives above the Navigator, so it reaches routes,
/// dialogs and sheets through this key.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Handles FCM messages when the app is in the background.
///
/// This must be:
/// - a top-level function
/// - not anonymous
/// - marked with @pragma('vm:entry-point')
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('Background notification: ${message.notification?.title}');

  debugPrint('Background message body: ${message.notification?.body}');

  debugPrint('Background message data: ${message.data}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw edge-to-edge with a transparent system navigation bar so the
  // Android nav bar never paints an opaque strip behind the floating
  // bottom nav pill in home.dart.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
    ),
  );

  // Initialize Firebase using the configuration generated
  // by "flutterfire configure".
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background message handler.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Ask the user for notification permission.
  final NotificationSettings settings = await FirebaseMessaging.instance
      .requestPermission(alert: true, badge: true, sound: true);

  debugPrint('Notification permission: ${settings.authorizationStatus}');

  // Get the FCM device token.
  //
  // Later, home.dart / NotificationService will send this
  // token to your PHP backend together with the donor ID.
  try {
    final String? token = await FirebaseMessaging.instance.getToken();

    debugPrint('FCM TOKEN: $token');
  } catch (e) {
    debugPrint('Unable to get FCM token: $e');
  }

  // Prepares local-notification display and push-tap handling. Safe to call
  // once here since main() only runs once per process.
  await NotificationService.instance.init();

  // Keep the backend's copy of the token in sync whenever Firebase rotates
  // it. Registered exactly once (main() runs once per process), so this
  // never creates duplicate listeners.
  FirebaseMessaging.instance.onTokenRefresh.listen(_handleTokenRefresh);

  // Check the existing login session.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Matches _NewsfeedPageState._checkLoginStatus()'s rule exactly so the
  // splash routing and the newsfeed's signed-in UI can never disagree.
  final bool loggedIn = prefs.getBool('isLoggedIn') ?? false;
  final String? donorId = prefs.getString('donorId');
  final bool isLoggedIn = loggedIn && donorId != null && donorId.isNotEmpty;

  // Load the cached streak first so the bubble shows instantly, then ask the
  // server to record today (idempotent, and silent if offline).
  await StreakController.instance.init();

  runApp(MyApp(isLoggedIn: isLoggedIn));

  if (isLoggedIn) unawaited(StreakController.instance.onLoggedIn());
}

Future<void> _handleTokenRefresh(String token) async {
  final prefs = await SharedPreferences.getInstance();
  final donorIdString = prefs.getString('donorId');
  final donorId = int.tryParse(donorIdString ?? '0') ?? 0;

  if (donorId <= 0) return;

  try {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/save_fcm_token.php'),
          body: {'donor_id': donorId.toString(), 'fcm_token': token},
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('FCM token refresh saved: ${response.body}');
  } catch (e) {
    debugPrint('Error saving refreshed FCM token: $e');
  }
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'eDonate',

      // Dugtong's floating bubble sits above every route. Each screen reports
      // itself with StreakScreen, and this observer follows the navigation.
      navigatorObservers: [streakRouteObserver],

      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          const StreakBubbleOverlay(),
        ],
      ),

      theme: ThemeData(
        useMaterial3: true,

        primarySwatch: Colors.red,

        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDC2626)),

        splashFactory: InkSparkle.splashFactory,

        visualDensity: VisualDensity.adaptivePlatformDensity,

        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),

            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),

            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),

            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),

            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),

      home: SplashScreen(isLoggedIn: isLoggedIn),
    );
  }
}
