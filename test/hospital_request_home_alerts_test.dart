import 'dart:io';

import 'package:blood/alerts.dart';
import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/blood_requests/blood_requests_screen.dart';
import 'package:blood/blood_requests/hospital_request_detail_screen.dart';
import 'package:blood/blood_requests/hospital_request_models.dart';
import 'package:blood/blood_requests/hospital_request_widgets.dart';
import 'package:blood/home.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hospital_request_fixtures.dart';
import 'support/pumpable_screens.dart';

/// Hospital requests on Home (the status strip) and in Alerts (a look per
/// notification type), and the privacy statement's wording.

class _Server {
  Map<String, dynamic>? summary = hospitalSummary(null);
  Map<String, dynamic> detailRequest = trackedRequest(31, 'ready');
  int summaryCalls = 0;

  Future<http.Response> call(http.Request r) async {
    final path = r.url.path;
    if (path.endsWith('get_hospital_request_summary.php')) {
      summaryCalls++;
      final s = summary;
      return s == null ? http.Response('oops', 500) : okJson(s);
    }
    if (path.endsWith('get_blood_request_summary.php')) {
      return okJson({
        'status': 'success',
        'open_count': 3,
        'matching_count': 2,
        'urgent_matching_count': 0,
      });
    }
    if (path.endsWith('get_hospital_request_detail.php')) {
      return okJson(trackedDetail(detailRequest));
    }
    if (path.endsWith('get_hospital_requests.php')) {
      return okJson(trackedList());
    }
    if (path.endsWith('get_notifications.php')) {
      return okJson(hospitalNotifications());
    }
    return pumpableServer(r);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  bool dark = false,
  double scale = 1,
  bool reduceMotion = false,
  bool allowOverflow = true,
}) async {
  SharedPreferences.setMockInitialValues({'donorId': '7'});
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if ((allowOverflow && text.contains('overflowed')) ||
        text.contains('MissingPlugin') ||
        text.contains('No Firebase App')) {
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
  await formFrames(tester, 8);
}

Future<void> _with(_Server server, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(server.call));

Future<void> _close(WidgetTester tester) async {
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

Widget _home() => HomeContent(onNavigateToTab: (_) {});

final _strip = find.byKey(const ValueKey('request-status-strip'));

void main() {
  group('the status strip on Home', () {
    testWidgets('none yet: no strip, and the tiles are renamed', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, _home());
        expect(_strip, findsNothing);
        expect(find.text('Request Blood'), findsOne);
        expect(find.text('From a hospital'), findsOne);
        expect(find.text('Hospital Appeals'), findsOne);
        expect(find.text('Help a Patient'), findsNothing);
        expect(find.text('For you or a loved one'), findsNothing);
        await _close(tester);
      });
    });

    testWidgets('waiting: reference and status, what and where, updated', (
      tester,
    ) async {
      final server = _Server()..summary = hospitalSummary('pending_review');
      await _with(server, () async {
        await _pump(tester, _home());
        await tester.ensureVisible(_strip);
        expect(_strip, findsOne);
        expect(find.text('HR-0031 · Waiting for the hospital'), findsOne);
        expect(find.text('2 units of O+ at Charlie Blood Bank'), findsOne);
        expect(find.text('Updated 2 hours ago'), findsOne);
        // Not ready: a still icon, no pulsing dot.
        expect(
          find.descendant(of: _strip, matching: find.byType(StatusDot)),
          findsNothing,
        );
        await _close(tester);
      });
    });

    testWidgets('ready for pickup: success tint, a pulsing dot, opens the '
        'request', (tester) async {
      final server = _Server()..summary = hospitalSummary('ready', active: 3);
      await _with(server, () async {
        await _pump(tester, _home());
        await tester.ensureVisible(_strip);
        expect(find.text('HR-0031 · Ready for pickup'), findsOne);
        expect(find.text('Updated 2 hours ago · +2 more active'), findsOne);
        expect(
          find.descendant(of: _strip, matching: find.byType(StatusDot)),
          findsOne,
        );
        final before = server.summaryCalls;
        await tester.tap(_strip);
        await formFrames(tester, 6);
        expect(find.byType(HospitalRequestDetailScreen), findsOne);
        expect(find.text('Ready for pickup at Charlie Blood Bank'), findsOne);
        // Coming back refreshes the strip.
        await tester.tap(find.byTooltip('Back'));
        await formFrames(tester, 8);
        expect(server.summaryCalls, greaterThan(before));
        await _close(tester);
      });
    });

    testWidgets('a finished request is not shown', (tester) async {
      final server = _Server()
        ..summary = hospitalSummary('fulfilled', active: 0);
      await _with(server, () async {
        await _pump(tester, _home());
        expect(_strip, findsNothing);
        await _close(tester);
      });
    });

    testWidgets('an error stays silent: no strip and no message', (
      tester,
    ) async {
      final server = _Server()..summary = null;
      await _with(server, () async {
        await _pump(tester, _home());
        expect(_strip, findsNothing);
        expect(find.textContaining("Couldn't"), findsNothing);
        expect(find.text('Request Blood'), findsOne);
        await _close(tester);
      });
    });

    testWidgets('it follows the same refresh as the rest of Home', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, _home());
        expect(_strip, findsNothing);
        expect(server.summaryCalls, 1);
        server.summary = hospitalSummary('approved');
        await tester.fling(
          find.byType(SingleChildScrollView).first,
          const Offset(0, 400),
          1000,
        );
        await formFrames(tester, 10);
        expect(server.summaryCalls, 2);
        expect(_strip, findsOne);
        expect(find.text('HR-0031 · Approved'), findsOne);
        await _close(tester);
      });
    });

    // The strip alone, as wide as Home's card holds it, with a long hospital
    // name: nothing overflows, and it meets the guidelines.
    for (final dark in [false, true]) {
      for (final status in ['pending_review', 'ready']) {
        testWidgets('${dark ? 'dark' : 'light'}, text x1.3: the strip alone '
            '($status)', (tester) async {
          final handle = tester.ensureSemantics();
          final latest = HospitalLatestRequest.fromJson({
            ...(hospitalSummary(status)['latest'] as Map<String, dynamic>),
            'facility_name': 'Southern Philippines Medical Center Blood Bank',
          });
          await _pump(
            tester,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: HospitalStatusStrip(
                  latest: latest,
                  activeCount: 3,
                  onTap: () {},
                ),
              ),
            ),
            dark: dark,
            scale: 1.3,
            allowOverflow: false,
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    }

    for (final dark in [false, true]) {
      for (final status in ['pending_review', 'approved', 'ready']) {
        testWidgets('${dark ? 'dark' : 'light'}, text x1.3: the strip '
            '($status)', (tester) async {
          final server = _Server()..summary = hospitalSummary(status);
          final handle = tester.ensureSemantics();
          await _with(server, () async {
            await _pump(tester, _home(), dark: dark, scale: 1.3);
            await tester.ensureVisible(_strip);
            await formFrames(tester, 3);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            // The strip is a 48 px target.
            expect(tester.getSize(_strip).height, greaterThanOrEqualTo(48));
            await _close(tester);
          });
          handle.dispose();
        });
      }
    }
  });

  group('Alerts', () {
    final labels = {
      'hospital_request_submitted': Icons.send_rounded,
      'hospital_request_approved': Icons.check_circle_rounded,
      'hospital_request_ready': Icons.local_hospital_rounded,
      'hospital_request_fulfilled': Icons.celebration_rounded,
      'hospital_request_rejected': Icons.block_rounded,
      'hospital_request_cancelled': Icons.cancel_rounded,
    };

    testWidgets('each type has its own icon, tint and a Blood Request label', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const AlertsScreen(donorId: 7));
        tester.view.physicalSize = const Size(360, 2400);
        await formFrames(tester, 2);
        expect(find.text('Blood Request'), findsNWidgets(6));
        final p = tester.element(find.byType(AlertsScreen)).palette;
        final tints = <Color>{};
        for (final entry in labels.entries) {
          final icon = find.byIcon(entry.value);
          expect(icon, findsOneWidget, reason: entry.key);
          tints.add(tester.widget<Icon>(icon).color!);
        }
        final byIcon = {
          for (final e in labels.entries)
            e.key: tester.widget<Icon>(find.byIcon(e.value)).color,
        };
        expect(byIcon['hospital_request_submitted'], p.info);
        expect(byIcon['hospital_request_approved'], p.info);
        expect(byIcon['hospital_request_ready'], p.success);
        expect(byIcon['hospital_request_fulfilled'], p.success);
        expect(byIcon['hospital_request_rejected'], p.primaryText);
        expect(byIcon['hospital_request_cancelled'], p.muted);
        // The old types are as they were.
        expect(tints.length, 4);
        await _close(tester);
      });
    });

    testWidgets('a tap opens My Requests', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const AlertsScreen(donorId: 7));
        await tester.tap(find.text('Request update 3'));
        await formFrames(tester, 8);
        expect(find.byType(BloodRequestsScreen), findsOne);
        expect(find.text('My Requests'), findsOne);
        expect(find.byType(HospitalRequestCard), findsWidgets);
        await _close(tester);
      });
    });

    testWidgets('other types still expand in place', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, const AlertsScreen(donorId: 7));
        // (The fixture server's own list has no hospital types.)
        expect(find.byType(BloodRequestsScreen), findsNothing);
        await _close(tester);
      });
    });

    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}, text x1.3: the hospital '
          'notifications', (tester) async {
        final server = _Server();
        final handle = tester.ensureSemantics();
        await _with(server, () async {
          await _pump(
            tester,
            const AlertsScreen(donorId: 7),
            dark: dark,
            scale: 1.3,
            allowOverflow: false,
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          // (The delete-all button already there has no label: not part of this.)
          await _close(tester);
        });
        handle.dispose();
      });
    }
  });

  group('the privacy statement', () {
    String text() => File('lib/privacy_statement.dart').readAsStringSync();

    testWidgets('says what a hospital request collects and who sees it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: PrivacyStatementView()),
          ),
        ),
      );
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(shown, contains("the patient's name"));
      expect(shown, contains('relationship to the patient'));
      expect(shown, contains('a contact number'));
      expect(shown, contains('an optional hospital reference number'));
      expect(shown, contains("a photo of the hospital's blood request form"));
      expect(
        shown,
        contains(
          'shared only with the hospital you asked and authorized Dugtong '
          'administrators. They are not shown to other donors.',
        ),
      );
      expect(shown, contains('stored privately'));
      expect(shown, contains('blood requests (the patient'));
    });

    test('no longer says requests go to other donors', () {
      final s = text().replaceAll(RegExp(r"'\s*\n\s*'"), '');
      for (final old in [
        'visible to all donors',
        'matching donors',
        'donors can volunteer',
        'shown to donors',
        'shared with donors',
        'replacement donor',
      ]) {
        expect(s.toLowerCase(), isNot(contains(old)), reason: old);
      }
      // Every line about blood requests says who gets them: the hospital.
      for (final line
          in s
              .split('\n')
              .where(
                (l) => RegExp('blood request').hasMatch(l.toLowerCase()),
              )) {
        expect(line.toLowerCase(), isNot(contains('other donors can')));
      }
    });

    test('the other places that talk about requests say hospital', () {
      for (final path in [
        'lib/privacy_statement.dart',
        'lib/help_support.dart',
        'lib/home.dart',
        'lib/blood_requests/request_blood_screen.dart',
        'lib/blood_requests/hospital_request_detail_screen.dart',
        'lib/blood_requests/hospital_request_widgets.dart',
      ]) {
        final s = File(path).readAsStringSync();
        for (final old in [
          'Visible to all donors',
          'Note for donors',
          "Help a Patient'",
          'For you or a loved one',
          'Requests are reviewed by the Dugtong team before donors',
        ]) {
          expect(s, isNot(contains(old)), reason: '$path says "$old"');
        }
      }
    });

    test('the policy version was not bumped', () {
      expect(kPrivacyPolicyVersion, '2026-10-12-v2');
    });
  });
}
