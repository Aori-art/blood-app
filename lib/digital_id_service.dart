// Shared data + persistence for the Digital Donor ID feature — fetches
// get_digital_id.php and keeps the per-device "masked" preference used by
// both the Home card and the Digital ID screen so they always agree.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s.toLowerCase() == 'null' ? null : s;
}

class DigitalIdCard {
  final String code;
  final String codeMasked;
  final String status;
  final String? issuedOn;
  final String? firstDonationDate;
  final String? qrPayload;

  DigitalIdCard({
    required this.code,
    required this.codeMasked,
    required this.status,
    this.issuedOn,
    this.firstDonationDate,
    this.qrPayload,
  });

  bool get isActive => status == 'active';

  factory DigitalIdCard.fromJson(Map<String, dynamic> json) => DigitalIdCard(
    code: _str(json['code']) ?? '',
    codeMasked: _str(json['code_masked']) ?? '',
    status: _str(json['status']) ?? 'active',
    issuedOn: _str(json['issued_on']),
    firstDonationDate: _str(json['first_donation_date']),
    qrPayload: _str(json['qr_payload']),
  );
}

class DigitalIdAddress {
  final String? street;
  final String? barangay;
  final String? city;
  final String? province;

  DigitalIdAddress({this.street, this.barangay, this.city, this.province});

  factory DigitalIdAddress.fromJson(Map<String, dynamic> json) => DigitalIdAddress(
    street: _str(json['street']),
    barangay: _str(json['barangay']),
    city: _str(json['city']),
    province: _str(json['province']),
  );
}

class DigitalIdDonor {
  final int donorId;
  final String fullName;
  final String? firstName;
  final String? lastName;
  final String? gender;
  final String? birthdate;
  final int? age;
  final String? contactNumber;
  final String? photoUrl;
  final String? photoPath;
  final String? bloodType;
  final bool bloodTypeVerified;
  final String? bloodTypeStatus;
  final bool isVerified;
  final bool isActive;
  final String? memberSince;
  final DigitalIdAddress? address;
  final String? addressLine;

  DigitalIdDonor({
    required this.donorId,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.gender,
    this.birthdate,
    this.age,
    this.contactNumber,
    this.photoUrl,
    this.photoPath,
    this.bloodType,
    required this.bloodTypeVerified,
    this.bloodTypeStatus,
    required this.isVerified,
    required this.isActive,
    this.memberSince,
    this.address,
    this.addressLine,
  });

  factory DigitalIdDonor.fromJson(Map<String, dynamic> json) => DigitalIdDonor(
    donorId: (json['donor_id'] as num?)?.toInt() ?? 0,
    fullName: _str(json['full_name']) ?? 'N/A',
    firstName: _str(json['first_name']),
    lastName: _str(json['last_name']),
    gender: _str(json['gender']),
    birthdate: _str(json['birthdate']),
    age: (json['age'] as num?)?.toInt(),
    contactNumber: _str(json['contact_number']),
    photoUrl: _str(json['photo_url']),
    photoPath: _str(json['photo_path']),
    bloodType: _str(json['blood_type']),
    bloodTypeVerified: json['blood_type_verified'] == true,
    bloodTypeStatus: _str(json['blood_type_status']),
    isVerified: json['is_verified'] == true,
    isActive: json['is_active'] == true,
    memberSince: _str(json['member_since']),
    address: json['address'] is Map
        ? DigitalIdAddress.fromJson(Map<String, dynamic>.from(json['address']))
        : null,
    addressLine: _str(json['address_line']),
  );
}

class DigitalIdMasked {
  final String? code;
  final String? contactNumber;
  final String? birthdate;
  final String? addressLine;

  DigitalIdMasked({this.code, this.contactNumber, this.birthdate, this.addressLine});

  factory DigitalIdMasked.fromJson(Map<String, dynamic> json) => DigitalIdMasked(
    code: _str(json['code']),
    contactNumber: _str(json['contact_number']),
    birthdate: _str(json['birthdate']),
    addressLine: _str(json['address_line']),
  );
}

class DigitalIdDonations {
  final int total;
  final int totalUnits;
  final int livesHelped;
  final String? firstDonationDate;
  final String? lastDonationDate;

  DigitalIdDonations({
    required this.total,
    required this.totalUnits,
    required this.livesHelped,
    this.firstDonationDate,
    this.lastDonationDate,
  });

  factory DigitalIdDonations.fromJson(Map<String, dynamic> json) => DigitalIdDonations(
    total: (json['total'] as num?)?.toInt() ?? 0,
    totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
    livesHelped: (json['lives_helped'] as num?)?.toInt() ?? 0,
    firstDonationDate: _str(json['first_donation_date']),
    lastDonationDate: _str(json['last_donation_date']),
  );
}

class DigitalIdEligibility {
  final String? status;
  final String? label;
  final String? nextEligibleDate;

  DigitalIdEligibility({this.status, this.label, this.nextEligibleDate});

  factory DigitalIdEligibility.fromJson(Map<String, dynamic> json) => DigitalIdEligibility(
    status: _str(json['status']),
    label: _str(json['label']),
    nextEligibleDate: _str(json['next_eligible_date']),
  );
}

class DigitalIdData {
  final DigitalIdCard card;
  final DigitalIdDonor donor;
  final DigitalIdMasked masked;
  final DigitalIdDonations donations;
  final DigitalIdEligibility? eligibility;

  DigitalIdData({
    required this.card,
    required this.donor,
    required this.masked,
    required this.donations,
    this.eligibility,
  });

  factory DigitalIdData.fromJson(Map<String, dynamic> json) => DigitalIdData(
    card: DigitalIdCard.fromJson(Map<String, dynamic>.from(json['digital_id'] ?? {})),
    donor: DigitalIdDonor.fromJson(Map<String, dynamic>.from(json['donor'] ?? {})),
    masked: DigitalIdMasked.fromJson(Map<String, dynamic>.from(json['masked'] ?? {})),
    donations: DigitalIdDonations.fromJson(Map<String, dynamic>.from(json['donations'] ?? {})),
    eligibility: json['eligibility'] is Map
        ? DigitalIdEligibility.fromJson(Map<String, dynamic>.from(json['eligibility']))
        : null,
  );
}

class DigitalIdServiceException implements Exception {
  final String message;
  DigitalIdServiceException(this.message);
  @override
  String toString() => message;
}

class DigitalIdService {
  static const _maskKeyPrefix = 'digital_id_masked_';

  /// Returns null when the donor hasn't unlocked their Digital ID yet.
  /// Throws [DigitalIdServiceException] on a network or server error.
  static Future<DigitalIdData?> fetch(String donorId) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.baseUrl}/get_digital_id.php',
      ).replace(queryParameters: {'donor_id': donorId});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }

      if (response.statusCode != 200 || decoded is! Map || decoded['status'] != 'success') {
        final message = decoded is Map ? _str(decoded['message']) : null;
        throw DigitalIdServiceException(message ?? 'Unable to load your Digital Donor ID.');
      }

      if (decoded['unlocked'] != true) return null;
      return DigitalIdData.fromJson(Map<String, dynamic>.from(decoded));
    } on DigitalIdServiceException {
      rethrow;
    } catch (_) {
      throw DigitalIdServiceException(
        'Unable to load your Digital Donor ID. Check your internet connection and try again.',
      );
    }
  }

  static Future<bool> isMasked(String donorId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_maskKeyPrefix$donorId') ?? false;
  }

  static Future<void> setMasked(String donorId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_maskKeyPrefix$donorId', value);
  }
}
