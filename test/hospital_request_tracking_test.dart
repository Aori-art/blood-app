import 'dart:async';
import 'dart:convert';

import 'package:blood/app_theme.dart';
import 'package:blood/blood_requests/blood_request_widgets.dart';
import 'package:blood/blood_requests/blood_requests_screen.dart';
import 'package:blood/blood_requests/hospital_request_detail_screen.dart';
import 'package:blood/blood_requests/hospital_request_widgets.dart';
import 'package:blood/blood_requests/request_blood_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hospital_request_fixtures.dart';
import 'support/pumpable_screens.dart';

/// Tracking a request sent to a hospital: the donor's list in the hub, the
/// request's screen in every status, cancelling it, and its refreshing.

class _Server {
  Map<String, dynamic>? list = trackedList();
  Completer<void>? holdList;
  Map<String, dynamic> request = trackedRequest(31, 'pending_review');
  Map<String, dynamic>? detailError;
  Map<String, dynamic>? cancelAnswer;

  int detailCalls = 0;
  final cancels = <Map<String, dynamic>>[];

  Future<http.Response> call(http.Request r) async {
    final path = r.url.path;
    if (path.endsWith('get_hospital_requests.php')) {
      await holdList?.future;
      final l = list;
      return l == null ? http.Response('oops', 500) : okJson(l);
    }
    if (path.endsWith('get_hospital_request_detail.php')) {
      detailCalls++;
      return okJson(detailError ?? trackedDetail(request));
    }
    if (path.endsWith('cancel_hospital_request.php')) {
      cancels.add(jsonDecode(r.body) as Map<String, dynamic>);
      final answer =
          cancelAnswer ??
          {
            'status': 'success',
            'code': 'REQUEST_CANCELLED',
            'request': {
              ...request,
              'status': 'cancelled',
              'status_label': 'Cancelled',
              'cancellation_reason': cancels.last['reason'],
              'can_cancel': false,
            },
          };
      if (answer['status'] == 'success') request = answer['request'];
      return okJson(answer);
    }
    if (path.endsWith('get_hospital_request_options.php')) {
      return okJson(hospitalOptions());
    }
    return pumpableServer(r);
  }
}

final _haptics = <String>[];

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  bool dark = false,
  double scale = 1,
  bool allowOverflow = true,
}) async {
  SharedPreferences.setMockInitialValues({'donorId': '7'});
  _haptics.clear();
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        _haptics.add('${call.arguments}');
      }
      return null;
    },
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if ((allowOverflow && text.contains('overflowed')) ||
        text.contains('MissingPlugin')) {
      return;
    }
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
      home: screen,
    ),
  );
  await formFrames(tester, 6);
}

Future<void> _with(_Server server, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(server.call));

/// The detail screen of request 31 on a fixed clock (Oct 30, 2099, 9 AM).
Widget _detail({Duration every = const Duration(seconds: 45)}) =>
    HospitalRequestDetailScreen(
      requestId: 31,
      refreshEvery: every,
      now: () => DateTime(2099, 10, 30, 9),
    );

/// Scrolls the detail screen until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('hospital-request-detail')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    position.jumpTo((position.pixels + 150).clamp(0, position.maxScrollExtent));
    await tester.pump();
  }
  await position.ensureVisible(
    tester.renderObject(finder.first),
    alignment: .3,
  );
  await tester.pump();
}

/// A Material button (plain or with an icon) labelled [label].
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  test('the pickup countdown', () {
    final now = DateTime(2099, 10, 30, 9);
    expect(pickupCountdownLabel('2099-10-30 17:00:00', now), 'Today 5:00 PM');
    expect(
      pickupCountdownLabel('2099-10-31 09:30:00', now),
      'Tomorrow 9:30 AM',
    );
    expect(pickupCountdownLabel('2099-11-01', now), 'in 2 days');
    expect(pickupCountdownLabel('2099-10-30', now), 'Today');
    expect(pickupCountdownLabel('2099-10-30 08:00:00', now), 'Deadline passed');
    expect(pickupCountdownLabel('2099-10-29', now), 'Deadline passed');
    expect(pickupCountdownLabel('soon', now), 'soon');
    expect(formatHospitalDate('2099-10-30 17:00:00'), 'Oct 30, 5:00 PM');
  });

  group('My Requests', () {
    testWidgets('the default tab: Active and History, a chip per status', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const BloodRequestsScreen());
        expect(find.text('My Requests'), findsOne);
        expect(find.text('Hospital Appeals'), findsOne);
        expect(
          find.text(
            "Requests go to the hospital you choose. Only the hospital sees "
            "the patient's details.",
          ),
          findsOne,
        );
        // Taller, so every card is built.
        tester.view.physicalSize = const Size(360, 3000);
        await formFrames(tester, 2);
        expect(find.text('Active'), findsOne);
        expect(find.text('History'), findsOne);
        expect(
          tester.getTopLeft(find.text('Active')).dy,
          lessThan(tester.getTopLeft(find.text('History')).dy),
        );
        for (final s in kStatusLabels.keys) {
          expect(find.byKey(ValueKey('status-$s')), findsOne, reason: s);
          expect(
            find.descendant(
              of: find.byKey(ValueKey('status-$s')),
              matching: find.text(kStatusLabels[s]!),
            ),
            findsOne,
          );
        }
        // The three active ones come first.
        final activeY = tester.getTopLeft(find.text('History')).dy;
        for (final s in ['pending_review', 'approved', 'ready']) {
          expect(
            tester.getTopLeft(find.byKey(ValueKey('status-$s'))).dy,
            lessThan(activeY),
          );
        }
        expect(find.text('2 units · Whole blood · O+'), findsNWidgets(7));
        expect(
          find.text('Needed by Oct 30 · Updated 5 minutes ago'),
          findsNWidgets(7),
        );
        // Ready for pickup: highlighted, "Action needed".
        expect(find.text('Action needed'), findsOne);
        final readyCard = tester.widget<Ink>(
          find.descendant(
            of: find.byKey(const ValueKey('request-card-3')),
            matching: find.byType(Ink),
          ),
        );
        final border = (readyCard.decoration! as BoxDecoration).border!;
        expect(border.top.width, 1.5);
        // The old pending banner is gone.
        expect(
          find.textContaining('reviewed by the Dugtong team'),
          findsNothing,
        );
        await _close(tester);
      });
    });

    testWidgets('a card opens its request', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const BloodRequestsScreen());
        await tester.tap(find.byKey(const ValueKey('request-card-1')));
        await formFrames(tester, 6);
        expect(find.byType(HospitalRequestDetailScreen), findsOne);
        expect(server.detailCalls, 1);
        await _close(tester);
      });
    });

    testWidgets('skeletons, then an error with retry', (tester) async {
      final server = _Server()
        ..holdList = Completer<void>()
        ..list = null;
      await _with(server, () async {
        await _pump(tester, const BloodRequestsScreen());
        expect(find.byType(HospitalRequestCard), findsNothing);
        expect(
          find.byWidgetPredicate((w) => '$w'.startsWith('BrSkeletonCard')),
          findsWidgets,
        );
        server.holdList!.complete();
        await formFrames(tester, 3);
        expect(find.text("Couldn't load requests"), findsOne);
        server
          ..holdList = null
          ..list = trackedList();
        await tester.tap(find.text('Try Again').first);
        await formFrames(tester, 4);
        expect(find.byType(HospitalRequestCard), findsWidgets);
        await _close(tester);
      });
    });

    testWidgets('nothing yet: the empty state asks a hospital', (tester) async {
      final server = _Server()
        ..list = {'status': 'success', 'counts': {}, 'requests': []};
      await _with(server, () async {
        await _pump(tester, const BloodRequestsScreen());
        expect(find.text('No requests yet'), findsOne);
        expect(
          find.text('Need blood for a patient? Ask a hospital.'),
          findsOne,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(BrEmptyState),
            matching: find.text('Request Blood'),
          ),
        );
        await formFrames(tester, 6);
        expect(find.byType(RequestBloodScreen), findsOne);
        await _close(tester);
      });
    });

    testWidgets('Hospital Appeals is the second tab', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const BloodRequestsScreen(initialTab: 1));
        expect(find.byType(HospitalRequestCard), findsNothing);
        await tester.tap(find.text('My Requests'));
        await formFrames(tester, 4);
        expect(find.byType(HospitalRequestCard), findsWidgets);
        await _close(tester);
      });
    });
  });

  group('the request screen', () {
    Future<void> show(WidgetTester tester, _Server server) async {
      await _pump(tester, _detail());
      expect(server.detailCalls, 1);
    }

    testWidgets('waiting: the hospital is reviewing; call; its stock', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await show(tester, server);
        expect(find.text('HR-0031'), findsOne);
        expect(find.text('Sent 2 hours ago'), findsOne);
        expect(find.byKey(const ValueKey('status-card-pending')), findsOne);
        expect(find.text('The hospital is reviewing your request'), findsOne);
        expect(
          find.text(
            'This can take a while. If it is urgent, call the hospital.',
          ),
          findsOne,
        );
        expect(find.text('In stock'), findsOne);
        expect(find.text('updated 2 hours ago'), findsOne);
        expect(_button('Call hospital'), findsOne);

        await _scrollTo(tester, find.byKey(const ValueKey('summary-card')));
        expect(find.text('Units requested'), findsOne);
        expect(find.text('Needed by'), findsOne);
        await _scrollTo(tester, find.byKey(const ValueKey('hospital-card')));
        expect(find.text('Charlie Blood Bank'), findsWidgets);
        expect(find.byTooltip('Call Charlie Blood Bank'), findsOne);
        expect(find.byTooltip('Directions to Charlie Blood Bank'), findsOne);
        await _scrollTo(tester, find.byKey(const ValueKey('timeline-card')));
        expect(find.text('Reviewed by the hospital'), findsOne);
        await _scrollTo(tester, find.byKey(const ValueKey('private-card')));
        expect(find.text('Only you and the hospital can see this'), findsOne);
        expect(find.text('Rey Ashlee Liwanag'), findsOne);
        expect(find.text('PT-0042'), findsOne);
        expect(find.text('Form photo attached'), findsOne);
        expect(find.text('Surgery on Friday'), findsOne);
        await _scrollTo(tester, find.text('Cancel Request'));
        expect(_button('Cancel Request'), findsOne);
        await _close(tester);
      });
    });

    testWidgets('approved: units set aside and the hospital\'s message', (
      tester,
    ) async {
      final server = _Server()..request = trackedRequest(31, 'approved');
      await _with(server, () async {
        await show(tester, server);
        expect(find.text('Approved by the hospital'), findsOne);
        expect(find.text('1 of 2 units set aside'), findsOne);
        expect(
          find.text('Please come to the blood bank on the 2nd floor.'),
          findsOne,
        );
        await _close(tester);
      });
    });

    testWidgets('ready: where, until when, what to bring, the way there', (
      tester,
    ) async {
      final server = _Server()..request = trackedRequest(31, 'ready');
      await _with(server, () async {
        await show(tester, server);
        expect(find.byKey(const ValueKey('status-card-ready')), findsOne);
        expect(find.text('Ready for pickup at Charlie Blood Bank'), findsOne);
        expect(find.text('Pick up by Oct 30, 5:00 PM'), findsOne);
        expect(find.text('Today 5:00 PM'), findsOne);
        await _scrollTo(tester, find.text('Get directions'));
        expect(find.text('A valid ID'), findsOne);
        expect(find.text("The hospital's blood request form"), findsOne);
        expect(find.text('Reference HR-0031'), findsOne);
        expect(_button('Get directions'), findsOne);
        expect(_button('Call hospital'), findsOne);
        await _close(tester);
      });
    });

    testWidgets('completed: wishes well and offers to book a donation', (
      tester,
    ) async {
      final server = _Server()..request = trackedRequest(31, 'fulfilled');
      await _with(server, () async {
        await show(tester, server);
        expect(find.text('Your request is complete'), findsOne);
        expect(find.text('We hope the patient gets well soon.'), findsOne);
        // No Home behind it here: the button does nothing.
        await tester.tap(find.text('Book a donation to help others'));
        await formFrames(tester, 2);
        expect(find.byType(HospitalRequestDetailScreen), findsOne);
        await _scrollTo(tester, find.byKey(const ValueKey('private-card')));
        expect(find.text('Cancel Request'), findsNothing);
        await _close(tester);
      });
    });

    testWidgets('declined: the reason and another hospital', (tester) async {
      final server = _Server()..request = trackedRequest(31, 'rejected');
      await _with(server, () async {
        await show(tester, server);
        expect(
          find.text("The hospital couldn't fulfil this request"),
          findsOne,
        );
        expect(find.text('We have no O+ platelets this week.'), findsOne);
        await tester.tap(find.text('Request from another hospital'));
        await formFrames(tester, 6);
        expect(find.byType(RequestBloodScreen), findsOne);
        await _close(tester);
      });
    });

    testWidgets('cancelled and expired: muted, and Request again', (
      tester,
    ) async {
      final server = _Server()..request = trackedRequest(31, 'cancelled');
      await _with(server, () async {
        await show(tester, server);
        expect(find.text('You cancelled this request'), findsOne);
        expect(find.text('No longer needed'), findsOne);
        expect(find.text('Request again'), findsOne);
        await _close(tester);
      });
      final expired = _Server()..request = trackedRequest(31, 'expired');
      await _with(expired, () async {
        await show(tester, expired);
        expect(find.text('This request expired'), findsOne);
        expect(
          find.text(
            'It expired because nobody answered it before the needed-by date.',
          ),
          findsOne,
        );
        expect(find.text('Request again'), findsOne);
        await _close(tester);
      });
    });
  });

  group('cancelling', () {
    Future<void> openDialog(WidgetTester tester) async {
      await _scrollTo(tester, find.text('Cancel Request'));
      await tester.tap(_button('Cancel Request'));
      await formFrames(tester, 3);
      expect(find.byType(AlertDialog), findsOne);
    }

    Finder confirm() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Cancel Request'),
    );

    testWidgets('a reason is needed; then the request is cancelled', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, _detail());
        await openDialog(tester);
        // Waiting for review: nothing set aside to release.
        expect(find.byKey(const ValueKey('cancel-release-note')), findsNothing);
        expect(tester.widget<TextButton>(confirm()).onPressed, isNull);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'ab',
        );
        await tester.pump();
        expect(find.text('Please write at least 3 characters.'), findsOne);
        expect(tester.widget<TextButton>(confirm()).onPressed, isNull);
        for (final q in [
          'No longer needed',
          'Got blood from another hospital',
          'I entered the wrong details',
        ]) {
          expect(find.text(q), findsOne);
        }
        await tester.tap(find.text('Patient was transferred'));
        await tester.pump();
        expect(tester.widget<TextButton>(confirm()).onPressed, isNotNull);
        await tester.tap(confirm());
        await formFrames(tester, 6);

        expect(server.cancels.single, {
          'donor_id': '7',
          'request_id': 31,
          'reason': 'Patient was transferred',
        });
        expect(find.text('Your request was cancelled'), findsOne);
        expect(find.byKey(const ValueKey('status-card-cancelled')), findsOne);
        expect(find.text('Patient was transferred'), findsOne);
        await _close(tester);
      });
    });

    testWidgets('approved: the dialog says the blood will be released', (
      tester,
    ) async {
      final server = _Server()..request = trackedRequest(31, 'approved');
      await _with(server, () async {
        await _pump(tester, _detail());
        await openDialog(tester);
        expect(
          find.text(
            'The hospital will be told and the blood set aside for you will '
            'be released.',
          ),
          findsOne,
        );
        await tester.tap(find.text('Back'));
        await formFrames(tester, 3);
        expect(server.cancels, isEmpty);
        await _close(tester);
      });
    });

    for (final (code, message) in [
      ('NOT_CANCELLABLE', 'This request can no longer be cancelled.'),
      ('NOT_FOUND', 'Request not found.'),
      ('INVALID_INPUT', 'Please give a reason (3 to 300 characters).'),
    ]) {
      testWidgets(
        '$code: a SnackBar${code == 'INVALID_INPUT' ? '' : ' and a reload'}',
        (tester) async {
          final server = _Server()
            ..cancelAnswer = {
              'status': 'error',
              'code': code,
              'message': message,
            };
          await _with(server, () async {
            await _pump(tester, _detail());
            await openDialog(tester);
            await tester.tap(find.text('No longer needed'));
            await tester.pump();
            await tester.tap(confirm());
            await formFrames(tester, 6);
            expect(find.text(message), findsOne);
            expect(server.detailCalls, code == 'INVALID_INPUT' ? 1 : 2);
            await _close(tester);
          });
        },
      );
    }
  });

  group('refreshing', () {
    testWidgets('every 45 s while active; a status change buzzes; it stops '
        'once the request is done', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, _detail());
        expect(server.detailCalls, 1);
        await tester.pump(const Duration(seconds: 45));
        await tester.pump();
        expect(server.detailCalls, 2);
        expect(_haptics.where((h) => h.contains('lightImpact')), isEmpty);

        server.request = trackedRequest(31, 'ready');
        await tester.pump(const Duration(seconds: 45));
        await formFrames(tester, 2);
        expect(server.detailCalls, 3);
        expect(find.byKey(const ValueKey('status-card-ready')), findsOne);
        expect(_haptics.where((h) => h.contains('lightImpact')), hasLength(1));

        server.request = trackedRequest(31, 'fulfilled');
        await tester.pump(const Duration(seconds: 45));
        await formFrames(tester, 2);
        expect(server.detailCalls, 4);
        // Done: no more checks.
        await tester.pump(const Duration(minutes: 5));
        expect(server.detailCalls, 4);
        await _close(tester);
      });
    });

    testWidgets('a finished request is never polled', (tester) async {
      final server = _Server()..request = trackedRequest(31, 'expired');
      await _with(server, () async {
        await _pump(tester, _detail());
        await tester.pump(const Duration(minutes: 3));
        expect(server.detailCalls, 1);
        await _close(tester);
      });
    });

    testWidgets('closed: the timer goes with it', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _detail()),
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await formFrames(tester, 6);
        expect(server.detailCalls, 1);
        await tester.tap(find.byTooltip('Back'));
        await formFrames(tester, 12);
        expect(find.byType(HospitalRequestDetailScreen), findsNothing);
        await tester.pump(const Duration(minutes: 3));
        expect(server.detailCalls, 1);
        // (A timer left behind would fail the test here.)
      });
    });

    testWidgets('hidden behind another screen: no checks', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, _detail());
        Navigator.of(
          tester.element(find.byType(HospitalRequestDetailScreen)),
        ).push(MaterialPageRoute(builder: (_) => const Scaffold()));
        await formFrames(tester, 6);
        await tester.pump(const Duration(seconds: 90));
        expect(server.detailCalls, 1);
        await _close(tester);
      });
    });

    testWidgets('back in the app: a silent refresh', (tester) async {
      final server = _Server()..request = trackedRequest(31, 'fulfilled');
      await _with(server, () async {
        await _pump(tester, _detail());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(server.detailCalls, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await formFrames(tester, 2);
        expect(server.detailCalls, 2);
        await _close(tester);
      });
    });
  });

  group('looks', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('$theme, text x1.3: My Requests', (tester) async {
        final server = _Server();
        final handle = tester.ensureSemantics();
        await _with(server, () async {
          await _pump(
            tester,
            const BloodRequestsScreen(),
            dark: dark,
            scale: 1.3,
            allowOverflow: false,
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await _close(tester);
        });
        handle.dispose();
      });
      for (final status in kStatusLabels.keys) {
        testWidgets('$theme, text x1.3: $status', (tester) async {
          final server = _Server()..request = trackedRequest(31, status);
          final handle = tester.ensureSemantics();
          await _with(server, () async {
            await _pump(
              tester,
              _detail(),
              dark: dark,
              scale: 1.3,
              allowOverflow: false,
            );
            for (final place in [
              find.byKey(
                ValueKey(
                  'status-card-${switch (status) {
                    'pending_review' => 'pending',
                    _ => status,
                  }}',
                ),
              ),
              find.byKey(const ValueKey('private-card')),
            ]) {
              await _scrollTo(tester, place);
              await formFrames(tester, 2);
              expect(tester.takeException(), isNull);
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
            }
            await _close(tester);
          });
          handle.dispose();
        });
      }
    }
  });
}
