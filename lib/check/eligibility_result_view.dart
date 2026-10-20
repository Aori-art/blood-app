// The result screens of the eligibility check (eligible, not eligible,
// temporarily deferred, under review). State, scoring, API calls and
// navigation stay in check.dart; this only draws what it is given.
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_palette.dart';
import '../check.dart' show formatEligibilityDate, retakeWhenText;
import '../home.dart' show FloatingNavMetrics;
import '../widgets/glow_pulse.dart';

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
  Widget build(BuildContext context) {
    final eligible = data.status == 'eligible',
        deferred = data.status == 'temporary_deferred',
        review = data.status == 'for_review' || data.status == 'pending';
    final showRetakeCountdown =
        !eligible && !data.canRetake && !review && data.retakeDate != null;
    final color = eligible
        ? context.palette.success
        : deferred || review
        ? context.palette.warning
        : context.palette.primaryText;
    final title = eligible
        ? "You're Eligible to Donate!"
        : deferred
        ? 'Temporarily Deferred'
        : review
        ? 'Under Review'
        : "You're Not Eligible Right Now";
    final icon = eligible
        ? Icons.verified_rounded
        : deferred
        ? Icons.schedule_rounded
        : review
        ? Icons.fact_check_rounded
        : Icons.block_rounded;
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
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad),
        children: [
          ScaleTransition(
            scale: CurvedAnimation(parent: entrance, curve: Curves.easeOutBack),
            child: FadeTransition(
              opacity: entrance,
              child: Column(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                color.withValues(alpha: .22),
                                color.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: color.withValues(alpha: .12),
                          child: Icon(icon, size: 54, color: color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: .18)),
                      boxShadow: context.palette.shadow,
                    ),
                    child: Column(
                      children: [
                        if (!review && data.reason?.isNotEmpty == true)
                          Text(
                            data.reason!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        if (!review && data.reason?.isNotEmpty == true)
                          const SizedBox(height: 8),
                        Text(
                          data.recommendation?.isNotEmpty == true
                              ? data.recommendation!
                              : fallback,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.palette.muted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (review) ...[
                    const SizedBox(height: 16),
                    _reviewSteps(context),
                  ],
                  if (!review &&
                      data.nextDate?.isNotEmpty == true &&
                      !(showRetakeCountdown &&
                          data.nextDate == data.retakeDate))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Next Eligible Date: ${formatEligibilityDate(data.nextDate!)}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
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
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'Book an Appointment',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withValues(alpha: .18)),
                        boxShadow: context.palette.shadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: .12),
                                ),
                                child: Icon(
                                  Icons.event_repeat_rounded,
                                  size: 20,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Retake Available',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: context.palette.foreground,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            formatEligibilityDate(data.retakeDate!),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: context.palette.foreground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can take the check again '
                            '${retakeWhenText(data.retakeDaysRemaining)}.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            deferred
                                ? 'You can take the check again once your deferral period ends.'
                                : 'This short waiting period lets your health settle before '
                                      "you're screened again.",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        label: Text(
                          'Available ${retakeWhenText(data.retakeDaysRemaining)}',
                        ),
                      ),
                    ),
                  ],
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
    );
  }

  /// "What happens next" while the screening is under review: a vertical
  /// three-step stepper joined by a line.
  Widget _reviewSteps(BuildContext context) {
    Widget step({
      required Widget marker,
      required String title,
      String? subtitle,
      required String state,
      required Color lineColor,
      bool last = false,
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
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: lineColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: state == 'upcoming'
                              ? context.palette.muted
                              : context.palette.foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happens next',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 16),
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
            lineColor: context.palette.success,
          ),
          step(
            marker: _PulsingDot(
              color: context.palette.warning,
              animate: !MediaQuery.disableAnimationsOf(context),
            ),
            title: 'Team review',
            state: 'current',
            lineColor: context.palette.border,
          ),
          step(
            marker: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.surfaceAlt,
                border: Border.all(color: context.palette.hint, width: 2),
              ),
            ),
            title: 'You get the result',
            subtitle: "We'll notify you in the app",
            state: 'upcoming',
            lineColor: context.palette.border,
            last: true,
          ),
        ],
      ),
    );
  }
}

/// The "current step" dot: a solid dot with a soft halo that pulses. With
/// [animate] off (reduced motion) the halo stays still.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool animate;

  const _PulsingDot({required this.color, required this.animate});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 + 14 * t,
                height: 14 + 14 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - t) + 0.06),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
