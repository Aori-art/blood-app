// Data models for blood requests sent to a HOSPITAL (a facility), as opposed
// to the donor appeals in blood_request_models.dart. Every model mirrors the
// JSON the PHP backend returns (get_hospital_request_options.php,
// get_blood_availability.php, submit_hospital_blood_request.php, ...) and
// reads each field defensively (defaulted or nullable): the server is the
// source of truth and the app must never crash on an unexpected shape.
import 'dart:typed_data';

import 'blood_request_models.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

bool _boolish(dynamic v) =>
    v == true || v?.toString() == '1' || v?.toString() == 'true';

/// Numbers may come as numbers or as strings ("3") from PHP.
int? _intOrNull(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v)?.toInt();
  return null;
}

int _int(dynamic v, [int fallback = 0]) => _intOrNull(v) ?? fallback;

String _str(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

/// Null for a missing or blank value.
String? _strOrNull(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

// ─── Options ────────────────────────────────────────────────────────────────

/// A blood component the hospital can give (whole blood, packed red cells,
/// platelets, plasma).
class ComponentOption {
  final String value;
  final String label;
  final String description;

  ComponentOption({
    required this.value,
    required this.label,
    required this.description,
  });

  factory ComponentOption.fromJson(Map<String, dynamic> json) =>
      ComponentOption(
        value: _str(json['value']),
        label: _str(json['label']),
        description: _str(json['description']),
      );
}

class HospitalRequestOptions {
  final bool canRequest;
  final VolunteerBlock? requestBlock;
  final int activeCount;
  final int maxActive;
  final List<BloodTypeOption> bloodTypes;
  final List<ComponentOption> components;
  final List<RelationshipOption> relationships;
  final List<UrgencyOption> urgencies;
  final List<BloodRequestFacility> facilities;

  // defaults
  final String? defaultFullName;
  final String defaultFirstName;
  final String defaultContactNumber;
  final int? defaultBloodTypeId;
  final String? defaultBloodType;

  // limits
  final int maxUnits;
  final int maxNeededByDays;
  final int notesMaxLength;
  final bool documentRequired;
  final int documentMaxMb;

  HospitalRequestOptions({
    required this.canRequest,
    this.requestBlock,
    required this.activeCount,
    required this.maxActive,
    required this.bloodTypes,
    required this.components,
    required this.relationships,
    required this.urgencies,
    required this.facilities,
    this.defaultFullName,
    required this.defaultFirstName,
    required this.defaultContactNumber,
    this.defaultBloodTypeId,
    this.defaultBloodType,
    required this.maxUnits,
    required this.maxNeededByDays,
    required this.notesMaxLength,
    required this.documentRequired,
    required this.documentMaxMb,
  });

  /// The largest form photo the server takes, in bytes.
  int get documentMaxBytes => documentMaxMb * 1024 * 1024;

  factory HospitalRequestOptions.fromJson(Map<String, dynamic> json) {
    final defaults = _map(json['defaults']);
    final limits = _map(json['limits']);
    return HospitalRequestOptions(
      canRequest: _boolish(json['can_request']),
      requestBlock: json['request_block'] is Map
          ? VolunteerBlock.fromJson(_map(json['request_block']))
          : null,
      activeCount: _int(json['active_count']),
      maxActive: _int(json['max_active'], 3),
      bloodTypes: _maps(json['blood_types'])
          .map(
            (e) => BloodTypeOption(
              bloodTypeId: _int(e['blood_type_id']),
              bloodType: _str(e['blood_type']),
              isUnknown: _boolish(e['is_unknown']),
            ),
          )
          .where((b) => b.bloodType.isNotEmpty)
          .toList(),
      components: _maps(
        json['components'],
      ).map(ComponentOption.fromJson).where((c) => c.value.isNotEmpty).toList(),
      relationships: _maps(json['relationships'])
          .map(
            (e) => RelationshipOption(
              value: _str(e['value']),
              label: _str(e['label']),
            ),
          )
          .where((r) => r.value.isNotEmpty)
          .toList(),
      urgencies: _maps(json['urgencies'])
          .map(
            (e) => UrgencyOption(
              value: _str(e['value']),
              label: _str(e['label']),
              description: _str(e['description']),
            ),
          )
          .where((u) => u.value.isNotEmpty)
          .toList(),
      facilities: _maps(
        json['facilities'],
      ).map(_facility).where((f) => f.facilityId > 0).toList(),
      defaultFullName: _strOrNull(defaults['full_name']),
      defaultFirstName: _str(defaults['first_name']),
      defaultContactNumber: _str(defaults['contact_number']),
      defaultBloodTypeId: _intOrNull(defaults['blood_type_id']),
      defaultBloodType: _strOrNull(defaults['blood_type']),
      maxUnits: _int(limits['max_units'], 4).clamp(1, 99),
      maxNeededByDays: _int(limits['max_needed_by_days'], 30).clamp(0, 365),
      notesMaxLength: _int(limits['notes_max_length'], 500).clamp(1, 5000),
      // A hospital wants its form: required unless the server says not.
      documentRequired: limits.containsKey('document_required')
          ? _boolish(limits['document_required'])
          : true,
      documentMaxMb: _int(limits['document_max_mb'], 8).clamp(1, 100),
    );
  }
}

/// A facility read with string-tolerant numbers (the old model expects them
/// as JSON numbers).
BloodRequestFacility _facility(Map<String, dynamic> json) {
  double? coord(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  return BloodRequestFacility(
    facilityId: _int(json['facility_id']),
    name: _str(json['name']),
    type: _str(json['type']),
    typeLabel: _str(json['type_label']),
    address: _strOrNull(json['address']),
    barangay: _strOrNull(json['barangay']),
    city: _strOrNull(json['city']),
    province: _strOrNull(json['province']),
    contactNumber: _strOrNull(json['contact_number']),
    latitude: coord(json['latitude']),
    longitude: coord(json['longitude']),
  );
}

// ─── Availability ───────────────────────────────────────────────────────────

/// How much of a blood type a hospital has: a level only, never a count.
enum StockLevel {
  available,
  limited,
  out,
  unknown;

  static StockLevel parse(dynamic v) {
    switch (v?.toString().trim().toLowerCase()) {
      case 'available':
        return StockLevel.available;
      case 'limited':
        return StockLevel.limited;
      case 'out':
        return StockLevel.out;
      default:
        return StockLevel.unknown;
    }
  }

  /// What to call it when the server sends no label.
  String get defaultLabel => switch (this) {
    StockLevel.available => 'In stock',
    StockLevel.limited => 'Limited',
    StockLevel.out => 'Out of stock',
    StockLevel.unknown => 'Not listed',
  };

  /// Order in the hospital list: stock first, "out" last.
  int get sortRank => switch (this) {
    StockLevel.available => 0,
    StockLevel.limited => 1,
    StockLevel.unknown => 2,
    StockLevel.out => 3,
  };

  bool get hasStock =>
      this == StockLevel.available || this == StockLevel.limited;
}

class StockAvailability {
  final int facilityId;
  final StockLevel level;
  final String label;

  /// "2 hours ago", or null when the hospital never said.
  final String? updatedAgo;

  StockAvailability({
    required this.facilityId,
    required this.level,
    required this.label,
    this.updatedAgo,
  });

  /// For a hospital the server did not list.
  factory StockAvailability.unknown(int facilityId) => StockAvailability(
    facilityId: facilityId,
    level: StockLevel.unknown,
    label: StockLevel.unknown.defaultLabel,
  );

  factory StockAvailability.fromJson(Map<String, dynamic> json) {
    final level = StockLevel.parse(json['level']);
    return StockAvailability(
      facilityId: _int(json['facility_id']),
      level: level,
      label: _strOrNull(json['label']) ?? level.defaultLabel,
      updatedAgo: _strOrNull(json['updated_ago']),
    );
  }

  /// The "availability" list of get_blood_availability.php, by facility.
  static Map<int, StockAvailability> listFromJson(Map<String, dynamic> json) {
    final result = <int, StockAvailability>{};
    for (final e in _maps(json['availability'])) {
      final a = StockAvailability.fromJson(e);
      if (a.facilityId > 0) result[a.facilityId] = a;
    }
    return result;
  }
}

// ─── Requests ───────────────────────────────────────────────────────────────

class HospitalRequest {
  final int requestId;
  final String reference;

  /// pending_review | approved | ready | fulfilled | rejected | cancelled |
  /// expired
  final String status;
  final String statusLabel;
  final String bloodType;
  final String component;
  final String componentLabel;
  final int unitsRequested;
  final int? unitsApproved;
  final String urgency;
  final String urgencyLabel;
  final String? neededBy;
  final String? createdAt;
  final String? createdAgo;
  final String? updatedAgo;
  final BloodRequestFacility? facility;
  final String patientName;
  final String relationship;
  final String relationshipLabel;
  final String contactNumber;
  final String? hospitalReference;
  final String? notes;
  final String? hospitalMessage;
  final String? pickupDeadline;
  final String? rejectionReason;
  final String? cancellationReason;
  final bool documentAttached;
  final bool canCancel;
  final bool needsAttention;

  HospitalRequest({
    required this.requestId,
    required this.reference,
    required this.status,
    required this.statusLabel,
    required this.bloodType,
    required this.component,
    required this.componentLabel,
    required this.unitsRequested,
    this.unitsApproved,
    required this.urgency,
    required this.urgencyLabel,
    this.neededBy,
    this.createdAt,
    this.createdAgo,
    this.updatedAgo,
    this.facility,
    required this.patientName,
    required this.relationship,
    required this.relationshipLabel,
    required this.contactNumber,
    this.hospitalReference,
    this.notes,
    this.hospitalMessage,
    this.pickupDeadline,
    this.rejectionReason,
    this.cancellationReason,
    required this.documentAttached,
    required this.canCancel,
    required this.needsAttention,
  });

  /// Still waiting on the hospital or on the donor's pick-up.
  bool get isActive =>
      status == 'pending_review' || status == 'approved' || status == 'ready';

  factory HospitalRequest.fromJson(Map<String, dynamic> json) =>
      HospitalRequest(
        requestId: _int(json['request_id']),
        reference: _str(json['reference']),
        status: _str(json['status'], 'pending_review'),
        statusLabel: _str(json['status_label']),
        bloodType: _str(json['blood_type']),
        component: _str(json['component']),
        componentLabel: _str(json['component_label']),
        unitsRequested: _int(json['units_requested'], 1),
        unitsApproved: _intOrNull(json['units_approved']),
        urgency: _str(json['urgency'], 'normal'),
        urgencyLabel: _str(json['urgency_label']),
        neededBy: _strOrNull(json['needed_by']),
        createdAt: _strOrNull(json['created_at']),
        createdAgo: _strOrNull(json['created_ago']),
        updatedAgo: _strOrNull(json['updated_ago']),
        facility: json['facility'] is Map
            ? _facility(_map(json['facility']))
            : null,
        patientName: _str(json['patient_name']),
        relationship: _str(json['relationship']),
        relationshipLabel: _str(json['relationship_label']),
        contactNumber: _str(json['contact_number']),
        hospitalReference: _strOrNull(json['hospital_reference']),
        notes: _strOrNull(json['notes']),
        hospitalMessage: _strOrNull(json['hospital_message']),
        pickupDeadline: _strOrNull(json['pickup_deadline']),
        rejectionReason: _strOrNull(json['rejection_reason']),
        cancellationReason: _strOrNull(json['cancellation_reason']),
        documentAttached: _boolish(json['document_attached']),
        canCancel: _boolish(json['can_cancel']),
        needsAttention: _boolish(json['needs_attention']),
      );
}

/// What submit_hospital_blood_request.php answers on success.
class HospitalRequestSubmitResult {
  final String code;
  final String message;

  /// True when the server had this submission_key already (a retry).
  final bool duplicate;
  final HospitalRequest request;

  HospitalRequestSubmitResult({
    required this.code,
    required this.message,
    required this.duplicate,
    required this.request,
  });

  factory HospitalRequestSubmitResult.fromJson(Map<String, dynamic> json) =>
      HospitalRequestSubmitResult(
        code: _str(json['code'], 'REQUEST_SUBMITTED'),
        message: _str(json['message']),
        duplicate: _boolish(json['duplicate']),
        request: HospitalRequest.fromJson(_map(json['request'])),
      );
}

/// The most recent request in get_hospital_request_summary.php.
class HospitalLatestRequest {
  final int requestId;
  final String reference;
  final String status;
  final String statusLabel;
  final String bloodType;
  final int unitsRequested;
  final String facilityName;
  final String? updatedAgo;
  final bool needsAttention;

  HospitalLatestRequest({
    required this.requestId,
    required this.reference,
    required this.status,
    required this.statusLabel,
    required this.bloodType,
    required this.unitsRequested,
    required this.facilityName,
    this.updatedAgo,
    required this.needsAttention,
  });

  /// Still waiting on the hospital or on the donor's pick-up.
  bool get isActive =>
      status == 'pending_review' || status == 'approved' || status == 'ready';

  factory HospitalLatestRequest.fromJson(Map<String, dynamic> json) =>
      HospitalLatestRequest(
        requestId: _int(json['request_id']),
        reference: _str(json['reference']),
        status: _str(json['status'], 'pending_review'),
        statusLabel: _str(json['status_label']),
        bloodType: _str(json['blood_type']),
        unitsRequested: _int(json['units_requested'], 1),
        facilityName: _str(json['facility_name']),
        updatedAgo: _strOrNull(json['updated_ago']),
        needsAttention: _boolish(json['needs_attention']),
      );
}

class HospitalRequestSummary {
  final int activeCount;
  final int readyCount;

  /// The latest request, or null when the donor has none.
  final HospitalLatestRequest? latest;

  HospitalRequestSummary({
    required this.activeCount,
    required this.readyCount,
    this.latest,
  });

  factory HospitalRequestSummary.fromJson(Map<String, dynamic> json) =>
      HospitalRequestSummary(
        activeCount: _int(json['active_count']),
        readyCount: _int(json['ready_count']),
        latest: json['latest'] is Map
            ? HospitalLatestRequest.fromJson(_map(json['latest']))
            : null,
      );
}

class HospitalRequestListResult {
  final List<HospitalRequest> requests;

  /// Per-filter counts (e.g. active, past), when the server sends them.
  final Map<String, int> counts;

  HospitalRequestListResult({required this.requests, required this.counts});

  factory HospitalRequestListResult.fromJson(Map<String, dynamic> json) =>
      HospitalRequestListResult(
        requests: _maps(
          json['requests'] ?? json['data'],
        ).map(HospitalRequest.fromJson).toList(),
        counts: _map(json['counts']).map((k, v) => MapEntry(k, _int(v))),
      );
}

class HospitalRequestDetailResult {
  final HospitalRequest request;
  final List<TimelineEvent> timeline;

  /// The chosen hospital's current stock of the requested type.
  final StockAvailability? availability;

  HospitalRequestDetailResult({
    required this.request,
    required this.timeline,
    this.availability,
  });

  factory HospitalRequestDetailResult.fromJson(Map<String, dynamic> json) =>
      HospitalRequestDetailResult(
        request: HospitalRequest.fromJson(_map(json['request'])),
        timeline: _maps(json['timeline']).map(TimelineEvent.fromJson).toList(),
        availability: json['availability'] is Map
            ? StockAvailability.fromJson(_map(json['availability']))
            : null,
      );
}

// ─── The form photo ─────────────────────────────────────────────────────────

/// A photo of the hospital's blood request form, ready to upload.
class FormPhoto {
  final Uint8List bytes;
  final String filename;

  FormPhoto({required this.bytes, required this.filename});

  int get sizeBytes => bytes.length;

  /// "jpg", "png" or "webp" (the types the server takes), else null.
  String? get extension {
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = filename.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'jpg';
    return const {'jpg', 'png', 'webp'}.contains(ext) ? ext : null;
  }
}
