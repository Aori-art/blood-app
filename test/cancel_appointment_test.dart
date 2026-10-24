import 'dart:async';
import 'dart:convert';

import 'package:blood/app_theme.dart';
import 'package:blood/book.dart';
import 'package:blood/cancel_appointment_sheet.dart';
import 'package:blood/privacy_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// Cancelling an appointment from the Book tab, and the "Booking is paused"
/// state, in both themes.

class _Server {
  String? status = 'approved'; // null: no appointment
  Map<String, dynamic>? policy = {
    'limit': 0,
    'consecutive_count': 0,
    'remaining': null,
    'restricted': false,
    'restriction_reason': null,
  };
  Map<String, dynamic> cancelResponse = {
    'success': true,
    'message': 'Appointment cancelled.',
    'consecutive_count': 1,
    'limit': 3,
    'remaining': 2,
    'restricted': false,
  };
  Map<String, dynamic>? policyAfterCancel;
  bool networkError = false;
  Completer<void>? policyGate;
  final bodies = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request r) async {
    switch (r.url.path.split('/').last) {
      case 'get_appointments.php':
        return okJson({
          'status': 'success',
          'data': status == null
              ? []
              : [
                  {
                    'appointment_id': 5,
                    'appointment_date': '2099-10-25',
                    'appointment_time': '09:00:00',
                    'donation_center': 'City Blood Center',
                    'status': status,
                  },
                ],
        });
      case 'get_cancel_policy.php':
        await policyGate?.future;
        return policy == null
            ? http.Response('nope', 500)
            : okJson({'success': true, 'policy': policy});
      case 'cancel_appointment.php':
        if (networkError) throw http.ClientException('offline');
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        if (cancelResponse['success'] == true) {
          status = null;
          if (policyAfterCancel != null) policy = policyAfterCancel;
        }
        return http.Response(jsonEncode(cancelResponse), 200);
    }
    return pumpableServer(r);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  bool dark = false,
  double scale = 1,
  Size size = const Size(360, 640),
}) async {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  // The test font is much wider than the real one (Roboto): overflow is not a
  // bug here (the layout is checked with real fonts separately).
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const BookScreen(),
    ),
  );
  await _frames(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

/// Runs [body] with the mock server serving the app's HTTP calls.
Future<void> _with(_Server s, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(s.handle));

final _screenCancel = find.widgetWithText(OutlinedButton, 'Cancel Appointment');
final _sheet = find.byType(CancelAppointmentSheet);
Finder _sheetConfirm() => find.descendant(
  of: _sheet,
  matching: find.widgetWithText(ElevatedButton, 'Cancel Appointment'),
);

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<ElevatedButton>(f).onPressed != null;

Future<void> _openSheet(WidgetTester tester) async {
  await _tap(tester, _screenCancel); // below the fold on a small phone
  await _frames(tester);
}

/// Scrolls to [f] (sheets and the small screen scroll) and taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  group('the Cancel button', () {
    for (final (status, shown) in [
      ('pending', true),
      ('scheduled', true),
      ('confirmed', true),
      ('approved', true),
      ('rescheduled', true),
      ('completed', false),
      ('cancelled', false),
      ('declined', false),
    ]) {
      testWidgets('is ${shown ? 'shown' : 'hidden'} for "$status"', (
        tester,
      ) async {
        final s = _Server()..status = status;
        await _with(s, () async {
          await _open(tester, s);
          expect(_screenCancel, shown ? findsOneWidget : findsNothing);
          // The Reschedule button is untouched either way.
          expect(find.text('Reschedule Appointment'), findsOneWidget);
          await _close(tester);
        });
      });
    }
  });

  group('the sheet', () {
    testWidgets('needs a reason; Other needs text', (tester) async {
      final s = _Server();
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        expect(find.text('Cancel this appointment?'), findsOneWidget);
        expect(find.text('City Blood Center'), findsWidgets);
        expect(_enabled(tester, _sheetConfirm()), isFalse);

        await _tap(tester, find.text('Not feeling well'));
        await _frames(tester, 2);
        expect(_enabled(tester, _sheetConfirm()), isTrue);

        // Other: a field appears, with a counter; two characters are not enough.
        await _tap(tester, find.text('Other'));
        await _frames(tester, 2);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('0/200'), findsOneWidget);
        expect(_enabled(tester, _sheetConfirm()), isFalse);
        await tester.enterText(find.byType(TextField), ' ab ');
        await _frames(tester, 2);
        expect(_enabled(tester, _sheetConfirm()), isFalse);
        await tester.enterText(find.byType(TextField), 'Out of town');
        await _frames(tester, 2);
        expect(_enabled(tester, _sheetConfirm()), isTrue);

        // Keeping the appointment closes the sheet and sends nothing.
        await _tap(tester, find.text('Keep Appointment'));
        await _frames(tester);
        expect(_sheet, findsNothing);
        expect(s.bodies, isEmpty);
        await _close(tester);
      });
    });

    for (final (name, policy, expected)
        in <(String, Map<String, dynamic>?, String?)>[
          (
            'no automatic restriction',
            {
              'limit': 0,
              'consecutive_count': 0,
              'remaining': null,
              'restricted': false,
            },
            null,
          ),
          (
            'normal',
            {
              'limit': 3,
              'consecutive_count': 1,
              'remaining': 2,
              'restricted': false,
            },
            "You've cancelled 1 appointment in a row. After 3 in a row, booking is "
                'paused until our team reviews your account.',
          ),
          (
            'last chance',
            {
              'limit': 3,
              'consecutive_count': 2,
              'remaining': 1,
              'restricted': false,
            },
            'This is your last cancellation before booking is paused.',
          ),
          ('failed to load', null, null),
        ]) {
      testWidgets('policy notice: $name', (tester) async {
        final s = _Server()..policy = policy;
        await _with(s, () async {
          await _open(tester, s);
          await _openSheet(tester);
          final notice = find.descendant(
            of: _sheet,
            matching: find.textContaining(RegExp(r'cancell')),
          );
          if (expected == null) {
            expect(
              find.descendant(
                of: _sheet,
                matching: find.textContaining('booking is paused'),
              ),
              findsNothing,
            );
          } else {
            expect(find.text(expected), findsOneWidget);
          }
          expect(notice, expected == null ? findsNothing : findsWidgets);
          expect(tester.takeException(), isNull);
          await _close(tester);
        });
      });
    }

    testWidgets('a skeleton line shows while the policy loads', (tester) async {
      final s = _Server();
      await _with(s, () async {
        await _open(tester, s);
        // The policy answer is held back until the sheet has been looked at.
        s.policyGate = Completer<void>();
        await _tap(tester, _screenCancel);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: _sheet,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'SkeletonPulse',
            ),
          ),
          findsOneWidget,
        );
        s.policyGate!.complete();
        await _frames(tester);
        expect(
          find.descendant(
            of: _sheet,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'SkeletonPulse',
            ),
          ),
          findsNothing,
        );
        await _close(tester);
      });
    });
  });

  group('cancelling', () {
    testWidgets('a successful cancel clears the appointment', (tester) async {
      final s = _Server();
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        await _tap(tester, find.text('Schedule conflict'));
        await _frames(tester, 2);
        await _tap(tester, _sheetConfirm());
        await _frames(tester, 14);
        expect(s.bodies, [
          {'donor_id': 7, 'appointment_id': 5, 'reason': 'Schedule conflict'},
        ]);
        expect(_sheet, findsNothing);
        expect(find.text('Appointment cancelled.'), findsOneWidget);
        // The appointment is gone and the booking form is back.
        expect(find.text('Your Appointment'), findsNothing);
        expect(find.text('Select Date'), findsOneWidget);
        await _close(tester);
      });
    });

    testWidgets('Other sends the typed text', (tester) async {
      final s = _Server();
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        await _tap(tester, find.text('Other'));
        await _frames(tester, 2);
        await tester.enterText(find.byType(TextField), '  Out of town  ');
        await _frames(tester, 2);
        await _tap(tester, _sheetConfirm());
        await _frames(tester, 14);
        expect(s.bodies.single['reason'], 'Out of town');
        await _close(tester);
      });
    });

    testWidgets('the restricted dialog, then the paused card', (tester) async {
      final s = _Server()
        ..cancelResponse = {
          'success': true,
          'message': 'Appointment cancelled.',
          'consecutive_count': 3,
          'limit': 3,
          'remaining': 0,
          'restricted': true,
        }
        ..policyAfterCancel = {
          'limit': 3,
          'consecutive_count': 3,
          'remaining': 0,
          'restricted': true,
          'restriction_reason':
              "You've cancelled 3 appointments in a row, so booking is paused "
              'until our team reviews your account.',
        };
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        await _tap(tester, find.text('Changed my mind'));
        await _frames(tester, 2);
        await _tap(tester, _sheetConfirm());
        await _frames(tester, 16);
        expect(find.text('Booking paused'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('3 appointments in a row'),
          ),
          findsOneWidget,
        );
        await _tap(tester, find.text('OK'));
        await _frames(tester);
        expect(find.text('Booking paused'), findsNothing);
        // The card replaces the booking form.
        expect(find.text('Booking is paused'), findsOneWidget);
        expect(find.text('Select Date'), findsNothing);
        await _close(tester);
      });
    });

    for (final code in [
      'NOT_CANCELLABLE',
      'APPOINTMENT_PASSED',
      'APPOINTMENT_NOT_FOUND',
    ]) {
      testWidgets('$code closes the sheet and reloads', (tester) async {
        final s = _Server()
          ..cancelResponse = {
            'success': false,
            'code': code,
            'message': 'It changed ($code).',
          };
        await _with(s, () async {
          await _open(tester, s);
          await _openSheet(tester);
          await _tap(tester, find.text('Not feeling well'));
          await _frames(tester, 2);
          await _tap(tester, _sheetConfirm());
          await _frames(tester, 14);
          expect(_sheet, findsNothing);
          expect(find.text('It changed ($code).'), findsOneWidget);
          await _close(tester);
        });
      });
    }

    testWidgets('another server error keeps the sheet open', (tester) async {
      final s = _Server()
        ..cancelResponse = {
          'success': false,
          'code': 'SERVER_ERROR',
          'message': 'Something went wrong.',
        };
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        await _tap(tester, find.text('Not feeling well'));
        await _frames(tester, 2);
        await _tap(tester, _sheetConfirm());
        await _frames(tester, 6);
        expect(_sheet, findsOneWidget);
        expect(find.text('Something went wrong.'), findsWidgets);
        expect(_enabled(tester, _sheetConfirm()), isTrue);
        await _close(tester);
      });
    });

    testWidgets('a network error keeps the sheet open', (tester) async {
      final s = _Server()..networkError = true;
      await _with(s, () async {
        await _open(tester, s);
        await _openSheet(tester);
        await _tap(tester, find.text('Not feeling well'));
        await _frames(tester, 2);
        await _tap(tester, _sheetConfirm());
        await _frames(tester, 6);
        expect(_sheet, findsOneWidget);
        expect(find.text('Connection error'), findsWidgets);
        await _close(tester);
      });
    });
  });

  group('restricted donors', () {
    testWidgets('the card replaces the booking form and its bar', (
      tester,
    ) async {
      final s = _Server()
        ..status = null
        ..policy = {
          'limit': 3,
          'consecutive_count': 3,
          'remaining': 0,
          'restricted': true,
          'restriction_reason': 'Too many cancellations in a row.',
        };
      await _with(s, () async {
        await _open(tester, s);
        expect(find.text('Booking is paused'), findsOneWidget);
        expect(find.text('Too many cancellations in a row.'), findsOneWidget);
        expect(
          find.textContaining('Our team will review your account.'),
          findsOneWidget,
        );
        expect(find.text('Select Date'), findsNothing);
        expect(find.text('Confirm Booking'), findsNothing);
        await _close(tester);
      });
    });

    testWidgets('a failed policy call counts as not restricted', (
      tester,
    ) async {
      final s = _Server()
        ..status = null
        ..policy = null;
      await _with(s, () async {
        await _open(tester, s);
        expect(find.text('Booking is paused'), findsNothing);
        expect(find.text('Select Date'), findsOneWidget);
        await _close(tester);
      });
    });

    testWidgets('an active appointment is still shown while restricted', (
      tester,
    ) async {
      final s = _Server()
        ..policy = {
          'limit': 3,
          'consecutive_count': 3,
          'remaining': 0,
          'restricted': true,
        };
      await _with(s, () async {
        await _open(tester, s);
        expect(find.text('Your Appointment'), findsOneWidget);
        expect(find.text('Booking is paused'), findsNothing);
        await _close(tester);
      });
    });
  });

  group('looks', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      Future<void> guidelines(WidgetTester tester) async {
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(
          tester,
          meetsGuideline(const _TapTargetsExceptHeader()),
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      testWidgets('the appointment with its Cancel button ($mode)', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final s = _Server()..status = 'rescheduled';
        await _with(s, () async {
          await _open(tester, s, dark: dark, scale: 1.3);
          await guidelines(tester);
          await _close(tester);
        });
        handle.dispose();
      });

      testWidgets('the sheet with Other and the last-chance notice ($mode)', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final s = _Server()
          ..policy = {
            'limit': 3,
            'consecutive_count': 2,
            'remaining': 1,
            'restricted': false,
          };
        await _with(s, () async {
          await _open(tester, s, dark: dark, scale: 1.3);
          await _openSheet(tester);
          await _tap(tester, find.text('Other'));
          await _frames(tester, 3);
          await tester.enterText(find.byType(TextField), 'Out of town');
          await _frames(tester, 3);
          await guidelines(tester);
          await _close(tester);
        });
        handle.dispose();
      });

      testWidgets('the paused card ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        final s = _Server()
          ..status = null
          ..policy = {
            'limit': 3,
            'consecutive_count': 3,
            'remaining': 0,
            'restricted': true,
            'restriction_reason': 'Too many cancellations in a row.',
          };
        await _with(s, () async {
          await _open(tester, s, dark: dark, scale: 1.3);
          await guidelines(tester);
          await _close(tester);
        });
        handle.dispose();
      });
    }
  });
}

/// The 48 px tap target guideline, except the shared header's 38 px Refresh
/// button (an existing look this change leaves alone).
class _TapTargetsExceptHeader extends MinimumTapTargetGuideline {
  const _TapTargetsExceptHeader()
    : super(size: const Size(48, 48), link: 'https://m3.material.io');

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      node.tooltip == 'Refresh' || super.shouldSkipNode(node);
}
