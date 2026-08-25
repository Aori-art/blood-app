import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'shared_design.dart';

class DigitalIdScreen extends StatefulWidget {
  const DigitalIdScreen({super.key});

  @override
  State<DigitalIdScreen> createState() => _DigitalIdScreenState();
}

class _DigitalIdScreenState extends State<DigitalIdScreen> {
  Map<String, dynamic>? _donor;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDigitalId();
  }

  Future<void> _loadDigitalId() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final donorId = prefs.getString('donorId')?.trim();
    if (donorId == null || donorId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Unable to load Digital Donor ID.\nPlease sign in again.';
      });
      return;
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.baseUrl}/get_digital_id.php',
      ).replace(queryParameters: {'donor_id': donorId});
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (!mounted) return;

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }

      if (response.statusCode == 200 &&
          decoded is Map &&
          decoded['status'] == 'success' &&
          decoded['data'] is Map) {
        setState(() {
          _donor = Map<String, dynamic>.from(decoded['data'] as Map);
          _loading = false;
        });
        return;
      }

      final message = decoded is Map ? _safeText(decoded['message']) : '';
      setState(() {
        _loading = false;
        _error = message.isEmpty
            ? 'Unable to load your Digital Donor ID.\nPlease try again.'
            : message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Unable to load your Digital Donor ID.\n'
            'Check your internet connection and try again.';
      });
    }
  }

  String _safeText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? '' : text;
  }

  String _value(String key) =>
      _safeText(_donor?[key]).isEmpty ? 'N/A' : _safeText(_donor?[key]);

  String _donorCode() {
    final code = _safeText(_donor?['donor_code']);
    if (code.isNotEmpty) return code;
    final id = _safeText(_donor?['donor_id']);
    return id.isEmpty ? 'N/A' : 'D$id';
  }

  String _formattedDate(String key) {
    final raw = _safeText(_donor?[key]);
    final date = DateTime.tryParse(raw);
    if (date == null) return 'N/A';
    const months = [
      '',
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
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9FAFB),
    body: SafeArea(
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: RefreshIndicator(
              color: kCrimson,
              onRefresh: _loadDigitalId,
              child: _body(),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: kHeaderGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        HeaderIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Digital Donor ID',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Your official eDonate donor information',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kCrimson));
    }
    if (_error != null) return _errorView();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Column(
        children: [
          _digitalIdCard(),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This digital ID contains your current donor information '
                    'from eDonate. Pull down to refresh your donor information.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 80),
      const Icon(Icons.badge_outlined, size: 64, color: Color(0xFF9CA3AF)),
      const SizedBox(height: 18),
      const Text(
        'Digital Donor ID unavailable',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF111827),
          fontWeight: FontWeight.bold,
          fontSize: 19,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 14,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 22),
      Center(
        child: ElevatedButton.icon(
          onPressed: _loadDigitalId,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: kCrimson,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _digitalIdCard() => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .10),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 54),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: kHeaderGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'eDonate',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'DIGITAL DONOR ID',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.volunteer_activism_rounded,
                color: Colors.white,
                size: 31,
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -34),
          child: Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFECACA), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                color: kCrimson,
                size: 35,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            children: [
              Text(
                _value('full_name').toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Donor ID: ${_donorCode()}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  border: Border.all(color: const Color(0xFFFECACA)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'BLOOD TYPE',
                      style: TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _value('blood_type'),
                      style: const TextStyle(
                        color: kCrimson,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _detail(
                Icons.person_outline_rounded,
                'Name',
                _value('full_name'),
              ),
              _detail(
                Icons.bloodtype_rounded,
                'Blood Type',
                _value('blood_type'),
                color: kCrimson,
              ),
              _detail(Icons.badge_outlined, 'Donor ID', _donorCode()),
              _detail(Icons.location_on_outlined, 'Address', _value('address')),
              _detail(
                Icons.phone_outlined,
                'Contact Number',
                _value('contact_number'),
              ),
              _detail(
                Icons.history_rounded,
                'Last Donation Date',
                _formattedDate('last_donation_date'),
              ),
              _detail(
                Icons.event_available_rounded,
                'Next Eligible Donation Date',
                _formattedDate('next_eligible_date'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _detail(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (color ?? const Color(0xFF6B7280)).withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color ?? kTextMuted),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: color ?? const Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
