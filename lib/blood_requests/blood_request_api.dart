// Thin HTTP client for the Blood Requests feature. Every method throws
// BloodRequestApiException on a server-reported error (status != success),
// carrying the same code/message/errors the backend sent so screens can map
// them to friendly UI without re-parsing raw JSON everywhere.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'blood_request_models.dart';

class BloodRequestApiException implements Exception {
  final String code;
  final String message;
  final Map<String, String>? errors;
  final Map<String, dynamic> raw;

  BloodRequestApiException(
    this.code,
    this.message, {
    this.errors,
    this.raw = const {},
  });

  @override
  String toString() => message;
}

class BloodRequestApi {
  static const _getTimeout = Duration(seconds: 10);
  static const _postTimeout = Duration(seconds: 15);

  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{};
    }
    if (body['status'] == 'success') return body;

    final code = body['code']?.toString() ?? 'UNKNOWN_ERROR';
    final message =
        body['message']?.toString() ?? 'Something went wrong. Please try again.';
    Map<String, String>? errors;
    if (body['errors'] is Map) {
      errors = (body['errors'] as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }
    throw BloodRequestApiException(code, message, errors: errors, raw: body);
  }

  static Future<BloodRequestSummary> fetchSummary(String donorId) async {
    final response = await http
        .get(
          Uri.parse(
            '${AppConfig.baseUrl}/get_blood_request_summary.php?donor_id=$donorId',
          ),
        )
        .timeout(_getTimeout);
    return BloodRequestSummary.fromJson(_decode(response));
  }

  static Future<BloodRequestListResult> fetchRequests({
    required String donorId,
    required String scope,
    String filter = 'all',
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/get_blood_requests.php',
    ).replace(
      queryParameters: {
        'donor_id': donorId,
        'scope': scope,
        'filter': filter,
      },
    );
    final response = await http.get(uri).timeout(_getTimeout);
    return BloodRequestListResult.fromJson(_decode(response));
  }

  static Future<BloodRequestDetailResult> fetchDetail({
    required String donorId,
    required int requestId,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/get_blood_request_detail.php',
    ).replace(
      queryParameters: {
        'donor_id': donorId,
        'request_id': requestId.toString(),
      },
    );
    final response = await http.get(uri).timeout(_getTimeout);
    return BloodRequestDetailResult.fromJson(_decode(response));
  }

  static Future<RequestFormOptions> fetchOptions(String donorId) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/get_blood_request_options.php?donor_id=$donorId',
    );
    final response = await http.get(uri).timeout(_getTimeout);
    return RequestFormOptions.fromJson(_decode(response));
  }

  static Future<BloodRequestActionResult> submitRequest(
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/submit_blood_request.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_postTimeout);
    return BloodRequestActionResult.fromJson(_decode(response));
  }

  static Future<BloodRequestActionResult> respond({
    required String donorId,
    required int requestId,
    required String action,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/respond_blood_request.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'donor_id': donorId,
            'request_id': requestId,
            'action': action,
          }),
        )
        .timeout(_postTimeout);
    return BloodRequestActionResult.fromJson(_decode(response));
  }

  static Future<BloodRequestActionResult> cancel({
    required String donorId,
    required int requestId,
    required String reason,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/cancel_blood_request.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'donor_id': donorId,
            'request_id': requestId,
            'reason': reason,
          }),
        )
        .timeout(_postTimeout);
    return BloodRequestActionResult.fromJson(_decode(response));
  }
}
