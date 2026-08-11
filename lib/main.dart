import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
import 'splash_screen/splash_screen.dart';

/// Handles FCM messages when the app is in the background.
///
/// This must be:
/// - a top-level function
/// - not anonymous
/// - marked with @pragma('vm:entry-point')
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint(
    'Background notification: ${message.notification?.title}',
  );

  debugPrint(
    'Background message body: ${message.notification?.body}',
  );

  debugPrint(
    'Background message data: ${message.data}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using the configuration generated
  // by "flutterfire configure".
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background message handler.
  FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );

  // Ask the user for notification permission.
  final NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  debugPrint(
    'Notification permission: ${settings.authorizationStatus}',
  );

  // Get the FCM device token.
  //
  // Later, home.dart / NotificationService will send this
  // token to your PHP backend together with the donor ID.
  try {
    final String? token =
        await FirebaseMessaging.instance.getToken();

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
  final SharedPreferences prefs =
      await SharedPreferences.getInstance();

  final bool isLoggedIn =
      prefs.getBool('isLoggedIn') ?? false;

  runApp(
    MyApp(
      isLoggedIn: isLoggedIn,
    ),
  );
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

  const MyApp({
    super.key,
    required this.isLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eDonate',

      theme: ThemeData(
        useMaterial3: true,

        primarySwatch: Colors.red,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDC2626),
        ),

        splashFactory: InkSparkle.splashFactory,

        visualDensity:
            VisualDensity.adaptivePlatformDensity,

        pageTransitionsTheme:
            const PageTransitionsTheme(
          builders: {
            TargetPlatform.android:
                CupertinoPageTransitionsBuilder(),

            TargetPlatform.iOS:
                CupertinoPageTransitionsBuilder(),

            TargetPlatform.windows:
                CupertinoPageTransitionsBuilder(),

            TargetPlatform.macOS:
                CupertinoPageTransitionsBuilder(),

            TargetPlatform.linux:
                CupertinoPageTransitionsBuilder(),
          },
        ),
      ),

      home: SplashScreen(
        isLoggedIn: isLoggedIn,
      ),
    );
  }
}