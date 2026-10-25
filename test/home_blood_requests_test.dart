import 'package:blood/app_theme.dart';
import 'package:blood/home.dart';
import 'package:blood/unread_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hospital_request_fixtures.dart';
import 'support/pumpable_screens.dart';

/// The Blood Requests section of Home: its two tiles are always the same
/// height, grow with the text, never lose their text, and the badge keeps
/// clear of the title. (The test font is much wider than the real one, so
/// nothing here asserts on overflow exceptions: the layout is checked
/// structurally.)

const _longHospital =
    'Southern Philippines Medical Center Blood Bank and Transfusion Services';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  required bool dark,
  required int appeals,
  String? hospitalRequest,
}) async {
  SharedPreferences.setMockInitialValues({'donorId': '7'});
  tester.view.physicalSize = Size(width, 2400);
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
  addTearDown(() => FlutterError.onError = previous);
  final summary = hospitalSummary(hospitalRequest);
  if (hospitalRequest != null) {
    (summary['latest'] as Map<String, dynamic>)['facility_name'] =
        _longHospital;
  }
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: HomeContent(onNavigateToTab: (_) {}),
        ),
      );
      await formFrames(tester, 8);
    },
    () => MockClient((r) async {
      if (r.url.path.endsWith('get_blood_request_summary.php')) {
        return okJson({
          'status': 'success',
          'open_count': appeals,
          'matching_count': appeals > 0 ? 1 : 0,
          'urgent_matching_count': 0,
        });
      }
      if (r.url.path.endsWith('get_hospital_request_summary.php')) {
        return okJson(summary);
      }
      if (r.url.path.endsWith('get_appointments.php')) {
        return okJson({
          'status': 'success',
          'data': [
            {
              'appointment_date': '2099-10-25',
              'appointment_time': '09:00:00',
              'donation_center': 'City Blood Center',
              'status': 'approved',
            },
          ],
        });
      }
      return pumpableServer(r);
    }),
  );
}

Future<void> _close(WidgetTester tester) async {
  UnreadNotifications.instance.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 70));
}

/// The 48 px guideline for the Blood Requests card only (the rest of Home
/// has its own tests): nodes outside [section] are skipped.
class _SectionTapTargets extends MinimumTapTargetGuideline {
  _SectionTapTargets(this.section)
    : super(size: const Size(48, 48), link: 'https://m3.material.io');

  final Rect section;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    var rect = node.rect;
    SemanticsNode? n = node;
    while (n != null) {
      final t = n.transform;
      if (t != null) rect = MatrixUtils.transformRect(t, rect);
      n = n.parent;
    }
    return !section.contains(rect.center) || super.shouldSkipNode(node);
  }
}

/// The places textContrastGuideline fails (as rectangles), from its report.
/// The guideline checks the whole of Home, whose appointment card has its own
/// known light-mode gap: this test only answers for the Blood Requests card.
Future<List<Rect>> _contrastFailures(WidgetTester tester) async {
  final result = await textContrastGuideline.evaluate(tester);
  if (result.passed) return const [];
  return [
    for (final m in RegExp(
      r'Rect\.fromLTRB\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)',
    ).allMatches(result.reason ?? ''))
      Rect.fromLTRB(
        double.parse(m.group(1)!),
        double.parse(m.group(2)!),
        double.parse(m.group(3)!),
        double.parse(m.group(4)!),
      ),
  ];
}

final _request = find.byKey(const ValueKey('request-tile'));
final _appeals = find.byKey(const ValueKey('appeals-tile'));
final _badge = find.byKey(const ValueKey('appeals-badge'));

void main() {
  const oldMinimum = 118.0;

  for (final dark in [false, true]) {
    for (final width in [320.0, 360.0, 411.0]) {
      testWidgets('${dark ? 'dark' : 'light'}, ${width.toInt()} px wide: the '
          'tiles match, grow with the text and keep their text', (
        tester,
      ) async {
        final heights = <double>[];
        for (final scale in [1.0, 1.3, 2.0]) {
          await _pump(
            tester,
            width: width,
            scale: scale,
            dark: dark,
            appeals: 1,
          );
          final a = tester.getSize(_request);
          final b = tester.getSize(_appeals);
          // Both tiles are always the same height, at least the old one.
          expect(a.height, b.height, reason: 'scale $scale');
          expect(a.height, greaterThanOrEqualTo(oldMinimum));
          heights.add(a.height);
          // Side by side with the same 12 px gap, each half the row.
          expect(a.width, closeTo(b.width, 0.01));
          expect(
            tester.getTopLeft(_appeals).dx - tester.getTopRight(_request).dx,
            closeTo(12, 0.01),
          );
          // Every text is limited and ends in an ellipsis.
          for (final tile in [_request, _appeals]) {
            final texts = tester.widgetList<Text>(
              find.descendant(of: tile, matching: find.byType(Text)),
            );
            expect(texts, isNotEmpty);
            for (final t in texts) {
              expect(t.maxLines, isNotNull, reason: '${t.data} at $scale');
              expect(t.overflow, TextOverflow.ellipsis);
            }
            // Nothing sticks out of the tile.
            final box = tester.getRect(tile);
            for (final e
                in find
                    .descendant(of: tile, matching: find.byType(Text))
                    .evaluate()) {
              final r = tester.getRect(find.byWidget(e.widget));
              expect(r.left, greaterThanOrEqualTo(box.left - 0.01));
              expect(r.right, lessThanOrEqualTo(box.right + 0.01));
              expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.01));
            }
          }
          // The badge keeps clear of the title and the icon.
          final badge = tester.getRect(_badge);
          expect(
            badge.overlaps(
              tester.getRect(
                find.descendant(
                  of: _appeals,
                  matching: find.text('Hospital Appeals'),
                ),
              ),
            ),
            isFalse,
            reason: 'scale $scale',
          );
          expect(
            badge.overlaps(
              tester.getRect(
                find.descendant(
                  of: _appeals,
                  matching: find.byIcon(Icons.volunteer_activism_rounded),
                ),
              ),
            ),
            isFalse,
            reason: 'scale $scale',
          );
          await _close(tester);
        }
        // It grows as the text grows.
        expect(heights[1], greaterThanOrEqualTo(heights[0]));
        expect(heights[2], greaterThan(heights[0]));
        // ignore: avoid_print
        print('HEIGHTS $width ${dark ? 'dark' : 'light'}: $heights');
      });
    }
  }

  for (final appeals in [1, 150]) {
    testWidgets('the badge reads ${appeals > 99 ? '99+' : '$appeals'}', (
      tester,
    ) async {
      await _pump(tester, width: 320, scale: 2, dark: false, appeals: appeals);
      expect(
        find.descendant(
          of: _badge,
          matching: find.text(appeals > 99 ? '99+' : '$appeals'),
        ),
        findsOne,
      );
      expect(
        tester
            .getRect(_badge)
            .overlaps(
              tester.getRect(
                find.descendant(
                  of: _appeals,
                  matching: find.text('Hospital Appeals'),
                ),
              ),
            ),
        isFalse,
      );
      await _close(tester);
    });
  }

  testWidgets('no appeals: no badge, and the tiles still match', (
    tester,
  ) async {
    await _pump(tester, width: 320, scale: 2, dark: false, appeals: 0);
    expect(_badge, findsNothing);
    expect(tester.getSize(_request).height, tester.getSize(_appeals).height);
    await _close(tester);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 360.0, 411.0]) {
      testWidgets('${dark ? 'dark' : 'light'}, ${width.toInt()} px wide: a '
          'long hospital name stays inside the strip', (tester) async {
        for (final scale in [1.0, 1.3, 2.0]) {
          await _pump(
            tester,
            width: width,
            scale: scale,
            dark: dark,
            appeals: 1,
            hospitalRequest: 'ready',
          );
          final strip = find.byKey(const ValueKey('request-status-strip'));
          expect(strip, findsOne);
          final box = tester.getRect(strip);
          // Within the card (the screen less Home's and the card's padding).
          expect(box.width, lessThanOrEqualTo(width - 32 - 36 + 0.01));
          expect(box.height, greaterThanOrEqualTo(48));
          for (final t in tester.widgetList<Text>(
            find.descendant(of: strip, matching: find.byType(Text)),
          )) {
            expect(t.maxLines, isNotNull, reason: '${t.data} at $scale');
            expect(t.overflow, TextOverflow.ellipsis);
          }
          for (final e
              in find
                  .descendant(of: strip, matching: find.byType(Text))
                  .evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(r.right, lessThanOrEqualTo(box.right + 0.01));
            expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.01));
          }
          await _close(tester);
        }
      });
    }
  }

  group('the header', () {
    testWidgets('its texts are limited and the button stays on screen', (
      tester,
    ) async {
      for (final width in [320.0, 411.0]) {
        await _pump(tester, width: width, scale: 2, dark: false, appeals: 1);
        final title = find.text('Blood Requests').first;
        expect(tester.widget<Text>(title).maxLines, 1);
        expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
        final sub = find.text('Ask a hospital for blood or answer an appeal');
        expect(tester.widget<Text>(sub).maxLines, isNotNull);
        final viewAll = find.text('View all');
        expect(tester.widget<Text>(viewAll).maxLines, 1);
        expect(tester.getRect(viewAll).right, lessThanOrEqualTo(width));
        await _close(tester);
      }
    });
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}, text x1.3: contrast and tap '
        'targets of the section', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        width: 360,
        scale: 1.3,
        dark: dark,
        appeals: 99,
        hospitalRequest: 'ready',
      );
      final section = tester
          .getRect(find.text('Blood Requests').first)
          .expandToInclude(tester.getRect(_request))
          .expandToInclude(
            tester.getRect(find.byKey(const ValueKey('request-status-strip'))),
          )
          .inflate(24);
      final failures = await _contrastFailures(tester);
      expect(
        failures.where((r) => r.overlaps(section)),
        isEmpty,
        reason: 'low contrast inside the Blood Requests card',
      );
      if (dark) expect(failures, isEmpty);
      await expectLater(tester, meetsGuideline(_SectionTapTargets(section)));
      // The tiles and the strip are at least 48 px tall targets; the
      // section's other buttons are checked as part of the whole Home below.
      for (final f in [
        _request,
        _appeals,
        find.byKey(const ValueKey('request-status-strip')),
      ]) {
        expect(tester.getSize(f).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(f).width, greaterThanOrEqualTo(48));
      }
      await _close(tester);
      handle.dispose();
    });
  }
}
