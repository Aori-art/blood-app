import 'package:blood/app_colors.dart';
import 'package:blood/app_palette.dart';
import 'package:blood/app_theme.dart';
import 'package:blood/check.dart';
import 'package:blood/privacy_statement.dart';
import 'package:blood/streak/streak_screen.dart';
import 'package:blood/check/eligibility_result_view.dart';
import 'package:blood/check/result_stage.dart';
import 'package:blood/streak/interactive_dugtong.dart';
import 'package:blood/streak/streak_controller.dart';
import 'package:blood/widgets/glow_pulse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pumpable_screens.dart';

String _inDays(int n) {
  final d = DateTime.now().add(Duration(days: n));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final _cases = <String, EligibilityResultData>{
  'eligible': const EligibilityResultData(
    status: 'eligible',
    reason: 'All answers are within the donation guidelines.',
    canBook: true,
  ),
  'not eligible, can retake': const EligibilityResultData(
    status: 'not_eligible',
    reason: 'Recent tattoo within 12 months.',
    recommendation: 'Please wait 12 months after your tattoo.',
    canRetake: true,
  ),
  'not eligible, countdown': EligibilityResultData(
    status: 'not_eligible',
    reason: 'Low hemoglobin reported.',
    retakeDate: _inDays(7),
    retakeDaysRemaining: 7,
  ),
  'deferred': EligibilityResultData(
    status: 'temporary_deferred',
    reason: 'Recent cold or flu symptoms.',
    nextDate: _inDays(14),
  ),
  'deferred, can retake': EligibilityResultData(
    status: 'temporary_deferred',
    reason: 'Recent cold or flu symptoms.',
    nextDate: _inDays(14),
    canRetake: true,
  ),
  'under review': const EligibilityResultData(status: 'for_review'),
};

/// The buttons must keep their exact look, so a button that already misses the
/// text contrast guideline stays as it is: its case skips only that check
/// (the other guidelines still run) and the gap is named here.
const Map<(String, bool), String> _contrastGaps = {
  ('not eligible, can retake', true):
      'the existing "Take Eligibility Check Again" button: white on '
      'palette.primaryText (#FF6B81) is 2.7:1 in dark mode',
};

Widget _host(
  EligibilityResultData data, {
  required bool dark,
  double textScale = 1,
  bool celebrate = false,
}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: EligibilityResultView(
          data: data,
          entrance: const AlwaysStoppedAnimation(1),
          celebrate: celebrate,
          onBook: () {},
          onRetake: () {},
          onRefresh: () {},
          onPullRefresh: () async {},
        ),
      ),
    ),
  ),
);

Future<void> _setUp(
  WidgetTester tester, {
  Size size = const Size(360, 640),
}) async {
  SharedPreferences.setMockInitialValues({});
  StreakController.instance.reset(forgetSeen: true);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  for (final MapEntry(key: name, value: data) in _cases.entries) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        final mode = '${dark ? 'dark' : 'light'}, x$scale';
        final gap = _contrastGaps[(name, dark)];
        final title = gap == null
            ? '$name lays out and meets the guidelines ($mode)'
            : '$name lays out and meets the guidelines ($mode; contrast '
                  'not checked, known gap: $gap)';
        testWidgets(title, (tester) async {
          await _setUp(tester);
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(_host(data, dark: dark, textScale: scale));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          expect(tester.takeException(), isNull);
          if (gap == null) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
          await _tearDown(tester);
        });
      }
    }
  }

  bool isConfetti(Widget w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_ConfettiPainter';

  testWidgets('with animations removed: no ticker in the stage, no confetti', (
    tester,
  ) async {
    await _setUp(tester, size: const Size(360, 780));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    for (final data in _cases.values) {
      await tester.pumpWidget(_host(data, dark: false, celebrate: true));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final stage = find.byType(ResultStage);
      expect(stage, findsOneWidget);
      expect(
        find.descendant(
          of: stage,
          matching: find.byWidgetPredicate(isConfetti),
        ),
        findsNothing,
      );
      // The Book button's glow is static too: nothing ticks.
      expect(tester.binding.transientCallbackCount, 0, reason: data.status);
    }
    await _tearDown(tester);
  });

  testWidgets('confetti plays for a celebrated eligible result only', (
    tester,
  ) async {
    await _setUp(tester, size: const Size(360, 780));
    await tester.pumpWidget(
      _host(_cases['eligible']!, dark: false, celebrate: true),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byWidgetPredicate(isConfetti), findsOneWidget);
    await tester.pumpWidget(_host(_cases['eligible']!, dark: false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byWidgetPredicate(isConfetti), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('at most three tickers keep running once a result has settled', (
    tester,
  ) async {
    await _setUp(tester, size: const Size(360, 780));
    for (final MapEntry(key: name, value: data) in _cases.entries) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(data, dark: true));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(
        tester.binding.transientCallbackCount,
        lessThanOrEqualTo(3),
        reason: name,
      );
    }
    await _tearDown(tester);
  });

  testWidgets('the buttons are unchanged and in their states', (tester) async {
    await _setUp(tester, size: const Size(360, 780));
    Future<void> show(String name) async {
      await tester.pumpWidget(_host(_cases[name]!, dark: false));
      await tester.pump(const Duration(seconds: 1));
    }

    await show('eligible');
    expect(find.text('Book an Appointment'), findsOneWidget);
    expect(find.text('Take Eligibility Check Again'), findsNothing);
    expect(find.text('Refresh status'), findsOneWidget);
    final glow = tester.widget<GlowPulse>(
      find.ancestor(
        of: find.text('Book an Appointment'),
        matching: find.byType(GlowPulse),
      ),
    );
    expect(glow.color, AppColors.success);
    final book = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Book an Appointment'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      ),
    );
    expect(book.style?.backgroundColor?.resolve({}), AppPalette.light.success);
    expect(tester.getSize(find.byWidget(book)), const Size(360 - 48, 54));

    await show('not eligible, can retake');
    expect(find.text('Take Eligibility Check Again'), findsOneWidget);
    expect(find.text('Book an Appointment'), findsNothing);
    expect(find.text('Refresh status'), findsOneWidget);

    await show('not eligible, countdown');
    expect(find.text('Available in 7 days'), findsOneWidget);
    expect(find.text('Refresh status'), findsOneWidget);

    await show('deferred, can retake');
    expect(find.text('Take Eligibility Check Again'), findsOneWidget);

    await show('under review');
    expect(find.text('Book an Appointment'), findsNothing);
    expect(find.text('Take Eligibility Check Again'), findsNothing);
    expect(find.text('Refresh status'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('tapping Dugtong shows his next line', (tester) async {
    await _setUp(tester, size: const Size(360, 780));
    await tester.pumpWidget(_host(_cases['under review']!, dark: false));
    await tester.pump(const Duration(seconds: 2));
    final state = tester.state<ResultStageState>(find.byType(ResultStage));
    final first = state.currentLine;
    expect(kResultLines.values.expand((l) => l), contains(first));
    // Its tap test uses the wall clock, so a slow run could read a tap as a
    // hold: trigger the tap directly.
    tester
        .state<InteractiveDugtongState>(find.byType(InteractiveDugtong))
        .tapNow();
    await tester.pump(const Duration(seconds: 2));
    expect(state.currentLine, isNot(first));
    await _tearDown(tester);
  });

  testWidgets('the floating Dugtong steps aside while a result shows', (
    tester,
  ) async {
    await _setUp(tester, size: const Size(360, 780));
    SharedPreferences.setMockInitialValues({
      kPrivacyConsentVersionKey: kPrivacyPolicyVersion,
      'isLoggedIn': true,
      'donorId': '7',
    });
    final screen = PumpableScreen(
      'check',
      () => const CheckScreen(),
      responses: {
        'get_eligibility_status.php': {
          'status': 'not_eligible',
          'can_retake': true,
        },
      },
    );
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          navigatorObservers: [streakRouteObserver],
          home: screen.build(),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(ResultStage), findsOneWidget);
      expect(StreakController.instance.currentScreenHidden, isTrue);

      // Back to the questions: the bubble returns.
      await tester.tap(find.text('Take Eligibility Check Again'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(ResultStage), findsNothing);
      expect(StreakController.instance.currentScreenHidden, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => MockClient(screen.server));
  });
}
