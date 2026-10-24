import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'streak/streak_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'book.dart';
import 'config.dart';
import 'digital_id.dart';
import 'digital_id_service.dart';
import 'home.dart' show FloatingNavMetrics;
import 'shared_design.dart';
import 'skeleton.dart';
import 'widgets/count_up_text.dart';
import 'widgets/glow_pulse.dart';
import 'app_palette.dart';
import 'home_nav.dart';

class DonationHistoryScreen extends StatefulWidget {
  const DonationHistoryScreen({super.key});

  @override
  State<DonationHistoryScreen> createState() => _DonationHistoryScreenState();
}

class _DonationHistoryScreenState extends State<DonationHistoryScreen> {
  List donations = [];
  bool isLoading = true;

  // "Status" tile — mirrors book.dart's active-appointment check
  // (get_appointments.php returns at most one active/upcoming appointment).
  bool _hasActiveAppointment = false;
  bool _checkingAppointment = true;
  bool _appointmentCheckFailed = false;

  // Only one donation card expanded at a time, same pattern as
  // alerts.dart's _NotificationCard (_expandedId on the parent State).
  int? _expandedDonationId;

  DigitalIdData? _digitalId;

  @override
  void initState() {
    super.initState();
    fetchDonationHistory();
    _fetchAppointmentStatus();
    _loadDigitalId();
  }

  Future<void> _loadDigitalId() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (donorId == null || donorId.isEmpty) return;
    try {
      final data = await DigitalIdService.fetch(donorId);
      if (mounted) setState(() => _digitalId = data);
    } catch (_) {
      // Keep whatever was last known — this button should never show an
      // error state, it just quietly doesn't update.
    }
  }

  Future<void> fetchDonationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "${AppConfig.baseUrl}/get_donation_history.php?donor_id=$donorId",
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] == "success") {
          setState(() {
            donations = data["data"];
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchAppointmentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (mounted) {
        setState(() {
          _hasActiveAppointment = false;
          _checkingAppointment = false;
          _appointmentCheckFailed = false;
        });
      }
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              "${AppConfig.baseUrl}/get_appointments.php?donor_id=$donorId",
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is Map ? data['data'] : null;

        if (data is Map && data['status'] == 'success' && list is List) {
          setState(() {
            _hasActiveAppointment = list.isNotEmpty;
            _checkingAppointment = false;
            _appointmentCheckFailed = false;
          });
        } else {
          setState(() {
            _checkingAppointment = false;
            _appointmentCheckFailed = true;
          });
        }
      } else {
        setState(() {
          _checkingAppointment = false;
          _appointmentCheckFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingAppointment = false;
          _appointmentCheckFailed = true;
        });
      }
    }
  }

  void _retryAppointmentStatus() {
    setState(() => _checkingAppointment = true);
    _fetchAppointmentStatus();
  }

  Future<void> _refresh() async {
    setState(() {
      isLoading = true;
      _checkingAppointment = true;
    });
    await Future.wait([
      fetchDonationHistory(),
      _fetchAppointmentStatus(),
      _loadDigitalId(),
    ]);
  }

  String formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return "${months[d.month - 1]} ${d.day}, ${d.year}";
    } catch (e) {
      return date;
    }
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return "N/A";
    try {
      final d = DateTime.parse(raw);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      int hour = d.hour;
      final period = hour >= 12 ? "PM" : "AM";
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      final minute = d.minute.toString().padLeft(2, '0');
      return "${months[d.month - 1]} ${d.day}, ${d.year} · $hour:$minute $period";
    } catch (_) {
      return raw;
    }
  }

  bool _isCompleted(dynamic item) {
    if (item is! Map) return false;
    return (item['donation_status']?.toString().toLowerCase() ?? '') ==
        'completed';
  }

  int get _completedCount => donations.where(_isCompleted).length;

  int get _completedUnits {
    int total = 0;
    for (final d in donations) {
      if (_isCompleted(d)) {
        total += int.tryParse(d["blood_units"].toString()) ?? 0;
      }
    }
    return total;
  }

  String get _statusTileValue {
    if (_checkingAppointment) return "...";
    if (_appointmentCheckFailed) return "Unknown";
    return _hasActiveAppointment ? "Active" : "No Upcoming";
  }

  // Status colors on the timeline: completed green, pending amber, deferred
  // red, failed gray. [_donationStatusColor] is the node / icon color, the
  // text color is the readable variant of it.
  Color _donationStatusColor(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return context.palette.success;
      case 'pending':
        return context.palette.warning;
      case 'deferred':
        return context.palette.criticalText;
      default:
        return context.palette.muted;
    }
  }

  Color _donationStatusText(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return context.palette.successDark;
      case 'pending':
        return context.palette.warningText;
      case 'deferred':
        return context.palette.criticalText;
      default:
        return context.palette.muted;
    }
  }

  Color _donationStatusBg(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return context.palette.successBg;
      case 'pending':
        return context.palette.warningBg;
      case 'deferred':
        return context.palette.accentBg;
      default:
        return context.palette.surfaceAlt;
    }
  }

  String _donationStatusLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'pending':
        return 'Pending';
      case 'deferred':
        return 'Deferred';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  // ── Derived from the list already loaded (no new calls) ─────────────────

  static const _filters = ['All', 'Completed', 'Pending', 'Deferred'];
  String _filter = 'All';

  bool _matchesFilter(dynamic item) {
    if (_filter == 'All') return true;
    final s = item is Map
        ? (item['donation_status']?.toString().toLowerCase() ?? '')
        : '';
    if (_filter == 'Deferred') return s == 'deferred' || s == 'failed';
    return s == _filter.toLowerCase();
  }

  DateTime? _lastCompletedDate() {
    DateTime? last;
    for (final d in donations) {
      if (!_isCompleted(d)) continue;
      final t = DateTime.tryParse(d['donation_date']?.toString() ?? '');
      if (t != null && (last == null || t.isAfter(last))) last = t;
    }
    return last;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── Summary card ────────────────────────────────────────────────────────

  Widget _summaryCard() {
    final last = _lastCompletedDate();
    final next = DateTime.tryParse(
      _digitalId?.eligibility?.nextEligibleDate ?? '',
    );
    const on = AppColors.onPrimary;
    const onMuted = AppColors.onPrimaryMuted;

    Widget stat(String label, Widget value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          value,
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: onMuted),
          ),
        ],
      ),
    );
    const statStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: on,
    );

    Widget? countdown;
    if (next != null) {
      final today = _dateOnly(DateTime.now());
      final daysLeft = _dateOnly(next).difference(today).inDays;
      final start = last == null ? null : _dateOnly(last);
      final span = start == null ? 0 : _dateOnly(next).difference(start).inDays;
      final progress = daysLeft <= 0
          ? 1.0
          : span <= 0
          ? 0.0
          : today.difference(start!).inDays / span;
      countdown = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.event_available_rounded, size: 14, color: on),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    daysLeft <= 0
                        ? 'You can donate again'
                        : 'Next eligible ${formatDate(next.toIso8601String())}',
                    style: const TextStyle(fontSize: 12, color: on),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (daysLeft > 0)
                Text(
                  daysLeft == 1 ? '1 day to go' : '$daysLeft days to go',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SlimProgressBar(
            value: progress,
            color: on,
            trackColor: on.withValues(alpha: .22),
          ),
        ],
      );
    }

    final status = Semantics(
      button: _appointmentCheckFailed,
      child: GestureDetector(
        onTap: _appointmentCheckFailed ? _retryAppointmentStatus : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on.withValues(alpha: .28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _appointmentCheckFailed
                    ? Icons.refresh_rounded
                    : Icons.calendar_today_rounded,
                size: 12,
                color: on,
              ),
              const SizedBox(width: 5),
              Text(
                _statusTileValue,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(
              alpha: context.palette.isDark ? .14 : .22,
            ),
            blurRadius: 22,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Decorative circles.
            Positioned(right: -36, top: -44, child: _ring(150, .10)),
            Positioned(right: 54, bottom: -60, child: _ring(110, .07)),
            Positioned(left: -30, bottom: -50, child: _ring(90, .06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TOTAL DONATIONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: onMuted,
                          ),
                        ),
                      ),
                      status,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CountUpText(
                        _completedCount,
                        style: const TextStyle(
                          fontSize: 44,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          color: on,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 7),
                        child: Icon(Icons.water_drop_rounded, color: on),
                      ),
                    ],
                  ),
                  if (_completedCount > 0)
                    const Text(
                      "Every donation can help save up to 3 lives 🩸",
                      style: TextStyle(fontSize: 11, color: onMuted),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      stat(
                        'Lives helped',
                        CountUpText(_completedCount * 3, style: statStyle),
                      ),
                      stat(
                        'Units',
                        CountUpText(_completedUnits, style: statStyle),
                      ),
                      stat(
                        'Last donation',
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            last == null
                                ? '—'
                                : formatDate(last.toIso8601String()),
                            style: statStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ?countdown,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.onPrimary.withValues(alpha: alpha),
    ),
  );

  // ── Milestones ──────────────────────────────────────────────────────────

  Widget _milestones() {
    const steps = [
      (1, 'First drop', Icons.water_drop_rounded),
      (3, '3 donations', Icons.favorite_rounded),
      (5, '5 donations', Icons.star_rounded),
      (10, '10 donations', Icons.workspace_premium_rounded),
    ];
    final p = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (n, label, icon) in steps) ...[
            Builder(
              builder: (context) {
                final unlocked = _completedCount >= n;
                return Semantics(
                  label: unlocked ? '$label, unlocked' : '$label, locked',
                  excludeSemantics: true,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: unlocked ? AppColors.primary : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: unlocked ? AppColors.primary : p.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          unlocked ? icon : Icons.lock_rounded,
                          size: 14,
                          color: unlocked ? AppColors.onPrimary : p.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: unlocked ? AppColors.onPrimary : p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ── Filters ─────────────────────────────────────────────────────────────

  Widget _filterChips() {
    final p = context.palette;
    return Row(
      children: [
        for (final f in _filters) ...[
          Expanded(
            child: Semantics(
              button: true,
              selected: _filter == f,
              child: GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _filter == f ? p.accentBg : p.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _filter == f ? p.primaryBorder : p.border,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _filter == f ? p.primaryText : p.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (f != _filters.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  // ── Timeline ────────────────────────────────────────────────────────────

  // A Stack sizes itself to its only non-positioned child (the card), so the
  // line and node always match the card's real height, including while it
  // grows or shrinks.
  Widget _timelineItem({
    required String? status,
    required bool first,
    required bool last,
    required Widget child,
  }) {
    final p = context.palette;
    final color = _donationStatusColor(status);
    return Stack(
      children: [
        Positioned(
          left: 13,
          top: first ? 30 : 0,
          bottom: last ? null : 0,
          height: last ? 30 : null,
          child: Container(width: 2, color: p.border),
        ),
        Positioned(
          left: 0,
          top: 16,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _donationStatusBg(status),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(_statusIcon(status), size: 14, color: color),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 12),
          child: child,
        ),
      ],
    );
  }

  IconData _statusIcon(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return Icons.water_drop_rounded;
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'deferred':
        return Icons.block_rounded;
      case 'failed':
        return Icons.close_rounded;
      default:
        return Icons.water_drop_outlined;
    }
  }

  Widget _timeline() {
    final shown = [
      for (var i = 0; i < donations.length; i++)
        if (_matchesFilter(donations[i])) i,
    ];
    final Widget body;
    if (shown.isEmpty) {
      body = Padding(
        key: ValueKey('none_$_filter'),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No ${_filter.toLowerCase()} donations yet.',
            style: TextStyle(fontSize: 13, color: context.palette.muted),
          ),
        ),
      );
    } else {
      body = Column(
        key: ValueKey(_filter),
        children: [
          for (final (n, index) in shown.indexed) _timelineEntry(index, n, shown),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: body,
    );
  }

  Widget _timelineEntry(int index, int n, List<int> shown) {
    final item = donations[index] as Map;
    final id =
        int.tryParse(item['donation_id']?.toString() ?? '') ?? -(index + 1);
    final status = item['donation_status']?.toString();
    return _timelineItem(
      status: status,
      first: n == 0,
      last: n == shown.length - 1,
      child: FadeSlideIn(
        index: n + 3,
        child: _DonationCard(
          item: item,
          fallbackNumber: donations.length - index,
          isExpanded: _expandedDonationId == id,
          status: status,
          deferredReason: item['deferred_reason']?.toString(),
          statusColor: _donationStatusText(status),
          statusBg: _donationStatusBg(status),
          statusLabel: _donationStatusLabel(status),
          formattedDate: formatDate(item["donation_date"] ?? ""),
          formattedTimestamp: _formatTimestamp(item['created_at']?.toString()),
          onTap: () {
            setState(() {
              _expandedDonationId = _expandedDonationId == id ? null : id;
            });
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: context.palette.foreground,
      ),
    ),
  );

  // ── Empty and loading states ────────────────────────────────────────────

  Widget _emptyState() => FadeSlideIn(
    child: Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        children: [
          const _EmptyIllustration(),
          const SizedBox(height: 20),
          Text(
            "No donation history found.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Your first donation starts your journey here. One visit can help save up to 3 lives.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.palette.muted,
            ),
          ),
          const SizedBox(height: 24),
          GlowPulse(
            sheen: true,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  // The Book tab, with the nav, when Home is open.
                  if (HomeNav.goTo(HomeTab.book)) return;
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => const BookScreen(showBackButton: true),
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text(
                  "Book an Appointment",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: context.palette.border,
                  disabledForegroundColor: context.palette.muted,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _skeleton() => SkeletonPulse(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(height: 190, radius: 24),
        const SizedBox(height: 16),
        const Row(
          children: [
            SkeletonBox(width: 92, height: 32, radius: 16),
            SizedBox(width: 8),
            SkeletonBox(width: 104, height: 32, radius: 16),
            SizedBox(width: 8),
            SkeletonBox(width: 104, height: 32, radius: 16),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(height: 36, radius: 12),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: SkeletonBox.circle(28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 104,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 80, height: 10),
                        SizedBox(height: 8),
                        SkeletonBox(width: 140, height: 14),
                        Spacer(),
                        Row(
                          children: [
                            SkeletonBox(width: 56, height: 22, radius: 11),
                            SizedBox(width: 8),
                            SkeletonBox(width: 64, height: 22, radius: 11),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'donation_history', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final List<Widget> content;
    if (isLoading) {
      content = [_skeleton()];
    } else if (donations.isEmpty) {
      content = [_emptyState()];
    } else {
      content = [
        FadeSlideIn(index: 0, child: _summaryCard()),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_sectionTitle('Milestones'), _milestones()],
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_sectionTitle('Your donations'), _filterChips()],
          ),
        ),
        const SizedBox(height: 16),
        _timeline(),
      ];
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          EdonateHeader(
            title: 'Donation History',
            subtitle: 'Your journey of saving lives',
            actions: _digitalId != null
                ? [
                    HeaderIconButton(
                      icon: Icons.badge_rounded,
                      tooltip: 'Digital Donor ID',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DigitalIdScreen(),
                        ),
                      ),
                    ),
                  ]
                : const [],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: context.palette.primaryText,
              backgroundColor: context.palette.surface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  FloatingNavMetrics.bottomPadding(context),
                ),
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EMPTY STATE ILLUSTRATION ────────────────────────────────────────────────

/// A large drop with a heart in a soft circle, and two small drops bobbing
/// beside it. Still when animations are removed.
class _EmptyIllustration extends StatefulWidget {
  const _EmptyIllustration();

  @override
  State<_EmptyIllustration> createState() => _EmptyIllustrationState();
}

class _EmptyIllustrationState extends State<_EmptyIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bob
        ..stop()
        ..value = 0.5;
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: SizedBox(
        width: 180,
        height: 150,
        child: AnimatedBuilder(
          animation: _bob,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_bob.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.accentBg,
                    border: Border.all(color: p.primaryBorder),
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(68, 94),
                      painter: _DropPainter(p.primaryText),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 26),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 26,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 6,
                  top: 30 + 8 * t,
                  child: CustomPaint(
                    size: const Size(15, 21),
                    painter: _DropPainter(p.primaryText.withValues(alpha: .55)),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 24 + 8 * (1 - t),
                  child: CustomPaint(
                    size: const Size(11, 15),
                    painter: _DropPainter(p.primaryText.withValues(alpha: .4)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A plain blood drop (the icon font's drop carries a highlight stroke that
/// fights with the heart on top).
class _DropPainter extends CustomPainter {
  final Color color;
  const _DropPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    final r = w / 2;
    final path = Path()
      ..moveTo(cx, 0)
      ..cubicTo(cx + w * .16, h * .2, w, h * .42, w, h - r)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..cubicTo(0, h * .42, cx - w * .16, h * .2, cx, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DropPainter old) => old.color != color;
}

// ── DONATION CARD (expandable) ──────────────────────────────────────────────

class _DonationCard extends StatelessWidget {
  final Map item;
  final int fallbackNumber;
  final bool isExpanded;
  final String? status;
  final String? deferredReason;
  final Color statusColor;
  final Color statusBg;
  final String statusLabel;
  final String formattedDate;
  final String formattedTimestamp;
  final VoidCallback onTap;

  const _DonationCard({
    required this.item,
    required this.fallbackNumber,
    required this.isExpanded,
    required this.status,
    required this.deferredReason,
    required this.statusColor,
    required this.statusBg,
    required this.statusLabel,
    required this.formattedDate,
    required this.formattedTimestamp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = "Donation $fallbackNumber";
    final units = item['blood_units'] ?? 0;
    final bloodType = item['blood_type']?.toString();
    final remarks = item['remarks']?.toString();
    final center =
        (item['facility_name'] ?? item['center_name'] ?? item['facility'])
            ?.toString();
    final normalizedStatus = (status ?? '').toLowerCase();
    final showDeferredReason =
        (normalizedStatus == 'deferred' || normalizedStatus == 'failed') &&
        deferredReason != null &&
        deferredReason!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isExpanded ? p.primaryBorder : p.border),
        boxShadow: p.shadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: p.foreground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isExpanded ? p.primaryText : p.muted,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                if (center != null && center.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 14, color: p.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (bloodType != null && bloodType.isNotEmpty)
                      _pill(
                        Icons.bloodtype_rounded,
                        bloodType,
                        fg: p.primaryText,
                        bg: p.accentBg,
                      ),
                    _pill(
                      Icons.water_drop_rounded,
                      "$units unit(s)",
                      fg: p.muted,
                      bg: p.surfaceAlt,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? _details(context, remarks, showDeferredReason)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: statusBg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
        ),
        const SizedBox(width: 5),
        Text(
          statusLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: statusColor,
          ),
        ),
      ],
    ),
  );

  Widget _pill(IconData icon, String text, {required Color fg, required Color bg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      );

  Widget _details(BuildContext context, String? remarks, bool showReason) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Divider(height: 1, color: p.border),
        const SizedBox(height: 14),
        // Why it didn't complete, in the status's own tint so it reads
        // distinctly from the general remarks note below.
        if (showReason) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: .3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (status ?? '').toLowerCase() == 'failed'
                            ? "Why this failed"
                            : "Why this was deferred",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        deferredReason!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: statusColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.accentBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            (remarks != null && remarks.isNotEmpty)
                ? remarks
                : "No remarks recorded.",
            style: TextStyle(fontSize: 13, color: p.primaryText, height: 1.55),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.access_time_rounded, size: 13, color: p.muted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                formattedTimestamp,
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
