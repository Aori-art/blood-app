// Loading and describing a donor's donation history, shared by the History
// tab and the donations preview on Home.
//
// get_donation_history.php?donor_id=ID answers
// {status: "success", data: [{donation_id, donation_date, blood_type,
// blood_units, donation_status, facility_name, ...}]}, newest first.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_palette.dart';
import 'config.dart';

class DonationHistoryApi {
  DonationHistoryApi._();

  /// The donor's donations as the server sent them. Throws when the
  /// request fails or the server does not say "success".
  static Future<List<Map<String, dynamic>>> fetch(String donorId) async {
    final response = await http.get(
      Uri.parse(
        '${AppConfig.baseUrl}/get_donation_history.php?donor_id=$donorId',
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Donation history failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['status'] != 'success') {
      throw Exception('Donation history failed');
    }
    final list = data['data'];
    if (list is! List) return [];
    return [
      for (final item in list)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
}

/// "Oct 1, 2026" from "2026-10-01"; the text itself when it is not a date.
String formatDonationDate(String date) {
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (e) {
    return date;
  }
}

/// The words for a donation_status.
String donationStatusLabel(String? raw) {
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

/// The text and background colors of a status chip.
({Color text, Color bg}) donationStatusChipColors(AppPalette p, String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'completed':
      return (text: p.successDark, bg: p.successBg);
    case 'pending':
      return (text: p.warningText, bg: p.warningBg);
    case 'deferred':
      // The brand red reads on the pale red background; criticalText does
      // not at this size.
      return (text: p.primaryText, bg: p.accentBg);
    default:
      return (text: p.muted, bg: p.surfaceAlt);
  }
}
