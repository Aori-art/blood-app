import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'streak/streak_screen.dart';

import 'anim.dart';
import 'check.dart';
import 'config.dart';
import 'home.dart' show FloatingNavMetrics, kBottomNavBarHeight;
import 'shared_design.dart';
import 'app_palette.dart';
import 'widgets/glow_pulse.dart';
import 'cancel_appointment_sheet.dart';

// Sticky bottom bar's own content height (12 top pad + 50 confirm button
// height + 12 bottom pad) — used so the scroll content ends exactly one
// gap above it instead of guessing at a fixed value.
const double kStickyBarHeight = 12 + 50 + 12;

/// One bookable time slot of a donation center (from the database).
class TimeSlot {
  final int id;

  /// Exactly the text sent as appointment_time, e.g. "8:00 AM - 9:00 AM".
  final String value;

  /// morning | afternoon | evening
  final String period;

  const TimeSlot({required this.id, required this.value, required this.period});
}

class BookScreen extends StatefulWidget {
  final bool showBackButton;
  final int? preselectedFacilityId;

  const BookScreen({
    super.key,
    this.showBackButton = false,
    this.preselectedFacilityId,
  });

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen>
    with SingleTickerProviderStateMixin {
  DateTime? selectedDate;
  int? selectedFacilityId;
  String? selectedTime;

  // Raw backend eligibility_status.status value: eligible / not_eligible /
  // pending / for_review (both shown as "Under Review") / temporary_deferred /
  // other.
  String? _eligibilityStatus;
  String? _eligibilityRecommendation;
  String? _nextEligibleDate;
  bool _canRetake = false;
  String? _retakeDate;
  int _retakeDaysRemaining = 0;
  bool _checkingEligibility = true;

  // Source of truth for "does the donor have an active appointment" — the
  // full object returned by get_appointments.php, needed for reschedule.
  Map<String, dynamic>? _currentAppointment;
  bool _checkingAppointment = true;
  bool _appointmentError = false;

  bool _isRescheduling = false;
  bool _isSubmitting = false;

  // Cancellation allowance (get_cancel_policy.php). A failed call counts as
  // "not restricted".
  CancelPolicy? _cancelPolicy;
  bool get _bookingPaused => _cancelPolicy?.restricted == true;

  // Post-donation success screen (get_donation_status.php) — the backend
  // decides when to show it via show_donation_success, we don't re-derive it.
  Map<String, dynamic>? _latestDonation;
  Map<String, dynamic>? _donationEligibility;
  int _totalDonations = 0;
  bool _showDonationSuccess = false;
  bool _checkingDonation = true;

  // Donation centers (facilities table) — fetched, not hardcoded.
  List<Map<String, dynamic>> _facilities = [];
  bool _loadingFacilities = true;
  bool _facilitiesError = false;
  bool _appliedPreselect = false;
  bool _showAllFacilities = false;
  final _facilitySearchCtrl = TextEditingController();
  String _facilitySearchQuery = '';

  final _dateStripCtrl = ScrollController();

  Map<String, dynamic>? get _selectedFacility {
    if (selectedFacilityId == null) return null;
    for (final f in _facilities) {
      if ((f['facility_id'] as num?)?.toInt() == selectedFacilityId) return f;
    }
    return null;
  }

  // Time slots per donation center (slots table) — fetched, not hardcoded.
  Map<int, List<TimeSlot>> _slotsByFacility = {};
  bool _loadingSlots = true;
  bool _slotsError = false;

  List<TimeSlot> get _slotsForSelectedFacility {
    final id = selectedFacilityId;
    if (id == null) return const [];
    return _slotsByFacility[id] ?? const [];
  }

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Confirm button's breathing stops with animations removed.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulseController
        ..stop()
        ..value = 0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dateStripCtrl.dispose();
    _facilitySearchCtrl.dispose();
    super.dispose();
  }

  // Mirrors _buildBody()'s branching to decide, without building the widget,
  // whether the booking/reschedule form is what's currently on screen — used
  // to decide whether the sticky bottom bar and step indicator should show.
  bool get _showingBookingForm {
    if (_checkingEligibility || _checkingDonation) return false;
    if (_showDonationSuccess && _latestDonation != null) return false;
    if ((_eligibilityStatus ?? 'not_checked') != 'eligible') return false;
    if (_checkingAppointment || _appointmentError) return false;
    if (_currentAppointment != null && !_isRescheduling) return false;
    // "Booking is paused" replaces the form (and its sticky bar).
    if (_currentAppointment == null && _bookingPaused) return false;
    return true;
  }

  Future<void> _loadStatuses() async {
    await Future.wait([
      _fetchEligibilityStatus(),
      _fetchCurrentAppointment(),
      _fetchDonationStatus(),
      _fetchFacilities(),
      _fetchTimeSlots(),
      _fetchCancelPolicy(),
    ]);
  }

  Future<void> _fetchCancelPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    CancelPolicy? policy;
    if (donorId != null && donorId.isNotEmpty) {
      policy = await CancelAppointmentApi.fetchPolicy(donorId);
    }
    if (!mounted) return;
    setState(() => _cancelPolicy = policy);
  }

  Future<void> _fetchEligibilityStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');

      if (donorId == null || donorId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _eligibilityStatus = 'not_checked';
          _checkingEligibility = false;
        });
        return;
      }

      final url = Uri.parse(
        "${AppConfig.baseUrl}/get_eligibility_status.php?donor_id=$donorId",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawStatus = data['status'];

        setState(() {
          _eligibilityStatus =
              rawStatus == null || rawStatus.toString().trim().isEmpty
              ? 'not_checked'
              : rawStatus.toString().trim().toLowerCase();
          _eligibilityRecommendation = data['recommendation_message']
              ?.toString();
          _nextEligibleDate = data['next_eligible_date']?.toString();
          _canRetake =
              data['can_retake'] == true ||
              data['can_retake'].toString() == '1';
          final retakeDate = data['retake_available_date']?.toString();
          _retakeDate = retakeDate?.isEmpty == true ? null : retakeDate;
          _retakeDaysRemaining =
              (data['retake_days_remaining'] as num?)?.toInt() ?? 0;
          _checkingEligibility = false;
        });
      } else {
        setState(() {
          _eligibilityStatus = 'not_checked';
          _checkingEligibility = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eligibilityStatus = 'not_checked';
        _checkingEligibility = false;
      });
    }
  }

  Future<void> _fetchCurrentAppointment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');

      if (donorId == null || donorId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _currentAppointment = null;
          _checkingAppointment = false;
          _appointmentError = false;
        });
        return;
      }

      final url = Uri.parse(
        "${AppConfig.baseUrl}/get_appointments.php?donor_id=$donorId",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is Map ? data['data'] : null;

        if (data is Map && data['status'] == 'success' && list is List) {
          setState(() {
            _currentAppointment = list.isNotEmpty
                ? Map<String, dynamic>.from(list.first as Map)
                : null;
            _checkingAppointment = false;
            _appointmentError = false;
          });
        } else {
          // Unexpected response shape — don't assume "no appointment",
          // surface a retryable error instead so we don't wrongly show
          // the booking form to someone who already has one.
          setState(() {
            _checkingAppointment = false;
            _appointmentError = true;
          });
        }
      } else {
        setState(() {
          _checkingAppointment = false;
          _appointmentError = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAppointment = false;
        _appointmentError = true;
      });
    }
  }

  Future<void> _fetchDonationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');

      if (donorId == null || donorId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _showDonationSuccess = false;
          _checkingDonation = false;
        });
        return;
      }

      final url = Uri.parse(
        "${AppConfig.baseUrl}/get_donation_status.php?donor_id=$donorId",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['status'] == 'success') {
          setState(() {
            _showDonationSuccess = data['show_donation_success'] == true;
            _latestDonation = data['latest_donation'] is Map
                ? Map<String, dynamic>.from(data['latest_donation'])
                : null;
            _donationEligibility = data['eligibility'] is Map
                ? Map<String, dynamic>.from(data['eligibility'])
                : null;
            _totalDonations = (data['total_donations'] as num?)?.toInt() ?? 0;
            _checkingDonation = false;
          });
        } else {
          setState(() {
            _showDonationSuccess = false;
            _checkingDonation = false;
          });
        }
      } else {
        setState(() {
          _showDonationSuccess = false;
          _checkingDonation = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showDonationSuccess = false;
        _checkingDonation = false;
      });
    }
  }

  Future<void> _fetchFacilities() async {
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/get_facilities.php");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is Map ? data['facilities'] : null;

        if (data is Map && data['status'] == 'success' && list is List) {
          final facilities = list
              .whereType<Map>()
              .map((f) => Map<String, dynamic>.from(f))
              .toList();

          int? preselect;
          if (!_appliedPreselect &&
              widget.preselectedFacilityId != null &&
              !_isRescheduling &&
              selectedFacilityId == null) {
            final exists = facilities.any(
              (f) =>
                  (f['facility_id'] as num?)?.toInt() ==
                  widget.preselectedFacilityId,
            );
            if (exists) preselect = widget.preselectedFacilityId;
          }

          setState(() {
            _facilities = facilities;
            _loadingFacilities = false;
            _facilitiesError = false;
            if (preselect != null) selectedFacilityId = preselect;
            _appliedPreselect = true;
          });
          return;
        }
      }
      setState(() {
        _loadingFacilities = false;
        _facilitiesError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingFacilities = false;
        _facilitiesError = true;
      });
    }
  }

  Future<void> _fetchTimeSlots() async {
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/get_facility_time_slots.php");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data is Map ? data['slots_by_facility'] : null;
        if (data is Map && data['status'] == 'success' && raw is Map) {
          final map = <int, List<TimeSlot>>{};
          raw.forEach((key, list) {
            final id = int.tryParse(key.toString());
            if (id == null || list is! List) return;
            final slots = <TimeSlot>[];
            for (final s in list.whereType<Map>()) {
              final value = s['value']?.toString() ?? '';
              if (value.isEmpty) continue;
              slots.add(
                TimeSlot(
                  id: (s['slot_id'] as num?)?.toInt() ?? slots.length,
                  value: value,
                  period: _slotPeriod(s),
                ),
              );
            }
            if (slots.isNotEmpty) map[id] = slots;
          });
          setState(() {
            _slotsByFacility = map;
            _loadingSlots = false;
            _slotsError = false;
            // The admin may have changed the slots: drop a time that is gone.
            if (selectedTime != null &&
                !_slotsForSelectedFacility.any((s) => s.value == selectedTime)) {
              selectedTime = null;
            }
          });
          return;
        }
      }
      setState(() {
        _loadingSlots = false;
        _slotsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSlots = false;
        _slotsError = true;
      });
    }
  }

  /// The slot's period; falls back to its start time if the server sent an
  /// unknown one, so a slot is never hidden.
  String _slotPeriod(Map s) {
    final p = s['period']?.toString().toLowerCase();
    if (p == 'morning' || p == 'afternoon' || p == 'evening') return p!;
    final hour = int.tryParse(
      (s['start_time']?.toString() ?? '').split(':').first,
    );
    if (hour == null || hour < 12) return 'morning';
    return hour < 17 ? 'afternoon' : 'evening';
  }

  Future<void> _retryFetchAppointment() async {
    if (mounted) {
      setState(() {
        _checkingAppointment = true;
        _appointmentError = false;
      });
    }
    await _fetchCurrentAppointment();
  }

  Future<void> _refreshStatuses() async {
    if (mounted) {
      setState(() {
        _checkingEligibility = true;
        _checkingAppointment = true;
        _appointmentError = false;
        _checkingDonation = true;
        _loadingFacilities = true;
        _facilitiesError = false;
        _loadingSlots = true;
        _slotsError = false;
      });
    }

    await _loadStatuses();
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
      // Light keeps its look; dark inherits the app's dark theme.
      builder: (context, child) {
        if (context.palette.isDark) return child!;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.foreground,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
      final today = DateTime.now();
      final tomorrow = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(const Duration(days: 1));
      final index = DateTime(
        picked.year,
        picked.month,
        picked.day,
      ).difference(tomorrow).inDays;
      if (index >= 0 && index < 14 && _dateStripCtrl.hasClients) {
        _dateStripCtrl.animateTo(
          (index * 70).toDouble(),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _showSnack(String message, {Color? color, IconData? icon}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon ?? Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color ?? AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showConfirmBookingSheet() {
    if (!_allSelected) return;
    HapticFeedback.selectionClick();

    final facility = _selectedFacility;
    final facilityName = facility?['facility_name']?.toString() ?? '';
    final facilityAddress = facility?['address']?.toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Confirm your booking?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Please review your appointment details.',
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  border: Border.all(color: context.palette.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _confirmSummaryRow(
                      icon: Icons.event_rounded,
                      label: 'Date',
                      value: _formatDate(selectedDate!),
                    ),
                    const SizedBox(height: 12),
                    _confirmSummaryRow(
                      icon: Icons.schedule_rounded,
                      label: 'Time',
                      value: selectedTime!,
                    ),
                    const SizedBox(height: 12),
                    _confirmSummaryRow(
                      icon: Icons.location_on_rounded,
                      label: 'Donation center',
                      value: facilityName,
                      sublabel:
                          (facilityAddress != null && facilityAddress.isNotEmpty)
                          ? facilityAddress
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.infoBg,
                  border: Border.all(color: context.palette.infoBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: context.palette.infoText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Arrive 10 minutes early and bring a valid ID.',
                        style: TextStyle(fontSize: 12, color: context.palette.infoText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.palette.muted,
                          side: BorderSide(color: context.palette.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Go Back',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _submitBooking();
                        },
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
                        child: const Text(
                          'Confirm Booking',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    String? sublabel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.palette.accentBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: context.palette.primaryText),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: context.palette.muted),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.palette.foreground,
                ),
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submitBooking() async {
    if (_eligibilityStatus != 'eligible') {
      _showSnack("You need to be eligible before booking an appointment.");
      return;
    }

    if (_currentAppointment != null) {
      _showSnack(
        "You already have an active appointment.",
        color: AppColors.warning,
        icon: Icons.schedule_rounded,
      );
      return;
    }

    if (selectedDate == null ||
        selectedFacilityId == null ||
        selectedTime == null) {
      _showSnack("Please fill in all fields");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (!mounted) return;
      _showSnack("Unable to find your account. Please sign in again.");
      return;
    }

    setState(() => _isSubmitting = true);

    final formattedDate =
        "${selectedDate!.year.toString().padLeft(4, '0')}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";

    final url = Uri.parse("${AppConfig.baseUrl}/book_appointment.php");

    try {
      final response = await http
          .post(
            url,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({
              "donor_id": int.tryParse(donorId) ?? donorId,
              "appointment_date": formattedDate,
              "appointment_time": selectedTime,
              "donation_center": _selectedFacility!['facility_name'],
              "facility_id": selectedFacilityId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() => _isSubmitting = false);
        _showSnack("Server error: ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (data is Map && data["success"] == true) {
        final appointment = data['appointment'];
        setState(() {
          selectedDate = null;
          selectedFacilityId = null;
          selectedTime = null;
          _isSubmitting = false;
          _currentAppointment = appointment is Map
              ? Map<String, dynamic>.from(appointment)
              : null;
        });
        // Fall back to a fresh fetch if the backend didn't echo the
        // appointment object, so the Manage Appointment view still appears.
        if (_currentAppointment == null) {
          await _fetchCurrentAppointment();
        }
        if (!mounted) return;
        _showSnack(
          "Appointment booked successfully!",
          color: AppColors.success,
          icon: Icons.check_circle_outline,
        );
      } else {
        setState(() => _isSubmitting = false);
        final message =
            (data is Map ? data["message"]?.toString() : null) ??
            "Unknown error";
        _showSnack(message);
        if (data is Map && data['code'] == 'INVALID_TIME_SLOT') {
          // The slots changed under the donor: clear the time, show current ones.
          setState(() => selectedTime = null);
          await _fetchTimeSlots();
          return;
        }
        await _refreshStatuses();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack("Connection error: $e");
    }
  }

  // ── Cancel the appointment ────────────────────────────────────────────────

  Future<void> _showCancelSheet() async {
    final appointment = _currentAppointment;
    if (appointment == null) return;
    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');
    if (!mounted) return;
    if (donorId == null || donorId.isEmpty) {
      _showSnack("Unable to find your account. Please sign in again.");
      return;
    }
    final result = await showCancelAppointmentSheet(
      context,
      appointment: appointment,
      donorId: donorId,
      formatDate: _formatDateString,
      formatTime: _formatAppointmentTime,
      showMessage: _showSnack,
    );
    if (!mounted || result == null) return;

    if (!result.success) {
      // The appointment changed (already cancelled, done, in the past or
      // gone): show why and reload what is true now.
      _showSnack(result.message ?? 'This appointment can no longer be cancelled.');
      await _refreshStatuses();
      return;
    }

    setState(() {
      _currentAppointment = null;
      _isRescheduling = false;
      selectedDate = null;
      selectedFacilityId = null;
      selectedTime = null;
    });
    await _refreshStatuses();
    if (!mounted) return;
    _showSnack(
      'Appointment cancelled.',
      color: AppColors.success,
      icon: Icons.check_circle_outline,
    );
    if (result.restricted) await _showBookingPausedDialog(result);
  }

  Future<void> _showBookingPausedDialog(CancelResult result) {
    final n = result.consecutiveCount ?? _cancelPolicy?.consecutiveCount;
    // The server's explanation (from the policy it just reloaded), else the
    // numbers it sent.
    final explanation =
        _cancelPolicy?.restrictionReason ??
        (n != null && n > 0
            ? "You've cancelled $n appointment${n == 1 ? '' : 's'} in a row, "
                  'so booking is paused until our team reviews your account.'
            : 'Booking is paused until our team reviews your account.');
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(
          Icons.pause_circle_rounded,
          size: 36,
          color: context.palette.warning,
        ),
        title: Text(
          'Booking paused',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: context.palette.foreground,
          ),
        ),
        content: Text(
          explanation,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.primaryText,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _startReschedule() async {
    final appointment = _currentAppointment;
    if (appointment == null) return;

    DateTime? prefillDate;
    try {
      prefillDate = DateTime.parse(appointment['appointment_date'].toString());
    } catch (_) {
      prefillDate = null;
    }

    final appointmentCenterName = appointment['donation_center']
        ?.toString()
        .trim()
        .toLowerCase();
    int? prefillFacilityId;
    if (appointmentCenterName != null && appointmentCenterName.isNotEmpty) {
      for (final f in _facilities) {
        final name = f['facility_name']?.toString().trim().toLowerCase();
        if (name != null && name == appointmentCenterName) {
          prefillFacilityId = (f['facility_id'] as num?)?.toInt();
          break;
        }
      }
    }

    // The slots differ per center: make sure they are loaded before matching.
    if (_slotsByFacility.isEmpty) {
      await _fetchTimeSlots();
      if (!mounted) return;
    }

    final formattedStart = _formatTime24(
      appointment['appointment_time']?.toString(),
    );
    String? prefillTime;
    if (formattedStart != null && prefillFacilityId != null) {
      // If the admin changed the slots nothing matches: the donor picks again.
      for (final slot in _slotsByFacility[prefillFacilityId] ?? <TimeSlot>[]) {
        if (slot.value.startsWith(formattedStart)) {
          prefillTime = slot.value;
          break;
        }
      }
    }

    setState(() {
      selectedDate = prefillDate;
      selectedFacilityId = prefillFacilityId;
      selectedTime = prefillTime;
      _isRescheduling = true;
    });
  }

  void _cancelReschedule() {
    setState(() {
      _isRescheduling = false;
      selectedDate = null;
      selectedFacilityId = null;
      selectedTime = null;
    });
  }

  Future<void> _confirmAndReschedule() async {
    if (selectedDate == null ||
        selectedFacilityId == null ||
        selectedTime == null) {
      _showSnack("Please fill in all fields");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Reschedule Appointment?",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          "Your existing appointment will be changed to the new date and time.",
          style: TextStyle(fontSize: 13, color: context.palette.muted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.muted,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("Confirm Reschedule"),
          ),
        ],
      ),
    );

    if (confirmed == true) await _submitReschedule();
  }

  Future<void> _submitReschedule() async {
    final appointment = _currentAppointment;
    if (appointment == null) return;

    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (!mounted) return;
      _showSnack("Unable to find your account. Please sign in again.");
      return;
    }

    setState(() => _isSubmitting = true);

    final formattedDate =
        "${selectedDate!.year.toString().padLeft(4, '0')}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";

    final url = Uri.parse("${AppConfig.baseUrl}/reschedule_appointment.php");

    try {
      final response = await http
          .post(
            url,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({
              "donor_id": int.tryParse(donorId) ?? donorId,
              "appointment_id": appointment['appointment_id'],
              "appointment_date": formattedDate,
              "appointment_time": selectedTime,
              "donation_center": _selectedFacility!['facility_name'],
              "facility_id": selectedFacilityId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() => _isSubmitting = false);
        _showSnack("Server error: ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (data is Map && data["success"] == true) {
        final updated = data['appointment'];
        setState(() {
          _isSubmitting = false;
          _isRescheduling = false;
          selectedDate = null;
          selectedFacilityId = null;
          selectedTime = null;
          if (updated is Map) {
            _currentAppointment = Map<String, dynamic>.from(updated);
          }
        });
        if (updated is! Map) {
          await _fetchCurrentAppointment();
        }
        if (!mounted) return;
        _showSnack(
          "Appointment rescheduled successfully.",
          color: AppColors.success,
          icon: Icons.check_circle_outline,
        );
      } else {
        setState(() => _isSubmitting = false);
        final message =
            (data is Map ? data["message"]?.toString() : null) ??
            "Unknown error";
        _showSnack(message);
        if (data is Map && data['code'] == 'INVALID_TIME_SLOT') {
          setState(() => selectedTime = null);
          await _fetchTimeSlots();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack("Connection error: $e");
    }
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];

    return "$weekday, $month ${date.day}, ${date.year}";
  }

  String _formatDateShort(DateTime date) {
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

    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  /// Formats a raw "date-ish" string (e.g. "2026-08-22") from the backend
  /// into "August 22, 2026", falling back to the raw value if unparsable.
  String _formatDateString(String? raw) {
    if (raw == null || raw.isEmpty) return "N/A";
    try {
      return _formatDateShort(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  /// Formats a 24h "HH:MM:SS" (or "HH:MM") backend time into "10:00 AM".
  /// Returns null if unparsable so callers can treat it as "no match".
  String? _formatTime24(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parts = raw.split(":");
      int hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? "PM" : "AM";
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return "$hour:${minute.toString().padLeft(2, '0')} $period";
    } catch (_) {
      return null;
    }
  }

  String _formatAppointmentTime(String? raw) =>
      _formatTime24(raw) ?? (raw ?? "N/A");

  String _formatAppointmentStatus(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return "Pending Confirmation";
      case 'confirmed':
        return "Confirmed";
      case 'rescheduled':
        return "Rescheduled";
      case 'scheduled':
        return "Scheduled";
      case 'cancelled':
      case 'canceled':
        return "Cancelled";
      case 'completed':
        return "Completed";
      default:
        final status = (raw ?? '').toLowerCase();
        if (status.isEmpty) return "Pending Confirmation";
        return status
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }

  // Short line shown under the status badge in the appointment summary card.
  String _appointmentStatusSupportingText(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
      case 'scheduled':
        return "We'll notify you once this is confirmed.";
      case 'approved':
      case 'confirmed':
        return "Your appointment is confirmed — please avoid rescheduling unless necessary, as slots are limited for other donors too.";
      case 'rescheduled':
        return "Your appointment has been moved — here are the new details.";
      default:
        return "";
    }
  }

  Color _appointmentStatusColor(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'cancelled':
      case 'canceled':
        return context.palette.primaryText;
      case 'pending':
      case 'scheduled':
        return context.palette.warning;
      case 'rescheduled':
        return context.palette.info;
      case 'approved':
      case 'confirmed':
      case 'completed':
        return context.palette.success;
      default:
        return context.palette.muted;
    }
  }

  bool get _allSelected =>
      selectedDate != null &&
      selectedFacilityId != null &&
      selectedTime != null;

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'book', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final showingForm = _showingBookingForm;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          _header(showingForm),
          Expanded(
            child: RefreshIndicator(
              color: context.palette.primaryText,
              onRefresh: _refreshStatuses,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  20,
                  16,
                  showingForm
                      ? kStickyBarHeight + 16
                      : (widget.showBackButton
                            ? 24
                            : FloatingNavMetrics.bottomPadding(context)),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: screenHeight * 0.6),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBody(),
                  ),
                ),
              ),
            ),
          ),
          if (showingForm) _stickyBottomBar(isReschedule: _isRescheduling),
        ],
      ),
    );
  }

  Widget _header(bool showSteps) => EdonateHeader(
    title: 'Book Appointment',
    subtitle: 'Schedule your blood donation',
    leading: widget.showBackButton
        ? HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).pop(),
          )
        : null,
    actions: [
      HeaderIconButton(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onTap: _refreshStatuses,
      ),
    ],
    bottom: showSteps ? _stepIndicatorRow() : null,
  );

  Widget _stepIndicatorRow() {
    final steps = [
      ('Date', selectedDate != null),
      ('Center', selectedFacilityId != null),
      ('Time', selectedTime != null),
    ];
    return Row(
      children: steps
          .map(
            (s) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: s.$2
                      ? context.palette.surface
                      : Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.$2) ...[
                      Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: context.palette.primaryText,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      s.$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: s.$2 ? context.palette.primaryText : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _formatMonthDay(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}';
  }

  Widget _stickyBottomBar({required bool isReschedule}) {
    final completedCount = [
      selectedDate,
      selectedFacilityId,
      selectedTime,
    ].where((e) => e != null).length;
    final stepN = (completedCount + 1).clamp(1, 3);

    Widget left;
    if (isReschedule) {
      left = Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _isSubmitting ? null : _cancelReschedule,
          style: TextButton.styleFrom(
            foregroundColor: context.palette.muted,
            padding: EdgeInsets.zero,
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    } else if (_allSelected) {
      left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_formatMonthDay(selectedDate!)} · $selectedTime',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
          Text(
            _selectedFacility?['facility_name']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.palette.muted),
          ),
        ],
      );
    } else {
      left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Step $stepN of 3',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
          Text(
            'Select a date, center and time',
            style: TextStyle(fontSize: 11, color: context.palette.muted),
          ),
        ],
      );
    }

    final bar = Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            _confirmButton(isReschedule: isReschedule),
          ],
        ),
      ),
    );

    // Tab mode: the floating nav sits at the bottom of the screen, so this bar
    // rides above it (Check button included).
    // Pushed mode: there's no bottom navigation, so clear the gesture area.
    if (widget.showBackButton) return SafeArea(top: false, child: bar);
    return Padding(
      padding: EdgeInsets.only(
        bottom: kBottomNavBarHeight + MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: bar,
    );
  }

  Widget _confirmButton({required bool isReschedule}) {
    final enabled = _allSelected && !_isSubmitting;
    return GlowPulse(
      enabled: enabled,
      child: AnimatedBuilder(
      animation: _pulseController,
      builder: (_, child) {
        final scale = enabled ? 1.0 + (_pulseController.value * 0.02) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: ElevatedButton(
        onPressed: enabled
            ? (isReschedule ? _confirmAndReschedule : _showConfirmBookingSheet)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Container(
          height: 50,
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: AppColors.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: enabled ? null : context.palette.border,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isReschedule ? 'Confirm Reschedule' : 'Confirm Booking',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: enabled ? Colors.white : context.palette.hint,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: enabled ? Colors.white : context.palette.hint,
                    ),
                  ],
                ),
        ),
      ),
      ),
    );
  }

  Widget _buildBody() {
    if (_checkingEligibility || _checkingDonation) {
      return const _BookingSkeleton(key: ValueKey('loading'));
    }

    if (_showDonationSuccess && _latestDonation != null) {
      return _DonationSuccessView(
        key: const ValueKey('donation_success'),
        donation: _latestDonation!,
        eligibility: _donationEligibility,
        totalDonations: _totalDonations,
        formatDate: _formatDateString,
      );
    }

    final status = _eligibilityStatus ?? 'not_checked';

    if (status != 'eligible') {
      return _EligibilityGate(
        key: ValueKey('eligibility_$status'),
        status: status,
        recommendation: _eligibilityRecommendation,
        nextEligibleDate: _nextEligibleDate,
        canRetake: _canRetake,
        retakeDate: _retakeDate,
        retakeDaysRemaining: _retakeDaysRemaining,
        onGoToCheck: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CheckScreen()));
        },
      );
    }

    if (_checkingAppointment) {
      return Center(
        key: ValueKey('appointment_loading'),
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: CircularProgressIndicator(
            color: context.palette.primaryText,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_appointmentError) {
      return _AppointmentFetchError(
        key: const ValueKey('appointment_error'),
        onRetry: _retryFetchAppointment,
      );
    }

    if (_currentAppointment != null && !_isRescheduling) {
      return _AppointmentManagementView(
        key: const ValueKey('manage_appointment'),
        appointment: _currentAppointment!,
        formatDate: _formatDateString,
        formatTime: _formatAppointmentTime,
        formatStatus: _formatAppointmentStatus,
        statusColor: _appointmentStatusColor,
        supportingText: _appointmentStatusSupportingText,
        onReschedule: _startReschedule,
        onCancel: _showCancelSheet,
      );
    }

    if (_currentAppointment != null && _isRescheduling) {
      return _buildBookingForm(
        key: const ValueKey('reschedule_form'),
        isReschedule: true,
      );
    }

    if (_bookingPaused) {
      return _BookingPausedCard(
        key: const ValueKey('booking_paused'),
        reason: _cancelPolicy?.restrictionReason,
      );
    }

    return _buildBookingForm(
      key: const ValueKey('booking_form'),
      isReschedule: false,
    );
  }

  Widget _buildBookingForm({required Key key, required bool isReschedule}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isReschedule) ...[
          Row(
            children: [
              IconButton(
                onPressed: _isSubmitting ? null : _cancelReschedule,
                icon: Icon(Icons.arrow_back, color: context.palette.muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashRadius: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "Reschedule Appointment",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        FadeSlideIn(
          index: 0,
          child: _sectionCard(
            icon: Icons.calendar_today,
            title: "Select Date",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dateStrip(),
                if (selectedDate != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.event_available_rounded,
                        size: 16,
                        color: context.palette.primaryText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(selectedDate!),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.palette.foreground,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 1,
          child: _sectionCard(
            icon: Icons.location_on,
            title: "Choose Donation Center",
            child: _donationCenterContent(),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 2,
          child: _sectionCard(
            icon: Icons.access_time,
            title: "Choose Time Slot",
            child: _timeSlotContent(),
          ),
        ),
        const SizedBox(height: 16),
        if (_allSelected) _bookingSummaryTicket(isReschedule: isReschedule),
        const SizedBox(height: 8),
        Text(
          isReschedule
              ? "Your appointment ID stays the same — only the date, time, and center are updated."
              : "You'll receive a confirmation message with all the details once your booking is confirmed.",
          style: TextStyle(fontSize: 11, color: context.palette.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.palette.primaryText, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ─── 5.3 Date strip ──────────────────────────────────────────────────────

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dateStrip() {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 1));
    final days = List.generate(14, (i) => start.add(Duration(days: i)));
    return SizedBox(
      height: 80,
      child: ListView.builder(
        controller: _dateStripCtrl,
        scrollDirection: Axis.horizontal,
        itemCount: days.length + 1,
        itemBuilder: (context, index) {
          if (index == days.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _moreDateTile(),
            );
          }
          final d = days[index];
          final selected =
              selectedDate != null && _isSameDate(selectedDate!, d);
          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
            child: _dateTile(d, selected, index),
          );
        },
      ),
    );
  }

  Widget _dateTile(DateTime d, bool selected, int index) {
    const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthsShort = [
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
    final weekdayLabel = index == 0 ? 'Tmrw' : weekdaysShort[d.weekday - 1];
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => selectedDate = d);
      },
      child: AnimatedScale(
        scale: selected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 62,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: AppColors.primaryGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : context.palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: selected ? null : Border.all(color: context.palette.border),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kCrimson.withValues(alpha: .3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                weekdayLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white70 : context.palette.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : context.palette.foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                monthsShort[d.month - 1],
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? Colors.white70 : context.palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreDateTile() => GestureDetector(
    onTap: _pickDate,
    child: Container(
      width: 62,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_rounded, size: 20, color: context.palette.primaryText),
          SizedBox(height: 6),
          Text(
            'More',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
        ],
      ),
    ),
  );

  // ─── 5.4 Donation center ─────────────────────────────────────────────────

  Widget _donationCenterContent() {
    if (_loadingFacilities) {
      return Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          border: Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.palette.primaryText,
          ),
        ),
      );
    }

    if (_facilitiesError) {
      return Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: context.palette.muted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't load donation centers",
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _loadingFacilities = true;
                _facilitiesError = false;
              });
              _fetchFacilities();
            },
            child: Text(
              "Retry",
              style: TextStyle(
                color: context.palette.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (_facilities.isEmpty) {
      return Text(
        "No donation centers are available right now.",
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      );
    }

    final query = _facilitySearchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _facilities
        : _facilities.where((f) {
            final name = (f['facility_name']?.toString() ?? '').toLowerCase();
            final barangay = (f['barangay_name']?.toString() ?? '')
                .toLowerCase();
            return name.contains(query) || barangay.contains(query);
          }).toList();

    final showSearch = _facilities.length > 6;
    final needsExpand = filtered.length > 4;
    List<Map<String, dynamic>> visible;
    if (!needsExpand || _showAllFacilities) {
      visible = filtered;
    } else {
      visible = filtered.take(4).toList();
      final selectedInVisible = visible.any(
        (f) => (f['facility_id'] as num?)?.toInt() == selectedFacilityId,
      );
      if (selectedFacilityId != null && !selectedInVisible) {
        final matches = filtered.where(
          (f) => (f['facility_id'] as num?)?.toInt() == selectedFacilityId,
        );
        if (matches.isNotEmpty) visible = [...visible.take(3), matches.first];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSearch) ...[_facilitySearchField(), const SizedBox(height: 10)],
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: Column(
            children: visible
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _facilityCard(f),
                  ),
                )
                .toList(),
          ),
        ),
        if (needsExpand && !_showAllFacilities)
          TextButton(
            onPressed: () => setState(() => _showAllFacilities = true),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
            ),
            child: Text(
              'Show all ${filtered.length} centers',
              style: TextStyle(
                color: context.palette.primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _facilitySearchField() => TextField(
    controller: _facilitySearchCtrl,
    onChanged: (v) => setState(() => _facilitySearchQuery = v),
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      hintText: 'Search by name or barangay',
      hintStyle: TextStyle(fontSize: 13, color: context.palette.muted),
      prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.palette.muted),
      isDense: true,
      filled: true,
      fillColor: context.palette.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.palette.primaryText, width: 1.5),
      ),
    ),
  );

  Widget _facilityCard(Map<String, dynamic> f) {
    final id = (f['facility_id'] as num?)?.toInt();
    final selected = selectedFacilityId != null && selectedFacilityId == id;
    final name = f['facility_name']?.toString() ?? '';
    final typeLabel = f['facility_type_label']?.toString();
    final barangay = f['barangay_name']?.toString();
    final subtitle = [
      if (typeLabel != null && typeLabel.isNotEmpty) typeLabel,
      if (barangay != null && barangay.isNotEmpty) barangay,
    ].join(' · ');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          selectedFacilityId = id;
          // Keep the time only if this center offers the same slot.
          if (selectedTime != null &&
              !_slotsForSelectedFacility.any((s) => s.value == selectedTime)) {
            selectedTime = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? context.palette.accentBg : context.palette.surface,
          border: Border.all(
            color: selected ? context.palette.primaryText : context.palette.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.palette.infoBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _facilityTypeIcon(f['facility_type']?.toString()),
                    color: context.palette.info,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.palette.foreground,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? kCrimson : Colors.transparent,
                    border: selected
                        ? null
                        : Border.all(
                            color: context.palette.border,
                            width: 1.5,
                          ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment.topCenter,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _facilityDetailsBox(f),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _facilityDetailsBox(Map<String, dynamic> facility) {
    final address = facility['address']?.toString();
    final contact = facility['contact_number']?.toString();

    final subParts = <String>[];
    for (final key in ['barangay_name', 'city', 'province']) {
      final v = facility[key]?.toString();
      if (v != null &&
          v.isNotEmpty &&
          !(address ?? '').toLowerCase().contains(v.toLowerCase())) {
        subParts.add(v);
      }
    }
    final addressLine = [
      if (address != null && address.isNotEmpty) address,
      if (subParts.isNotEmpty) subParts.join(', '),
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (addressLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 12,
                  color: context.palette.primaryText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    addressLine,
                    style: TextStyle(fontSize: 12, color: context.palette.foreground),
                  ),
                ),
              ],
            ),
          ),
        if (contact != null && contact.isNotEmpty)
          Row(
            children: [
              Icon(Icons.call_rounded, size: 12, color: context.palette.primaryText),
              const SizedBox(width: 6),
              Text(
                contact,
                style: TextStyle(fontSize: 12, color: context.palette.foreground),
              ),
            ],
          ),
      ],
    );
  }

  // ─── 5.5 Time slots ──────────────────────────────────────────────────────

  String _compactSlotLabel(String slot) {
    final parts = slot.split(' - ');
    if (parts.length != 2) return slot;
    final start = parts[0].trim();
    final end = parts[1].trim();
    final startPeriod = start.endsWith('AM') ? 'AM' : 'PM';
    final endPeriod = end.endsWith('AM') ? 'AM' : 'PM';
    if (startPeriod == endPeriod) {
      final startTime = start.replaceAll(RegExp(r'\s*(AM|PM)$'), '');
      return '$startTime – $end';
    }
    return '$start – $end';
  }

  Widget _timeSlotContent() {
    if (selectedFacilityId == null) {
      return Text(
        "Choose a donation center to see its available times.",
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      );
    }

    if (_loadingSlots) {
      return Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          border: Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.palette.primaryText,
          ),
        ),
      );
    }

    if (_slotsError) {
      return Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: context.palette.muted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't load time slots",
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _loadingSlots = true;
                _slotsError = false;
              });
              _fetchTimeSlots();
            },
            child: Text(
              "Retry",
              style: TextStyle(
                color: context.palette.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    final slots = _slotsForSelectedFacility;
    if (slots.isEmpty) {
      return Text(
        "No time slots are available at this center right now. Please choose another center.",
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      );
    }

    // Morning, Afternoon and (only when it has slots) Evening; empty groups
    // are hidden.
    final groups = <(IconData, Color, String, List<TimeSlot>)>[
      (
        Icons.wb_sunny_rounded,
        context.palette.warning,
        'Morning',
        slots.where((s) => s.period == 'morning').toList(),
      ),
      (
        Icons.wb_twilight_rounded,
        context.palette.orange,
        'Afternoon',
        slots.where((s) => s.period == 'afternoon').toList(),
      ),
      (
        Icons.nights_stay_rounded,
        context.palette.info,
        'Evening',
        slots.where((s) => s.period == 'evening').toList(),
      ),
    ].where((g) => g.$4.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _timeGroupHeader(groups[i].$1, groups[i].$2, groups[i].$3),
          const SizedBox(height: 8),
          _timeChipGrid(groups[i].$4),
        ],
      ],
    );
  }
  Widget _timeGroupHeader(IconData icon, Color color, String label) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.palette.muted,
        ),
      ),
    ],
  );

  Widget _timeChipGrid(List<TimeSlot> slots) => LayoutBuilder(
    builder: (context, constraints) {
      final chipWidth = (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: slots.map((slot) {
          final selected = selectedTime == slot.value;
          return SizedBox(
            width: chipWidth,
            height: 44,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => selectedTime = slot.value);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? kCrimson : context.palette.surface,
                  border: Border.all(
                    color: selected ? context.palette.primaryText : context.palette.border,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _compactSlotLabel(slot.value),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : context.palette.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    },
  );

  // ─── 5.6 Booking summary ticket ──────────────────────────────────────────

  Widget _bookingSummaryTicket({required bool isReschedule}) {
    final d = selectedDate!;
    const monthsShort = [
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
    const weekdaysShort = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return TweenAnimationBuilder<double>(
      key: const ValueKey('booking_summary'),
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: _TicketCard(
        top: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 64,
              decoration: BoxDecoration(
                color: context.palette.accentBg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    monthsShort[d.month - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.palette.primaryText,
                    ),
                  ),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: context.palette.foreground,
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
                  Row(
                    children: [
                      Icon(
                        Icons.confirmation_number_rounded,
                        size: 16,
                        color: context.palette.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isReschedule
                            ? 'New Schedule Summary'
                            : 'Booking Summary',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.palette.foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedFacility?['facility_name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.palette.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: context.palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        selectedTime!,
                        style: TextStyle(fontSize: 12, color: context.palette.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    weekdaysShort[d.weekday - 1],
                    style: TextStyle(fontSize: 11, color: context.palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: context.palette.info,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Arrive 10 minutes early and bring a valid ID.',
                style: TextStyle(fontSize: 11.5, color: context.palette.infoText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── LOADING SKELETON (5.1) ──────────────────────────────────────────────────

class _BookingSkeleton extends StatefulWidget {
  const _BookingSkeleton({super.key});

  @override
  State<_BookingSkeleton> createState() => _BookingSkeletonState();
}

class _BookingSkeletonState extends State<_BookingSkeleton>
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

  Widget _block(double height) => Container(
    width: double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
    ),
  );

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          _block(96),
          const SizedBox(height: 16),
          _block(150),
          const SizedBox(height: 16),
          _block(120),
        ],
      ),
    ),
  );
}

// ── TICKET CARD (shared by the booking summary and appointment views) ──────

class _TicketCard extends StatelessWidget {
  final Widget top;
  final Widget bottom;
  final Color? topBandColor;

  const _TicketCard({
    required this.top,
    required this.bottom,
    this.topBandColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.border),
      boxShadow: context.palette.shadow,
    ),
    child: Column(
      children: [
        if (topBandColor != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: topBandColor!.withValues(alpha: .10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: top,
          )
        else
          Padding(padding: const EdgeInsets.all(16), child: top),
        const _TicketDashedDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: bottom,
        ),
      ],
    ),
  );
}

class _TicketDashedDivider extends StatelessWidget {
  const _TicketDashedDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 16,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        Positioned.fill(child: CustomPaint(painter: _DashedLinePainter(context.palette.border))),
        const Positioned(left: -8, child: _TicketNotch()),
        const Positioned(right: -8, child: _TicketNotch()),
      ],
    ),
  );
}

class _TicketNotch extends StatelessWidget {
  const _TicketNotch();

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.palette.surfaceAlt,
    ),
  );
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  const _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 6.0, gap = 4.0;
    final y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

Widget _appointmentDateBlock(BuildContext context, 
  String? rawDate,
  String Function(String?) formatDate,
) {
  const monthsShort = [
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
  DateTime? d;
  if (rawDate != null) {
    try {
      d = DateTime.parse(rawDate);
    } catch (_) {}
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 58,
        height: 64,
        decoration: BoxDecoration(
          color: context.palette.accentBg,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: d == null
            ? Icon(Icons.calendar_today_rounded, color: context.palette.primaryText)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    monthsShort[d.month - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.palette.primaryText,
                    ),
                  ),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: context.palette.foreground,
                    ),
                  ),
                ],
              ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Date',
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
            const SizedBox(height: 2),
            Text(
              formatDate(rawDate),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.foreground,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ── APPOINTMENT MANAGEMENT VIEW ────────────────────────────────────────────

class _AppointmentManagementView extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final String Function(String?) formatDate;
  final String Function(String?) formatTime;
  final String Function(String?) formatStatus;
  final Color Function(String?) statusColor;
  final String Function(String?) supportingText;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  const _AppointmentManagementView({
    super.key,
    required this.appointment,
    required this.formatDate,
    required this.formatTime,
    required this.formatStatus,
    required this.statusColor,
    required this.supportingText,
    required this.onReschedule,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final status = appointment['status']?.toString();
    final color = statusColor(status);
    final subtitle = supportingText(status);
    final isConfirmed = const [
      'approved',
      'confirmed',
    ].contains((status ?? '').toLowerCase());
    // Only an appointment that is still ahead can be cancelled.
    final canCancel = const [
      'pending',
      'scheduled',
      'confirmed',
      'approved',
      'rescheduled',
    ].contains((status ?? '').toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          index: 0,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.palette.accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: context.palette.primaryText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Your Appointment",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 1,
          child: _TicketCard(
            topBandColor: color,
            top: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: color),
                      const SizedBox(width: 6),
                      Text(
                        formatStatus(status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ],
            ),
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isConfirmed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.palette.infoBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.palette.infoBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: context.palette.info,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "You're all set for this appointment. Reschedule only if something comes up — this keeps a slot open for another donor in the meantime.",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.infoText,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _appointmentDateBlock(context, 
                  appointment['appointment_date']?.toString(),
                  formatDate,
                ),
                const SizedBox(height: 14),
                _infoRow(context, 
                  icon: Icons.access_time_rounded,
                  label: "Time",
                  value: formatTime(
                    appointment['appointment_time']?.toString(),
                  ),
                ),
                Divider(height: 24, color: context.palette.surfaceAlt),
                _infoRow(context, 
                  icon: Icons.location_on_rounded,
                  label: "Donation Center",
                  value: appointment['donation_center']?.toString() ?? "N/A",
                ),
                Divider(height: 24, color: context.palette.surfaceAlt),
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                      color: context.palette.muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appointment['appointment_id'] != null
                          ? 'Appointment #${appointment['appointment_id']}'
                          : 'Appointment',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.palette.foreground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Show this at the donation center',
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 2,
          child: GlowPulse(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
            width: double.infinity,
            height: 50,
            child: isConfirmed
                ? OutlinedButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 19),
                    label: const Text(
                      "Reschedule Appointment",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.primaryText,
                      side: BorderSide(color: context.palette.primaryText),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 19),
                    label: const Text(
                      "Reschedule Appointment",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: context.palette.border,
                      disabledForegroundColor: context.palette.muted,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
          ),
        ),
        if (canCancel) ...[
          const SizedBox(height: 14),
          FadeSlideIn(
            index: 3,
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.event_busy_rounded, size: 19),
                label: const Text(
                  'Cancel Appointment',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.primaryText,
                  side: BorderSide(color: context.palette.primaryBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          "You can only manage one active appointment at a time. Pull down to refresh once your appointment status changes.",
          style: TextStyle(fontSize: 11, color: context.palette.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── BOOKING PAUSED ───────────────────────────────────────────────────────────

/// Shown instead of the booking form while the donor's bookings are paused
/// (too many cancellations in a row).
class _BookingPausedCard extends StatelessWidget {
  final String? reason;
  const _BookingPausedCard({super.key, this.reason});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FadeSlideIn(
      child: MergeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.warningBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.warningBorder),
          ),
          child: Column(
            children: [
              Icon(Icons.pause_circle_rounded, size: 44, color: p.warning),
              const SizedBox(height: 12),
              Text(
                'Booking is paused',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: p.warningText,
                ),
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reason!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.warningText,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Our team will review your account. Please contact the '
                'donation center if you need help.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SHARED HELPERS ──────────────────────────────────────────────────────────

Widget _infoRow(BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
}) {
  return Row(
    children: [
      Icon(icon, size: 18, color: context.palette.muted),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.foreground,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

IconData _facilityTypeIcon(String? facilityType) {
  switch (facilityType) {
    case 'hospital':
      return Icons.local_hospital_rounded;
    case 'blood_bank':
      return Icons.bloodtype_rounded;
    case 'clinic':
      return Icons.medical_services_rounded;
    case 'health_center':
      return Icons.health_and_safety_rounded;
    default:
      return Icons.apartment_rounded;
  }
}

/// Formats 1/2/3/4/11/12/13/21/... into "1st"/"2nd"/"3rd"/"4th"/"11th"/etc.
String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

// ── DONATION SUCCESS VIEW ────────────────────────────────────────────────────

class _DonationSuccessView extends StatelessWidget {
  final Map<String, dynamic> donation;
  final Map<String, dynamic>? eligibility;
  final int totalDonations;
  final String Function(String?) formatDate;

  const _DonationSuccessView({
    super.key,
    required this.donation,
    required this.eligibility,
    required this.totalDonations,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(index: 0, child: _hero(context)),
        const SizedBox(height: 20),
        FadeSlideIn(index: 1, child: _nextEligibleCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 2, child: _detailsCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 3, child: _impactBanner(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 4, child: _aftercareCard(context)),
        const SizedBox(height: 16),
        Text(
          "Booking will reopen automatically on your next eligible date. Pull down to refresh.",
          style: TextStyle(fontSize: 11, color: context.palette.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.palette.successBg,
              border: Border.all(color: context.palette.successBorder, width: 3),
              boxShadow: [
                BoxShadow(
                  color: context.palette.success.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.volunteer_activism_rounded,
              size: 50,
              color: context.palette.success,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Thank You for Donating!",
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          "Your donation was completed successfully. One donation can help save up to 3 lives.",
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
            height: 1.55,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: context.palette.successBg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: context.palette.successBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: context.palette.success,
              ),
              SizedBox(width: 7),
              Text(
                "Donation Completed",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.palette.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nextEligibleCard(BuildContext context) {
    final elig = eligibility;
    final daysRemaining = (elig?['days_remaining'] as num?)?.toInt();
    final totalWaitDays = (elig?['total_wait_days'] as num?)?.toInt();
    final nextEligibleDate = elig?['next_eligible_date']?.toString();
    final donationDate = donation['donation_date']?.toString();

    final showBar =
        daysRemaining != null && totalWaitDays != null && totalWaitDays > 0;
    final progress = showBar
        ? ((totalWaitDays - daysRemaining) / totalWaitDays).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_repeat_rounded,
                color: context.palette.primaryText,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                "Next Donation",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (elig == null)
            Text(
              "We'll let you know when you can donate again.",
              style: TextStyle(
                fontSize: 13,
                color: context.palette.muted,
                height: 1.5,
              ),
            )
          else ...[
            Text(
              formatDate(nextEligibleDate),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.palette.foreground,
              ),
            ),
            if (daysRemaining != null) ...[
              const SizedBox(height: 4),
              Text(
                daysRemaining == 1
                    ? "1 day to go"
                    : "$daysRemaining days to go",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.primaryText,
                ),
              ),
            ],
            if (showBar) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: context.palette.success,
                  backgroundColor: context.palette.border,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Donated ${formatDate(donationDate)}",
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
                  Text(
                    "Eligible ${formatDate(nextEligibleDate)}",
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _detailsCard(BuildContext context) {
    final donationDateRaw = donation['donation_date']?.toString();
    final bloodTypeRaw = donation['blood_type']?.toString();
    final unitsRaw = donation['blood_units'];
    final centerRaw = donation['donation_center']?.toString();
    final idRaw = donation['donation_id'];

    final rows = <Widget>[];
    void addRow(IconData icon, String label, String value) {
      if (rows.isNotEmpty) {
        rows.add(Divider(height: 24, color: context.palette.surfaceAlt));
      }
      rows.add(_infoRow(context, icon: icon, label: label, value: value));
    }

    if (donationDateRaw != null && donationDateRaw.isNotEmpty) {
      addRow(
        Icons.calendar_today_rounded,
        "Donation Date",
        formatDate(donationDateRaw),
      );
    }
    if (bloodTypeRaw != null && bloodTypeRaw.isNotEmpty) {
      addRow(Icons.bloodtype_rounded, "Blood Type", bloodTypeRaw);
    }
    if (unitsRaw != null) {
      final n = (unitsRaw as num).toInt();
      addRow(
        Icons.water_drop_rounded,
        "Units Donated",
        "$n unit${n == 1 ? '' : 's'}",
      );
    }
    if (centerRaw != null && centerRaw.isNotEmpty) {
      addRow(Icons.location_on_rounded, "Donation Center", centerRaw);
    }
    if (idRaw != null) {
      addRow(Icons.tag_rounded, "Donation ID", "#$idRaw");
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                color: context.palette.primaryText,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                "Donation Details",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: context.palette.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...rows,
        ],
      ),
    );
  }

  Widget _impactBanner(BuildContext context) {
    final text = totalDonations > 1
        ? "This was your ${_ordinal(totalDonations)} donation — together they could help save up to ${totalDonations * 3} lives."
        : "This was your first donation — welcome to the Dugtong donor community!";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.infoBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.infoBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_rounded,
            color: context.palette.info,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.infoText,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aftercareCard(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border.all(color: context.palette.border, width: 2),
      borderRadius: BorderRadius.circular(16),
      boxShadow: context.palette.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.health_and_safety_rounded,
              color: context.palette.primaryText,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              "Aftercare Tips",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: context.palette.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _aftercareRow(context, "Drink extra fluids for the next 24–48 hours."),
        _aftercareRow(context, "Avoid heavy lifting or strenuous exercise today."),
        _aftercareRow(context, 
          "Eat iron-rich foods like leafy greens, beans, and lean meat.",
        ),
      ],
    ),
  );

  Widget _aftercareRow(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: context.palette.success,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.palette.foreground,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── APPOINTMENT FETCH ERROR ─────────────────────────────────────────────────

class _AppointmentFetchError extends StatelessWidget {
  final VoidCallback onRetry;

  const _AppointmentFetchError({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: context.palette.muted,
            size: 30,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't check your appointment status",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: context.palette.foreground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            "Please check your connection and try again.",
            style: TextStyle(fontSize: 12, color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onRetry,
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: context.palette.primaryText,
            ),
            label: Text(
              "Retry",
              style: TextStyle(
                color: context.palette.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── ELIGIBILITY GATE ────────────────────────────────────────────────────────

class _EligibilityGate extends StatelessWidget {
  final String status;
  final VoidCallback onGoToCheck;
  final String? recommendation;
  final String? nextEligibleDate;
  final bool canRetake;
  final String? retakeDate;
  final int retakeDaysRemaining;

  const _EligibilityGate({
    super.key,
    required this.status,
    required this.onGoToCheck,
    required this.recommendation,
    required this.nextEligibleDate,
    required this.canRetake,
    required this.retakeDate,
    required this.retakeDaysRemaining,
  });

  bool get _isNotEligible => status == 'not_eligible';
  bool get _isDeferred => status == 'temporary_deferred';
  bool get _isNotChecked => status == 'not_checked';

  String _retakeWhen(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  String _formatLongDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _isNotEligible
        ? context.palette.primaryText
        : context.palette.warning;
    final Color accentBg = _isNotEligible
        ? context.palette.accentBg
        : context.palette.warningBg;
    final Color accentBorder = _isNotEligible
        ? context.palette.primaryBorder
        : context.palette.warningBorder;
    final IconData icon = _isNotEligible
        ? Icons.block_rounded
        : Icons.hourglass_top_rounded;

    final String title = _isNotChecked
        ? "Eligibility Check Required"
        : _isNotEligible
        ? "Not Eligible to Book"
        : _isDeferred
        ? "Temporarily Deferred"
        : "Under Review";

    final String message = _isNotChecked
        ? "Complete the eligibility screening before booking a donation appointment."
        : _isNotEligible
        ? recommendation ??
              "You are currently not eligible to schedule a blood donation."
        : _isDeferred
        ? recommendation ?? "Your eligibility has been temporarily deferred."
        : "Your eligibility is under review. You can book once our team approves it.";

    final String badgeLabel = _isNotChecked
        ? "Status: Not Checked"
        : _isNotEligible
        ? "Status: Not Eligible"
        : _isDeferred
        ? "Status: Temporarily Deferred"
        : "Status: Under Review";

    final bool showRetakePill =
        (_isNotEligible || _isDeferred) && !canRetake && retakeDate != null;

    return Center(
      child: FadeSlideIn(
        index: 0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.border),
            boxShadow: context.palette.shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentBg,
                  border: Border.all(color: accentBorder, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, size: 46, color: accent),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.muted,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (showRetakePill)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accentBg,
                      border: Border.all(color: accentBorder),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_repeat_rounded,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'Retake the check on ${_formatLongDate(retakeDate!)} · '
                            '${_retakeWhen(retakeDaysRemaining)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isDeferred &&
                  nextEligibleDate != null &&
                  nextEligibleDate!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Next Eligible Date: $nextEligibleDate',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: accentBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isNotEligible
                          ? Icons.cancel_rounded
                          : Icons.schedule_rounded,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.infoBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.infoBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: context.palette.info,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        showRetakePill
                            ? "Once your retake date arrives, take the eligibility check again from the Check tab. You'll be able to book once you're eligible."
                            : _isNotEligible
                            ? "Complete the eligibility screening in the Check tab. Once you're eligible, you'll be able to book an appointment."
                            : "Once your screening has been reviewed, this page will update automatically and you'll be able to book an appointment.",
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.infoText,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isNotChecked ||
                  (_isNotEligible && canRetake) ||
                  (_isDeferred && canRetake)) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: onGoToCheck,
                    icon: const Icon(
                      Icons.assignment_turned_in_outlined,
                      size: 19,
                    ),
                    label: Text(
                      _isNotChecked
                          ? "Take Eligibility Check"
                          : "Take Eligibility Check Again",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
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
              ],
              const SizedBox(height: 10),
              Text(
                "Pull down to refresh this page after your status changes.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
