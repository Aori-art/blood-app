import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:blood/app_theme.dart';
import 'package:blood/book.dart';
import 'package:blood/donation_history.dart';
import 'package:blood/history.dart';
import 'package:blood/home.dart';
import 'package:blood/home_stat_sheets.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

/// The preview sheets of Home's stat cards: the blood type matching, the
/// donations with their loading states, the lives math, the footer buttons
/// and the look in both themes.

/// What the server says in these tests.
class _Server {
  String bloodType = 'A+';
  int donations = 4;

  /// 'ok', 'empty', 'fail' or 'wait' (until [gate] completes).
  String history = 'ok';
  Completer<void>? gate;
  int historyCalls = 0;

  /// When set, the profile (the numbers on the cards) waits for it.
  Completer<void>? profileGate;

  Future<http.Response> handle(http.Request r) async {
    final name = r.url.path.split('/').last;
    if (name == 'get_profile.php') {
      await profileGate?.future;
      return okJson({
        'status': 'success',
        'data': {'blood_type': bloodType, 'total_donations': donations},
      });
    }
    if (name == 'get_donation_history.php') {
      historyCalls++;
      if (history == 'wait') await gate?.future;
      if (history == 'fail') return http.Response('nope', 500);
      if (history == 'empty') {
        return okJson({'status': 'success', 'data': <Object>[]});
      }
      return okJson(
        pumpableScreens
            .firstWhere((s) => s.name == 'donation history (with donations)')
            .responses['get_donation_history.php']!,
      );
    }
    return pumpableServer(r);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Overflow reported for [home_stat_sheets.dart] (the test font is wider than
/// the real one, so overflow elsewhere is ignored).
final _overflows = <String>[];

void _setUp(WidgetTester tester, {bool reduceMotion = false}) {
  SharedPreferences.setMockInitialValues({
    kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
    'isLoggedIn': true,
    'donorId': '7',
    'userName': 'Rey Ashlee',
    'userEmail': 'rey@example.com',
  });
  StreakController.instance.reset(forgetSeen: true);
  _overflows.clear();
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
    if (text.contains('overflowed')) {
      if (details.toString().contains('home_stat_sheets.dart')) {
        _overflows.add(text);
      }
      return;
    }
    if (text.contains('MissingPlugin') || text.contains('No Firebase App')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _close(WidgetTester tester) async {
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

Future<void> _with(_Server s, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(s.handle));

/// Home, with its stats loaded.
Future<void> _pumpHome(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  );
  await _frames(tester, 16);
}

/// Only a sheet opener (no Home underneath): the footer buttons then find
/// no Home to switch tabs on.
Future<void> _pumpOpener(
  WidgetTester tester,
  StatKind kind, {
  required String? bloodType,
  required int donations,
  bool dark = false,
  double scale = 1,
  // Pump only this long after the tap (the count-up test looks early).
  int settleFrames = 16,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showStatPreview(
                context,
                kind,
                bloodType: bloodType,
                donations: donations,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _frames(tester, settleFrames);
}

Finder get _sheet => find.byType(StatPreviewSheet);

Finder _inSheet(Finder f) => find.descendant(of: _sheet, matching: f);

void main() {
  group('blood type matching', () {
    const table = <String, (List<String>, List<String>)>{
      'O-': (['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'], ['O-']),
      'O+': (['O+', 'A+', 'B+', 'AB+'], ['O-', 'O+']),
      'A-': (['A-', 'A+', 'AB-', 'AB+'], ['O-', 'A-']),
      'A+': (['A+', 'AB+'], ['O-', 'O+', 'A-', 'A+']),
      'B-': (['B-', 'B+', 'AB-', 'AB+'], ['O-', 'B-']),
      'B+': (['B+', 'AB+'], ['O-', 'O+', 'B-', 'B+']),
      'AB-': (['AB-', 'AB+'], ['O-', 'A-', 'B-', 'AB-']),
      'AB+': (['AB+'], ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+']),
    };

    for (final e in table.entries) {
      test('${e.key} gives to ${e.value.$1.join(', ')}', () {
        final m = bloodCompatibility(e.key)!;
        expect(m.giveTo, e.value.$1);
        expect(m.receiveFrom, e.value.$2);
      });
    }

    test('the spelling of a type is forgiven; anything else is unknown', () {
      expect(normalizeBloodType(' ab - '), 'AB-');
      expect(normalizeBloodType('o positive'), 'O+');
      expect(normalizeBloodType('B negative'), 'B-');
      for (final bad in [null, '', 'N/A', '-', '—', 'C+', 'A', 'unknown']) {
        expect(normalizeBloodType(bad), isNull, reason: '$bad');
        expect(bloodCompatibility(bad), isNull);
      }
    });
  });

  group('the cards open the sheets', () {
    testWidgets('each card opens its own sheet', (tester) async {
      _setUp(tester);
      await _with(_Server(), () async {
        await _pumpHome(tester);
        for (final (card, title) in [
          ('Blood Type', 'Your blood type'),
          ('Donations', 'Your donations'),
          ('Lives Saved', 'Lives saved'),
        ]) {
          await tester.tap(find.text(card));
          await _frames(tester, 12);
          expect(_inSheet(find.text(title)), findsOneWidget, reason: card);
          await tester.tap(find.byTooltip('Close'));
          await _frames(tester, 8);
          expect(_sheet, findsNothing);
        }
        await _close(tester);
      });
    });

    testWidgets('a card is not tappable while its number loads', (
      tester,
    ) async {
      _setUp(tester);
      final handle = tester.ensureSemantics();
      final s = _Server()..profileGate = Completer<void>();
      await _with(s, () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        );
        await _frames(tester, 6);
        // The profile has not come back: the card does nothing.
        await tester.tap(find.text('Donations'), warnIfMissed: false);
        await _frames(tester, 6);
        expect(_sheet, findsNothing);
        s.profileGate!.complete();
        await _frames(tester, 16);
        expect(
          find.bySemanticsLabel('Donations 4, double tap for details'),
          findsOneWidget,
        );
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('the cards say what a tap does', (tester) async {
      _setUp(tester);
      final handle = tester.ensureSemantics();
      await _with(_Server(), () async {
        await _pumpHome(tester);
        expect(
          find.bySemanticsLabel('Blood type A+, double tap for details'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Lives saved 12, double tap for details'),
          findsOneWidget,
        );
        await _close(tester);
      });
      handle.dispose();
    });
  });

  group('blood type sheet', () {
    testWidgets('a known type: the circle, who it gives to and receives from', (
      tester,
    ) async {
      _setUp(tester);
      final handle = tester.ensureSemantics();
      await _with(_Server(), () async {
        await _pumpHome(tester);
        await tester.tap(find.text('Blood Type'));
        await _frames(tester, 12);
        expect(_inSheet(find.text('A+')), findsWidgets);
        expect(
          find.bySemanticsLabel('You can donate to: A+, AB+'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('You can receive from: O-, O+, A-, A+'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Matching shown for red blood cells. The donation center '
            'confirms the final match.',
          ),
          findsOneWidget,
        );
        expect(find.text('Open profile'), findsNothing);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('an unknown type: no chips, a note and Open profile', (
      tester,
    ) async {
      _setUp(tester);
      await _with(_Server()..bloodType = 'N/A', () async {
        await _pumpHome(tester);
        await tester.tap(find.text('Blood Type'));
        await _frames(tester, 12);
        expect(find.text('You can donate to'), findsNothing);
        expect(
          find.text(
            "Your blood type isn't set yet. You can add it in your profile.",
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Open profile'));
        await _frames(tester, 12);
        expect(_sheet, findsNothing);
        expect(find.byType(HistoryScreen), findsOneWidget);
        await _close(tester);
      });
    });
  });

  group('donations sheet', () {
    testWidgets('loading shows skeleton rows, then the latest three', (
      tester,
    ) async {
      _setUp(tester);
      final s = _Server()
        ..history = 'wait'
        ..gate = Completer<void>();
      // (the card test below holds the profile back the same way)
      await _with(s, () async {
        await _pumpHome(tester);
        await tester.tap(find.text('Donations'));
        await _frames(tester, 6);
        expect(_inSheet(find.text('Recent donations')), findsOneWidget);
        expect(_inSheet(find.text('Oct 1, 2026')), findsNothing);
        expect(
          _inSheet(find.byWidgetPredicate((w) => w is SizedBox)),
          findsWidgets,
        );

        s.gate!.complete();
        await _frames(tester, 12);
        expect(_inSheet(find.text('Oct 1, 2026')), findsOneWidget);
        expect(_inSheet(find.text('Sep 2, 2026')), findsOneWidget);
        expect(_inSheet(find.text('May 10, 2026')), findsOneWidget);
        expect(_inSheet(find.textContaining('1 unit')), findsWidgets);
        expect(_inSheet(find.textContaining('0 units')), findsOneWidget);
        expect(_inSheet(find.text('Pending')), findsOneWidget);
        expect(_inSheet(find.text('Completed')), findsOneWidget);
        expect(_inSheet(find.text('Deferred')), findsOneWidget);
        // The count and the next milestone (4 donations: 1 more to 5).
        expect(_inSheet(find.text('4')), findsOneWidget);
        expect(_inSheet(find.text('donations')), findsOneWidget);
        expect(
          _inSheet(find.text('1 more donation to reach 5')),
          findsOneWidget,
        );
        await _close(tester);
      });
    });

    testWidgets('no donations: the empty state with Book an appointment', (
      tester,
    ) async {
      _setUp(tester);
      await _with(
        _Server()
          ..history = 'empty'
          ..donations = 0,
        () async {
          await _pumpHome(tester);
          await tester.tap(find.text('Donations'));
          await _frames(tester, 12);
          expect(
            find.text(
              'No donations yet. Your first donation can help save up to 3 lives.',
            ),
            findsOneWidget,
          );
          expect(_inSheet(find.text('donations')), findsOneWidget);
          expect(find.text('1 more donation to reach 1'), findsOneWidget);
          expect(find.text('Book an appointment'), findsOneWidget);
          await _close(tester);
        },
      );
    });

    testWidgets('a failure: a message, and Retry loads again', (tester) async {
      _setUp(tester);
      final s = _Server()..history = 'fail';
      await _with(s, () async {
        await _pumpHome(tester);
        await tester.tap(find.text('Donations'));
        await _frames(tester, 12);
        expect(find.text("Couldn't load your donations"), findsOneWidget);
        final calls = s.historyCalls;

        s.history = 'ok';
        await tester.tap(find.text('Retry'));
        await _frames(tester, 12);
        expect(s.historyCalls, calls + 1);
        expect(find.text("Couldn't load your donations"), findsNothing);
        expect(_inSheet(find.text('Oct 1, 2026')), findsOneWidget);
        await _close(tester);
      });
    });

    testWidgets('milestones: 0 -> 1, 3 -> 5, 10 -> all reached', (
      tester,
    ) async {
      _setUp(tester);
      for (final (n, text) in [
        (0, '1 more donation to reach 1'),
        (1, '2 more donations to reach 3'),
        (3, '2 more donations to reach 5'),
        (5, '5 more donations to reach 10'),
        (10, "You've reached every milestone. Thank you!"),
      ]) {
        await _with(_Server()..history = 'empty', () async {
          await _pumpOpener(
            tester,
            StatKind.donations,
            bloodType: 'A+',
            donations: n,
          );
          expect(find.text(text), findsOneWidget, reason: '$n donations');
          await _close(tester);
        });
      }
    });
  });

  group('lives sheet', () {
    Future<void> lives(WidgetTester tester, int donations) async {
      await _pumpOpener(
        tester,
        StatKind.lives,
        bloodType: 'A+',
        donations: donations,
      );
    }

    int filled() =>
        _inSheet(find.byIcon(Icons.person_rounded)).evaluate().length;
    int outlined() =>
        _inSheet(find.byIcon(Icons.person_outline_rounded)).evaluate().length;

    testWidgets('the math: donations x 3 and the people row', (tester) async {
      _setUp(tester);
      await lives(tester, 2); // 6 lives
      await _frames(tester, 12);
      expect(_inSheet(find.text('6')), findsOneWidget);
      expect(find.text('2 donations x 3 lives'), findsOneWidget);
      expect(filled(), 6);
      expect(outlined(), 6);
      expect(find.textContaining('more'), findsNothing);
      expect(
        find.text(
          'One donation can help save up to 3 lives. These are estimates.',
        ),
        findsOneWidget,
      );
      await _close(tester);
    });

    testWidgets('exactly 12 lives fill the row; more says +N more', (
      tester,
    ) async {
      _setUp(tester);
      await lives(tester, 4); // 12
      await _frames(tester, 12);
      expect(filled(), 12);
      expect(outlined(), 0);
      expect(find.textContaining('more'), findsNothing);
      await _close(tester);

      await lives(tester, 5); // 15
      await _frames(tester, 12);
      expect(filled(), 12);
      expect(find.text('+3 more'), findsOneWidget);
      expect(find.text('5 donations x 3 lives'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('one donation is singular; zero looks ahead', (tester) async {
      _setUp(tester);
      await lives(tester, 1);
      await _frames(tester, 12);
      expect(find.text('1 donation x 3 lives'), findsOneWidget);
      expect(filled(), 3);
      await _close(tester);

      await lives(tester, 0);
      await _frames(tester, 12);
      expect(
        find.text('Your first donation could help save up to 3 lives.'),
        findsOneWidget,
      );
      expect(filled(), 0);
      expect(outlined(), 12);
      await _close(tester);
    });
  });

  group('footer buttons', () {
    Future<bool> navSelected(WidgetTester tester, String label) async {
      return tester
              .getSemantics(find.bySemanticsLabel(label))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
    }

    testWidgets('with Home open they select the History and Book tabs', (
      tester,
    ) async {
      _setUp(tester);
      final handle = tester.ensureSemantics();
      await _with(_Server(), () async {
        await _pumpHome(tester);
        await tester.tap(find.text('Donations'));
        await _frames(tester, 12);
        await tester.tap(find.text('View donation history'));
        await _frames(tester, 25);
        expect(_sheet, findsNothing);
        expect(await navSelected(tester, 'Donation history'), isTrue);

        await tester.tap(find.bySemanticsLabel('Home'));
        await _frames(tester, 25);
        await tester.tap(find.text('Lives Saved'));
        await _frames(tester, 12);
        await tester.tap(find.text('Book a donation'));
        await _frames(tester, 25);
        expect(_sheet, findsNothing);
        expect(await navSelected(tester, 'Book an appointment'), isTrue);
        await _close(tester);
      });
      handle.dispose();
    });

    testWidgets('with no Home they push the screens', (tester) async {
      _setUp(tester);
      await _with(_Server()..history = 'empty', () async {
        await _pumpOpener(
          tester,
          StatKind.donations,
          bloodType: 'A+',
          donations: 0,
        );
        await tester.tap(find.text('View donation history'));
        await _frames(tester, 12);
        expect(find.byType(DonationHistoryScreen), findsOneWidget);
        await _close(tester);
      });
      await _with(_Server(), () async {
        await _pumpOpener(
          tester,
          StatKind.lives,
          bloodType: 'A+',
          donations: 2,
        );
        await tester.tap(find.text('Book a donation'));
        await _frames(tester, 12);
        expect(find.byType(BookScreen), findsOneWidget);
        await _close(tester);
      });
    });

    testWidgets('the empty state\'s Book button goes to the Book tab', (
      tester,
    ) async {
      _setUp(tester);
      final handle = tester.ensureSemantics();
      await _with(
        _Server()
          ..history = 'empty'
          ..donations = 0,
        () async {
          await _pumpHome(tester);
          await tester.tap(find.text('Donations'));
          await _frames(tester, 12);
          // On a short screen the empty state scrolls: bring the button in.
          await tester.ensureVisible(find.text('Book an appointment'));
          await tester.pump();
          await tester.tap(find.text('Book an appointment'));
          await _frames(tester, 25);
          expect(_sheet, findsNothing);
          expect(await navSelected(tester, 'Book an appointment'), isTrue);
          await _close(tester);
        },
      );
      handle.dispose();
    });
  });

  group('motion', () {
    testWidgets('numbers count up, and not with animations off', (
      tester,
    ) async {
      _setUp(tester);
      await _with(_Server()..history = 'empty', () async {
        await _pumpOpener(
          tester,
          StatKind.lives,
          bloodType: 'A+',
          donations: 4,
          settleFrames: 1,
        );
        // 700 ms count-up: a moment in, the number is part-way.
        final lives = _inSheet(find.textContaining(RegExp(r'^[0-9]+$')));
        final early = int.parse((tester.widget<Text>(lives.first).data ?? '0'));
        expect(early, lessThan(12));
        await _frames(tester, 12);
        expect(_inSheet(find.text('12')), findsOneWidget);
        await _close(tester);
      });

      _setUp(tester, reduceMotion: true);
      await _with(_Server()..history = 'empty', () async {
        await _pumpOpener(
          tester,
          StatKind.lives,
          bloodType: 'A+',
          donations: 4,
        );
        expect(_inSheet(find.text('12')), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        await _close(tester);
      });
    });
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      for (final (name, kind, type, n) in [
        ('blood type', StatKind.bloodType, 'AB-', 4),
        ('unknown blood type', StatKind.bloodType, 'N/A', 0),
        ('donations', StatKind.donations, 'A+', 4),
        ('lives', StatKind.lives, 'A+', 6),
      ]) {
        testWidgets('$name sheet meets the guidelines '
            '(${dark ? 'dark' : 'light'}, text x$scale)', (tester) async {
          _setUp(tester);
          final handle = tester.ensureSemantics();
          await _with(_Server(), () async {
            await _pumpOpener(
              tester,
              kind,
              bloodType: type,
              donations: n,
              dark: dark,
              scale: scale,
            );
            await _frames(tester, 12);
            expect(tester.takeException(), isNull);
            expect(_overflows, isEmpty, reason: _overflows.join(' | '));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await _close(tester);
          });
          handle.dispose();
        });
      }
    }
  }
}
