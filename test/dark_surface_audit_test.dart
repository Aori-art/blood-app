import 'package:blood/app_colors.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/check.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// In DARK mode no opaque white surface may be left over (the contrast tests
/// only look at text, so a white card or button would slip through them).
///
/// White stays allowed where it is content ON the brand red (chips, rings and
/// dots inside a red header or card) — found automatically by looking for a
/// red ancestor — plus the few intentional cases listed below.

const _white = Color(0xFFFFFFFF);

/// Intentional white surfaces, matched against the widget's creator chain.
const Map<String, String> _allowed = {
  // A QR code must stay dark-on-white to scan, in both modes.
  'QrImageView': 'QR code quiet zone',
  '_qrBox': 'QR code card',
};

bool _isWhite(Color? c) => c != null && c.toARGB32() == _white.toARGB32();

bool _isRed(Color c) =>
    c.toARGB32() == AppColors.primary.toARGB32() ||
    c.toARGB32() == AppColors.primaryDark.toARGB32();

Color? _fill(Widget w) {
  if (w is ColoredBox) return w.color;
  if (w is DecoratedBox && w.decoration is BoxDecoration) {
    return (w.decoration as BoxDecoration).color;
  }
  if (w is Material) {
    return w.type == MaterialType.transparency ? null : w.color;
  }
  if (w is PhysicalModel) return w.color;
  if (w is PhysicalShape) return w.color;
  return null;
}

bool _paintsRed(Widget w) {
  if (w is DecoratedBox && w.decoration is BoxDecoration) {
    final d = w.decoration as BoxDecoration;
    if (d.color != null && _isRed(d.color!)) return true;
    final g = d.gradient;
    if (g != null && g.colors.any(_isRed)) return true;
  }
  final f = _fill(w);
  return f != null && _isRed(f);
}

List<String> _whiteSurfaces(WidgetTester tester) {
  final found = <String>[];
  for (final e in tester.allElements) {
    if (!_isWhite(_fill(e.widget))) continue;
    // White content on the brand red is allowed.
    var onRed = false;
    e.visitAncestorElements((a) {
      if (_paintsRed(a.widget)) {
        onRed = true;
        return false;
      }
      return true;
    });
    if (onRed) continue;
    final chain = e.debugGetCreatorChain(8);
    if (_allowed.keys.any(chain.contains)) continue;
    found.add('${e.widget.runtimeType} <- $chain');
  }
  return found;
}

/// Every result of the eligibility check (the Dugtong stage, the cards and the
/// buttons). Dugtong's own whites (eyes, label, the medal's check) are painted
/// on a canvas, not widget fills, so they need no entry in [_allowed].
PumpableScreen _result(String name, Map<String, dynamic> status) =>
    PumpableScreen(
      'check result: $name',
      () => const CheckScreen(),
      responses: {'get_eligibility_status.php': status},
    );

final _resultScreens = [
  _result('eligible', {'status': 'eligible', 'can_book': true}),
  _result('not eligible', {'status': 'not_eligible', 'can_retake': true}),
  _result('retake countdown', {
    'status': 'not_eligible',
    'retake_available_date': '2099-01-01',
    'retake_days_remaining': 7,
  }),
  _result('deferred', {
    'status': 'temporary_deferred',
    'next_eligible_date': '2099-01-01',
  }),
  _result('under review', {'status': 'for_review'}),
];

void main() {
  for (final screen in [...pumpableScreens, ..._resultScreens]) {
    testWidgets(
      'no white surface in dark: ${screen.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
          'isLoggedIn': true,
          'donorId': '7',
          'userName': 'Rey Ashlee',
          'userEmail': 'rey@example.com',
          ...screen.prefs,
        });
        StreakController.instance.reset(forgetSeen: true);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.exceptionAsString();
          if (text.contains('overflowed') ||
              text.contains('MissingPlugin') ||
              text.contains('No Firebase App')) {
            return;
          }
          previous?.call(details);
        };
        late List<String> found;
        try {
          await http.runWithClient(() async {
            await tester.pumpWidget(
              MaterialApp(theme: AppTheme.dark, home: screen.build()),
            );
            await tester.pump(const Duration(milliseconds: 1600));
            await screen.act?.call(tester);
            found = _whiteSurfaces(tester);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 10));
          }, () => MockClient(screen.server));
        } finally {
          FlutterError.onError = previous;
        }
        expect(found, isEmpty, reason: found.join('\n'));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
