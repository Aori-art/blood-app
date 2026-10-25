// HTTP client for blood requests sent to a hospital. Like BloodRequestApi,
// every method throws BloodRequestApiException on a server-reported error,
// with the server's code, message and field errors (the same decoding).
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'blood_request_api.dart';
import 'hospital_request_models.dart';

/// The endpoints. (The summary's name follows the pattern of the others.)
class HospitalRequestEndpoints {
  static const options = 'get_hospital_request_options.php';
  static const availability = 'get_blood_availability.php';
  static const submit = 'submit_hospital_blood_request.php';
  static const list = 'get_hospital_requests.php';
  static const detail = 'get_hospital_request_detail.php';
  static const cancel = 'cancel_hospital_request.php';
  static const summary = 'get_hospital_request_summary.php';
}

Uri _uri(String endpoint, [Map<String, String>? query]) =>
    Uri.parse('${AppConfig.baseUrl}/$endpoint').replace(queryParameters: query);

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The multipart request for submit_hospital_blood_request.php, built without
/// sending it (so tests can read its fields and files). Optional fields that
/// are blank are left out; the form photo goes in the "document" file field.
http.MultipartRequest buildSubmitRequest({
  required String donorId,
  required String submissionKey,
  required int facilityId,
  required int bloodTypeId,
  required String bloodComponent,
  required int unitsRequested,
  required String urgency,
  required DateTime neededBy,
  required String patientName,
  required String relationship,
  required String contactNumber,
  String? hospitalReference,
  String? notes,
  FormPhoto? document,
}) {
  final request = http.MultipartRequest(
    'POST',
    _uri(HospitalRequestEndpoints.submit),
  );
  final reference = hospitalReference?.trim() ?? '';
  final note = notes?.trim() ?? '';
  request.fields.addAll({
    'donor_id': donorId,
    'submission_key': submissionKey,
    'facility_id': '$facilityId',
    'blood_type_id': '$bloodTypeId',
    'blood_component': bloodComponent,
    'units_requested': '$unitsRequested',
    'urgency': urgency,
    'needed_by': _isoDate(neededBy),
    'patient_name': patientName.trim(),
    'relationship': relationship,
    'contact_number': contactNumber.trim(),
    if (reference.isNotEmpty) 'hospital_reference': reference,
    if (note.isNotEmpty) 'notes': note,
  });
  if (document != null) {
    // Like the app's other uploads, the type is told by the file name.
    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        document.bytes,
        filename: document.filename,
      ),
    );
  }
  return request;
}

class HospitalRequestApi {
  static const _getTimeout = Duration(seconds: 10);
  static const _postTimeout = Duration(seconds: 15);

  /// A photo can take a while on a slow connection.
  static const _submitTimeout = Duration(seconds: 40);

  static Future<HospitalRequestOptions> fetchOptions(String donorId) async {
    final response = await http
        .get(_uri(HospitalRequestEndpoints.options, {'donor_id': donorId}))
        .timeout(_getTimeout);
    return HospitalRequestOptions.fromJson(
      decodeBloodRequestResponse(response),
    );
  }

  /// Each facility's stock of [bloodTypeId], by facility id.
  static Future<Map<int, StockAvailability>> fetchAvailability(
    int bloodTypeId,
  ) async {
    final response = await http
        .get(
          _uri(HospitalRequestEndpoints.availability, {
            'blood_type_id': '$bloodTypeId',
          }),
        )
        .timeout(_getTimeout);
    return StockAvailability.listFromJson(decodeBloodRequestResponse(response));
  }

  /// Sends a request built by [buildSubmitRequest].
  static Future<HospitalRequestSubmitResult> submit(
    http.MultipartRequest request,
  ) async {
    final streamed = await request.send().timeout(_submitTimeout);
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(_submitTimeout);
    return HospitalRequestSubmitResult.fromJson(
      decodeBloodRequestResponse(response),
    );
  }

  /// The donor's requests: [scope] is active, history or all.
  static Future<HospitalRequestListResult> fetchList({
    required String donorId,
    String scope = 'all',
  }) async {
    final response = await http
        .get(
          _uri(HospitalRequestEndpoints.list, {
            'donor_id': donorId,
            'scope': scope,
          }),
        )
        .timeout(_getTimeout);
    return HospitalRequestListResult.fromJson(
      decodeBloodRequestResponse(response),
    );
  }

  static Future<HospitalRequestDetailResult> fetchDetail({
    required String donorId,
    required int requestId,
  }) async {
    final response = await http
        .get(
          _uri(HospitalRequestEndpoints.detail, {
            'donor_id': donorId,
            'request_id': '$requestId',
          }),
        )
        .timeout(_getTimeout);
    return HospitalRequestDetailResult.fromJson(
      decodeBloodRequestResponse(response),
    );
  }

  /// Cancels a request ([reason]: 3 to 300 characters); returns it as it is
  /// now (null if the server sent none back). Errors: NOT_FOUND,
  /// NOT_CANCELLABLE, INVALID_INPUT.
  static Future<HospitalRequest?> cancel({
    required String donorId,
    required int requestId,
    required String reason,
  }) async {
    final response = await http
        .post(
          _uri(HospitalRequestEndpoints.cancel),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'donor_id': donorId,
            'request_id': requestId,
            'reason': reason,
          }),
        )
        .timeout(_postTimeout);
    final body = decodeBloodRequestResponse(response);
    final request = body['request'];
    return request is Map
        ? HospitalRequest.fromJson(Map<String, dynamic>.from(request))
        : null;
  }

  static Future<HospitalRequestSummary> fetchSummary(String donorId) async {
    final response = await http
        .get(_uri(HospitalRequestEndpoints.summary, {'donor_id': donorId}))
        .timeout(_getTimeout);
    return HospitalRequestSummary.fromJson(
      decodeBloodRequestResponse(response),
    );
  }
}
