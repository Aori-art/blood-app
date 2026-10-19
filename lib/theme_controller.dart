import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

/// The preference key of the chosen mode. It survives logout and account
/// deletion (see `clearSessionKeepConsent`).
const String kThemeModeKey = 'theme_mode';

/// Whether the app is in dark mode. Light is the default, so nothing changes
/// for anyone who never touches the switch.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  bool _isDark = false;
  bool get isDark => _isDark;

  /// Call before `runApp`, so the first frame already has the right mode.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getString(kThemeModeKey) == 'dark';
    } catch (_) {
      _isDark = false;
    }
  }

  Future<void> setDark(bool value) async {
    if (value == _isDark) return;
    _isDark = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kThemeModeKey, value ? 'dark' : 'light');
    } catch (_) {
      // The mode still applies for this session.
    }
  }

  /// The system bar style that matches the mode.
  static SystemUiOverlayStyle overlayStyle(bool dark) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}
