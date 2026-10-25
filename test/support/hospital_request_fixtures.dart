// What the hospital request form is tested with: the server's options and
// stock answers, a fake photo picker, and helpers that fill the form.
import 'dart:convert';
import 'dart:typed_data';

import 'package:blood/blood_requests/hospital_request_models.dart';
import 'package:blood/blood_requests/hospital_request_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real 1 x 1 PNG, so thumbnails decode.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQ'
  'GAhKmMIQAAAABJRU5ErkJggg==',
);

const kBloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// O+ is the donor's own type (id 7).
const kOPositive = 7;

Map<String, dynamic> hospitalFacility(
  int id,
  String name, {
  String type = 'hospital',
  String city = 'Tagum',
  String barangay = 'Poblacion',
  String? number = '0841234567',
}) => {
  'facility_id': id,
  'name': name,
  'type': type,
  'type_label': type == 'hospital' ? 'Hospital' : 'Blood bank',
  'address': '12 Rizal St.',
  'barangay': barangay,
  'city': city,
  'province': 'Davao del Norte',
  'contact_number': number,
  'latitude': 7.44,
  'longitude': 125.8,
};

Map<String, dynamic> hospitalOptions({
  bool canRequest = true,
  Map<String, dynamic>? block,
  bool documentRequired = true,
  int documentMaxMb = 8,
  int maxUnits = 6,
}) => {
  'status': 'success',
  'can_request': canRequest,
  'request_block': block,
  'active_count': 0,
  'max_active': 3,
  'blood_types': [
    for (final (i, t) in kBloodTypes.indexed)
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
    {
      'value': 'platelets',
      'label': 'Platelets',
      'description': 'For dengue and bleeding.',
    },
    {
      'value': 'plasma',
      'label': 'Plasma',
      'description': 'For burns and clotting problems.',
    },
  ],
  'relationships': [
    {'value': 'self', 'label': 'Myself'},
    {'value': 'parent', 'label': 'Parent'},
    {'value': 'child', 'label': 'Child'},
    {'value': 'friend', 'label': 'Friend'},
  ],
  'urgencies': [
    {'value': 'normal', 'label': 'Normal', 'description': 'Within the week'},
    {'value': 'high', 'label': 'High', 'description': 'In 2 to 3 days'},
    {'value': 'critical', 'label': 'Critical', 'description': 'Today'},
  ],
  // Alphabetical order differs from the stock order on purpose.
  'facilities': [
    hospitalFacility(1, 'Alpha Medical Center'),
    hospitalFacility(2, 'Bravo General Hospital', city: 'Panabo'),
    hospitalFacility(3, 'Charlie Blood Bank', type: 'blood_bank'),
    hospitalFacility(4, 'Delta Hospital', number: null),
  ],
  'defaults': {
    'full_name': 'Rey Ashlee Liwanag',
    'first_name': 'Rey',
    'contact_number': '09171234567',
    'blood_type_id': kOPositive,
    'blood_type': 'O+',
  },
  'limits': {
    'max_units': maxUnits,
    'max_needed_by_days': 14,
    'notes_max_length': 300,
    'document_required': documentRequired,
    'document_max_mb': documentMaxMb,
  },
};

/// Alpha is out, Bravo limited, Charlie available, Delta not listed.
Map<String, dynamic> hospitalAvailability() => {
  'status': 'success',
  'availability': [
    {'facility_id': 1, 'level': 'out', 'label': 'Out of stock'},
    {
      'facility_id': 2,
      'level': 'limited',
      'label': 'Limited',
      'updated_ago': '3 hours ago',
    },
    {
      'facility_id': 3,
      'level': 'available',
      'label': 'In stock',
      'updated_ago': '2 hours ago',
    },
  ],
};

Map<String, dynamic> hospitalRequestJson({String facilityName = 'Alpha'}) => {
  'request_id': 31,
  'reference': 'HR-0031',
  'status': 'pending_review',
  'status_label': 'Waiting for the hospital',
  'blood_type': 'O+',
  'component': 'whole_blood',
  'component_label': 'Whole blood',
  'units_requested': 1,
  'urgency': 'normal',
  'urgency_label': 'Normal',
  'needed_by': '2099-11-02',
  'facility': hospitalFacility(3, facilityName),
  'patient_name': 'Rey Ashlee Liwanag',
  'relationship': 'self',
  'relationship_label': 'Myself',
  'contact_number': '09171234567',
  'document_attached': true,
  'can_cancel': true,
  'needs_attention': false,
};

/// Hands out [next] (or throws [error]) and remembers what was asked.
class FakeFormPhotoPicker extends FormPhotoPicker {
  FakeFormPhotoPicker();

  FormPhoto? next;
  Object? error;
  final sources = <FormPhotoSource>[];

  static FormPhoto photo({int size = 0, String name = 'form.png'}) =>
      FormPhoto(bytes: size == 0 ? tinyPng : Uint8List(size), filename: name);

  @override
  Future<FormPhoto?> pick(FormPhotoSource source) async {
    sources.add(source);
    if (error != null) throw error!;
    return next ?? photo();
  }
}

/// A picker that always gives a small photo (for the audits).
class AlwaysPhotoPicker extends FormPhotoPicker {
  const AlwaysPhotoPicker();

  @override
  Future<FormPhoto?> pick(FormPhotoSource source) async =>
      FakeFormPhotoPicker.photo();
}

Future<void> formFrames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _stepKeys = ['step-patient', 'step-blood', 'step-hospital'];

/// The list of the step the header names.
Finder currentStepList(WidgetTester tester) {
  final header = tester
      .widget<Text>(find.textContaining(RegExp(r'^Step \d of 3')))
      .data!;
  final step = int.parse(RegExp(r'Step (\d)').firstMatch(header)!.group(1)!);
  return find.byKey(PageStorageKey(_stepKeys[step - 1]));
}

/// Scrolls the current step until [finder] is on screen. (It moves the list
/// itself: a drag in the middle could land on the notes field, whose own
/// scrolling takes it.)
Future<void> scrollStepTo(WidgetTester tester, Finder finder) async {
  // Like a donor closing the keyboard first: a focused field keeps scrolling
  // itself back into view.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: currentStepList(tester),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  if (finder.evaluate().isEmpty) {
    position.jumpTo(0);
    await tester.pump();
  }
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    position.jumpTo(
      (position.pixels + 150).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pump();
  }
  // Only this list moves (tester.ensureVisible would also slide the pages).
  await position.ensureVisible(
    tester.renderObject(finder.first),
    alignment: 0.3,
  );
  await tester.pump();
}

Future<void> tapInStep(WidgetTester tester, Finder finder) async {
  await scrollStepTo(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> continueStep(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await formFrames(tester, 5);
}

/// Step 1 by "Myself" (the name and O+ from the profile) and a photo.
Future<void> fillPatientStep(WidgetTester tester) async {
  await tapInStep(tester, find.text('Myself'));
  await tapInStep(tester, find.text('Take photo'));
  await formFrames(tester, 2);
}

/// Step 2: the date picker's first offer (today).
Future<void> fillBloodStep(WidgetTester tester) async {
  await tapInStep(tester, find.text('Select a date'));
  await formFrames(tester, 3);
  await tester.tap(find.text('OK'));
  await formFrames(tester, 3);
}

/// Through steps 1 and 2 to the hospital step, with its stock loaded.
Future<void> fillToHospitalStep(WidgetTester tester) async {
  await fillPatientStep(tester);
  await continueStep(tester);
  await fillBloodStep(tester);
  await continueStep(tester);
  await formFrames(tester, 3);
}

/// Picks [hospital] and ticks the consent.
Future<void> fillHospitalStep(
  WidgetTester tester, {
  String hospital = 'Charlie Blood Bank',
}) async {
  await tapInStep(tester, find.text(hospital));
  await formFrames(tester, 3);
  await tapInStep(tester, find.byType(Checkbox));
}

// ─── Tracking ───────────────────────────────────────────────────────────────

const kStatusLabels = {
  'pending_review': 'Waiting for the hospital',
  'approved': 'Approved',
  'ready': 'Ready for pickup',
  'fulfilled': 'Completed',
  'rejected': 'Declined',
  'cancelled': 'Cancelled',
  'expired': 'Expired',
};

/// A request in [status], as get_hospital_request(s) sends it.
Map<String, dynamic> trackedRequest(
  int id,
  String status, {
  bool? canCancel,
  String? pickupDeadline = '2099-10-30 17:00:00',
}) => {
  ...hospitalRequestJson(facilityName: 'Charlie Blood Bank'),
  'request_id': id,
  'reference': 'HR-${id.toString().padLeft(4, '0')}',
  'status': status,
  'status_label': kStatusLabels[status],
  'units_requested': 2,
  'units_approved': status == 'approved' || status == 'ready' ? 1 : null,
  'urgency': 'high',
  'urgency_label': 'High',
  'needed_by': '2099-10-30',
  'created_ago': '2 hours ago',
  'updated_ago': '5 minutes ago',
  'hospital_message': status == 'approved' || status == 'ready'
      ? 'Please come to the blood bank on the 2nd floor.'
      : null,
  'pickup_deadline': status == 'ready' ? pickupDeadline : null,
  'rejection_reason': status == 'rejected'
      ? 'We have no O+ platelets this week.'
      : null,
  'cancellation_reason': status == 'cancelled' ? 'No longer needed' : null,
  'hospital_reference': 'PT-0042',
  'notes': 'Surgery on Friday',
  'can_cancel': canCancel ?? kStatusLabels.keys.take(3).contains(status),
  'needs_attention': status == 'ready',
};

/// The donor's list: one request in every status.
Map<String, dynamic> trackedList() => {
  'status': 'success',
  'counts': {'active': 3, 'history': 4},
  'requests': [
    for (final (i, s) in kStatusLabels.keys.indexed) trackedRequest(i + 1, s),
  ],
};

Map<String, dynamic> trackedDetail(Map<String, dynamic> request) => {
  'status': 'success',
  'request': request,
  'timeline': [
    {
      'key': 'submitted',
      'label': 'Sent',
      'at': '2099-10-25 09:00:00',
      'done': true,
    },
    {
      'key': 'reviewed',
      'label': 'Reviewed by the hospital',
      'at': null,
      'done': false,
    },
    {'key': 'ready', 'label': 'Ready for pickup', 'at': null, 'done': false},
  ],
  'availability': {
    'facility_id': 3,
    'level': 'available',
    'label': 'In stock',
    'updated_ago': '2 hours ago',
  },
};
