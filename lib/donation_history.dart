import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'book.dart';
import 'config.dart';
import 'home.dart' show kBottomNavBarHeight;

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

  @override
  void initState() {
    super.initState();
    fetchDonationHistory();
    _fetchAppointmentStatus();
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
            "${AppConfig.baseUrl}/get_donation_history.php?donor_id=$donorId"),
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
    await Future.wait([fetchDonationHistory(), _fetchAppointmentStatus()]);
  }

  String formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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

  Color get _statusTileColor {
    if (_checkingAppointment || _appointmentCheckFailed) {
      return const Color(0xFF6B7280);
    }
    return _hasActiveAppointment
        ? const Color(0xFF16A34A)
        : const Color(0xFF6B7280);
  }

  // Mirrors book.dart's _appointmentStatusColor conventions applied to the
  // donation_records.donation_status enum ('completed'|'deferred'|'failed').
  Color _donationStatusColor(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return const Color(0xFF16A34A);
      case 'deferred':
        return const Color(0xFFF59E0B);
      case 'failed':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Color _donationStatusBg(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return const Color(0xFFF0FDF4);
      case 'deferred':
        return const Color(0xFFFFFBEB);
      case 'failed':
        return const Color(0xFFFEF2F2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  String _donationStatusLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'deferred':
        return 'Deferred';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  Widget summaryItem(
    IconData icon,
    String value,
    String label, {
    Color? color,
    VoidCallback? onTap,
  }) {
    final c = color ?? const Color(0xFFDC2626);
    final content = Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: c),
            if (onTap != null)
              Positioned(
                right: -7,
                top: -4,
                child: Icon(Icons.refresh_rounded, size: 13, color: c),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ],
    );
    return onTap == null
        ? content
        : GestureDetector(onTap: onTap, child: content);
  }

  Widget _statDivider() => Container(
    width: 1,
    height: 34,
    color: const Color(0xFFDC2626).withValues(alpha: .15),
  );

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 🔥 HEADER (IMPROVED)
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              bottom: screenHeight * 0.03,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
              ),
            ),
            child: Column(
              children: const [
                Text(
                  "Donation History",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  "Your journey of saving lives",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // 🔥 CONTENT
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: const Color(0xFFDC2626),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFDC2626),
                        ),
                      )
                    : donations.isEmpty
                        ? Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOut,
                              builder: (_, v, child) => Opacity(
                                opacity: v,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - v) * 12),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.water_drop_outlined,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "No donation history found.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () => Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).push(
                                        MaterialPageRoute(
                                          builder: (_) => const BookScreen(
                                            showBackButton: true,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.calendar_month_rounded,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        "Book an Appointment",
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFDC2626,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              // 🔥 SUMMARY CARD
                              FadeSlideIn(
                                index: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  margin:
                                      const EdgeInsets.only(bottom: 15),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFEBEE),
                                        Color(0xFFFFCDD2)
                                      ],
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.red.shade200),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: summaryItem(
                                                Icons.water_drop,
                                                _completedCount.toString(),
                                                "Donations"),
                                          ),
                                          _statDivider(),
                                          Expanded(
                                            child: summaryItem(
                                                Icons.trending_up,
                                                "$_completedUnits",
                                                "Units"),
                                          ),
                                          _statDivider(),
                                          Expanded(
                                            child: summaryItem(
                                                Icons.calendar_today,
                                                _statusTileValue,
                                                "Status",
                                                color: _statusTileColor,
                                                onTap: _appointmentCheckFailed
                                                    ? _retryAppointmentStatus
                                                    : null),
                                          ),
                                        ],
                                      ),
                                      if (_completedCount > 0) ...[
                                        const SizedBox(height: 10),
                                        const Text(
                                          "Every donation can help save up to 3 lives 🩸",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                              // 🔥 LIST
                              Expanded(
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    bottom: kBottomNavBarHeight +
                                        MediaQuery.of(context).padding.bottom,
                                  ),
                                  itemCount: donations.length,
                                  itemBuilder: (context, index) {
                                    final item =
                                        donations[index] as Map;
                                    final id = int.tryParse(
                                            item['donation_id']
                                                    ?.toString() ??
                                                '') ??
                                        -(index + 1);
                                    final status =
                                        item['donation_status']
                                            ?.toString();

                                    return FadeSlideIn(
                                      index: index + 1,
                                      child: _DonationCard(
                                        item: item,
                                        fallbackNumber:
                                            donations.length - index,
                                        isExpanded:
                                            _expandedDonationId == id,
                                        status: status,
                                        deferredReason: item['deferred_reason']
                                            ?.toString(),
                                        statusColor:
                                            _donationStatusColor(status),
                                        statusBg:
                                            _donationStatusBg(status),
                                        statusLabel:
                                            _donationStatusLabel(status),
                                        formattedDate: formatDate(
                                            item["donation_date"] ?? ""),
                                        formattedTimestamp:
                                            _formatTimestamp(
                                                item['created_at']
                                                    ?.toString()),
                                        onTap: () {
                                          setState(() {
                                            _expandedDonationId =
                                                _expandedDonationId == id
                                                    ? null
                                                    : id;
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── DONATION CARD (expandable, blood-themed) ────────────────────────────────

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
    final title = "Donation $fallbackNumber";
    final units = item['blood_units'] ?? 0;
    final bloodType = item['blood_type']?.toString();
    final remarks = item['remarks']?.toString();
    final normalizedStatus = (status ?? '').toLowerCase();
    final showDeferredReason =
        (normalizedStatus == 'deferred' || normalizedStatus == 'failed') &&
            deferredReason != null &&
            deferredReason!.isNotEmpty;

    IconData leadingIcon;
    switch (normalizedStatus) {
      case 'deferred':
        leadingIcon = Icons.hourglass_top_rounded;
        break;
      case 'failed':
        leadingIcon = Icons.block_rounded;
        break;
      default:
        leadingIcon = Icons.water_drop_rounded;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: isExpanded
                  ? const Color(0xFFDC2626).withValues(alpha: .12)
                  : Colors.black.withValues(alpha: .06),
              blurRadius: isExpanded ? 16 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── COLLAPSED ROW ───────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(leadingIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isExpanded
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFD1D5DB),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            // ── EXPANDED DETAILS ────────────────────────────
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    height: 1,
                    color: Colors.grey.shade100,
                    indent: 14,
                    endIndent: 14,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Why it didn't complete — styled in the status's
                        // own color so it reads distinctly from the
                        // general remarks note below.
                        if (showDeferredReason) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: statusColor.withValues(alpha: .3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        normalizedStatus == 'failed'
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
                                          color: statusColor.withValues(
                                            alpha: .9,
                                          ),
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
                        // Remarks — soft pastel red/pink card, distinct
                        // from the green used for notifications.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            (remarks != null && remarks.isNotEmpty)
                                ? remarks
                                : "No remarks recorded.",
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(
                                0xFFDC2626,
                              ).withValues(alpha: .85),
                              height: 1.55,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Footer: units, blood type, recorded timestamp.
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            _footerStat(
                              Icons.water_drop_rounded,
                              "$units unit(s)",
                            ),
                            if (bloodType != null && bloodType.isNotEmpty)
                              _footerStat(
                                Icons.bloodtype_rounded,
                                bloodType,
                              ),
                            _footerStat(
                              Icons.access_time_rounded,
                              formattedTimestamp,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerStat(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: Colors.grey.shade400),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
    ],
  );
}
