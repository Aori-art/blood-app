// Shared visual pieces for the Blood Requests feature — badges, chips, the
// request card, empty/skeleton states, and small date/id helpers reused by
// every screen in lib/blood_requests/.
import 'dart:math';

import 'package:flutter/material.dart';

import '../anim.dart';
import '../shared_design.dart';
import 'blood_request_models.dart';

// ─── Blood drop badge ─────────────────────────────────────────────────────────

class BloodDropBadge extends StatelessWidget {
  final String? bloodType;
  final double size;
  final bool inverted;

  const BloodDropBadge({
    super.key,
    required this.bloodType,
    this.size = 52,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _BloodDropPainter(inverted: inverted),
        ),
        Align(
          alignment: const Alignment(0, 0.38),
          child: Text(
            bloodType?.isNotEmpty == true ? bloodType! : '?',
            style: TextStyle(
              color: inverted ? kCrimson : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.26,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BloodDropPainter extends CustomPainter {
  final bool inverted;
  _BloodDropPainter({required this.inverted});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, w * 0.1, h * 0.42, w * 0.1, h * 0.66)
      ..cubicTo(w * 0.1, h * 0.87, w * 0.27, h, w * 0.5, h)
      ..cubicTo(w * 0.73, h, w * 0.9, h * 0.87, w * 0.9, h * 0.66)
      ..cubicTo(w * 0.9, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();

    canvas.drawShadow(
      path,
      inverted ? Colors.black26 : kCrimson.withValues(alpha: .4),
      inverted ? 3 : 6,
      false,
    );

    final paint = Paint();
    if (inverted) {
      paint.color = Colors.white;
    } else {
      paint.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BloodDropPainter oldDelegate) =>
      oldDelegate.inverted != inverted;
}

// ─── Urgency chip ─────────────────────────────────────────────────────────────

class UrgencyChip extends StatefulWidget {
  final String urgency;
  final bool onGradient;
  const UrgencyChip({
    super.key,
    required this.urgency,
    this.onGradient = false,
  });

  @override
  State<UrgencyChip> createState() => _UrgencyChipState();
}

class _UrgencyChipState extends State<UrgencyChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;

  bool get _critical => widget.urgency == 'critical';

  @override
  void initState() {
    super.initState();
    if (_critical) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late Color fg, bg, border;
    late String label;
    bool showDot = true;
    switch (widget.urgency) {
      case 'critical':
        fg = const Color(0xFFDC2626);
        bg = const Color(0xFFFFF1F1);
        border = const Color(0xFFFECACA);
        label = 'CRITICAL';
        break;
      case 'high':
        fg = const Color(0xFFEA580C);
        bg = const Color(0xFFFFF7ED);
        border = const Color(0xFFFED7AA);
        label = 'URGENT';
        break;
      default:
        fg = const Color(0xFF2563EB);
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        label = 'NORMAL';
        showDot = false;
    }

    Widget dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fg),
    );
    if (_pulseCtrl != null) {
      dot = AnimatedBuilder(
        animation: _pulseCtrl!,
        builder: (_, child) =>
            Opacity(opacity: 0.35 + (_pulseCtrl!.value * 0.65), child: child),
        child: dot,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: widget.onGradient ? Colors.white : bg,
        border: Border.all(color: widget.onGradient ? Colors.white : border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[dot, const SizedBox(width: 5)],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Request status chip ──────────────────────────────────────────────────────

class RequestStatusChip extends StatelessWidget {
  final String status;
  final String label;
  final bool onGradient;
  const RequestStatusChip({
    super.key,
    required this.status,
    required this.label,
    this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    late Color fg, bg, border;
    late IconData icon;
    switch (status) {
      case 'pending_review':
        fg = const Color(0xFFD97706);
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFDE68A);
        icon = Icons.hourglass_top_rounded;
        break;
      case 'open':
        fg = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFFBBF7D0);
        icon = Icons.radio_button_checked_rounded;
        break;
      case 'fulfilled':
        fg = const Color(0xFF15803D);
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFFBBF7D0);
        icon = Icons.check_circle_rounded;
        break;
      case 'cancelled':
        fg = const Color(0xFF6B7280);
        bg = const Color(0xFFF3F4F6);
        border = const Color(0xFFE5E7EB);
        icon = Icons.block_rounded;
        break;
      case 'expired':
        fg = const Color(0xFF6B7280);
        bg = const Color(0xFFF3F4F6);
        border = const Color(0xFFE5E7EB);
        icon = Icons.timer_off_rounded;
        break;
      case 'rejected':
        fg = const Color(0xFFDC2626);
        bg = const Color(0xFFFFF1F1);
        border = const Color(0xFFFECACA);
        icon = Icons.gpp_bad_rounded;
        break;
      default:
        fg = const Color(0xFF6B7280);
        bg = const Color(0xFFF3F4F6);
        border = const Color(0xFFE5E7EB);
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onGradient ? Colors.white : bg,
        border: Border.all(color: onGradient ? Colors.white : border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

// ─── Match badge ───────────────────────────────────────────────────────────────

class MatchBadge extends StatelessWidget {
  final String? matchType;
  const MatchBadge({super.key, required this.matchType});

  @override
  Widget build(BuildContext context) {
    late Color fg, bg, border;
    late String label;
    late IconData icon;
    switch (matchType) {
      case 'exact':
        fg = const Color(0xFF16A34A);
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFFBBF7D0);
        label = 'Exact match';
        icon = Icons.verified_rounded;
        break;
      case 'compatible':
        fg = const Color(0xFF2563EB);
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        label = 'Compatible';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'replacement_any':
        fg = const Color(0xFF9333EA);
        bg = const Color(0xFFFAF5FF);
        border = const Color(0xFFE9D5FF);
        label = 'Any type accepted';
        icon = Icons.all_inclusive_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

// ─── Donor progress bar ───────────────────────────────────────────────────────

class DonorProgressBar extends StatelessWidget {
  final int volunteers;
  final int required;
  final bool showLabel;
  const DonorProgressBar({
    super.key,
    required this.volunteers,
    required this.required,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final full = required > 0 && volunteers >= required;
    final ratio = required <= 0 ? 0.0 : (volunteers / required).clamp(0.0, 1.0);
    final color = full ? const Color(0xFF16A34A) : kCrimson;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Donors',
                  style: TextStyle(fontSize: 11, color: kTextMuted),
                ),
                Text(
                  '$volunteers of $required',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Request card ──────────────────────────────────────────────────────────────

class BloodRequestCard extends StatelessWidget {
  final BloodRequest request;
  final VoidCallback? onTap;
  final bool ownerView;
  const BloodRequestCard({
    super.key,
    required this.request,
    this.onTap,
    this.ownerView = false,
  });

  Widget _rightBadge() {
    if (ownerView) {
      return RequestStatusChip(
        status: request.status,
        label: request.statusLabel,
      );
    }
    if (request.myResponse?.isCommitted == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          border: Border.all(color: const Color(0xFFBBF7D0)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, size: 12, color: Color(0xFF16A34A)),
            SizedBox(width: 4),
            Text(
              "You're donating",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
              ),
            ),
          ],
        ),
      );
    }
    if (request.isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Fully matched',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
      );
    }
    return MatchBadge(matchType: request.myMatchType);
  }

  @override
  Widget build(BuildContext context) {
    final critical = request.urgency == 'critical';
    final showUrgency =
        !ownerView || request.status == 'open' || request.status == 'pending_review';
    final locationBits = [request.facility?.typeLabel, request.facility?.locationLine]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    final neededBits = [
      if (request.neededBy != null) 'Needed by ${brShortDate(request.neededBy)}',
      if (request.timeLeftLabel != null) request.timeLeftLabel!,
    ].join(' · ');

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: critical ? const Color(0xFFFFFBFB) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (critical) Container(width: 4, color: kCrimson),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'br_drop_${request.requestId}',
                            child: BloodDropBadge(bloodType: request.bloodType),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (showUrgency)
                                      UrgencyChip(urgency: request.urgency),
                                    const Spacer(),
                                    if (request.createdAgo != null)
                                      Text(
                                        request.createdAgo!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  request.facility?.name ?? 'Blood facility',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: kTextPrimary,
                                  ),
                                ),
                                if (locationBits.isNotEmpty)
                                  Text(
                                    locationBits,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: kTextMuted),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.groups_rounded,
                            size: 14,
                            color: Color(0xFF374151),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              request.requirementText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF374151),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DonorProgressBar(
                        volunteers: request.volunteersCount,
                        required: request.requiredDonors,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.event_rounded,
                                    size: 13,
                                    color: kTextMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      neededBits,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: kTextPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _rightBadge(),
                        ],
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
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class BrEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const BrEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      kCrimson.withValues(alpha: .14),
                      kCrimson.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              CircleAvatar(
                radius: 40,
                backgroundColor: kCrimson.withValues(alpha: .1),
                child: Icon(icon, size: 40, color: kCrimson),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: kTextMuted, height: 1.5),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: PrimaryButton(label: actionLabel!, onTap: onAction),
          ),
        ],
      ],
    ),
  );
}

// ─── Skeleton card ─────────────────────────────────────────────────────────────

class BrSkeletonCard extends StatefulWidget {
  const BrSkeletonCard({super.key});

  @override
  State<BrSkeletonCard> createState() => _BrSkeletonCardState();
}

class _BrSkeletonCardState extends State<BrSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.5,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block({double width = double.infinity, double height = 12}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(6),
    ),
  );

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _block(width: 120, height: 14),
                    const SizedBox(height: 8),
                    _block(width: 160, height: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _block(height: 10),
          const SizedBox(height: 8),
          _block(width: 200, height: 10),
        ],
      ),
    ),
  );
}

// ─── Date helpers ──────────────────────────────────────────────────────────────

const _brMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _brMonthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String brShortDate(String? value) {
  if (value == null || value.isEmpty) return '';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return '${_brMonthsShort[d.month - 1]} ${d.day}';
}

String brLongDate(String? value) {
  if (value == null || value.isEmpty) return '';
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return '${_brMonthsLong[d.month - 1]} ${d.day}, ${d.year}';
}

String brRelativeDay(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}

// ─── Submission idempotency key ───────────────────────────────────────────────

String brNewSubmissionKey() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
