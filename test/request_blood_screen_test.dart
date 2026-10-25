import 'dart:async';
import 'dart:convert';

import 'package:blood/app_theme.dart';
import 'package:blood/blood_requests/hospital_request_widgets.dart';
import 'package:blood/blood_requests/request_blood_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hospital_request_fixtures.dart';
import 'support/pumpable_screens.dart';

/// The "Request Blood" form: a request to a hospital, in three steps
/// (Patient, Blood, Hospital), the form photo, stock chips, the review, the
/// server's errors and the sent screen.

/// The fake server: answers can be swapped per test.
class _Server {
  Map<String, dynamic> options = hospitalOptions();
  Map<String, dynamic>? availability = hospitalAvailability();
  Completer<void>? holdAvailability;
  Map<String, dynamic> submitAnswer = {
    'status': 'success',
    'code': 'REQUEST_SUBMITTED',
    'message': 'Sent',
    'duplicate': false,
    'request': hospitalRequestJson(facilityName: 'Charlie Blood Bank'),
  };
  bool submitThrows = false;

  final availabilityAsked = <String>[];
  final submits = <http.Request>[];

  Future<http.Response> call(http.Request r) async {
    final path = r.url.path;
    if (path.endsWith('get_hospital_request_options.php')) {
      return okJson(options);
    }
    if (path.endsWith('get_blood_availability.php')) {
      availabilityAsked.add(r.url.queryParameters['blood_type_id'] ?? '');
      await holdAvailability?.future;
      final a = availability;
      return a == null ? http.Response('oops', 500) : okJson(a);
    }
    if (path.endsWith('submit_hospital_blood_request.php')) {
      submits.add(r);
      if (submitThrows) throw http.ClientException('offline');
      return okJson(submitAnswer);
    }
    return pumpableServer(r);
  }

  /// The fields of the last multipart submit.
  Map<String, String> lastFields() => fieldsOf(submits.last);

  static Map<String, String> fieldsOf(http.Request request) {
    final body = latin1.decode(request.bodyBytes);
    final fields = <String, String>{};
    final re = RegExp(
      r'name="([^"]+)"\r\n(?:content-type[^\r]*\r\n)?\r\n([^\r]*)\r\n',
    );
    for (final m in re.allMatches(body)) {
      fields[m.group(1)!] = m.group(2)!;
    }
    return fields;
  }
}

bool? _launcherResult;

/// Opens the form like the hub does, and keeps what it returned.
class _Launcher extends StatelessWidget {
  const _Launcher(this.picker);
  final FakeFormPhotoPicker picker;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          _launcherResult = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => RequestBloodScreen(photoPicker: picker),
            ),
          );
        },
        child: const Text('Open the form'),
      ),
    ),
  );
}

Future<FakeFormPhotoPicker> _pump(
  WidgetTester tester,
  _Server server, {
  bool dark = false,
  double scale = 1,
  bool allowOverflow = true,
}) async {
  SharedPreferences.setMockInitialValues({'donorId': '7'});
  _launcherResult = null;
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clipboard = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add('${(call.arguments as Map)['text']}');
      }
      return null;
    },
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if ((allowOverflow && text.contains('overflowed')) ||
        text.contains('MissingPlugin')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  final picker = FakeFormPhotoPicker();
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: _Launcher(picker),
    ),
  );
  await tester.tap(find.text('Open the form'));
  await formFrames(tester, 6);
  return picker;
}

Future<void> _with(_Server server, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(server.call));

/// A Semantics widget with [label] (no semantics tree needed).
Finder _labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// A tall screen, so every hospital card is built and on screen.
Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 2400);
  await formFrames(tester, 2);
}

String _header(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining(RegExp(r'^Step \d of 3'))).data!;

void main() {
  testWidgets('a whole request: three steps, sent, then the sent screen', (
    tester,
  ) async {
    final server = _Server();
    await _with(server, () async {
      await _pump(tester, server);
      expect(_header(tester), 'Step 1 of 3 · Patient');
      await fillPatientStep(tester);
      await continueStep(tester);
      expect(_header(tester), 'Step 2 of 3 · Blood');
      await fillBloodStep(tester);
      await continueStep(tester);
      expect(_header(tester), 'Step 3 of 3 · Hospital');
      expect(server.availabilityAsked, ['$kOPositive']);
      await fillHospitalStep(tester);
      await tester.tap(find.text('Send Request'));
      await formFrames(tester, 8);

      expect(server.submits, hasLength(1));
      final fields = server.lastFields();
      expect(fields['donor_id'], '7');
      expect(fields['facility_id'], '3');
      expect(fields['blood_type_id'], '$kOPositive');
      expect(fields['blood_component'], 'whole_blood');
      expect(fields['units_requested'], '1');
      expect(fields['urgency'], 'normal');
      expect(fields['patient_name'], 'Rey Ashlee Liwanag');
      expect(fields['relationship'], 'self');
      expect(fields['contact_number'], '09171234567');
      expect(fields['submission_key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(
        latin1.decode(server.submits.last.bodyBytes),
        contains('name="document"; filename="form.png"'),
      );

      expect(_launcherResult, isTrue);
      expect(find.byType(HospitalRequestSubmittedScreen), findsOneWidget);
      expect(find.text('HR-0031'), findsOneWidget);
      expect(
        find.text('The hospital reviews your request and form'),
        findsOneWidget,
      );
      expect(
        find.text('You get a notification when it is approved'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Pick up the blood at Charlie Blood Bank with your ID and the form',
        ),
        findsOneWidget,
      );
      expect(find.text('Track Request'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('step 1: patient', () {
    testWidgets('each field says what is missing; Myself fills from the '
        'profile', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, server);
        await continueStep(tester);
        expect(_header(tester), 'Step 1 of 3 · Patient');
        expect(find.text("Please enter the patient's full name."), findsOne);
        expect(
          find.text('Please select your relationship to the patient.'),
          findsOne,
        );
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('error-document')),
        );
        expect(
          find.text("Please add a photo of the hospital's blood request form."),
          findsOne,
        );

        await tapInStep(tester, find.text('Myself'));
        await formFrames(tester, 3);
        // (The name is above the chips: look there.)
        await scrollStepTo(
          tester,
          find.byType(TextField, skipOffstage: false).first,
        );
        expect(find.text('Rey Ashlee Liwanag'), findsOne);
        expect(find.text('Filled from your profile'), findsOne);
        expect(
          find.text("Please enter the patient's full name."),
          findsNothing,
        );
        // Another relationship clears what Myself filled in.
        await tapInStep(tester, find.text('Parent'));
        await formFrames(tester, 3);
        await scrollStepTo(
          tester,
          find.byType(TextField, skipOffstage: false).first,
        );
        expect(
          find.text('Rey Ashlee Liwanag', skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text('Filled from your profile', skipOffstage: false),
          findsNothing,
        );
        // The photo is still missing: no way on.
        await continueStep(tester);
        expect(_header(tester), 'Step 1 of 3 · Patient');
      });
    });

    testWidgets('the form photo card: empty, picked, too large, removed', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        final picker = await _pump(tester, server);
        final card = find.byKey(const ValueKey('form-photo-card'));
        await scrollStepTo(tester, card);
        expect(
          find.text("Photo of the hospital's blood request form"),
          findsOne,
        );
        expect(
          find.text(
            'Ask the hospital for its blood request form signed by the '
            'doctor and take a clear photo of it.',
          ),
          findsOne,
        );
        expect(find.text('Required · up to 8 MB'), findsOne);
        expect(find.text('Take photo'), findsOne);
        expect(find.text('Choose from gallery'), findsOne);

        // Too large: refused, with the sizes.
        picker.next = FakeFormPhotoPicker.photo(size: 9 * 1024 * 1024);
        await tapInStep(tester, find.text('Choose from gallery'));
        await formFrames(tester, 2);
        expect(picker.sources.last, FormPhotoSource.gallery);
        expect(
          find.text(
            'This photo is 9.0 MB. The limit is 8 MB: please use a smaller '
            'photo.',
          ),
          findsOne,
        );
        expect(find.text('Form photo added'), findsNothing);

        // Not a photo type the hospital takes.
        picker.next = FakeFormPhotoPicker.photo(name: 'form.heic');
        await tapInStep(tester, find.text('Take photo'));
        await formFrames(tester, 2);
        expect(find.text('Please use a JPG, PNG or WebP photo.'), findsOne);

        // Picked: a thumbnail, Replace and Remove.
        picker.next = FakeFormPhotoPicker.photo();
        await tapInStep(tester, find.text('Take photo'));
        await formFrames(tester, 2);
        expect(picker.sources.last, FormPhotoSource.camera);
        expect(find.text('Form photo added'), findsOne);
        expect(_labelled('Form photo'), findsOne);
        expect(find.text('Replace'), findsOne);
        expect(find.text('Remove'), findsOne);
        expect(find.textContaining('This photo is'), findsNothing);

        // Replace: the camera or the gallery again.
        await tapInStep(tester, find.text('Replace'));
        await formFrames(tester, 4);
        await tester.tap(find.text('Choose from gallery').last);
        await formFrames(tester, 4);
        expect(picker.sources.last, FormPhotoSource.gallery);
        expect(find.text('Form photo added'), findsOne);

        // Removed: back to the two buttons.
        await tapInStep(tester, find.text('Remove'));
        await formFrames(tester, 2);
        expect(find.text('Form photo added'), findsNothing);
        expect(find.text('Take photo'), findsOne);

        // A picker that fails says so.
        picker.error = PlatformException(code: 'camera_access_denied');
        await tapInStep(tester, find.text('Take photo'));
        await formFrames(tester, 2);
        expect(find.textContaining("Couldn't open the camera"), findsOne);
      });
    });

    testWidgets('the photo is optional when the server says so', (
      tester,
    ) async {
      final server = _Server()
        ..options = hospitalOptions(documentRequired: false);
      await _with(server, () async {
        await _pump(tester, server);
        await tapInStep(tester, find.text('Myself'));
        await scrollStepTo(tester, find.text('Optional · up to 8 MB'));
        await continueStep(tester);
        expect(_header(tester), 'Step 2 of 3 · Blood');
      });
    });
  });

  group('step 2: blood', () {
    testWidgets('8 types, the components, units, urgency and the date', (
      tester,
    ) async {
      final server = _Server()..options = hospitalOptions(maxUnits: 3);
      await _with(server, () async {
        await _pump(tester, server);
        await tester.enterText(find.byType(TextField).first, 'Maria Santos');
        await tapInStep(tester, find.text('Parent'));
        await tapInStep(tester, find.text('Take photo'));
        await formFrames(tester, 2);
        await continueStep(tester);
        expect(_header(tester), 'Step 2 of 3 · Blood');

        for (final t in kBloodTypes) {
          expect(find.text(t), findsOne, reason: t);
        }
        expect(find.textContaining("don't know"), findsNothing);
        expect(find.textContaining('Unknown'), findsNothing);
        // Nothing left from the donor requests.
        expect(find.textContaining('Compatible donors'), findsNothing);
        expect(find.textContaining('can donate'), findsNothing);
        expect(find.textContaining('Donors needed'), findsNothing);
        expect(find.textContaining('or compatible'), findsNothing);

        await continueStep(tester);
        expect(find.text("Please select the patient's blood type."), findsOne);
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('error-needed_by')),
        );
        expect(find.text('Please select a date.'), findsOne);

        // Whole blood by default; one choice at a time.
        await scrollStepTo(tester, find.text('Packed red cells'));
        // The choice card's own Semantics says whether it is selected.
        bool selected(String label) =>
            tester
                .widget<Semantics>(
                  find
                      .ancestor(
                        of: find.text(label, skipOffstage: false),
                        matching: find.byWidgetPredicate(
                          (w) => w is Semantics && w.properties.button == true,
                        ),
                      )
                      .first,
                )
                .properties
                .selected ??
            false;
        expect(selected('Whole blood'), isTrue);
        await tester.tap(find.text('Platelets'));
        await tester.pump();
        expect(selected('Platelets'), isTrue);
        expect(selected('Whole blood'), isFalse);
        expect(find.text('For dengue and bleeding.'), findsOne);

        // Units: 1 up to the limit.
        await scrollStepTo(tester, _labelled('More units'));
        for (var i = 0; i < 5; i++) {
          await tester.tap(_labelled('More units'));
          await tester.pump();
        }
        expect(find.text('3'), findsOne);
        expect(find.text('units'), findsOne);

        await tapInStep(tester, find.text('High'));
        await tapInStep(tester, find.text('B-'));
        await fillBloodStep(tester);
        await continueStep(tester);
        expect(_header(tester), 'Step 3 of 3 · Hospital');
        // B- is the 4th type.
        expect(server.availabilityAsked, ['4']);
      });
    });
  });

  group('step 3: hospital', () {
    List<String> order(WidgetTester tester) {
      final names =
          [
                'Alpha Medical Center',
                'Bravo General Hospital',
                'Charlie Blood Bank',
                'Delta Hospital',
              ]
              .where(
                (n) => find.text(n, skipOffstage: false).evaluate().isNotEmpty,
              )
              .toList();
      names.sort(
        (a, b) => tester
            .getTopLeft(find.text(a, skipOffstage: false).first)
            .dy
            .compareTo(
              tester.getTopLeft(find.text(b, skipOffstage: false).first).dy,
            ),
      );
      return names;
    }

    testWidgets('stock chips, sorted by stock, and the in-stock filter', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        await _tall(tester);
        // Available, limited, not listed, out (not by name).
        expect(order(tester), [
          'Charlie Blood Bank',
          'Bravo General Hospital',
          'Delta Hospital',
          'Alpha Medical Center',
        ]);
        expect(find.text('In stock'), findsOne);
        expect(find.text('Limited'), findsOne);
        expect(find.text('Not listed'), findsOne);
        expect(find.text('Out of stock'), findsOne);
        expect(find.text('updated 2 hours ago'), findsOne);
        expect(find.text('updated 3 hours ago'), findsOne);

        await tapInStep(tester, find.text('In stock only'));
        await formFrames(tester, 2);
        expect(order(tester), ['Charlie Blood Bank', 'Bravo General Hospital']);

        // The search: by name, barangay or city.
        await tapInStep(tester, find.text('In stock only'));
        await tester.enterText(find.byType(TextField).first, 'panabo');
        await tester.pump();
        expect(order(tester), ['Bravo General Hospital']);
        await tester.enterText(find.byType(TextField).first, 'zzz');
        await tester.pump();
        expect(find.text('No hospitals match your search.'), findsOne);
      });
    });

    testWidgets('skeleton chips while loading; on failure no chips and a '
        'retry', (tester) async {
      final server = _Server()..holdAvailability = Completer<void>();
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        await _tall(tester);
        expect(find.byType(StockChipSkeleton), findsWidgets);
        expect(find.byType(StockChip), findsNothing);
        server.availability = null; // the answer will be an error
        server.holdAvailability!.complete();
        await formFrames(tester, 3);
        expect(find.byType(StockChipSkeleton), findsNothing);
        expect(find.byType(StockChip), findsNothing);
        expect(find.text('Charlie Blood Bank'), findsOne);
        // Alphabetical without stock.
        expect(order(tester).first, 'Alpha Medical Center');

        server.holdAvailability = null;
        server.availability = hospitalAvailability();
        await tester.tap(find.byKey(const ValueKey('stock-retry')));
        await formFrames(tester, 3);
        expect(find.byType(StockChip), findsWidgets);
        expect(find.byKey(const ValueKey('stock-retry')), findsNothing);
        expect(server.availabilityAsked, ['7', '7']);
      });
    });

    testWidgets('a new blood type reloads the stock', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        await tester.tap(find.text('Back'));
        await formFrames(tester, 5);
        await tapInStep(tester, find.text('AB+'));
        await formFrames(tester, 3);
        expect(server.availabilityAsked, ['7', '5']);
        await continueStep(tester);
        // Already loaded for AB+: not asked again.
        expect(server.availabilityAsked, ['7', '5']);
      });
    });

    testWidgets('a hospital out of stock: the note and the link to donate; '
        'the card opens with its address and number', (tester) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        await tapInStep(tester, find.text('Alpha Medical Center'));
        await formFrames(tester, 3);
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('out-of-stock-banner')),
        );
        expect(
          find.text(
            'This hospital is out of O+ right now. You can still send your '
            'request: the hospital will tell you if it can help. Or pick '
            'another hospital that has stock.',
          ),
          findsOne,
        );
        // No Home behind the form here: the link does nothing.
        await tapInStep(tester, find.text('Donate blood to help restock'));
        await formFrames(tester, 2);
        expect(_header(tester), 'Step 3 of 3 · Hospital');

        await scrollStepTo(tester, find.byTooltip('Call Alpha Medical Center'));
        expect(
          find.text('12 Rizal St., Poblacion, Tagum, Davao del Norte'),
          findsOne,
        );
        expect(find.byTooltip('Call Alpha Medical Center'), findsOne);
        await tester.tap(find.text('0841234567'));
        await tester.pump();
        expect(find.text('Number copied'), findsOne);

        // Another hospital with stock: no note.
        await tapInStep(tester, find.text('Charlie Blood Bank'));
        await formFrames(tester, 3);
        expect(find.byKey(const ValueKey('out-of-stock-banner')), findsNothing);
      });
    });

    testWidgets('the review card: everything, and Edit goes back', (
      tester,
    ) async {
      final server = _Server();
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        final notes = find.widgetWithText(
          TextField,
          'e.g. Surgery on Friday morning.',
          skipOffstage: false,
        );
        await scrollStepTo(tester, notes);
        await tester.enterText(notes, 'Surgery Friday');
        await fillHospitalStep(tester, hospital: 'Bravo General Hospital');
        final review = find.byKey(const ValueKey('review-card'));
        await scrollStepTo(tester, review);
        Finder inReview(Finder f) => find.descendant(of: review, matching: f);
        expect(inReview(find.text('Bravo General Hospital')), findsOne);
        expect(inReview(find.text('Limited')), findsOne);
        expect(inReview(find.text('Whole blood')), findsOne);
        expect(inReview(find.text('1 unit of O+')), findsOne);
        expect(inReview(find.textContaining('Needed by')), findsOne);
        expect(inReview(find.text('PRIVATE')), findsOne);
        expect(inReview(find.text('Rey Ashlee Liwanag')), findsOne);
        expect(inReview(find.text('Myself')), findsOne);
        expect(inReview(find.text('09171234567')), findsOne);
        expect(inReview(find.text('Form photo attached')), findsOne);
        expect(
          find.text('Only you and the hospital see this.', skipOffstage: false),
          findsOne,
        );
        expect(
          find.textContaining(
            'I confirm this request is genuine, the patient is under the care '
            'of the selected hospital',
            skipOffstage: false,
          ),
          findsOne,
        );
        expect(find.text('Send Request'), findsOne);

        await tester.tap(_labelled('Edit blood'));
        await formFrames(tester, 2);
        expect(_header(tester), 'Step 2 of 3 · Blood');
        await continueStep(tester);
        await scrollStepTo(tester, review);
        await tester.tap(_labelled('Edit patient'));
        await formFrames(tester, 2);
        expect(_header(tester), 'Step 1 of 3 · Patient');
      });
    });

    testWidgets('the hospital, the number and the consent are checked', (
      tester,
    ) async {
      final server = _Server()
        ..options = (hospitalOptions()
          ..['defaults'] = {
            ...hospitalOptions()['defaults'] as Map<String, dynamic>,
            'contact_number': '12345',
          });
      await _with(server, () async {
        await _pump(tester, server);
        await fillToHospitalStep(tester);
        await tester.tap(find.text('Send Request'));
        await tester.pump();
        expect(server.submits, isEmpty);
        expect(find.text('Please choose a hospital.'), findsOne);
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('error-contact_number')),
        );
        expect(
          find.text('Enter a valid PH mobile number (e.g. 09171234567).'),
          findsOne,
        );
        await scrollStepTo(tester, find.byKey(const ValueKey('error-consent')));
        expect(find.text('Please confirm before sending.'), findsOne);
      });
    });
  });

  testWidgets('blocked: the server says why, with Verify Now', (tester) async {
    final server = _Server()
      ..options = hospitalOptions(
        canRequest: false,
        block: {
          'reason': 'not_verified',
          'message': 'Verify your account to request blood.',
          'action': 'verify',
        },
      );
    await _with(server, () async {
      await _pump(tester, server);
      expect(find.text('Unable to Request Blood'), findsOne);
      expect(find.text('Verify your account to request blood.'), findsOne);
      expect(find.text('Verify Now'), findsOne);
      expect(find.text('Continue'), findsNothing);
    });
  });

  group('the server says no', () {
    Map<String, dynamic> error(
      String code,
      String message, [
      Map<String, String>? errors,
    ]) => {
      'status': 'error',
      'code': code,
      'message': message,
      'errors': ?errors,
    };

    Future<void> send(WidgetTester tester) async {
      await fillToHospitalStep(tester);
      await fillHospitalStep(tester);
      await tester.tap(find.text('Send Request'));
      await formFrames(tester, 4);
    }

    testWidgets('field errors land on their step', (tester) async {
      final server = _Server()
        ..submitAnswer = error('VALIDATION_FAILED', 'Please check the form.', {
          'units_requested': 'Too many units.',
          'notes': 'Too long.',
        });
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        // The first step with an error: Blood.
        expect(_header(tester), 'Step 2 of 3 · Blood');
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('error-units_requested')),
        );
        expect(find.text('Too many units.'), findsOne);
        expect(find.text('Please check the form.'), findsOne);

        server.submitAnswer = error('VALIDATION_FAILED', 'Check it.', {
          'document': 'The photo is unreadable.',
        });
        await continueStep(tester);
        await tester.tap(find.text('Send Request'));
        await formFrames(tester, 4);
        expect(_header(tester), 'Step 1 of 3 · Patient');
        await scrollStepTo(
          tester,
          find.byKey(const ValueKey('error-document')),
        );
        expect(find.text('The photo is unreadable.'), findsOne);
        // One form, one key: both sends were the same request.
        expect(server.submits, hasLength(2));
        expect(
          server.lastFields()['submission_key'],
          _Server.fieldsOf(server.submits.first)['submission_key'],
        );
      });
    });

    testWidgets('not verified: a dialog with Verify Now', (tester) async {
      final server = _Server()
        ..submitAnswer = error('NOT_VERIFIED', 'Verify your account first.');
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        expect(find.byType(AlertDialog), findsOne);
        expect(find.text('Verify your account first.'), findsOne);
        expect(find.text('Verify Now'), findsOne);
      });
    });

    testWidgets('too many requests: a dialog with View My Requests', (
      tester,
    ) async {
      final server = _Server()
        ..submitAnswer = error('MAX_ACTIVE', 'You have 3 active requests.');
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        expect(find.text('You have 3 active requests.'), findsOne);
        expect(find.text('View My Requests'), findsOne);
      });
    });

    testWidgets('hospital unavailable: back to the list, stock reloaded', (
      tester,
    ) async {
      final server = _Server()
        ..submitAnswer = error(
          'FACILITY_UNAVAILABLE',
          'This hospital is not taking requests right now.',
        );
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        await formFrames(tester, 3);
        expect(_header(tester), 'Step 3 of 3 · Hospital');
        expect(
          find.text('This hospital is not taking requests right now.'),
          findsOne,
        );
        expect(server.availabilityAsked, ['7', '7']);
      });
    });

    testWidgets('a duplicate: a SnackBar with View', (tester) async {
      final server = _Server()
        ..submitAnswer = error(
          'DUPLICATE_REQUEST',
          'You already sent this request.',
        );
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        expect(find.text('You already sent this request.'), findsOne);
        expect(find.widgetWithText(SnackBarAction, 'View'), findsOne);
      });
    });

    testWidgets('no connection: the form stays, with Retry', (tester) async {
      final server = _Server()..submitThrows = true;
      await _with(server, () async {
        await _pump(tester, server);
        await send(tester);
        expect(find.textContaining("Couldn't send your request"), findsOne);
        expect(_header(tester), 'Step 3 of 3 · Hospital');
        server.submitThrows = false;
        await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
        await formFrames(tester, 8);
        expect(find.byType(HospitalRequestSubmittedScreen), findsOne);
        expect(server.submits, hasLength(2));
        expect(
          _Server.fieldsOf(server.submits.first)['submission_key'],
          server.lastFields()['submission_key'],
        );
      });
    });
  });

  group('looks', () {
    // Each step, and the hospital step scrolled to the review.
    final places = <String, Future<void> Function(WidgetTester)>{
      'patient': (tester) async {},
      'patient with a photo': (tester) async {
        await fillPatientStep(tester);
        await scrollStepTo(tester, find.text('Form photo added'));
      },
      'blood': (tester) async {
        await fillPatientStep(tester);
        await continueStep(tester);
      },
      'hospital': (tester) async {
        await fillToHospitalStep(tester);
        await tapInStep(tester, find.text('Alpha Medical Center'));
        await formFrames(tester, 3);
      },
      'review': (tester) async {
        await fillToHospitalStep(tester);
        await fillHospitalStep(tester);
        await scrollStepTo(tester, find.byKey(const ValueKey('review-card')));
      },
    };
    for (final dark in [false, true]) {
      for (final MapEntry(key: place, value: go) in places.entries) {
        testWidgets('${dark ? 'dark' : 'light'}, text x1.3, $place: no '
            'overflow, contrast and tap targets', (tester) async {
          final server = _Server();
          final handle = tester.ensureSemantics();
          await _with(server, () async {
            await _pump(
              tester,
              server,
              dark: dark,
              scale: 1.3,
              allowOverflow: false,
            );
            await go(tester);
            await formFrames(tester, 3);
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          });
          handle.dispose();
        });
      }
      testWidgets('${dark ? 'dark' : 'light'}, text x1.3: the sent screen', (
        tester,
      ) async {
        final server = _Server();
        final handle = tester.ensureSemantics();
        await _with(server, () async {
          await _pump(
            tester,
            server,
            dark: dark,
            scale: 1.3,
            allowOverflow: false,
          );
          await fillToHospitalStep(tester);
          await fillHospitalStep(tester);
          await tester.tap(find.text('Send Request'));
          await formFrames(tester, 8);
          expect(find.byType(HospitalRequestSubmittedScreen), findsOne);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        });
        handle.dispose();
      });
    }
  });
}
