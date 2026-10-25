import 'dart:convert';
import 'dart:typed_data';

import 'package:blood/blood_requests/blood_request_api.dart';
import 'package:blood/blood_requests/hospital_request_api.dart';
import 'package:blood/blood_requests/hospital_request_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Requests to a hospital: the models read every shape the server may send,
/// and the submit request is exactly the server's contract.

Map<String, dynamic> fullOptions() => {
  'status': 'success',
  'can_request': true,
  'request_block': null,
  'active_count': 1,
  'max_active': 3,
  'blood_types': [
    for (final (i, t) in [
      'A+',
      'A-',
      'B+',
      'B-',
      'AB+',
      'AB-',
      'O+',
      'O-',
    ].indexed)
      {'blood_type_id': i + 1, 'blood_type': t},
  ],
  'components': [
    {
      'value': 'whole_blood',
      'label': 'Whole blood',
      'description': 'Red cells, plasma and platelets together.',
    },
    {
      'value': 'packed_red_cells',
      'label': 'Packed red cells',
      'description': 'For anemia and blood loss.',
    },
  ],
  'relationships': [
    {'value': 'self', 'label': 'Myself'},
    {'value': 'parent', 'label': 'Parent'},
  ],
  'urgencies': [
    {'value': 'normal', 'label': 'Normal', 'description': 'Within the week'},
    {'value': 'critical', 'label': 'Critical', 'description': 'Today'},
  ],
  'facilities': [
    {
      'facility_id': 4,
      'name': 'City General Hospital',
      'type': 'hospital',
      'type_label': 'Hospital',
      'address': '12 Rizal St.',
      'barangay': 'Poblacion',
      'city': 'Tagum',
      'province': 'Davao del Norte',
      'contact_number': '0841234567',
      'latitude': 7.44,
      'longitude': 125.8,
    },
  ],
  'defaults': {
    'full_name': 'Rey Ashlee Liwanag',
    'first_name': 'Rey',
    'contact_number': '09171234567',
    'blood_type_id': 7,
    'blood_type': 'O+',
  },
  'limits': {
    'max_units': 6,
    'max_needed_by_days': 14,
    'notes_max_length': 300,
    'document_required': true,
    'document_max_mb': 8,
  },
};

Map<String, dynamic> fullRequest() => {
  'request_id': 31,
  'reference': 'HR-0031',
  'status': 'approved',
  'status_label': 'Approved',
  'blood_type': 'O+',
  'component': 'packed_red_cells',
  'component_label': 'Packed red cells',
  'units_requested': 2,
  'units_approved': 1,
  'urgency': 'critical',
  'urgency_label': 'Critical',
  'needed_by': '2099-11-02',
  'created_at': '2099-10-25 09:00:00',
  'created_ago': '2 hours ago',
  'updated_ago': '5 minutes ago',
  'facility': fullOptions()['facilities'][0],
  'patient_name': 'Maria Santos',
  'relationship': 'parent',
  'relationship_label': 'Parent',
  'contact_number': '09171234567',
  'hospital_reference': 'PT-0042',
  'notes': 'Surgery on Friday',
  'hospital_message': 'Bring the form to the blood bank.',
  'pickup_deadline': '2099-11-03',
  'rejection_reason': null,
  'cancellation_reason': null,
  'document_attached': true,
  'can_cancel': true,
  'needs_attention': false,
};

void main() {
  group('HospitalRequestOptions', () {
    test('reads the full contract', () {
      final o = HospitalRequestOptions.fromJson(fullOptions());
      expect(o.canRequest, isTrue);
      expect(o.requestBlock, isNull);
      expect(o.activeCount, 1);
      expect(o.maxActive, 3);
      expect(o.bloodTypes.map((b) => b.bloodType), [
        'A+',
        'A-',
        'B+',
        'B-',
        'AB+',
        'AB-',
        'O+',
        'O-',
      ]);
      expect(o.bloodTypes.any((b) => b.isUnknown), isFalse);
      expect(o.components.map((c) => c.value), [
        'whole_blood',
        'packed_red_cells',
      ]);
      expect(o.components.first.description, contains('Red cells'));
      expect(o.relationships.first.label, 'Myself');
      expect(o.urgencies.last.value, 'critical');
      final f = o.facilities.single;
      expect(f.facilityId, 4);
      expect(f.locationLine, 'Poblacion, Tagum');
      expect(f.contactNumber, '0841234567');
      expect(f.latitude, 7.44);
      expect(o.defaultFullName, 'Rey Ashlee Liwanag');
      expect(o.defaultFirstName, 'Rey');
      expect(o.defaultContactNumber, '09171234567');
      expect(o.defaultBloodTypeId, 7);
      expect(o.defaultBloodType, 'O+');
      expect(o.maxUnits, 6);
      expect(o.maxNeededByDays, 14);
      expect(o.notesMaxLength, 300);
      expect(o.documentRequired, isTrue);
      expect(o.documentMaxMb, 8);
      expect(o.documentMaxBytes, 8 * 1024 * 1024);
    });

    test('a minimal answer gets safe defaults', () {
      final o = HospitalRequestOptions.fromJson({'status': 'success'});
      expect(o.canRequest, isFalse);
      expect(o.requestBlock, isNull);
      expect(o.maxActive, 3);
      expect(o.bloodTypes, isEmpty);
      expect(o.components, isEmpty);
      expect(o.facilities, isEmpty);
      expect(o.defaultFullName, isNull);
      expect(o.defaultContactNumber, '');
      expect(o.defaultBloodTypeId, isNull);
      expect(o.maxUnits, 4);
      expect(o.maxNeededByDays, 30);
      expect(o.notesMaxLength, 500);
      expect(o.documentRequired, isTrue);
      expect(o.documentMaxMb, 8);
    });

    test('odd values: strings for numbers, junk in lists, a block', () {
      final o = HospitalRequestOptions.fromJson({
        'can_request': '0',
        'request_block': {
          'reason': 'not_verified',
          'message': 'Verify your account first.',
          'action': 'verify',
        },
        'active_count': '2',
        'max_active': 'lots',
        'blood_types': [
          {'blood_type_id': '3', 'blood_type': 'B+'},
          'junk',
          {'blood_type_id': 9},
        ],
        'components': [
          {'label': 'No value'},
          {'value': 'plasma', 'label': 'Plasma'},
        ],
        'facilities': [
          {'facility_id': '8', 'name': 'Clinic', 'latitude': '7.5'},
          {'name': 'No id'},
        ],
        'defaults': {'blood_type_id': '', 'full_name': '  '},
        'limits': {
          'max_units': '0',
          'document_required': '0',
          'document_max_mb': '5',
        },
      });
      expect(o.canRequest, isFalse);
      expect(o.requestBlock!.action, 'verify');
      expect(o.requestBlock!.message, 'Verify your account first.');
      expect(o.activeCount, 2);
      expect(o.maxActive, 3);
      expect(o.bloodTypes.single.bloodTypeId, 3);
      expect(o.components.single.description, '');
      expect(o.facilities.single.facilityId, 8);
      expect(o.facilities.single.latitude, 7.5);
      expect(o.defaultBloodTypeId, isNull);
      expect(o.defaultFullName, isNull);
      expect(o.maxUnits, 1);
      expect(o.documentRequired, isFalse);
      expect(o.documentMaxMb, 5);
    });
  });

  group('StockAvailability', () {
    test('levels, labels and the list by facility', () {
      final map = StockAvailability.listFromJson({
        'availability': [
          {
            'facility_id': 4,
            'level': 'available',
            'label': 'Available',
            'updated_ago': '2 hours ago',
          },
          {'facility_id': '5', 'level': 'LIMITED'},
          {'facility_id': 6, 'level': 'out', 'label': ''},
          {'facility_id': 7, 'level': 'plenty'},
          {'level': 'available'},
          'junk',
        ],
      });
      expect(map.keys, [4, 5, 6, 7]);
      expect(map[4]!.level, StockLevel.available);
      expect(map[4]!.label, 'Available');
      expect(map[4]!.updatedAgo, '2 hours ago');
      expect(map[5]!.level, StockLevel.limited);
      expect(map[5]!.label, 'Limited');
      expect(map[5]!.updatedAgo, isNull);
      expect(map[6]!.label, 'Out of stock');
      expect(map[7]!.level, StockLevel.unknown);
      expect(map[7]!.label, 'Not listed');
      expect(StockAvailability.listFromJson({}), isEmpty);
    });

    test('sorting rank and stock', () {
      final sorted = [...StockLevel.values]
        ..sort((a, b) => a.sortRank.compareTo(b.sortRank));
      expect(sorted, [
        StockLevel.available,
        StockLevel.limited,
        StockLevel.unknown,
        StockLevel.out,
      ]);
      expect(StockLevel.limited.hasStock, isTrue);
      expect(StockLevel.unknown.hasStock, isFalse);
    });
  });

  group('HospitalRequest', () {
    test('reads the full contract', () {
      final r = HospitalRequest.fromJson(fullRequest());
      expect(r.requestId, 31);
      expect(r.reference, 'HR-0031');
      expect(r.status, 'approved');
      expect(r.isActive, isTrue);
      expect(r.componentLabel, 'Packed red cells');
      expect(r.unitsRequested, 2);
      expect(r.unitsApproved, 1);
      expect(r.facility!.name, 'City General Hospital');
      expect(r.relationshipLabel, 'Parent');
      expect(r.hospitalReference, 'PT-0042');
      expect(r.hospitalMessage, contains('blood bank'));
      expect(r.pickupDeadline, '2099-11-03');
      expect(r.rejectionReason, isNull);
      expect(r.documentAttached, isTrue);
      expect(r.canCancel, isTrue);
      expect(r.needsAttention, isFalse);
    });

    test('a minimal or odd request', () {
      final r = HospitalRequest.fromJson({
        'request_id': '9',
        'status': 'expired',
        'units_approved': null,
        'units_requested': 'two',
        'facility': 'nowhere',
        'notes': '',
        'can_cancel': 1,
      });
      expect(r.requestId, 9);
      expect(r.reference, '');
      expect(r.isActive, isFalse);
      expect(r.unitsRequested, 1);
      expect(r.unitsApproved, isNull);
      expect(r.facility, isNull);
      expect(r.notes, isNull);
      expect(r.canCancel, isTrue);
      expect(HospitalRequest.fromJson({}).status, 'pending_review');
    });

    test('submit, list, detail and summary results', () {
      final submitted = HospitalRequestSubmitResult.fromJson({
        'status': 'success',
        'code': 'REQUEST_SUBMITTED',
        'message': 'Sent',
        'duplicate': true,
        'request': fullRequest(),
      });
      expect(submitted.duplicate, isTrue);
      expect(submitted.request.reference, 'HR-0031');

      final list = HospitalRequestListResult.fromJson({
        'requests': [fullRequest(), 'junk'],
        'counts': {'active': '1', 'past': 0},
      });
      expect(list.requests.single.requestId, 31);
      expect(list.counts, {'active': 1, 'past': 0});
      expect(HospitalRequestListResult.fromJson({}).requests, isEmpty);

      final detail = HospitalRequestDetailResult.fromJson({
        'request': fullRequest(),
        'timeline': [
          {'key': 'submitted', 'label': 'Submitted', 'done': true},
        ],
        'availability': {'facility_id': 4, 'level': 'limited'},
      });
      expect(detail.timeline.single.done, isTrue);
      expect(detail.availability!.level, StockLevel.limited);
      expect(HospitalRequestDetailResult.fromJson({}).availability, isNull);

      final summary = HospitalRequestSummary.fromJson({
        'can_request': true,
        'active_count': 1,
        'latest_request': fullRequest(),
      });
      expect(summary.canRequest, isTrue);
      expect(summary.latestRequest!.reference, 'HR-0031');
      expect(HospitalRequestSummary.fromJson({}).latestRequest, isNull);
    });
  });

  test('FormPhoto knows the types the server takes', () {
    FormPhoto photo(String name) =>
        FormPhoto(bytes: Uint8List(3), filename: name);
    expect(photo('a.JPEG').extension, 'jpg');
    expect(photo('a.jpg').extension, 'jpg');
    expect(photo('form.png').extension, 'png');
    expect(photo('form.webp').extension, 'webp');
    expect(photo('form.heic').extension, isNull);
    expect(photo('form').extension, isNull);
    expect(photo('a.jpg').sizeBytes, 3);
  });

  group('buildSubmitRequest', () {
    test('the fields and the file are exactly the contract', () async {
      final bytes = Uint8List.fromList(List.generate(64, (i) => i));
      final request = buildSubmitRequest(
        donorId: '7',
        submissionKey: 'key-1',
        facilityId: 4,
        bloodTypeId: 7,
        bloodComponent: 'packed_red_cells',
        unitsRequested: 2,
        urgency: 'critical',
        neededBy: DateTime(2099, 3, 4),
        patientName: '  Maria Santos ',
        relationship: 'parent',
        contactNumber: '09171234567',
        hospitalReference: 'PT-0042',
        notes: 'Surgery on Friday',
        document: FormPhoto(bytes: bytes, filename: 'form.jpg'),
      );
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/submit_hospital_blood_request.php'));
      expect(request.fields, {
        'donor_id': '7',
        'submission_key': 'key-1',
        'facility_id': '4',
        'blood_type_id': '7',
        'blood_component': 'packed_red_cells',
        'units_requested': '2',
        'urgency': 'critical',
        'needed_by': '2099-03-04',
        'patient_name': 'Maria Santos',
        'relationship': 'parent',
        'contact_number': '09171234567',
        'hospital_reference': 'PT-0042',
        'notes': 'Surgery on Friday',
      });
      final file = request.files.single;
      expect(file.field, 'document');
      expect(file.filename, 'form.jpg');
      expect(file.length, 64);
      expect(await file.finalize().expand((b) => b).toList(), bytes);
    });

    test('blank optional fields and no photo are left out', () {
      final request = buildSubmitRequest(
        donorId: '7',
        submissionKey: 'key-1',
        facilityId: 4,
        bloodTypeId: 7,
        bloodComponent: 'whole_blood',
        unitsRequested: 1,
        urgency: 'normal',
        neededBy: DateTime(2099, 12, 31),
        patientName: 'Maria',
        relationship: 'self',
        contactNumber: '09171234567',
        hospitalReference: '   ',
        notes: '',
      );
      expect(request.fields.containsKey('hospital_reference'), isFalse);
      expect(request.fields.containsKey('notes'), isFalse);
      expect(request.fields['needed_by'], '2099-12-31');
      expect(request.files, isEmpty);
    });
  });

  group('HospitalRequestApi', () {
    Future<T> withServer<T>(
      Future<http.Response> Function(http.Request) handler,
      Future<T> Function() body,
    ) => http.runWithClient(body, () => MockClient(handler));

    http.Response json(Map<String, dynamic> body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    test('submit sends the multipart body and reads the request', () async {
      late http.Request seen;
      final result = await withServer(
        (r) async {
          seen = r;
          return json({
            'status': 'success',
            'code': 'REQUEST_SUBMITTED',
            'message': 'Sent',
            'duplicate': false,
            'request': fullRequest(),
          });
        },
        () {
          return HospitalRequestApi.submit(
            buildSubmitRequest(
              donorId: '7',
              submissionKey: 'k',
              facilityId: 4,
              bloodTypeId: 7,
              bloodComponent: 'whole_blood',
              unitsRequested: 1,
              urgency: 'normal',
              neededBy: DateTime(2099, 1, 2),
              patientName: 'Maria',
              relationship: 'self',
              contactNumber: '09171234567',
              document: FormPhoto(
                bytes: Uint8List.fromList([1, 2, 3]),
                filename: 'form.png',
              ),
            ),
          );
        },
      );
      expect(result.request.reference, 'HR-0031');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="submission_key"'));
      expect(body, contains('name="document"; filename="form.png"'));
    });

    test('errors come back as BloodRequestApiException', () async {
      await withServer(
        (r) async => json({
          'status': 'error',
          'code': 'VALIDATION_FAILED',
          'message': 'Check the form.',
          'errors': {'patient_name': 'Too short.'},
        }),
        () async {
          await expectLater(
            HospitalRequestApi.fetchOptions('7'),
            throwsA(
              isA<BloodRequestApiException>()
                  .having((e) => e.code, 'code', 'VALIDATION_FAILED')
                  .having((e) => e.errors, 'errors', {
                    'patient_name': 'Too short.',
                  }),
            ),
          );
        },
      );
      // Not JSON at all: the same exception, with a fallback code.
      await withServer(
        (r) async => http.Response('<html>oops</html>', 500),
        () async {
          await expectLater(
            HospitalRequestApi.fetchAvailability(7),
            throwsA(
              isA<BloodRequestApiException>().having(
                (e) => e.code,
                'code',
                'UNKNOWN_ERROR',
              ),
            ),
          );
        },
      );
    });

    test('availability asks for the blood type', () async {
      late Uri seen;
      final map = await withServer((r) async {
        seen = r.url;
        return json({
          'status': 'success',
          'availability': [
            {'facility_id': 4, 'level': 'out'},
          ],
        });
      }, () => HospitalRequestApi.fetchAvailability(3));
      expect(seen.path, endsWith('/get_blood_availability.php'));
      expect(seen.queryParameters, {'blood_type_id': '3'});
      expect(map[4]!.level, StockLevel.out);
    });
  });
}
