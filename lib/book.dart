import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'check.dart';
import 'config.dart';

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
  // pending / temporary_deferred / other.
  String? _eligibilityStatus;
  String? _eligibilityRecommendation;
  String? _nextEligibleDate;
  bool _canRetake = false;
  bool _checkingEligibility = true;

  // Source of truth for "does the donor have an active appointment" — the
  // full object returned by get_appointments.php, needed for reschedule.
  Map<String, dynamic>? _currentAppointment;
  bool _checkingAppointment = true;
  bool _appointmentError = false;

  bool _isRescheduling = false;
  bool _isSubmitting = false;

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

  Map<String, dynamic>? get _selectedFacility {
    if (selectedFacilityId == null) return null;
    for (final f in _facilities) {
      if ((f['facility_id'] as num?)?.toInt() == selectedFacilityId) return f;
    }
    return null;
  }

  final List<String> timeSlots = [
    "8:00 AM - 9:00 AM",
    "9:00 AM - 10:00 AM",
    "10:00 AM - 11:00 AM",
    "1:00 PM - 2:00 PM",
    "2:00 PM - 3:00 PM",
    "3:00 PM - 4:00 PM",
  ];

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadStatuses() async {
    await Future.wait([
      _fetchEligibilityStatus(),
      _fetchCurrentAppointment(),
      _fetchDonationStatus(),
      _fetchFacilities(),
    ]);
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
              (f) => (f['facility_id'] as num?)?.toInt() == widget.preselectedFacilityId,
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFDC2626),
              onPrimary: Colors.white,
              onSurface: Color(0xFF111827),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
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
        backgroundColor: color ?? const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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
        color: const Color(0xFFF59E0B),
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
          color: Colors.green,
          icon: Icons.check_circle_outline,
        );
      } else {
        setState(() => _isSubmitting = false);
        final message =
            (data is Map ? data["message"]?.toString() : null) ??
            "Unknown error";
        _showSnack(message);
        await _refreshStatuses();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack("Connection error: $e");
    }
  }

  void _startReschedule() {
    final appointment = _currentAppointment;
    if (appointment == null) return;

    DateTime? prefillDate;
    try {
      prefillDate = DateTime.parse(appointment['appointment_date'].toString());
    } catch (_) {
      prefillDate = null;
    }

    final appointmentCenterName =
        appointment['donation_center']?.toString().trim().toLowerCase();
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

    final formattedStart = _formatTime24(
      appointment['appointment_time']?.toString(),
    );
    String? prefillTime;
    if (formattedStart != null) {
      for (final slot in timeSlots) {
        if (slot.startsWith(formattedStart)) {
          prefillTime = slot;
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
        content: const Text(
          "Your existing appointment will be changed to the new date and time.",
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
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
          color: Colors.green,
          icon: Icons.check_circle_outline,
        );
      } else {
        setState(() => _isSubmitting = false);
        final message =
            (data is Map ? data["message"]?.toString() : null) ??
            "Unknown error";
        _showSnack(message);
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
        return const Color(0xFFDC2626);
      case 'pending':
      case 'scheduled':
        return const Color(0xFFF59E0B);
      case 'rescheduled':
        return const Color(0xFF2563EB);
      case 'approved':
      case 'confirmed':
      case 'completed':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF6B7280);
    }
  }

  bool get _allSelected =>
      selectedDate != null && selectedFacilityId != null && selectedTime != null;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Column(
                  children: [
                    Text(
                      "Book Appointment",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Schedule your blood donation",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                if (widget.showBackButton)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFDC2626),
              onRefresh: _refreshStatuses,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
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
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_checkingEligibility || _checkingDonation) {
      return const Center(
        key: ValueKey('loading'),
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: CircularProgressIndicator(color: Color(0xFFDC2626)),
        ),
      );
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
        onGoToCheck: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CheckScreen()));
        },
      );
    }

    if (_checkingAppointment) {
      return const Center(
        key: ValueKey('appointment_loading'),
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: CircularProgressIndicator(
            color: Color(0xFFDC2626),
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
      );
    }

    if (_currentAppointment != null && _isRescheduling) {
      return _buildBookingForm(
        key: const ValueKey('reschedule_form'),
        isReschedule: true,
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
                icon: const Icon(Icons.arrow_back, color: Color(0xFF6B7280)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashRadius: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                "Reschedule Appointment",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF111827),
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
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: Color(0xFF9CA3AF),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selectedDate == null
                            ? "Choose a date"
                            : _formatDate(selectedDate!),
                        style: TextStyle(
                          color: selectedDate == null
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF111827),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      color: Color(0xFF9CA3AF),
                      size: 20,
                    ),
                  ],
                ),
              ),
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
            child: _styledDropdown<String>(
              value: selectedTime,
              hint: "Select a time",
              items: timeSlots,
              onChanged: (val) {
                setState(() => selectedTime = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_allSelected)
          TweenAnimationBuilder<double>(
            key: const ValueKey('booking_summary'),
            tween: Tween(begin: 0.9, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFF16A34A),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isReschedule
                            ? "New Schedule Summary"
                            : "Booking Summary",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _summaryRow("Date", _formatDateShort(selectedDate!)),
                  const SizedBox(height: 6),
                  _summaryRow("Time", selectedTime!),
                  const SizedBox(height: 6),
                  _summaryRow("Center", _selectedFacility!['facility_name'].toString()),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, child) {
            final scale = _allSelected
                ? 1.0 + (_pulseController.value * 0.03)
                : 1.0;
            return Transform.scale(scale: scale, child: child);
          },
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_allSelected && !_isSubmitting)
                  ? (isReschedule ? _confirmAndReschedule : _submitBooking)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                disabledBackgroundColor: const Color(0xFFF87171),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isReschedule
                              ? "Confirm Reschedule"
                              : "Confirm Booking",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ),
        ),
        if (isReschedule) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : _cancelReschedule,
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          isReschedule
              ? "Your appointment ID stays the same — only the date, time, and center are updated."
              : "You'll receive a confirmation message with all the details once your booking is confirmed.",
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFDC2626), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF111827),
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

  Widget _styledDropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        hint: Text(
          hint,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more, color: Color(0xFF9CA3AF)),
        style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
        items: items
            .map(
              (e) => DropdownMenuItem<T>(value: e, child: Text(e.toString())),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _donationCenterContent() {
    if (_loadingFacilities) {
      return Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
        ),
      );
    }

    if (_facilitiesError) {
      return Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF9CA3AF), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Couldn't load donation centers",
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
            child: const Text(
              "Retry",
              style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    if (_facilities.isEmpty) {
      return const Text(
        "No donation centers are available right now.",
        style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
      );
    }

    final selected = _selectedFacility;
    return Column(
      children: [
        _facilityDropdown(),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _facilityDetailsBox(selected),
        ],
      ],
    );
  }

  Widget _facilityDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<int>(
        value: selectedFacilityId,
        isExpanded: true,
        itemHeight: 60,
        menuMaxHeight: 360,
        hint: const Text(
          "Select a center",
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more, color: Color(0xFF9CA3AF)),
        style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
        selectedItemBuilder: (context) => _facilities.map((f) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              f['facility_name']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
            ),
          );
        }).toList(),
        items: _facilities.map((f) {
          final id = (f['facility_id'] as num?)?.toInt();
          final name = f['facility_name']?.toString() ?? '';
          final typeLabel = f['facility_type_label']?.toString();
          final barangay = f['barangay_name']?.toString();
          final subtitle = [
            if (typeLabel != null && typeLabel.isNotEmpty) typeLabel,
            if (barangay != null && barangay.isNotEmpty) barangay,
          ].join(' · ');

          return DropdownMenuItem<int>(
            value: id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                ),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              ],
            ),
          );
        }).toList(),
        onChanged: (val) => setState(() => selectedFacilityId = val),
      ),
    );
  }

  Widget _facilityDetailsBox(Map<String, dynamic> facility) {
    final facilityType = facility['facility_type']?.toString();
    final typeLabel = facility['facility_type_label']?.toString();
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typeLabel != null && typeLabel.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_facilityTypeIcon(facilityType), size: 12, color: const Color(0xFF2563EB)),
                  const SizedBox(width: 4),
                  Text(
                    typeLabel,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (address != null && address.isNotEmpty) ...[
            const Text("Address", style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(address, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            if (subParts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subParts.join(', '), style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ],
          ],
          if (contact != null && contact.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.call_rounded, size: 12, color: Color(0xFF2563EB)),
                const SizedBox(width: 6),
                Text(contact, style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }
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

  const _AppointmentManagementView({
    super.key,
    required this.appointment,
    required this.formatDate,
    required this.formatTime,
    required this.formatStatus,
    required this.statusColor,
    required this.supportingText,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    final status = appointment['status']?.toString();
    final color = statusColor(status);
    final subtitle = supportingText(status);
    final isConfirmed = const ['approved', 'confirmed'].contains(
      (status ?? '').toLowerCase(),
    );

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
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Your Appointment",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
                const Divider(height: 24, color: Color(0xFFF3F4F6)),
                if (isConfirmed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF2563EB),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "You're all set for this appointment. Reschedule only if something comes up — this keeps a slot open for another donor in the meantime.",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D4ED8),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _infoRow(
                  icon: Icons.calendar_today_rounded,
                  label: "Date",
                  value: formatDate(
                    appointment['appointment_date']?.toString(),
                  ),
                ),
                const Divider(height: 24, color: Color(0xFFF3F4F6)),
                _infoRow(
                  icon: Icons.access_time_rounded,
                  label: "Time",
                  value: formatTime(
                    appointment['appointment_time']?.toString(),
                  ),
                ),
                const Divider(height: 24, color: Color(0xFFF3F4F6)),
                _infoRow(
                  icon: Icons.location_on_rounded,
                  label: "Donation Center",
                  value: appointment['donation_center']?.toString() ?? "N/A",
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          index: 2,
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
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
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
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "You can only manage one active appointment at a time. Pull down to refresh once your appointment status changes.",
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── SHARED HELPERS ──────────────────────────────────────────────────────────

Widget _infoRow({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Row(
    children: [
      Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
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
        FadeSlideIn(index: 0, child: _hero()),
        const SizedBox(height: 20),
        FadeSlideIn(index: 1, child: _nextEligibleCard()),
        const SizedBox(height: 16),
        FadeSlideIn(index: 2, child: _detailsCard()),
        const SizedBox(height: 16),
        FadeSlideIn(index: 3, child: _impactBanner()),
        const SizedBox(height: 16),
        FadeSlideIn(index: 4, child: _aftercareCard()),
        const SizedBox(height: 16),
        const Text(
          "Booking will reopen automatically on your next eligible date. Pull down to refresh.",
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _hero() {
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
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0), width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              size: 50,
              color: Color(0xFF16A34A),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Thank You for Donating!",
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          "Your donation was completed successfully. One donation can help save up to 3 lives.",
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.55),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF16A34A)),
              SizedBox(width: 7),
              Text(
                "Donation Completed",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nextEligibleCard() {
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_repeat_rounded, color: Color(0xFFDC2626), size: 20),
              SizedBox(width: 8),
              Text(
                "Next Donation",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (elig == null)
            const Text(
              "We'll let you know when you can donate again.",
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            )
          else ...[
            Text(
              formatDate(nextEligibleDate),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            if (daysRemaining != null) ...[
              const SizedBox(height: 4),
              Text(
                daysRemaining == 1 ? "1 day to go" : "$daysRemaining days to go",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDC2626),
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
                  color: const Color(0xFF16A34A),
                  backgroundColor: const Color(0xFFE5E7EB),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Donated ${formatDate(donationDate)}",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                  Text(
                    "Eligible ${formatDate(nextEligibleDate)}",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _detailsCard() {
    final donationDateRaw = donation['donation_date']?.toString();
    final bloodTypeRaw = donation['blood_type']?.toString();
    final unitsRaw = donation['blood_units'];
    final centerRaw = donation['donation_center']?.toString();
    final idRaw = donation['donation_id'];

    final rows = <Widget>[];
    void addRow(IconData icon, String label, String value) {
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 24, color: Color(0xFFF3F4F6)));
      }
      rows.add(_infoRow(icon: icon, label: label, value: value));
    }

    if (donationDateRaw != null && donationDateRaw.isNotEmpty) {
      addRow(Icons.calendar_today_rounded, "Donation Date", formatDate(donationDateRaw));
    }
    if (bloodTypeRaw != null && bloodTypeRaw.isNotEmpty) {
      addRow(Icons.bloodtype_rounded, "Blood Type", bloodTypeRaw);
    }
    if (unitsRaw != null) {
      final n = (unitsRaw as num).toInt();
      addRow(Icons.water_drop_rounded, "Units Donated", "$n unit${n == 1 ? '' : 's'}");
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: Color(0xFFDC2626), size: 20),
              SizedBox(width: 8),
              Text(
                "Donation Details",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF111827),
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

  Widget _impactBanner() {
    final text = totalDonations > 1
        ? "This was your ${_ordinal(totalDonations)} donation — together they could help save up to ${totalDonations * 3} lives."
        : "This was your first donation — welcome to the eDonate donor community!";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite_rounded, color: Color(0xFF2563EB), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aftercareCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.health_and_safety_rounded, color: Color(0xFFDC2626), size: 20),
            SizedBox(width: 8),
            Text(
              "Aftercare Tips",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _aftercareRow("Drink extra fluids for the next 24–48 hours."),
        _aftercareRow("Avoid heavy lifting or strenuous exercise today."),
        _aftercareRow("Eat iron-rich foods like leafy greens, beans, and lean meat."),
      ],
    ),
  );

  Widget _aftercareRow(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF111827), height: 1.4),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: Color(0xFF9CA3AF),
            size: 30,
          ),
          const SizedBox(height: 12),
          const Text(
            "Couldn't check your appointment status",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF111827),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            "Please check your connection and try again.",
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 18,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              "Retry",
              style: TextStyle(
                color: Color(0xFFDC2626),
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

  const _EligibilityGate({
    super.key,
    required this.status,
    required this.onGoToCheck,
    required this.recommendation,
    required this.nextEligibleDate,
    required this.canRetake,
  });

  bool get _isNotEligible => status == 'not_eligible';
  bool get _isDeferred => status == 'temporary_deferred';
  bool get _isNotChecked => status == 'not_checked';

  @override
  Widget build(BuildContext context) {
    final Color accent = _isNotEligible
        ? const Color(0xFFDC2626)
        : const Color(0xFFF59E0B);
    final Color accentBg = _isNotEligible
        ? const Color(0xFFFFF1F1)
        : const Color(0xFFFFFBEB);
    final Color accentBorder = _isNotEligible
        ? const Color(0xFFFECACA)
        : const Color(0xFFFDE68A);
    final IconData icon = _isNotEligible
        ? Icons.block_rounded
        : Icons.hourglass_top_rounded;

    final String title = _isNotChecked
        ? "Eligibility Check Required"
        : _isNotEligible
        ? "Not Eligible to Book"
        : _isDeferred
        ? "Temporarily Deferred"
        : "Screening Under Review";

    final String message = _isNotChecked
        ? "Complete the eligibility screening before booking a donation appointment."
        : _isNotEligible
        ? recommendation ??
              "You are currently not eligible to schedule a blood donation."
        : _isDeferred
        ? recommendation ?? "Your eligibility has been temporarily deferred."
        : "Your eligibility screening is still being reviewed. You'll be able to book an appointment once it has been approved.";

    final String badgeLabel = _isNotChecked
        ? "Status: Not Checked"
        : _isNotEligible
        ? "Status: Not Eligible"
        : _isDeferred
        ? "Status: Temporarily Deferred"
        : "Status: Pending Review";

    return Center(
      child: Column(
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
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isDeferred &&
              nextEligibleDate != null &&
              nextEligibleDate!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Next Eligible Date: $nextEligibleDate',
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
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
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isNotEligible
                        ? "Complete the eligibility screening in the Check tab. Once you're eligible, you'll be able to book an appointment."
                        : "Once your screening has been reviewed, this page will update automatically and you'll be able to book an appointment.",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1D4ED8),
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
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 19),
                label: Text(
                  _isNotChecked
                      ? "Take Eligibility Check"
                      : "Take Eligibility Check Again",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
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
          const Text(
            "Pull down to refresh this page after your status changes.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}
