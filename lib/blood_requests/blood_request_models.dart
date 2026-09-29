// Data models for the Blood Requests feature. Every model mirrors the exact
// JSON shape returned by the PHP backend (see get_blood_request_*.php) —
// fields are read defensively (defaulted/nullable) since the server is the
// source of truth and the app must never crash on an unexpected shape.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<String> _stringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

bool _boolish(dynamic v) => v == true || v?.toString() == '1';

int _int(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

double _double(dynamic v, [double fallback = 0]) =>
    (v as num?)?.toDouble() ?? fallback;

class BloodRequestFacility {
  final int facilityId;
  final String name;
  final String type;
  final String typeLabel;
  final String? address;
  final String? barangay;
  final String? city;
  final String? province;
  final String? contactNumber;
  final double? latitude;
  final double? longitude;

  BloodRequestFacility({
    required this.facilityId,
    required this.name,
    required this.type,
    required this.typeLabel,
    this.address,
    this.barangay,
    this.city,
    this.province,
    this.contactNumber,
    this.latitude,
    this.longitude,
  });

  String get locationLine =>
      [barangay, city].where((e) => e != null && e.isNotEmpty).join(', ');

  factory BloodRequestFacility.fromJson(Map<String, dynamic> json) =>
      BloodRequestFacility(
        facilityId: _int(json['facility_id']),
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        typeLabel: json['type_label']?.toString() ?? '',
        address: json['address']?.toString(),
        barangay: json['barangay']?.toString(),
        city: json['city']?.toString(),
        province: json['province']?.toString(),
        contactNumber: json['contact_number']?.toString(),
        latitude: json['latitude'] == null ? null : _double(json['latitude']),
        longitude:
            json['longitude'] == null ? null : _double(json['longitude']),
      );
}

class MyResponse {
  final String status;
  final bool isCommitted;
  final bool canWithdraw;
  final String? respondedAt;

  MyResponse({
    required this.status,
    required this.isCommitted,
    required this.canWithdraw,
    this.respondedAt,
  });

  factory MyResponse.fromJson(Map<String, dynamic> json) => MyResponse(
    status: json['status']?.toString() ?? '',
    isCommitted: _boolish(json['is_committed']),
    canWithdraw: _boolish(json['can_withdraw']),
    respondedAt: json['responded_at']?.toString(),
  );
}

class BloodRequestPrivate {
  final String? patientName;
  final String? relationship;
  final String? relationshipLabel;
  final String? contactNumber;
  final String? hospitalReference;
  final String? rejectionReason;
  final String? cancellationReason;
  final String? fulfillmentNote;

  BloodRequestPrivate({
    this.patientName,
    this.relationship,
    this.relationshipLabel,
    this.contactNumber,
    this.hospitalReference,
    this.rejectionReason,
    this.cancellationReason,
    this.fulfillmentNote,
  });

  factory BloodRequestPrivate.fromJson(Map<String, dynamic> json) =>
      BloodRequestPrivate(
        patientName: json['patient_name']?.toString(),
        relationship: json['relationship']?.toString(),
        relationshipLabel: json['relationship_label']?.toString(),
        contactNumber: json['contact_number']?.toString(),
        hospitalReference: json['hospital_reference']?.toString(),
        rejectionReason: json['rejection_reason']?.toString(),
        cancellationReason: json['cancellation_reason']?.toString(),
        fulfillmentNote: json['fulfillment_note']?.toString(),
      );
}

class BloodRequest {
  final int requestId;
  final String reference;
  final String? bloodType;
  final List<String> compatibleDonorTypes;
  final String urgency;
  final String urgencyLabel;
  final String status;
  final String statusLabel;
  final int requiredDonors;
  final bool specificMatchRequired;
  final bool allowOtherBloodTypes;
  final String requirementText;
  final int volunteersCount;
  final int remainingCount;
  final double progress;
  final bool isFull;
  final String? notes;
  final String? neededBy;
  final String? expiresAt;
  final String? timeLeftLabel;
  final String? createdAt;
  final String? createdAgo;
  final String source;
  final bool isMine;
  final BloodRequestFacility? facility;
  final String? myMatchType;
  final MyResponse? myResponse;
  final bool canHelp;
  final BloodRequestPrivate? private;

  BloodRequest({
    required this.requestId,
    required this.reference,
    this.bloodType,
    required this.compatibleDonorTypes,
    required this.urgency,
    required this.urgencyLabel,
    required this.status,
    required this.statusLabel,
    required this.requiredDonors,
    required this.specificMatchRequired,
    required this.allowOtherBloodTypes,
    required this.requirementText,
    required this.volunteersCount,
    required this.remainingCount,
    required this.progress,
    required this.isFull,
    this.notes,
    this.neededBy,
    this.expiresAt,
    this.timeLeftLabel,
    this.createdAt,
    this.createdAgo,
    required this.source,
    required this.isMine,
    this.facility,
    this.myMatchType,
    this.myResponse,
    required this.canHelp,
    this.private,
  });

  factory BloodRequest.fromJson(Map<String, dynamic> json) => BloodRequest(
    requestId: _int(json['request_id']),
    reference: json['reference']?.toString() ?? '',
    bloodType: json['blood_type']?.toString(),
    compatibleDonorTypes: _stringList(json['compatible_donor_types']),
    urgency: json['urgency']?.toString() ?? 'normal',
    urgencyLabel: json['urgency_label']?.toString() ?? '',
    status: json['status']?.toString() ?? 'open',
    statusLabel: json['status_label']?.toString() ?? '',
    requiredDonors: _int(json['required_donors'], 1),
    specificMatchRequired: _boolish(json['specific_match_required']),
    allowOtherBloodTypes: _boolish(json['allow_other_blood_types']),
    requirementText: json['requirement_text']?.toString() ?? '',
    volunteersCount: _int(json['volunteers_count']),
    remainingCount: _int(json['remaining_count']),
    progress: _double(json['progress']),
    isFull: _boolish(json['is_full']),
    notes: json['notes']?.toString(),
    neededBy: json['needed_by']?.toString(),
    expiresAt: json['expires_at']?.toString(),
    timeLeftLabel: json['time_left_label']?.toString(),
    createdAt: json['created_at']?.toString(),
    createdAgo: json['created_ago']?.toString(),
    source: json['source']?.toString() ?? 'app',
    isMine: _boolish(json['is_mine']),
    facility: json['facility'] is Map
        ? BloodRequestFacility.fromJson(_map(json['facility']))
        : null,
    myMatchType: json['my_match_type']?.toString(),
    myResponse: json['my_response'] is Map
        ? MyResponse.fromJson(_map(json['my_response']))
        : null,
    canHelp: _boolish(json['can_help']),
    private: json['private'] is Map
        ? BloodRequestPrivate.fromJson(_map(json['private']))
        : null,
  );
}

class VolunteerBlock {
  final String reason;
  final String message;
  final String? action;

  VolunteerBlock({required this.reason, required this.message, this.action});

  factory VolunteerBlock.fromJson(Map<String, dynamic> json) =>
      VolunteerBlock(
        reason: json['reason']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        action: json['action']?.toString(),
      );
}

class ActiveCommitment {
  final int requestId;
  final String reference;

  ActiveCommitment({required this.requestId, required this.reference});

  factory ActiveCommitment.fromJson(Map<String, dynamic> json) =>
      ActiveCommitment(
        requestId: _int(json['request_id']),
        reference: json['reference']?.toString() ?? '',
      );
}

class ViewerContext {
  final String? bloodType;
  final bool bloodTypeConfirmed;
  final List<String> canDonateTo;
  final bool canVolunteer;
  final VolunteerBlock? volunteerBlock;
  final ActiveCommitment? activeCommitment;

  ViewerContext({
    this.bloodType,
    required this.bloodTypeConfirmed,
    required this.canDonateTo,
    required this.canVolunteer,
    this.volunteerBlock,
    this.activeCommitment,
  });

  factory ViewerContext.fromJson(Map<String, dynamic> json) => ViewerContext(
    bloodType: json['blood_type']?.toString(),
    bloodTypeConfirmed: _boolish(json['blood_type_confirmed']),
    canDonateTo: _stringList(json['can_donate_to']),
    canVolunteer: _boolish(json['can_volunteer']),
    volunteerBlock: json['volunteer_block'] is Map
        ? VolunteerBlock.fromJson(_map(json['volunteer_block']))
        : null,
    activeCommitment: json['active_commitment'] is Map
        ? ActiveCommitment.fromJson(_map(json['active_commitment']))
        : null,
  );
}

class TopUrgentRequest {
  final int requestId;
  final String reference;
  final String? bloodType;
  final String urgency;
  final String? facilityName;
  final String? timeLeftLabel;

  TopUrgentRequest({
    required this.requestId,
    required this.reference,
    this.bloodType,
    required this.urgency,
    this.facilityName,
    this.timeLeftLabel,
  });

  factory TopUrgentRequest.fromJson(Map<String, dynamic> json) =>
      TopUrgentRequest(
        requestId: _int(json['request_id']),
        reference: json['reference']?.toString() ?? '',
        bloodType: json['blood_type']?.toString(),
        urgency: json['urgency']?.toString() ?? 'normal',
        facilityName: json['facility_name']?.toString(),
        timeLeftLabel: json['time_left_label']?.toString(),
      );
}

class BloodRequestSummary {
  final bool canRequest;
  final VolunteerBlock? requestBlock;
  final int openCount;
  final int matchingCount;
  final int urgentMatchingCount;
  final TopUrgentRequest? topUrgent;
  final BloodRequest? myActiveRequest;
  final int myActiveCount;
  final BloodRequest? myCommitment;
  final ViewerContext? viewer;

  BloodRequestSummary({
    required this.canRequest,
    this.requestBlock,
    required this.openCount,
    required this.matchingCount,
    required this.urgentMatchingCount,
    this.topUrgent,
    this.myActiveRequest,
    required this.myActiveCount,
    this.myCommitment,
    this.viewer,
  });

  factory BloodRequestSummary.fromJson(Map<String, dynamic> json) =>
      BloodRequestSummary(
        canRequest: _boolish(json['can_request']),
        requestBlock: json['request_block'] is Map
            ? VolunteerBlock.fromJson(_map(json['request_block']))
            : null,
        openCount: _int(json['open_count']),
        matchingCount: _int(json['matching_count']),
        urgentMatchingCount: _int(json['urgent_matching_count']),
        topUrgent: json['top_urgent'] is Map
            ? TopUrgentRequest.fromJson(_map(json['top_urgent']))
            : null,
        myActiveRequest: json['my_active_request'] is Map
            ? BloodRequest.fromJson(_map(json['my_active_request']))
            : null,
        myActiveCount: _int(json['my_active_count']),
        myCommitment: json['my_commitment'] is Map
            ? BloodRequest.fromJson(_map(json['my_commitment']))
            : null,
        viewer: json['viewer'] is Map
            ? ViewerContext.fromJson(_map(json['viewer']))
            : null,
      );
}

class BloodTypeOption {
  final int bloodTypeId;
  final String bloodType;

  BloodTypeOption({required this.bloodTypeId, required this.bloodType});

  factory BloodTypeOption.fromJson(Map<String, dynamic> json) =>
      BloodTypeOption(
        bloodTypeId: _int(json['blood_type_id']),
        bloodType: json['blood_type']?.toString() ?? '',
      );
}

class RelationshipOption {
  final String value;
  final String label;

  RelationshipOption({required this.value, required this.label});

  factory RelationshipOption.fromJson(Map<String, dynamic> json) =>
      RelationshipOption(
        value: json['value']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
      );
}

class UrgencyOption {
  final String value;
  final String label;
  final String description;

  UrgencyOption({
    required this.value,
    required this.label,
    required this.description,
  });

  factory UrgencyOption.fromJson(Map<String, dynamic> json) => UrgencyOption(
    value: json['value']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
  );
}

class RequestFormOptions {
  final bool canRequest;
  final VolunteerBlock? requestBlock;
  final int activeCount;
  final int maxActive;
  final List<BloodTypeOption> bloodTypes;
  final List<BloodRequestFacility> facilities;
  final List<RelationshipOption> relationships;
  final List<UrgencyOption> urgencies;
  final String defaultContactNumber;
  final String defaultFirstName;
  final int maxDonors;
  final int maxNeededByDays;
  final int notesMaxLength;
  final bool autoApprove;

  RequestFormOptions({
    required this.canRequest,
    this.requestBlock,
    required this.activeCount,
    required this.maxActive,
    required this.bloodTypes,
    required this.facilities,
    required this.relationships,
    required this.urgencies,
    required this.defaultContactNumber,
    required this.defaultFirstName,
    required this.maxDonors,
    required this.maxNeededByDays,
    required this.notesMaxLength,
    required this.autoApprove,
  });

  factory RequestFormOptions.fromJson(Map<String, dynamic> json) {
    final defaults = _map(json['defaults']);
    final limits = _map(json['limits']);
    return RequestFormOptions(
      canRequest: _boolish(json['can_request']),
      requestBlock: json['request_block'] is Map
          ? VolunteerBlock.fromJson(_map(json['request_block']))
          : null,
      activeCount: _int(json['active_count']),
      maxActive: _int(json['max_active'], 3),
      bloodTypes: (json['blood_types'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BloodTypeOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      facilities: (json['facilities'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => BloodRequestFacility.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      relationships: (json['relationships'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => RelationshipOption.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      urgencies: (json['urgencies'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => UrgencyOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      defaultContactNumber: defaults['contact_number']?.toString() ?? '',
      defaultFirstName: defaults['first_name']?.toString() ?? '',
      maxDonors: _int(limits['max_donors'], 10),
      maxNeededByDays: _int(limits['max_needed_by_days'], 30),
      notesMaxLength: _int(limits['notes_max_length'], 500),
      autoApprove: _boolish(json['auto_approve']),
    );
  }
}

class RequestCounts {
  final int all;
  final int match;
  final int urgent;

  const RequestCounts({
    required this.all,
    required this.match,
    required this.urgent,
  });

  factory RequestCounts.fromJson(Map<String, dynamic> json) => RequestCounts(
    all: _int(json['all']),
    match: _int(json['match']),
    urgent: _int(json['urgent']),
  );
}

class BloodRequestListResult {
  final String scope;
  final String filter;
  final ViewerContext? viewer;
  final RequestCounts counts;
  final List<BloodRequest> requests;

  BloodRequestListResult({
    required this.scope,
    required this.filter,
    this.viewer,
    required this.counts,
    required this.requests,
  });

  factory BloodRequestListResult.fromJson(Map<String, dynamic> json) =>
      BloodRequestListResult(
        scope: json['scope']?.toString() ?? '',
        filter: json['filter']?.toString() ?? 'all',
        viewer: json['viewer'] is Map
            ? ViewerContext.fromJson(_map(json['viewer']))
            : null,
        counts: json['counts'] is Map
            ? RequestCounts.fromJson(_map(json['counts']))
            : const RequestCounts(all: 0, match: 0, urgent: 0),
        requests: (json['requests'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => BloodRequest.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TimelineEvent {
  final String key;
  final String label;
  final String? at;
  final bool done;

  TimelineEvent({
    required this.key,
    required this.label,
    this.at,
    required this.done,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
    key: json['key']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    at: json['at']?.toString(),
    done: _boolish(json['done']),
  );
}

class RequestVolunteer {
  final String name;
  final String? bloodType;
  final String? matchType;
  final String status;
  final String? respondedAt;

  RequestVolunteer({
    required this.name,
    this.bloodType,
    this.matchType,
    required this.status,
    this.respondedAt,
  });

  factory RequestVolunteer.fromJson(Map<String, dynamic> json) =>
      RequestVolunteer(
        name: json['name']?.toString() ?? '',
        bloodType: json['blood_type']?.toString(),
        matchType: json['match_type']?.toString(),
        status: json['status']?.toString() ?? '',
        respondedAt: json['responded_at']?.toString(),
      );
}

class BloodRequestDetailResult {
  final BloodRequest request;
  final ViewerContext? viewer;
  final List<TimelineEvent> timeline;
  final List<RequestVolunteer> volunteers;

  BloodRequestDetailResult({
    required this.request,
    this.viewer,
    required this.timeline,
    required this.volunteers,
  });

  factory BloodRequestDetailResult.fromJson(Map<String, dynamic> json) =>
      BloodRequestDetailResult(
        request: BloodRequest.fromJson(
          json['request'] is Map ? _map(json['request']) : json,
        ),
        viewer: json['viewer'] is Map
            ? ViewerContext.fromJson(_map(json['viewer']))
            : null,
        timeline: (json['timeline'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => TimelineEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        volunteers: (json['volunteers'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => RequestVolunteer.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList(),
      );
}

class BloodRequestActionResult {
  final BloodRequest request;
  final ViewerContext? viewer;
  final String message;
  final bool duplicate;

  BloodRequestActionResult({
    required this.request,
    this.viewer,
    required this.message,
    this.duplicate = false,
  });

  factory BloodRequestActionResult.fromJson(Map<String, dynamic> json) =>
      BloodRequestActionResult(
        request: BloodRequest.fromJson(
          json['request'] is Map ? _map(json['request']) : json,
        ),
        viewer: json['viewer'] is Map
            ? ViewerContext.fromJson(_map(json['viewer']))
            : null,
        message: json['message']?.toString() ?? '',
        duplicate: _boolish(json['duplicate']),
      );
}
