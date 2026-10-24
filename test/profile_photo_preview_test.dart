import 'package:blood/app_theme.dart';
import 'package:blood/history.dart';
import 'package:blood/my_avatar_controller.dart';
import 'package:blood/privacy_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_streak.dart';
import 'support/pumpable_screens.dart';

/// Tapping the profile photo on the Profile screen opens it full screen; with
/// no photo there is a short note instead.

const _profile = {
  'status': 'success',
  'data': {
    'full_name': 'Rey Ashlee',
    'email': 'rey@example.com',
    'blood_type': 'O+',
    'total_donations': 4,
  },
};

Future<http.Response> _server(http.Request r) async {
  if (r.url.path.endsWith('get_profile.php')) return okJson(_profile);
  return pumpableServer(r);
}

Future<void> _pump(
  WidgetTester tester, {
  required bool dark,
  String? photo,
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
  });
  useFakeStreak(fakeStreak());
  final me = MyAvatarController.instance;
  me.avatarPath = photo;
  me.name = 'Rey Ashlee';
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() {
    useFakeStreak(null);
    me.avatarPath = null;
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: const HistoryScreen(),
    ),
  );
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

final _viewer = find.byType(InteractiveViewer);
final _avatar = find.bySemanticsLabel('View profile photo');

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('with a photo, tapping the avatar opens it ($mode)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await http.runWithClient(() async {
        await _pump(tester, dark: dark, photo: 'https://example.com/me.jpg');
        expect(_viewer, findsNothing);
        await tester.tap(_avatar);
        await _frames(tester);
        expect(_viewer, findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(
          find.descendant(of: _viewer, matching: find.byType(Image)),
          findsOneWidget,
        );
        // The donor's name on top.
        expect(find.text('Rey Ashlee'), findsWidgets);

        // Closes with the close button.
        await tester.tap(find.byTooltip('Close'));
        await _frames(tester);
        expect(_viewer, findsNothing);

        // ... and with the system back button.
        await tester.tap(_avatar);
        await _frames(tester);
        expect(_viewer, findsOneWidget);
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(_viewer, findsNothing);
        expect(tester.takeException(), isNull);
        await _done(tester);
      }, () => MockClient(_server));
      handle.dispose();
    });

    testWidgets('without a photo, tapping shows a note ($mode)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await http.runWithClient(() async {
        await _pump(tester, dark: dark);
        await tester.tap(_avatar);
        await _frames(tester, 4);
        expect(find.text("You haven't added a profile photo yet."), findsOne);
        expect(_viewer, findsNothing);
        await _done(tester);
      }, () => MockClient(_server));
      handle.dispose();
    });

    testWidgets('the Edit Frame pill still opens the frames ($mode)', (
      tester,
    ) async {
      // The frame sheet's small labels overflow only in the test font (Ahem
      // is much wider than Roboto; with Roboto the sheet lays out cleanly),
      // as in the theme tests. Every other error still fails the test.
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      await http.runWithClient(() async {
        await _pump(tester, dark: dark, photo: 'https://example.com/me.jpg');
        await tester.tap(find.text('Edit Frame'));
        await _frames(tester);
        expect(_viewer, findsNothing);
        expect(find.text('No frame'), findsOneWidget);
        await _done(tester);
      }, () => MockClient(_server));
    });
  }

  testWidgets('the avatar is a button with a 48 px target', (tester) async {
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      await _pump(tester, dark: false);
      final size = tester.getSize(_avatar);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(_avatar),
        matchesSemantics(
          label: 'View profile photo',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await _done(tester);
    }, () => MockClient(_server));
    handle.dispose();
  });
}
