// The 3-step "Request Blood" wizard (Patient & Hospital → Blood Needed →
// Contact & Review) plus the success screen shown right after submitting.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_design.dart';
import '../verify.dart';
import 'blood_request_api.dart';
import 'blood_request_detail_screen.dart';
import 'blood_request_models.dart';
import 'blood_request_widgets.dart';

// Mirrors the backend's donor-compatibility table so the "Compatible donors"
// hint can be shown instantly, without a round trip.
const Map<String, List<String>> _compatibleDonorsTable = {
  'O-': ['O-'],
  'O+': ['O+', 'O-'],
  'A-': ['A-', 'O-'],
  'A+': ['A+', 'A-', 'O+', 'O-'],
  'B-': ['B-', 'O-'],
  'B+': ['B+', 'B-', 'O+', 'O-'],
  'AB-': ['AB-', 'A-', 'B-', 'O-'],
  'AB+': ['AB+', 'AB-', 'A+', 'A-', 'B+', 'B-', 'O+', 'O-'],
};

const _stepNames = ['Patient', 'Blood', 'Contact'];
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class RequestBloodScreen extends StatefulWidget {
  const RequestBloodScreen({super.key});

  @override
  State<RequestBloodScreen> createState() => _RequestBloodScreenState();
}

class _RequestBloodScreenState extends State<RequestBloodScreen> {
  late final String _submissionKey;
  late final PageController _pageCtrl;

  RequestFormOptions? _options;
  bool _loadingOptions = true;
  bool _optionsError = false;
  String _donorId = '';

  int _step = 0;
  bool _submitting = false;
  final Map<String, String> _errors = {};

  // Step 1
  final _patientNameCtrl = TextEditingController();
  final _hospitalRefCtrl = TextEditingController();
  String? _relationship;
  BloodRequestFacility? _facility;

  // Step 2
  String? _bloodType;
  int? _bloodTypeId;
  int _donorsNeeded = 1;
  bool _allowOtherTypes = false;
  int _specificMatchRequired = 1;
  String _urgency = 'normal';
  DateTime? _neededBy;

  // Step 3
  final _contactCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _submissionKey = brNewSubmissionKey();
    _pageCtrl = PageController();
    _loadOptions();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _patientNameCtrl.dispose();
    _hospitalRefCtrl.dispose();
    _contactCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _optionsError = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _donorId = prefs.getString('donorId') ?? '';
      final options = await BloodRequestApi.fetchOptions(_donorId);
      if (!mounted) return;
      setState(() {
        _options = options;
        _contactCtrl.text = options.defaultContactNumber;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = true;
      });
    }
  }

  List<String> _compatibleDonors(String bloodType) =>
      _compatibleDonorsTable[bloodType] ?? [bloodType];

  String _requirementText() {
    final n = _donorsNeeded;
    final plural = n > 1 ? 's' : '';
    final type = _bloodType ?? '';
    if (!_allowOtherTypes) {
      return '$n donor$plural · all must be $type or compatible';
    }
    if (_specificMatchRequired <= 0) {
      return '$n donor$plural · any blood type accepted';
    }
    return '$n donor$plural · $_specificMatchRequired must be $type or '
        'compatible · others any type';
  }

  String _relationshipLabel() {
    final matches = (_options?.relationships ?? const [])
        .where((r) => r.value == _relationship);
    return matches.isEmpty ? '—' : matches.first.label;
  }

  String _formatFullDayDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';

  String _neededByShort() {
    if (_neededBy == null) return '';
    return '${_monthsShort[_neededBy!.month - 1]} ${_neededBy!.day}';
  }

  String _dateToIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<String> _fieldsForStep(int step) {
    switch (step) {
      case 0:
        return ['patient_name', 'relationship', 'facility_id'];
      case 1:
        return ['blood_type_id', 'needed_by'];
      default:
        return ['contact_number', 'consent'];
    }
  }

  bool _validateStep(int step) {
    final errs = <String, String>{};
    if (step == 0) {
      if (_patientNameCtrl.text.trim().length < 2) {
        errs['patient_name'] = "Please enter the patient's full name.";
      }
      if (_relationship == null) {
        errs['relationship'] = 'Please select your relationship to the patient.';
      }
      if (_facility == null) {
        errs['facility_id'] = 'Please select a hospital or facility.';
      }
    } else if (step == 1) {
      if (_bloodType == null) {
        errs['blood_type_id'] = "Please select the patient's blood type.";
      }
      if (_neededBy == null) {
        errs['needed_by'] = 'Please select a date.';
      }
    } else {
      final phone = _contactCtrl.text.replaceAll(RegExp(r'[\s-]'), '');
      if (!RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(phone)) {
        errs['contact_number'] = 'Enter a valid PH mobile number (e.g. 09171234567).';
      }
      if (!_consent) {
        errs['consent'] = 'Please confirm before submitting.';
      }
    }
    setState(() {
      _errors.removeWhere((k, _) => _fieldsForStep(step).contains(k));
      _errors.addAll(errs);
    });
    return errs.isEmpty;
  }

  bool get _currentStepValid {
    switch (_step) {
      case 0:
        return _patientNameCtrl.text.trim().length >= 2 &&
            _relationship != null &&
            _facility != null;
      case 1:
        return _bloodType != null && _neededBy != null;
      default:
        final phone = _contactCtrl.text.replaceAll(RegExp(r'[\s-]'), '');
        return RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(phone) && _consent;
    }
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageCtrl.jumpToPage(step);
  }

  void _next() {
    if (!_validateStep(_step)) return;
    if (_step == 2) {
      _submit();
      return;
    }
    setState(() => _step += 1);
    _pageCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
    _pageCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int _stepForFirstError(Iterable<String> keys) {
    for (var i = 0; i < 3; i++) {
      if (keys.any(_fieldsForStep(i).contains)) return i;
    }
    return 0;
  }

  Future<void> _confirmDiscard() async {
    final hasEntered = _patientNameCtrl.text.isNotEmpty ||
        _relationship != null ||
        _facility != null ||
        _bloodType != null ||
        _hospitalRefCtrl.text.isNotEmpty ||
        _notesCtrl.text.isNotEmpty;
    if (!hasEntered) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard this request?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard', style: TextStyle(color: kCrimson)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickFacility() async {
    final selected = await showModalBottomSheet<BloodRequestFacility>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FacilityPickerSheet(
        facilities: _options?.facilities ?? const [],
        selected: _facility,
      ),
    );
    if (selected != null) {
      setState(() {
        _facility = selected;
        _errors.remove('facility_id');
      });
    }
  }

  Future<void> _pickNeededByDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDays = _options?.maxNeededByDays ?? 30;
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? today,
      firstDate: today,
      lastDate: today.add(Duration(days: maxDays)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kCrimson,
            onPrimary: Colors.white,
            onSurface: kTextPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _neededBy = picked;
        _errors.remove('needed_by');
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final payload = {
      'donor_id': _donorId,
      'submission_key': _submissionKey,
      'facility_id': _facility!.facilityId,
      'blood_type_id': _bloodTypeId,
      'required_donors': _donorsNeeded,
      'allow_other_blood_types': _allowOtherTypes,
      'specific_match_required':
          _allowOtherTypes ? _specificMatchRequired : _donorsNeeded,
      'urgency': _urgency,
      'needed_by': _dateToIso(_neededBy!),
      'patient_name': _patientNameCtrl.text.trim(),
      'relationship': _relationship,
      'contact_number': _contactCtrl.text.trim(),
      if (_hospitalRefCtrl.text.trim().isNotEmpty)
        'hospital_reference': _hospitalRefCtrl.text.trim(),
      if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
    };

    try {
      final result = await BloodRequestApi.submitRequest(payload);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      // pushReplacement's `result` immediately resolves whoever awaited the
      // Navigator.push that opened this screen — this both hands the caller
      // `true` (so it knows to reload) and swaps this screen for the
      // submitted-confirmation screen in one step.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BloodRequestSubmittedScreen(request: result.request),
        ),
        result: true,
      );
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.code == 'VALIDATION_FAILED' && e.errors != null) {
        setState(() {
          _errors.addAll(e.errors!);
          _step = _stepForFirstError(e.errors!.keys);
        });
        _pageCtrl.jumpToPage(_step);
      }
      _showSnack(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(
        'Unable to reach the server. Please check your connection and try again.',
        isError: true,
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? kCrimson : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingOptions) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9FAFB),
        body: SafeArea(child: Center(child: CircularProgressIndicator(color: kCrimson))),
      );
    }
    if (_optionsError) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: BrEmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load the request form",
            message: 'Check your connection and try again.',
            actionLabel: 'Try Again',
            onAction: _loadOptions,
          ),
        ),
      );
    }

    final options = _options!;
    if (!options.canRequest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: kTextPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: BrEmptyState(
                  icon: Icons.bloodtype_outlined,
                  title: 'Unable to Request Blood',
                  message: options.requestBlock?.message ??
                      'You cannot create a request right now.',
                  actionLabel:
                      options.requestBlock?.action == 'verify' ? 'Verify Now' : null,
                  onAction: options.requestBlock?.action == 'verify'
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const VerifyScreen()),
                          )
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              _stepIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_step1(options), _step2(options), _step3(options)],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Frame ───────────────────────────────────────────────────────────────

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
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
          icon: Icons.close_rounded,
          tooltip: 'Close',
          onTap: _confirmDiscard,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Blood',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Step ${_step + 1} of 3 · ${_stepNames[_step]}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _stepIndicator() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Column(
      children: [
        Row(
          children: List.generate(3, (i) {
            final active = i <= _step;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                height: 5,
                decoration: BoxDecoration(
                  color: active ? kCrimson : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(3, (i) {
            final current = i == _step;
            return Expanded(
              child: Text(
                _stepNames[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: current ? kCrimson : kTextMuted,
                ),
              ),
            );
          }),
        ),
      ],
    ),
  );

  Widget _bottomBar() {
    final valid = _currentStepValid;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (_step > 0) ...[
                Expanded(
                  child: OutlineBtn(
                    label: 'Back',
                    onTap: _submitting ? () {} : _back,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: valid ? kCrimson : const Color(0xFFE5E7EB),
                      foregroundColor: valid ? Colors.white : kTextMuted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(
                            _step == 2 ? 'Submit Request' : 'Continue',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kTextMuted, fontSize: 13),
    filled: true,
    fillColor: kInputFill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kCrimson, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
    ),
  );

  Widget _fieldError(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: const TextStyle(fontSize: 11, color: kCrimson)),
  );

  Widget _infoBanner(IconData icon, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2563EB), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), height: 1.4),
          ),
        ),
      ],
    ),
  );

  // ─── Step 1 — Patient & Hospital ────────────────────────────────────────

  Widget _step1(RequestFormOptions options) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _infoBanner(
        Icons.lock_outline_rounded,
        "Only you and the eDonate team can see the patient's name and your contact details.",
      ),
      const SizedBox(height: 18),
      _fieldLabel("Patient's full name"),
      TextField(
        controller: _patientNameCtrl,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _errors.remove('patient_name')),
        decoration: _inputDecoration('e.g. Maria Santos'),
      ),
      if (_errors['patient_name'] != null) _fieldError(_errors['patient_name']!),
      const SizedBox(height: 18),
      _fieldLabel('Your relationship to the patient'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.relationships.map((r) {
          final selected = _relationship == r.value;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _relationship = r.value;
                _errors.remove('relationship');
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? kCrimson : Colors.white,
                border: Border.all(color: selected ? kCrimson : kBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    r.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : kTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      if (_errors['relationship'] != null) _fieldError(_errors['relationship']!),
      const SizedBox(height: 18),
      _fieldLabel('Hospital or facility'),
      InkWell(
        onTap: _pickFacility,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: kInputFill,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_hospital_outlined, color: kTextMuted, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: _facility == null
                    ? const Text(
                        'Select a hospital or facility',
                        style: TextStyle(color: kTextMuted, fontSize: 14),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _facility!.name,
                            style: const TextStyle(
                              fontSize: 14,
                              color: kTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_facility!.typeLabel} · ${_facility!.locationLine}',
                            style: const TextStyle(fontSize: 11, color: kTextMuted),
                          ),
                        ],
                      ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: kTextMuted),
            ],
          ),
        ),
      ),
      if (_errors['facility_id'] != null) _fieldError(_errors['facility_id']!),
      const SizedBox(height: 18),
      _fieldLabel('Hospital reference number (optional)'),
      TextField(controller: _hospitalRefCtrl, decoration: _inputDecoration('e.g. PT-0042')),
      const SizedBox(height: 6),
      const Text(
        'Patient or chart number, if the hospital gave you one.',
        style: TextStyle(fontSize: 11, color: kTextMuted),
      ),
    ],
  );

  // ─── Step 2 — Blood Needed ──────────────────────────────────────────────

  Widget _step2(RequestFormOptions options) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _fieldLabel("Patient's blood type"),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
        children: options.bloodTypes.map((bt) {
          final selected = _bloodType == bt.bloodType;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _bloodType = bt.bloodType;
                _bloodTypeId = bt.bloodTypeId;
                _errors.remove('blood_type_id');
              });
            },
            child: AnimatedScale(
              scale: selected ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)])
                      : null,
                  color: selected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? Colors.transparent : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: kCrimson.withValues(alpha: .3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(16, 20),
                      painter: _MiniDropPainter(color: selected ? Colors.white : kCrimson),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bt.bloodType,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : kTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
      if (_errors['blood_type_id'] != null) _fieldError(_errors['blood_type_id']!),
      if (_bloodType != null) ...[
        const SizedBox(height: 10),
        Text(
          'Compatible donors: ${_compatibleDonors(_bloodType!).join(', ')}',
          style: const TextStyle(fontSize: 12, color: kTextMuted),
        ),
      ],
      const SizedBox(height: 24),
      _fieldLabel('Donors needed'),
      _stepperCard(
        value: _donorsNeeded,
        unitLabel: 'donor(s)',
        min: 1,
        max: options.maxDonors,
        onChanged: (v) => setState(() {
          _donorsNeeded = v;
          if (_specificMatchRequired > _donorsNeeded) {
            _specificMatchRequired = _donorsNeeded;
          }
        }),
      ),
      const SizedBox(height: 6),
      const Text(
        'Hospitals usually ask for 1–3 replacement donors per blood unit.',
        style: TextStyle(fontSize: 11, color: kTextMuted),
      ),
      const SizedBox(height: 18),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: kCrimson,
        value: _allowOtherTypes,
        onChanged: (v) => setState(() {
          _allowOtherTypes = v;
          if (v && _specificMatchRequired > _donorsNeeded) {
            _specificMatchRequired = _donorsNeeded;
          }
          if (v && _specificMatchRequired < 1 && _donorsNeeded > 0) {
            _specificMatchRequired = 1;
          }
        }),
        title: const Text(
          'Any blood type can donate as a replacement',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPrimary),
        ),
        subtitle: const Text(
          'Many hospitals accept any blood type from replacement donors — this '
          'helps you find donors faster.',
          style: TextStyle(fontSize: 11, color: kTextMuted, height: 1.4),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        child: _allowOtherTypes
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Must be type or compatible'),
                    _stepperCard(
                      value: _specificMatchRequired,
                      unitLabel: 'donor(s)',
                      min: 0,
                      max: _donorsNeeded,
                      onChanged: (v) => setState(() => _specificMatchRequired = v),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'The rest can be any blood type.',
                      style: TextStyle(fontSize: 11, color: kTextMuted),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 24),
      _fieldLabel('How urgent is it?'),
      ...options.urgencies.map(
        (u) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _urgencyCard(u)),
      ),
      const SizedBox(height: 10),
      _fieldLabel('Needed by'),
      InkWell(
        onTap: _pickNeededByDate,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: kInputFill,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, color: kTextMuted, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: _neededBy == null
                    ? const Text('Select a date', style: TextStyle(color: kTextMuted, fontSize: 14))
                    : Row(
                        children: [
                          Text(
                            _formatFullDayDate(_neededBy!),
                            style: const TextStyle(
                              fontSize: 14,
                              color: kTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            brRelativeDay(_neededBy!),
                            style: const TextStyle(fontSize: 12, color: kTextMuted),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      if (_errors['needed_by'] != null) _fieldError(_errors['needed_by']!),
    ],
  );

  Widget _stepperCard({
    required int value,
    required String unitLabel,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: kInputFill,
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stepperButton(Icons.remove_rounded, value > min ? () => onChanged(value - 1) : null),
        Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kTextPrimary),
            ),
            Text(unitLabel, style: const TextStyle(fontSize: 11, color: kTextMuted)),
          ],
        ),
        _stepperButton(Icons.add_rounded, value < max ? () => onChanged(value + 1) : null),
      ],
    ),
  );

  Widget _stepperButton(IconData icon, VoidCallback? onTap) => InkWell(
    onTap: onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onTap();
          },
    customBorder: const CircleBorder(),
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onTap == null ? const Color(0xFFE5E7EB) : Colors.white,
        border: Border.all(color: kBorder),
        boxShadow: onTap == null
            ? null
            : const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Icon(icon, size: 18, color: onTap == null ? kTextMuted : kCrimson),
    ),
  );

  Widget _urgencyCard(UrgencyOption u) {
    final selected = _urgency == u.value;
    final color = u.value == 'critical'
        ? kCrimson
        : u.value == 'high'
            ? const Color(0xFFEA580C)
            : const Color(0xFF2563EB);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _urgency = u.value);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .06) : Colors.white,
          border: Border.all(color: selected ? color : kBorder, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextPrimary),
                  ),
                  Text(u.description, style: const TextStyle(fontSize: 12, color: kTextMuted)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? color : kBorder,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 3 — Contact & Review ──────────────────────────────────────────

  Widget _step3(RequestFormOptions options) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _fieldLabel('Contact number'),
      TextField(
        controller: _contactCtrl,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() => _errors.remove('contact_number')),
        decoration: _inputDecoration('09XXXXXXXXX'),
      ),
      if (_errors['contact_number'] != null) _fieldError(_errors['contact_number']!),
      const SizedBox(height: 6),
      const Text(
        'The eDonate team may call to confirm your request.',
        style: TextStyle(fontSize: 11, color: kTextMuted),
      ),
      const SizedBox(height: 20),
      _fieldLabel('Note for donors (optional)'),
      TextField(
        controller: _notesCtrl,
        maxLines: 4,
        maxLength: options.notesMaxLength,
        onChanged: (_) => setState(() {}),
        decoration: _inputDecoration(
          'e.g. Surgery on Friday. Please mention the reference number at the blood bank.',
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.visibility_rounded, size: 13, color: Color(0xFFD97706)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              "Visible to all donors. Don't include the patient's name or diagnosis.",
              style: TextStyle(fontSize: 11, color: Color(0xFFD97706), height: 1.4),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _reviewCard(),
      const SizedBox(height: 18),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: kCrimson,
        value: _consent,
        onChanged: (v) => setState(() {
          _consent = v ?? false;
          _errors.remove('consent');
        }),
        title: const Text(
          'I confirm this request is genuine and the patient is at the selected '
          'facility. False requests may lead to account suspension.',
          style: TextStyle(fontSize: 12, color: kTextPrimary, height: 1.4),
        ),
      ),
      if (_errors['consent'] != null) _fieldError(_errors['consent']!),
      const SizedBox(height: 8),
      Text(
        options.autoApprove
            ? 'Your request will be visible to matching donors right away.'
            : "The eDonate team reviews every request before it's shown to donors.",
        style: const TextStyle(fontSize: 11, color: kTextMuted),
      ),
    ],
  );

  Widget _reviewCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BloodDropBadge(bloodType: _bloodType, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _facility?.name ?? '—',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                      _editLink(0),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _requirementText(),
                    style: const TextStyle(fontSize: 12, color: kTextMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            UrgencyChip(urgency: _urgency),
            const SizedBox(width: 8),
            if (_neededBy != null)
              Expanded(
                child: Text(
                  'Needed by ${_neededByShort()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextPrimary),
                ),
              ),
            _editLink(1),
          ],
        ),
        const Divider(height: 28, color: Color(0xFFF3F4F6)),
        Row(
          children: [
            const Icon(Icons.lock_rounded, size: 14, color: kTextMuted),
            const SizedBox(width: 6),
            const Text(
              'PRIVATE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kTextMuted, letterSpacing: 0.6),
            ),
            const Spacer(),
            _editLink(0),
          ],
        ),
        const SizedBox(height: 8),
        _reviewRow(
          'Patient',
          _patientNameCtrl.text.trim().isEmpty ? '—' : _patientNameCtrl.text.trim(),
        ),
        _reviewRow('Relationship', _relationshipLabel()),
        _reviewRow(
          'Contact',
          _contactCtrl.text.trim().isEmpty ? '—' : _contactCtrl.text.trim(),
        ),
        if (_hospitalRefCtrl.text.trim().isNotEmpty)
          _reviewRow('Hospital ref.', _hospitalRefCtrl.text.trim()),
      ],
    ),
  );

  Widget _editLink(int step) => GestureDetector(
    onTap: () => _goToStep(step),
    child: const Text(
      'Edit',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kCrimson),
    ),
  );

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: kTextMuted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextPrimary),
          ),
        ),
      ],
    ),
  );
}

class _MiniDropPainter extends CustomPainter {
  final Color color;
  _MiniDropPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.5, 0, 0, h * 0.42, 0, h * 0.66)
      ..cubicTo(0, h * 0.87, w * 0.25, h, w * 0.5, h)
      ..cubicTo(w * 0.75, h, w, h * 0.87, w, h * 0.66)
      ..cubicTo(w, h * 0.42, w * 0.5, 0, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniDropPainter oldDelegate) => oldDelegate.color != color;
}

// ─── Facility picker sheet ──────────────────────────────────────────────────

class _FacilityPickerSheet extends StatefulWidget {
  final List<BloodRequestFacility> facilities;
  final BloodRequestFacility? selected;
  const _FacilityPickerSheet({required this.facilities, this.selected});

  @override
  State<_FacilityPickerSheet> createState() => _FacilityPickerSheetState();
}

class _FacilityPickerSheetState extends State<_FacilityPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'blood_bank':
        return Icons.bloodtype_rounded;
      case 'clinic':
        return Icons.medical_services_rounded;
      case 'health_center':
        return Icons.health_and_safety_rounded;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.facilities.where((f) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return f.name.toLowerCase().contains(q) ||
          (f.barangay ?? '').toLowerCase().contains(q);
    }).toList();

    final grouped = <String, List<BloodRequestFacility>>{};
    for (final f in filtered) {
      grouped.putIfAbsent(f.typeLabel.isEmpty ? 'Other' : f.typeLabel, () => []).add(f);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(999)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search by name or barangay',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: kInputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kCrimson, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No facilities found', style: TextStyle(color: kTextMuted)),
                  )
                : ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: grouped.entries
                        .expand(
                          (entry) => [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTextMuted,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...entry.value.map((f) {
                              final isSelected = widget.selected?.facilityId == f.facilityId;
                              return InkWell(
                                onTap: () => Navigator.pop(context, f),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF1F1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(_iconFor(f.type), color: kCrimson, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              f.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: kTextPrimary,
                                              ),
                                            ),
                                            Text(
                                              f.locationLine,
                                              style: const TextStyle(fontSize: 11, color: kTextMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, color: kCrimson, size: 20),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Submitted screen ───────────────────────────────────────────────────────

class BloodRequestSubmittedScreen extends StatelessWidget {
  final BloodRequest request;
  const BloodRequestSubmittedScreen({super.key, required this.request});

  bool get _pending => request.status == 'pending_review';

  void _copyReference(BuildContext context) {
    Clipboard.setData(ClipboardData(text: request.reference));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('Reference copied'),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _pending
        ? const [
            'eDonate reviews your request',
            'Matching donors can volunteer',
            'Donors visit facility and mention your reference',
          ]
        : const [
            'Matching donors can volunteer',
            'Donors visit facility and mention your reference',
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(color: const Color(0xFFBBF7D0), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF16A34A).withValues(alpha: .2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, size: 54, color: Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _pending ? 'Request Submitted' : 'Your Request Is Live',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: kTextPrimary),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _copyReference(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: kBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          request.reference,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy_rounded, size: 16, color: kTextMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What happens next',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kTextPrimary),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(
                        steps.length,
                        (i) => _stepRow(i + 1, steps[i], i == steps.length - 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'View Request',
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => BloodRequestDetailScreen(requestId: request.requestId),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done', style: TextStyle(color: kTextMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(int number, String label, bool isLast) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: kCrimson),
                child: Text(
                  '$number',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: const Color(0xFFE5E7EB))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 3),
              child: Text(label, style: const TextStyle(fontSize: 13, color: kTextPrimary, height: 1.3)),
            ),
          ),
        ],
      ),
    ),
  );
}
