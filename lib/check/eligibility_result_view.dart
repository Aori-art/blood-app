// The result screens of the eligibility check (eligible, not eligible,
// temporarily deferred, under review). State, scoring, API calls and
// navigation stay in check.dart; this only draws what it is given.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../anim.dart';
import '../app_colors.dart';
import '../app_palette.dart';
import '../check.dart' show formatEligibilityDate, retakeWhenText;
import '../home.dart' show FloatingNavMetrics;
import '../widgets/glow_pulse.dart';
import 'result_clock.dart';
import 'result_stage.dart';
import 'result_style.dart';

/// What the server said about the donor's screening.
class EligibilityResultData {
  final String status;
  final String? reason;
  final String? recommendation;
  final String? nextDate;
  final String? retakeDate;
  final int retakeDaysRemaining;
  final bool canBook;
  final bool canRetake;

  const EligibilityResultData({
    required this.status,
    this.reason,
    this.recommendation,
    this.nextDate,
    this.retakeDate,
    this.retakeDaysRemaining = 0,
    this.canBook = false,
    this.canRetake = false,
  });
}

class EligibilityResultView extends StatelessWidget {
  final EligibilityResultData data;

  /// Runs once when the result appears (0..1).
  final Animation<double> entrance;

  /// True the first time an eligible result is shown (confetti).
  final bool celebrate;

  final VoidCallback onBook;
  final VoidCallback onRetake;
  final VoidCallback onRefresh;
  final Future<void> Function() onPullRefresh;

  const EligibilityResultView({
    super.key,
    required this.data,
    required this.entrance,
    this.celebrate = false,
    required this.onBook,
    required this.onRetake,
    required this.onRefresh,
    required this.onPullRefresh,
  });

  @override
  Widget build(BuildContext context) =>
      ResultClock(child: Builder(builder: _body));

  Widget _body(BuildContext context) {
    final eligible = data.status == 'eligible',
        deferred = data.status == 'temporary_deferred',
        review = data.status == 'for_review' || data.status == 'pending';
    final showRetakeCountdown =
        !eligible && !data.canRetake && !review && data.retakeDate != null;
    // The buttons' own color (unchanged).
    final color = eligible
        ? context.palette.success
        : deferred || review
        ? context.palette.warning
        : context.palette.primaryText;
    final style = ResultStyle.of(context, data.status);
    final title = eligible
        ? "You're Eligible to Donate!"
        : deferred
        ? 'Temporarily Deferred'
        : review
        ? 'Under Review'
        : "You're Not Eligible Right Now";
    final fallback = eligible
        ? 'Your automated eligibility screening indicates that you may proceed to schedule a blood donation appointment. Final donor clearance will still take place at the donation center.'
        : deferred
        ? 'Your eligibility has been temporarily deferred.'
        : review
        ? 'Some of your answers need a closer look. Our team will review your '
              'screening and notify you of the result.'
        : 'You are not eligible to book at this time.';
    final bottomPad = FloatingNavMetrics.bottomPadding(context);
    return RefreshIndicator(
      onRefresh: onPullRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          children: [
            FadeTransition(
              opacity: entrance,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(
                  CurvedAnimation(parent: entrance, curve: Curves.easeOutCubic),
                ),
                child: ResultStage(style: style, celebrate: celebrate),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: FadeTransition(
                opacity: entrance,
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: context.palette.foreground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StatusChip(style: style),
                    const SizedBox(height: 12),
                    _summaryCard(context, style, review, fallback),
                    if (!review &&
                        data.nextDate?.isNotEmpty == true &&
                        !(showRetakeCountdown &&
                            data.nextDate == data.retakeDate))
                      deferred && DateTime.tryParse(data.nextDate!) != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _nextDateCountdown(context, style),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                'Next Eligible Date: ${formatEligibilityDate(data.nextDate!)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    const SizedBox(height: 16),
                    ..._buttons(
                      context,
                      color: color,
                      eligible: eligible,
                      deferred: deferred,
                      review: review,
                      showRetakeCountdown: showRetakeCountdown,
                      style: style,
                    ),
                    ..._guidance(
                      context,
                      style,
                      eligible: eligible,
                      deferred: deferred,
                      review: review,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        !eligible &&
                                !review &&
                                !data.canRetake &&
                                data.retakeDaysRemaining == 0
                            ? 'Check again'
                            : 'Refresh status',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The server's reason and recommendation, beside the state's icon.
  Widget _summaryCard(
    BuildContext context,
    ResultStyle style,
    bool review,
    String fallback,
  ) {
    final p = context.palette;
    final reason = !review && data.reason?.isNotEmpty == true
        ? data.reason!
        : null;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
          boxShadow: p.shadow,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: style.accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: style.tint,
                        ),
                        child: Icon(style.icon, size: 22, color: style.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reason != null) ...[
                              Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: p.foreground,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              data.recommendation?.isNotEmpty == true
                                  ? data.recommendation!
                                  : fallback,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The result's buttons (and the retake countdown), exactly as before.
  List<Widget> _buttons(
    BuildContext context, {
    required Color color,
    required bool eligible,
    required bool deferred,
    required bool review,
    required bool showRetakeCountdown,
    required ResultStyle style,
  }) => [
    if (eligible && data.canBook)
      GlowPulse(
        color: AppColors.success,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
            label: const Text(
              'Book an Appointment',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    if (!eligible && !review && data.canRetake)
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onRetake,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          child: const Text('Take Eligibility Check Again'),
        ),
      ),
    if (showRetakeCountdown) ...[
      _retakeCountdown(context, style, deferred),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.palette.border,
            foregroundColor: context.palette.muted,
            disabledBackgroundColor: context.palette.border,
            disabledForegroundColor: context.palette.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.lock_clock_rounded, size: 18),
          label: Text('Available ${retakeWhenText(data.retakeDaysRemaining)}'),
        ),
      ),
    ],
  ];

  // ─── Guidance cards ─────────────────────────────────────────────────────

  /// The state's guidance, below the buttons.
  List<Widget> _guidance(
    BuildContext context,
    ResultStyle style, {
    required bool eligible,
    required bool deferred,
    required bool review,
  }) {
    final cards = <Widget>[
      if (eligible)
        _card(context, style, 'Before you donate', [
          (Icons.badge_rounded, 'Bring a valid ID.'),
          (
            Icons.restaurant_rounded,
            'Eat a healthy meal and drink plenty of water.',
          ),
          (Icons.bedtime_rounded, "Get a good night's sleep."),
        ]),
      if (!eligible && !deferred && !review)
        _card(context, style, 'What you can do', [
          (Icons.menu_book_rounded, 'Read the guidance above carefully.'),
          if (data.retakeDate != null || data.canRetake)
            (
              Icons.event_repeat_rounded,
              'You can take the check again when the waiting period ends.',
            ),
          (
            Icons.support_agent_rounded,
            'Questions? Contact the donation center or open Help & Support.',
          ),
        ]),
      if (deferred)
        _card(context, style, 'What a deferral means', [
          (
            Icons.hourglass_bottom_rounded,
            'A deferral is a waiting period, not a permanent decision.',
          ),
          (
            Icons.event_repeat_rounded,
            'You can take the check again once your deferral period ends.',
          ),
        ]),
      if (review) _reviewSteps(context, style),
    ];
    return [
      for (final (i, card) in cards.indexed) ...[
        const SizedBox(height: 12),
        FadeSlideIn(index: i + 2, child: card),
      ],
    ];
  }

  BoxDecoration _cardBox(BuildContext context) => BoxDecoration(
    color: context.palette.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: context.palette.border),
    boxShadow: context.palette.shadow,
  );

  Widget _cardTitle(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: context.palette.foreground,
    ),
  );

  Widget _card(
    BuildContext context,
    ResultStyle style,
    String title,
    List<(IconData, String)> rows,
  ) {
    final p = context.palette;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardBox(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(context, title),
            for (final (icon, text) in rows) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: style.tint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 17, color: style.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.foreground,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Countdowns ─────────────────────────────────────────────────────────

  /// The retake date as a countdown (above the disabled "Available ..."
  /// button).
  Widget _retakeCountdown(
    BuildContext context,
    ResultStyle style,
    bool deferred,
  ) {
    final days = data.retakeDaysRemaining;
    return _countdownCard(
      context,
      style,
      date: DateTime.tryParse(data.retakeDate!),
      days: days,
      label: days <= 0
          ? 'You can take the check again today'
          : days == 1
          ? 'You can take the check again tomorrow'
          : 'days until you can retake',
      dateLine: formatEligibilityDate(data.retakeDate!),
      note: deferred
          ? 'You can take the check again once your deferral period ends.'
          : 'This short waiting period lets your health settle before '
                "you're screened again.",
    );
  }

  /// A deferral's next eligible date as a countdown.
  Widget _nextDateCountdown(BuildContext context, ResultStyle style) {
    final date = DateTime.parse(data.nextDate!);
    final now = DateTime.now();
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return _countdownCard(
      context,
      style,
      date: date,
      days: days,
      label: days <= 0 ? 'You can donate again' : 'until you can donate',
      dateLine: 'Next eligible date: ${formatEligibilityDate(data.nextDate!)}',
      daysWord: true,
    );
  }

  /// A calendar tile beside a day count that counts up from 0 (once, over
  /// 700 ms), the [label] and the long date.
  Widget _countdownCard(
    BuildContext context,
    ResultStyle style, {
    required DateTime? date,
    required int days,
    required String label,
    required String dateLine,
    String? note,
    bool daysWord = false,
  }) {
    final p = context.palette;
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final countStyle = TextStyle(
      fontSize: 26,
      height: 1.1,
      fontWeight: FontWeight.w800,
      color: style.text,
    );
    String count(int n) {
      if (days <= 0) return 'Today';
      if (days == 1 && !daysWord) return 'Tomorrow';
      return daysWord ? (n == 1 ? '1 day' : '$n days') : '$n';
    }

    final Widget number = days <= 0 || (days == 1 && !daysWord)
        ? Text(count(days), style: countStyle)
        : ValueListenableBuilder<Duration>(
            valueListenable: ResultClock.of(context),
            builder: (context, now, _) {
              final u = ResultClock.stillOf(context)
                  ? 1.0
                  : Curves.easeOutCubic.transform(
                      clockProgress(
                        now,
                        const Duration(milliseconds: 450),
                        const Duration(milliseconds: 700),
                      ),
                    );
              return Text(count((days * u).round()), style: countStyle);
            },
          );
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _cardBox(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 58,
                  decoration: BoxDecoration(
                    color: style.tint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: style.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        date == null ? '—' : months[date.month - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: style.text,
                        ),
                      ),
                      Text(
                        date == null ? '' : '${date.day}',
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: p.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      number,
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              dateLine,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: p.foreground,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(
                note,
                style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Under review ───────────────────────────────────────────────────────

  /// "What happens next" while the screening is under review: a vertical
  /// three-step stepper. The line to the current step draws itself down
  /// when the result first shows.
  Widget _reviewSteps(BuildContext context, ResultStyle style) {
    final p = context.palette;
    Widget step({
      required Widget marker,
      required String title,
      String? subtitle,
      required String state,
      Widget? line,
    }) {
      return Semantics(
        label: '$title, $state',
        excludeSemantics: true,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(child: marker),
                    ),
                    if (line != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: line,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 4,
                    bottom: line == null ? 0 : 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: state == 'upcoming' ? p.muted : p.foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget bar(Color color) => Container(
      width: 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    // Grows from the done step down to the current one.
    final drawn = CustomPaint(
      painter: _GrowingLinePainter(
        clock: ResultClock.of(context),
        still: ResultClock.stillOf(context),
        track: p.border,
        fill: p.success,
      ),
      child: const SizedBox(width: 2),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, 'What happens next'),
          const SizedBox(height: 14),
          step(
            marker: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            title: 'Answers submitted',
            state: 'done',
            line: drawn,
          ),
          step(
            marker: _ClockDot(color: style.accent, size: 14),
            title: 'Team review',
            state: 'current',
            line: bar(p.border),
          ),
          step(
            marker: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.surfaceAlt,
                border: Border.all(color: p.hint, width: 2),
              ),
            ),
            title: 'You get the result',
            subtitle: "We'll notify you in the app",
            state: 'upcoming',
          ),
        ],
      ),
    );
  }
}

/// The stepper's line from the done step to the current one: it draws itself
/// down once (500 ms in, over 700 ms).
class _GrowingLinePainter extends CustomPainter {
  final ValueListenable<Duration> clock;
  final bool still;
  final Color track;
  final Color fill;

  _GrowingLinePainter({
    required this.clock,
    required this.still,
    required this.track,
    required this.fill,
  }) : super(repaint: still ? null : clock);

  @override
  void paint(Canvas canvas, Size size) {
    final u = still
        ? 1.0
        : Curves.easeInOutCubic.transform(
            clockProgress(
              clock.value,
              const Duration(milliseconds: 500),
              const Duration(milliseconds: 700),
            ),
          );
    final r = Radius.circular(size.width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height * u),
        r,
      ),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(covariant _GrowingLinePainter old) =>
      old.still != still || old.track != track || old.fill != fill;
}

/// The result as a pill: "ELIGIBLE", "NOT ELIGIBLE", "DEFERRED" or "UNDER
/// REVIEW" (with a pulsing dot).
class _StatusChip extends StatelessWidget {
  final ResultStyle style;
  const _StatusChip({required this.style});

  @override
  Widget build(BuildContext context) {
    final review = style.kind == ResultKind.review;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (review)
            _ClockDot(color: style.accent)
          else
            Icon(style.icon, size: 14, color: style.text),
          const SizedBox(width: 6),
          Text(
            style.chipLabel,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: style.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dot that pulses on the result clock (still with animations
/// removed).
class _ClockDot extends StatelessWidget {
  final Color color;
  final double size;
  const _ClockDot({required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final clock = ResultClock.of(context);
    return SizedBox.square(
      dimension: size * 1.8,
      child: ValueListenableBuilder<Duration>(
        valueListenable: clock,
        builder: (context, now, _) {
          final t = ResultClock.stillOf(context)
              ? 0.0
              : (math.sin(now.inMilliseconds / 1400 * 2 * math.pi) + 1) / 2;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * (1 + 0.8 * t),
                height: size * (1 + 0.8 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.3 * (1 - t) + 0.08),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ],
          );
        },
      ),
    );
  }
}
