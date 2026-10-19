import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny app wired like main.dart: the mode comes from the controller.
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeController.instance,
    builder: (context, _) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeController.instance.isDark
          ? ThemeMode.dark
          : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 250),
      home: Scaffold(
        body: Builder(
          builder: (context) => Container(
            key: const Key('box'),
            color: context.palette.surface,
            child: Text(
              'hello',
              style: TextStyle(color: context.palette.foreground),
            ),
          ),
        ),
      ),
    ),
  );
}

Color _boxColor(WidgetTester tester) =>
    (tester.widget<Container>(find.byKey(const Key('box'))).color)!;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.load();
  });

  test('light is the default, so nothing changes for anyone', () async {
    expect(ThemeController.instance.isDark, isFalse);
  });

  testWidgets('switching the mode changes everything that reads the palette', (
    tester,
  ) async {
    await tester.pumpWidget(const _App());
    expect(_boxColor(tester), AppPalette.light.surface);

    await ThemeController.instance.setDark(true);
    await tester.pump(); // rebuild with the dark theme
    await tester.pump(const Duration(milliseconds: 125)); // mid-fade
    final mid = _boxColor(tester);
    expect(mid, isNot(AppPalette.light.surface));
    expect(mid, isNot(AppPalette.dark.surface));

    await tester.pump(const Duration(milliseconds: 300));
    expect(_boxColor(tester), AppPalette.dark.surface);

    await ThemeController.instance.setDark(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_boxColor(tester), AppPalette.light.surface);
  });

  test('the choice is saved and survives a restart', () async {
    await ThemeController.instance.setDark(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kThemeModeKey), 'dark');

    // "Restart": a fresh read of the preferences.
    await ThemeController.instance.setDark(false);
    SharedPreferences.setMockInitialValues({kThemeModeKey: 'dark'});
    await ThemeController.instance.load();
    expect(ThemeController.instance.isDark, isTrue);
  });

  test('logout and account deletion keep the chosen mode', () async {
    SharedPreferences.setMockInitialValues({
      kThemeModeKey: 'dark',
      'isLoggedIn': true,
      'donorId': '7',
      'userName': 'Rey',
    });
    final prefs = await SharedPreferences.getInstance();
    await clearSessionKeepConsent(prefs);
    expect(prefs.getString(kThemeModeKey), 'dark');
    expect(prefs.getBool('isLoggedIn'), isNull);
    expect(prefs.getString('donorId'), isNull);
  });

  test('status and navigation bar icons flip with the mode', () {
    final light = ThemeController.overlayStyle(false);
    final dark = ThemeController.overlayStyle(true);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(dark.systemNavigationBarContrastEnforced, isFalse);
  });
}
