import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'check.dart';
import 'config.dart';

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  DateTime? selectedDate;
  String? selectedCenter;
  String? selectedTime;

  // ── Eligibility ───────────────────────────────────────────────
  String? _eligibilityStatus; // 'approved' | 'pending' | 'declined' | null
  bool _checkingEligibility = true;

  final List<String> centers = ["Lipa City Hall"];

  final List<String> timeSlots = [
    "8:00 AM - 9:00 AM",
    "9:00 AM - 10:00 AM",
    "10:00 AM - 11:00 AM",
    "1:00 PM - 2:00 PM",
    "2:00 PM - 3:00 PM",
  ];

  @override
  void initState() {
    super.initState();
    _fetchEligibilityStatus();
  }

  // ── Fetch eligibility status from backend ─────────────────────
  Future<void> _fetchEligibilityStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');

      if (donorId == null || donorId.isEmpty) {
        setState(() {
          _eligibilityStatus = 'pending';
          _checkingEligibility = false;
        });
        return;
      }

      final url = Uri.parse(
          "${AppConfig.baseUrl}/get_eligibility_status.php?donor_id=$donorId");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _eligibilityStatus = data['status'] ?? 'pending';
          _checkingEligibility = false;
        });
      } else {
        setState(() {
          _eligibilityStatus = 'pending';
          _checkingEligibility = false;
        });
      }
    } catch (_) {
      setState(() {
        _eligibilityStatus = 'pending';
        _checkingEligibility = false;
      });
    }
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

  Future<void> _submitBooking() async {
    if (selectedDate == null || selectedCenter == null || selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text("Please fill in all fields"),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final donorId = prefs.getString('donorId');

    if (donorId == null || donorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Unable to find your account. Please sign in again.")),
      );
      return;
    }

    final formattedDate =
        "${selectedDate!.year.toString().padLeft(4, '0')}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";
    final url =
        Uri.parse("${AppConfig.baseUrl}/book_appointment.php");

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "donor_id": int.tryParse(donorId) ?? donorId,
          "appointment_date": formattedDate,
          "appointment_time": selectedTime,
          "donation_center": selectedCenter,
        }),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Server error: ${response.statusCode}")),
        );
        return;
      }

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (data["success"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text("Appointment booked successfully!"),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        setState(() {
          selectedDate = null;
          selectedCenter = null;
          selectedTime = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(data["message"] ?? "Unknown error")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection error: $e")),
      );
    }
  }

  String _formatDate(DateTime date) {
    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    return "$weekday, $month ${date.day}, ${date.year}";
  }

  String _formatDateShort(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  bool get _allSelected =>
      selectedDate != null &&
      selectedCenter != null &&
      selectedTime != null;

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          // ── Main booking UI ──────────────────────────────────
          Column(
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
                child: const Column(
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
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // DATE SELECTION CARD
                      _sectionCard(
                        icon: Icons.calendar_today,
                        title: "Select Date",
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              border: Border.all(
                                  color: const Color(0xFFD1D5DB)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                    Icons.calendar_month_outlined,
                                    color: Color(0xFF9CA3AF),
                                    size: 18),
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
                                const Icon(Icons.expand_more,
                                    color: Color(0xFF9CA3AF),
                                    size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // DONATION CENTER CARD
                      _sectionCard(
                        icon: Icons.location_on,
                        title: "Choose Donation Center",
                        child: Column(
                          children: [
                            _styledDropdown<String>(
                              value: selectedCenter,
                              hint: "Select a center",
                              items: centers,
                              onChanged: (val) =>
                                  setState(() => selectedCenter = val),
                            ),
                            if (selectedCenter != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: const Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text("Address",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280))),
                                    SizedBox(height: 2),
                                    Text(
                                        "123 Health Street, Medical District",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13)),
                                    SizedBox(height: 4),
                                    Text("Open: Mon-Sat, 8 AM - 6 PM",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF2563EB))),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // TIME SLOT CARD
                      _sectionCard(
                        icon: Icons.access_time,
                        title: "Choose Time Slot",
                        child: _styledDropdown<String>(
                          value: selectedTime,
                          hint: "Select a time",
                          items: timeSlots,
                          onChanged: (val) =>
                              setState(() => selectedTime = val),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // BOOKING SUMMARY
                      if (_allSelected)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFF0FDF4),
                                Color(0xFFDCFCE7)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                                color: const Color(0xFFBBF7D0),
                                width: 2),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Color(0xFF16A34A),
                                      size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "Booking Summary",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _summaryRow("Date",
                                  _formatDateShort(selectedDate!)),
                              const SizedBox(height: 6),
                              _summaryRow("Time", selectedTime!),
                              const SizedBox(height: 6),
                              _summaryRow("Center", selectedCenter!),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // CONFIRM BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed:
                              _allSelected ? _submitBooking : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFDC2626),
                            disabledBackgroundColor:
                                const Color(0xFFF87171),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                "Confirm Booking",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        "You'll receive a confirmation message with all the details once your booking is confirmed.",
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Eligibility gate overlay ─────────────────────────
          if (_checkingEligibility)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xFFF9FAFB),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            )
          else if (_eligibilityStatus == 'pending' ||
              _eligibilityStatus == 'declined')
            Positioned.fill(
              child: _EligibilityGate(
                status: _eligibilityStatus!,
                onGoToCheck: () {
                  // Navigate to CheckScreen — adjust to your router
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CheckScreen(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────
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
        border:
            Border.all(color: const Color(0xFFE5E7EB), width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: const Color(0xFFDC2626), size: 20),
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
        hint: Text(hint,
            style: const TextStyle(
                color: Color(0xFF9CA3AF), fontSize: 14)),
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more,
            color: Color(0xFF9CA3AF)),
        style: const TextStyle(
            color: Color(0xFF111827), fontSize: 14),
        items: items
            .map((e) => DropdownMenuItem<T>(
                value: e, child: Text(e.toString())))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827)),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Eligibility Gate Widget
// ═══════════════════════════════════════════════════════════════
class _EligibilityGate extends StatelessWidget {
  final String status;
  final VoidCallback onGoToCheck;

  const _EligibilityGate({
    required this.status,
    required this.onGoToCheck,
  });

  bool get _isPending => status == 'pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.97),
      child: SafeArea(
        child: SingleChildScrollView(                          // ← fix
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Icon badge ──────────────────────────────
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPending
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFFFF1F1),
                      border: Border.all(
                        color: _isPending
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFFECACA),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isPending
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFDC2626))
                              .withOpacity(0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPending
                          ? Icons.hourglass_top_rounded
                          : Icons.block_rounded,
                      size: 46,
                      color: _isPending
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFDC2626),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Title ───────────────────────────────────
                  Text(
                    _isPending
                        ? "Eligibility Pending"
                        : "Not Eligible to Book",
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 10),

                  // ── Subtitle ────────────────────────────────
                  Text(
                    _isPending
                        ? "Your eligibility screening hasn't been completed or is still under review. Complete the check before booking."
                        : "You are currently not eligible based on your screening results. Complete a new eligibility check to update your status.",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // ── Status chip ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: _isPending
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: _isPending
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFFECACA),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPending
                              ? Icons.schedule_rounded
                              : Icons.cancel_rounded,
                          size: 15,
                          color: _isPending
                              ? const Color(0xFFD97706)
                              : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _isPending
                              ? "Status: Pending Review"
                              : "Status: Declined",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isPending
                                ? const Color(0xFFD97706)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Info box ────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Color(0xFF2563EB), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Complete the eligibility screening in the Check tab. Once approved, you'll be able to book an appointment.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D4ED8),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── CTA button ──────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: onGoToCheck,
                      icon: const Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 19),
                      label: const Text(
                        "Go to Eligibility Check",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
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

                  const SizedBox(height: 10),

                  const Text(
                    "Your eligibility status is checked every time you open this page.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}