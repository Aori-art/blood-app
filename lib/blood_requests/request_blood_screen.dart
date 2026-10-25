// The 3-step "Request Blood" wizard: a request to a HOSPITAL (Patient → Blood
// → Hospital & Review), plus the photo of the hospital's request form. The
// screen shown after sending is HospitalRequestSubmittedScreen.
import 'package:flutter/material.dart';
import 'package:blood/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home_nav.dart';
import '../shared_design.dart';
import '../verify.dart';
import 'blood_request_api.dart';
import 'blood_request_models.dart';
import 'blood_request_widgets.dart';
import 'blood_requests_screen.dart';
import 'hospital_request_api.dart';
import 'hospital_request_models.dart';
import 'hospital_request_widgets.dart';
import '../app_palette.dart';

const _stepNames = ['Patient', 'Blood', 'Hospital'];
const _monthsShort = [
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
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

final _phMobile = RegExp(r'^(09\d{9}|\+639\d{9})$');

class RequestBloodScreen extends StatefulWidget {
  const RequestBloodScreen({
    super.key,
    this.photoPicker = const ImagePickerFormPhotoPicker(),
  });

  /// Where the form photo comes from (tests give a fake).
  final FormPhotoPicker photoPicker;

  @override
  State<RequestBloodScreen> createState() => _RequestBloodScreenState();
}

class _RequestBloodScreenState extends State<RequestBloodScreen> {
  // One per form session: a retried send is the same request to the server.
  late final String _submissionKey;
  late final PageController _pageCtrl;
  final _hospitalStepCtrl = ScrollController();

  HospitalRequestOptions? _options;
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
  FormPhoto? _photo;

  // Step 2
  String? _bloodType;
  int? _bloodTypeId;
  String? _component;
  int _units = 1;
  String _urgency = 'normal';
  DateTime? _neededBy;

  // "Myself" auto-fill — remembers what the relationship chip filled in, so
  // switching away only clears values the user never touched themselves.
  String? _autoFilledName;
  int? _autoFilledBloodTypeId;

  // Step 3
  BloodRequestFacility? _facility;
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _inStockOnly = false;
  Map<int, StockAvailability>? _availability;
  int? _availabilityFor;
  bool _availabilityLoading = false;
  bool _availabilityFailed = false;
  int _availabilityToken = 0;
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
    _hospitalStepCtrl.dispose();
    _patientNameCtrl.dispose();
    _hospitalRefCtrl.dispose();
    _searchCtrl.dispose();
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
      final options = await HospitalRequestApi.fetchOptions(_donorId);
      if (!mounted) return;
      setState(() {
        _options = options;
        _contactCtrl.text = options.defaultContactNumber;
        final components = options.components.map((c) => c.value);
        _component = components.contains('whole_blood')
            ? 'whole_blood'
            : (components.isEmpty ? null : components.first);
        final urgencies = options.urgencies.map((u) => u.value);
        if (urgencies.isNotEmpty && !urgencies.contains(_urgency)) {
          _urgency = urgencies.first;
        }
        _units = _units.clamp(1, options.maxUnits);
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

  // ─── Availability ───────────────────────────────────────────────────────

  /// Loads each hospital's stock of the chosen blood type (newest call wins).
  Future<void> _loadAvailability() async {
    final typeId = _bloodTypeId;
    if (typeId == null) return;
    final token = ++_availabilityToken;
    setState(() {
      _availability = null;
      _availabilityFor = typeId;
      _availabilityLoading = true;
      _availabilityFailed = false;
    });
    try {
      final map = await HospitalRequestApi.fetchAvailability(typeId);
      if (!mounted || token != _availabilityToken) return;
      setState(() {
        _availability = map;
        _availabilityLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _availabilityToken) return;
      setState(() {
        _availabilityLoading = false;
        _availabilityFailed = true;
        _inStockOnly = false;
      });
    }
  }

  /// The hospital step opened: load the stock unless it is already there
  /// (or on its way) for this blood type.
  void _ensureAvailability() {
    if (_bloodTypeId == null) return;
    if (_availabilityFor == _bloodTypeId &&
        (_availabilityLoading || _availability != null)) {
      return;
    }
    _loadAvailability();
  }

  StockAvailability? _stockOf(BloodRequestFacility f) {
    final map = _availability;
    if (map == null) return null;
    return map[f.facilityId] ?? StockAvailability.unknown(f.facilityId);
  }

  void _setBloodType(BloodTypeOption bt) {
    final changed = _bloodTypeId != bt.bloodTypeId;
    _bloodType = bt.bloodType;
    _bloodTypeId = bt.bloodTypeId;
    _errors.remove('blood_type_id');
    // Once the hospitals were shown, a new type reloads their stock.
    if (changed && _availabilityFor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAvailability();
      });
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _relationshipLabel() {
    final matches = (_options?.relationships ?? const []).where(
      (r) => r.value == _relationship,
    );
    return matches.isEmpty ? '—' : matches.first.label;
  }

  ComponentOption? get _componentOption {
    for (final c in _options?.components ?? const <ComponentOption>[]) {
      if (c.value == _component) return c;
    }
    return null;
  }

  // "Myself" fills in the patient name and blood type from the donor's own
  // profile — re-applied every time the chip is tapped (even if already
  // selected), so it always reflects the latest defaults.
  void _applySelfDefaults(HospitalRequestOptions options) {
    final name = options.defaultFullName;
    if (name != null && name.isNotEmpty) {
      _patientNameCtrl.text = name;
      _autoFilledName = name;
      _errors.remove('patient_name');
    }
    final btId = options.defaultBloodTypeId;
    if (btId != null) {
      for (final b in options.bloodTypes) {
        if (b.bloodTypeId == btId && !b.isUnknown) {
          _setBloodType(b);
          _autoFilledBloodTypeId = b.bloodTypeId;
          break;
        }
      }
    }
  }

  // Clears only what "Myself" filled in and the user never edited — anything
  // the user typed or picked themselves is left untouched.
  void _clearSelfDefaults() {
    if (_autoFilledName != null && _patientNameCtrl.text == _autoFilledName) {
      _patientNameCtrl.clear();
    }
    if (_autoFilledBloodTypeId != null &&
        _bloodTypeId == _autoFilledBloodTypeId) {
      _bloodType = null;
      _bloodTypeId = null;
    }
    _autoFilledName = null;
    _autoFilledBloodTypeId = null;
  }

  String _formatFullDayDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';

  String _neededByShort() {
    if (_neededBy == null) return '';
    return '${_monthsShort[_neededBy!.month - 1]} ${_neededBy!.day}';
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  bool get _phoneValid =>
      _phMobile.hasMatch(_contactCtrl.text.replaceAll(RegExp(r'[\s-]'), ''));

  // ─── Steps ──────────────────────────────────────────────────────────────

  /// The fields each step owns (server errors jump to the first step that
  /// has one).
  List<String> _fieldsForStep(int step) => switch (step) {
    0 => ['patient_name', 'relationship', 'hospital_reference', 'document'],
    1 => [
      'blood_type_id',
      'blood_component',
      'units_requested',
      'urgency',
      'needed_by',
    ],
    _ => ['facility_id', 'contact_number', 'notes', 'consent'],
  };

  Map<String, String> _stepErrors(int step) {
    final options = _options!;
    final errs = <String, String>{};
    if (step == 0) {
      if (_patientNameCtrl.text.trim().length < 2) {
        errs['patient_name'] = "Please enter the patient's full name.";
      }
      if (_relationship == null) {
        errs['relationship'] =
            'Please select your relationship to the patient.';
      }
      if (options.documentRequired && _photo == null) {
        errs['document'] =
            "Please add a photo of the hospital's blood request form.";
      }
    } else if (step == 1) {
      if (_bloodType == null) {
        errs['blood_type_id'] = "Please select the patient's blood type.";
      }
      if (_component == null) {
        errs['blood_component'] = 'Please choose what the patient needs.';
      }
      if (_units < 1 || _units > options.maxUnits) {
        errs['units_requested'] =
            'Choose between 1 and ${options.maxUnits} units.';
      }
      if (_neededBy == null) {
        errs['needed_by'] = 'Please select a date.';
      }
    } else {
      if (_facility == null) {
        errs['facility_id'] = 'Please choose a hospital.';
      }
      if (!_phoneValid) {
        errs['contact_number'] =
            'Enter a valid PH mobile number (e.g. 09171234567).';
      }
      if (!_consent) {
        errs['consent'] = 'Please confirm before sending.';
      }
    }
    return errs;
  }

  bool _validateStep(int step) {
    final errs = _stepErrors(step);
    setState(() {
      _errors.removeWhere((k, _) => _fieldsForStep(step).contains(k));
      _errors.addAll(errs);
    });
    return errs.isEmpty;
  }

  bool get _currentStepValid => _stepErrors(_step).isEmpty;

  void _onStepShown(int step) {
    if (step == 2) _ensureAvailability();
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageCtrl.jumpToPage(step);
    _onStepShown(step);
  }

  void _next() {
    if (!_validateStep(_step)) return;
    if (_step == 2) {
      _submit();
      return;
    }
    setState(() => _step += 1);
    _onStepShown(_step);
    _pageCtrl.animateToPage(
      _step,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
    _pageCtrl.animateToPage(
      _step,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int _stepForFirstError(Iterable<String> keys) {
    for (var i = 0; i < 3; i++) {
      if (keys.any(_fieldsForStep(i).contains)) return i;
    }
    return _step;
  }

  /// Back to the hospital list (the review's Edit for the hospital).
  void _showHospitalList() {
    if (!_hospitalStepCtrl.hasClients) return;
    _hospitalStepCtrl.animateTo(
      0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _confirmDiscard() async {
    final hasEntered =
        _patientNameCtrl.text.isNotEmpty ||
        _relationship != null ||
        _photo != null ||
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
            child: Text(
              'Discard',
              style: TextStyle(color: context.palette.primaryText),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
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
      // Light keeps its look; dark inherits the app's dark theme.
      builder: (context, child) => context.palette.isDark
          ? child!
          : Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: kCrimson,
                  onPrimary: Colors.white,
                  onSurface: AppColors.foreground,
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

  // ─── The form photo ─────────────────────────────────────────────────────

  Future<void> _pickPhoto(FormPhotoSource source) async {
    final options = _options!;
    FormPhoto? photo;
    try {
      photo = await widget.photoPicker.pick(source);
    } catch (_) {
      _showSnack(
        source == FormPhotoSource.camera
            ? "Couldn't open the camera. Try choosing from your gallery."
            : "Couldn't open your photos. Try taking a photo instead.",
        isError: true,
      );
      return;
    }
    if (photo == null || !mounted) return;
    final picked = photo;
    setState(() {
      if (picked.extension == null) {
        _errors['document'] = 'Please use a JPG, PNG or WebP photo.';
      } else if (picked.sizeBytes > options.documentMaxBytes) {
        _errors['document'] =
            'This photo is ${_mb(picked.sizeBytes)} MB. The limit is '
            '${options.documentMaxMb} MB: please use a smaller photo.';
      } else {
        _photo = picked;
        _errors.remove('document');
      }
    });
  }

  Future<void> _replacePhoto() async {
    final source = await showModalBottomSheet<FormPhotoSource>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.photo_camera_outlined,
                  color: c.palette.primaryText,
                ),
                title: Text(
                  'Take photo',
                  style: TextStyle(color: c.palette.foreground),
                ),
                onTap: () => Navigator.pop(c, FormPhotoSource.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: c.palette.primaryText,
                ),
                title: Text(
                  'Choose from gallery',
                  style: TextStyle(color: c.palette.foreground),
                ),
                onTap: () => Navigator.pop(c, FormPhotoSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  // ─── Hospital contact ───────────────────────────────────────────────────

  void _copyNumber(String number) {
    Clipboard.setData(ClipboardData(text: number));
    _showSnack('Number copied');
  }

  Future<void> _call(String number) async {
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: number));
      if (!opened) throw Exception('not opened');
    } catch (_) {
      _showSnack("Couldn't open the phone app.", isError: true);
    }
  }

  void _openMyRequests() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const BloodRequestsScreen(initialTab: 1),
      ),
    );
  }

  void _openVerify() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerifyScreen()),
    );
  }

  // ─── Sending ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final request = buildSubmitRequest(
      donorId: _donorId,
      submissionKey: _submissionKey,
      facilityId: _facility!.facilityId,
      bloodTypeId: _bloodTypeId!,
      bloodComponent: _component!,
      unitsRequested: _units,
      urgency: _urgency,
      neededBy: _neededBy!,
      patientName: _patientNameCtrl.text,
      relationship: _relationship!,
      contactNumber: _contactCtrl.text,
      hospitalReference: _hospitalRefCtrl.text,
      notes: _notesCtrl.text,
      document: _photo,
    );

    try {
      final result = await HospitalRequestApi.submit(request);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      // pushReplacement's `result` immediately resolves whoever awaited the
      // Navigator.push that opened this screen — this both hands the caller
      // `true` (so it knows to reload) and swaps this screen for the
      // sent-confirmation screen in one step.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HospitalRequestSubmittedScreen(
            request: result.request,
            hospitalName: _facility?.name,
          ),
        ),
        result: true,
      );
    } on BloodRequestApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _onServerError(e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(
        "Couldn't send your request. Check your connection and try again.",
        isError: true,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _submit,
        ),
      );
    }
  }

  void _onServerError(BloodRequestApiException e) {
    switch (e.code) {
      case 'VALIDATION_FAILED':
        final errors = e.errors ?? const <String, String>{};
        final step = _stepForFirstError(errors.keys);
        setState(() => _errors.addAll(errors));
        if (step != _step) _goToStep(step);
        _showSnack(e.message, isError: true);
      case 'NOT_VERIFIED':
        _showActionDialog(
          title: 'Verify your account first',
          message: e.message,
          actionLabel: 'Verify Now',
          onAction: _openVerify,
        );
      case 'MAX_ACTIVE':
        _showActionDialog(
          title: 'Too many active requests',
          message: e.message,
          actionLabel: 'View My Requests',
          onAction: _openMyRequests,
        );
      case 'FACILITY_UNAVAILABLE':
        setState(() => _errors['facility_id'] = e.message);
        if (_step != 2) _goToStep(2);
        _loadAvailability();
        _showHospitalList();
      case 'DUPLICATE_REQUEST':
        _showSnack(
          e.message,
          isError: true,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: _openMyRequests,
          ),
        );
      default:
        _showSnack(e.message, isError: true);
    }
  }

  Future<void> _showActionDialog({
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              actionLabel,
              style: TextStyle(color: context.palette.primaryText),
            ),
          ),
        ],
      ),
    );
    if (go == true && mounted) onAction();
  }

  void _showSnack(
    String message, {
    bool isError = false,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
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
        action: action,
        backgroundColor: isError ? kCrimson : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingOptions) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(
              color: context.palette.primaryText,
            ),
          ),
        ),
      );
    }
    if (_optionsError) {
      return Scaffold(
        backgroundColor: context.palette.background,
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
      final verify = options.requestBlock?.action == 'verify';
      return Scaffold(
        backgroundColor: context.palette.background,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: context.palette.foreground,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: BrEmptyState(
                  icon: Icons.bloodtype_outlined,
                  title: 'Unable to Request Blood',
                  message:
                      options.requestBlock?.message ??
                      'You cannot create a request right now.',
                  actionLabel: verify ? 'Verify Now' : null,
                  onAction: verify ? _openVerify : null,
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
        backgroundColor: context.palette.background,
        body: SafeArea(
          bottom: false,
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
            ],
          ),
        ),
        // In the Scaffold's slot, so a SnackBar floats above it instead of
        // covering the buttons.
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  // ─── Frame ──────────────────────────────────────────────────────────────

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(11, 7, 16, 13),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: kHeaderGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        _closeButton(),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Blood',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Step ${_step + 1} of 3 · ${_stepNames[_step]}',
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// The header's close button (HeaderIconButton's 38 px look) in a 48 px
  /// target; the header's padding is 5 px less around it, so it sits where
  /// it always did.
  Widget _closeButton() => Tooltip(
    message: 'Close',
    child: Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      child: InkResponse(
        onTap: _confirmDiscard,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16),
                border: Border.all(color: Colors.white30, width: 1.2),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _stepIndicator() => Container(
    color: context.palette.surface,
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
                  color: active ? kCrimson : context.palette.border,
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
                  color: current
                      ? context.palette.primaryText
                      : context.palette.muted,
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
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
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
                      backgroundColor: valid
                          ? kCrimson
                          : context.palette.border,
                      foregroundColor: valid
                          ? Colors.white
                          : context.palette.muted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _step == 2 ? 'Send Request' : 'Continue',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
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

  InputDecoration _inputDecoration(
    String hint, {
    Widget? prefixIcon,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.palette.muted, fontSize: 13),
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: context.palette.surfaceAlt,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.palette.primaryText, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.palette.foreground,
      ),
    ),
  );

  Widget _fieldError(String key) {
    final text = _errors[key];
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: ValueKey('error-$key'),
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: context.palette.primaryText),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: context.palette.muted),
    ),
  );

  Widget _infoBanner(IconData icon, String text, {Key? key}) => Container(
    key: key,
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.palette.infoBg,
      border: Border.all(color: context.palette.infoBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.palette.info, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.infoText,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _autoFilledPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.palette.infoBg,
      border: Border.all(color: context.palette.infoBorder),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_rounded, size: 13, color: context.palette.info),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Filled from your profile',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.palette.info,
            ),
          ),
        ),
      ],
    ),
  );

  /// A single-choice card (component, urgency): a dot, a title and a line.
  Widget _choiceCard({
    required String label,
    required String description,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) => Semantics(
    container: true,
    button: true,
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: .06)
              : context.palette.surface,
          border: Border.all(
            color: selected ? color : context.palette.border,
            width: selected ? 1.5 : 1,
          ),
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
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.palette.foreground,
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? color : context.palette.faint,
            ),
          ],
        ),
      ),
    ),
  );

  // ─── Step 1 — Patient ───────────────────────────────────────────────────

  Widget _step1(HospitalRequestOptions options) => ListView(
    key: const PageStorageKey('step-patient'),
    padding: const EdgeInsets.all(16),
    children: [
      _infoBanner(
        Icons.lock_outline_rounded,
        "Only you and the hospital see the patient's name, the form photo "
        'and your contact details.',
      ),
      const SizedBox(height: 18),
      _fieldLabel("Patient's full name"),
      TextField(
        controller: _patientNameCtrl,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _errors.remove('patient_name')),
        decoration: _inputDecoration('e.g. Maria Santos'),
      ),
      _fieldError('patient_name'),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child:
            (_relationship == 'self' &&
                _autoFilledName != null &&
                _patientNameCtrl.text == _autoFilledName)
            ? Padding(
                key: const ValueKey('name_autofill_pill'),
                padding: const EdgeInsets.only(top: 8),
                child: _autoFilledPill(),
              )
            : const SizedBox.shrink(key: ValueKey('no_name_autofill_pill')),
      ),
      const SizedBox(height: 18),
      _fieldLabel('Your relationship to the patient'),
      Wrap(
        spacing: 8,
        children: options.relationships
            .map((r) => _relationshipChip(options, r))
            .toList(),
      ),
      _fieldError('relationship'),
      const SizedBox(height: 18),
      _fieldLabel('Hospital request or chart number (optional)'),
      TextField(
        controller: _hospitalRefCtrl,
        onChanged: (_) => setState(() => _errors.remove('hospital_reference')),
        decoration: _inputDecoration('e.g. PT-0042'),
      ),
      _fieldError('hospital_reference'),
      _hint('If the hospital gave you one.'),
      const SizedBox(height: 22),
      _photoCard(options),
      _fieldError('document'),
    ],
  );

  /// A relationship chip: the pill as before, in a 48 px tall target.
  Widget _relationshipChip(
    HospitalRequestOptions options,
    RelationshipOption r,
  ) {
    final selected = _relationship == r.value;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            final wasSelf = _relationship == 'self';
            _relationship = r.value;
            _errors.remove('relationship');
            if (r.value == 'self') {
              _applySelfDefaults(options);
            } else if (wasSelf) {
              _clearSelfDefaults();
            }
          });
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? kCrimson : context.palette.surface,
                border: Border.all(
                  color: selected
                      ? context.palette.primaryText
                      : context.palette.border,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : context.palette.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoCard(HospitalRequestOptions options) {
    final photo = _photo;
    final p = context.palette;
    return Container(
      key: const ValueKey('form-photo-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(
          color: _errors.containsKey('document') ? p.primaryText : p.border,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.accentBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: p.primaryText,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Photo of the hospital's blood request form",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      options.documentRequired
                          ? 'Required · up to ${options.documentMaxMb} MB'
                          : 'Optional · up to ${options.documentMaxMb} MB',
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Ask the hospital for its blood request form signed by the doctor "
            'and take a clear photo of it.',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (photo == null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _pickPhoto(FormPhotoSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kCrimson,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(FormPhotoSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Choose from gallery'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.primaryText,
                  side: BorderSide(color: p.primaryBorder),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                _thumbnail(photo.bytes, 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: p.success,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Form photo added',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: p.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_mb(photo.sizeBytes)} MB',
                        style: TextStyle(fontSize: 11, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _replacePhoto,
                  icon: Icon(Icons.refresh_rounded, color: p.primaryText),
                  label: Text(
                    'Replace',
                    style: TextStyle(
                      color: p.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _photo = null),
                  icon: Icon(Icons.delete_outline_rounded, color: p.muted),
                  label: Text(
                    'Remove',
                    style: TextStyle(
                      color: p.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumbnail(Uint8List bytes, double size) => Semantics(
    image: true,
    label: 'Form photo',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size / 6),
      child: Container(
        width: size,
        height: size,
        color: context.palette.surfaceAlt,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => Icon(
            Icons.image_outlined,
            size: size / 2,
            color: context.palette.muted,
          ),
        ),
      ),
    ),
  );

  // ─── Step 2 — Blood ─────────────────────────────────────────────────────

  Widget _step2(HospitalRequestOptions options) => ListView(
    key: const PageStorageKey('step-blood'),
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
        children: options.bloodTypes
            .where((bt) => !bt.isUnknown)
            .map(_bloodTypeTile)
            .toList(),
      ),
      _fieldError('blood_type_id'),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child:
            (_relationship == 'self' &&
                _autoFilledBloodTypeId != null &&
                _bloodTypeId == _autoFilledBloodTypeId)
            ? Padding(
                key: const ValueKey('bloodtype_autofill_pill'),
                padding: const EdgeInsets.only(top: 10),
                child: _autoFilledPill(),
              )
            : const SizedBox.shrink(
                key: ValueKey('no_bloodtype_autofill_pill'),
              ),
      ),
      const SizedBox(height: 24),
      _fieldLabel('What does the patient need?'),
      ...options.components.map(
        (c) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _choiceCard(
            label: c.label,
            description: c.description,
            selected: _component == c.value,
            color: context.palette.primaryText,
            onTap: () => setState(() {
              _component = c.value;
              _errors.remove('blood_component');
            }),
          ),
        ),
      ),
      _fieldError('blood_component'),
      const SizedBox(height: 14),
      _fieldLabel('Units'),
      _stepperCard(
        value: _units,
        unitLabel: _units == 1 ? 'unit' : 'units',
        min: 1,
        max: options.maxUnits,
        onChanged: (v) => setState(() {
          _units = v;
          _errors.remove('units_requested');
        }),
      ),
      _fieldError('units_requested'),
      _hint("As written on the hospital's form."),
      const SizedBox(height: 24),
      _fieldLabel('How urgent is it?'),
      ...options.urgencies.map(
        (u) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _choiceCard(
            label: u.label,
            description: u.description,
            selected: _urgency == u.value,
            color: u.value == 'critical'
                ? context.palette.criticalText
                : u.value == 'high'
                ? context.palette.orange
                : context.palette.info,
            onTap: () => setState(() {
              _urgency = u.value;
              _errors.remove('urgency');
            }),
          ),
        ),
      ),
      _fieldError('urgency'),
      const SizedBox(height: 10),
      _fieldLabel('Needed by'),
      InkWell(
        onTap: _pickNeededByDate,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            border: Border.all(color: context.palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.event_rounded, color: context.palette.muted, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: _neededBy == null
                    ? Text(
                        'Select a date',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 14,
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _formatFullDayDate(_neededBy!),
                              style: TextStyle(
                                fontSize: 14,
                                color: context.palette.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '  ${brRelativeDay(_neededBy!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      _fieldError('needed_by'),
      _hint('Up to ${options.maxNeededByDays} days from today.'),
    ],
  );

  Widget _bloodTypeTile(BloodTypeOption bt) {
    final selected = _bloodTypeId == bt.bloodTypeId;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _setBloodType(bt));
        },
        child: AnimatedScale(
          scale: selected ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: AppColors.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: selected ? null : context.palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Colors.transparent : context.palette.border,
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
                  painter: _MiniDropPainter(
                    color: selected
                        ? Colors.white
                        : context.palette.primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bt.bloodType,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : context.palette.foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepperCard({
    required int value,
    required String unitLabel,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      border: Border.all(color: context.palette.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stepperButton(
          Icons.remove_rounded,
          'Fewer units',
          value > min ? () => onChanged(value - 1) : null,
        ),
        Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: context.palette.foreground,
              ),
            ),
            Text(
              unitLabel,
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            ),
          ],
        ),
        _stepperButton(
          Icons.add_rounded,
          'More units',
          value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );

  /// The 44 px round button as before, in a 48 px target.
  Widget _stepperButton(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        enabled: onTap != null,
        onTap: onTap,
        child: InkResponse(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: onTap == null
                      ? context.palette.border
                      : context.palette.surface,
                  border: Border.all(color: context.palette.border),
                  boxShadow: onTap == null
                      ? null
                      : const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: onTap == null
                      ? context.palette.muted
                      : context.palette.primaryText,
                ),
              ),
            ),
          ),
        ),
      );

  // ─── Step 3 — Hospital & Review ─────────────────────────────────────────

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

  /// The hospitals that match the search (and the stock filter): stock
  /// first (available, limited, not listed, out), then by name.
  List<BloodRequestFacility> _visibleFacilities(HospitalRequestOptions o) {
    final q = _query.trim().toLowerCase();
    final list = o.facilities.where((f) {
      if (q.isEmpty) return true;
      return f.name.toLowerCase().contains(q) ||
          (f.barangay ?? '').toLowerCase().contains(q) ||
          (f.city ?? '').toLowerCase().contains(q);
    }).toList();
    final stock = _availability;
    if (stock != null && _inStockOnly) {
      list.retainWhere((f) => _stockOf(f)!.level.hasStock);
    }
    list.sort((a, b) {
      if (stock != null) {
        final byStock = _stockOf(
          a,
        )!.level.sortRank.compareTo(_stockOf(b)!.level.sortRank);
        if (byStock != 0) return byStock;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Widget _step3(HospitalRequestOptions options) {
    final p = context.palette;
    final facilities = _visibleFacilities(options);
    final chosen = _facility;
    final chosenOut =
        chosen != null && _stockOf(chosen)?.level == StockLevel.out;
    return ListView(
      key: const PageStorageKey('step-hospital'),
      controller: _hospitalStepCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        _fieldLabel('Hospital'),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: _inputDecoration(
            'Search by name, barangay or city',
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: p.muted),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('In stock only'),
              selected: _inStockOnly,
              showCheckmark: true,
              onSelected: _availability == null
                  ? null
                  : (v) => setState(() => _inStockOnly = v),
            ),
            if (_availabilityFailed)
              TextButton.icon(
                key: const ValueKey('stock-retry'),
                onPressed: _loadAvailability,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: p.primaryText,
                ),
                label: Text(
                  "Couldn't load stock · Retry",
                  style: TextStyle(fontSize: 12, color: p.primaryText),
                ),
              ),
          ],
        ),
        if (_bloodType != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Stock of $_bloodType at each hospital. Hospitals share a '
              'level only, not a count.',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          ),
        _fieldError('facility_id'),
        const SizedBox(height: 8),
        if (facilities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _inStockOnly
                    ? 'No hospital with stock matches your search.'
                    : 'No hospitals match your search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted),
              ),
            ),
          ),
        ...facilities.map(_hospitalCard),
        if (chosenOut) ...[
          const SizedBox(height: 4),
          _infoBanner(
            Icons.info_outline_rounded,
            'This hospital is out of $_bloodType right now. You can still '
            'send your request: the hospital will tell you if it can help. '
            'Or pick another hospital that has stock.',
            key: const ValueKey('out-of-stock-banner'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => HomeNav.goTo(HomeTab.book),
              icon: Icon(
                Icons.volunteer_activism_rounded,
                size: 18,
                color: p.primaryText,
              ),
              label: Text(
                'Donate blood to help restock',
                style: TextStyle(
                  color: p.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _fieldLabel('Contact number'),
        TextField(
          controller: _contactCtrl,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() => _errors.remove('contact_number')),
          decoration: _inputDecoration('09XXXXXXXXX'),
        ),
        _fieldError('contact_number'),
        _hint('The hospital may call to confirm your request.'),
        const SizedBox(height: 20),
        _fieldLabel('Note for the hospital (optional)'),
        TextField(
          controller: _notesCtrl,
          maxLines: 4,
          maxLength: options.notesMaxLength,
          onChanged: (_) => setState(() => _errors.remove('notes')),
          decoration: _inputDecoration('e.g. Surgery on Friday morning.'),
        ),
        _fieldError('notes'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Only you and the hospital see this.',
                style: TextStyle(fontSize: 11, color: p.muted, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _reviewCard(options),
        const SizedBox(height: 18),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: p.primaryText,
          value: _consent,
          onChanged: (v) => setState(() {
            _consent = v ?? false;
            _errors.remove('consent');
          }),
          title: Text(
            'I confirm this request is genuine, the patient is under the care '
            'of the selected hospital, and I will bring the hospital\'s blood '
            'request form and a valid ID. False requests may lead to account '
            'suspension.',
            style: TextStyle(fontSize: 12, color: p.foreground, height: 1.4),
          ),
        ),
        _fieldError('consent'),
      ],
    );
  }

  Widget _hospitalCard(BloodRequestFacility f) {
    final p = context.palette;
    final selected = _facility?.facilityId == f.facilityId;
    final stock = _stockOf(f);
    final address = [
      f.address,
      f.barangay,
      f.city,
      f.province,
    ].where((e) => e != null && e.isNotEmpty).join(', ');
    final number = f.contactNumber;
    return Padding(
      key: ValueKey('hospital-${f.facilityId}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(
            color: selected ? p.primaryText : p.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Semantics(
              container: true,
              button: true,
              selected: selected,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _facility = f;
                    _errors.remove('facility_id');
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: p.accentBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _iconFor(f.type),
                          color: p.primaryText,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: p.foreground,
                              ),
                            ),
                            if (f.locationLine.isNotEmpty)
                              Text(
                                f.locationLine,
                                style: TextStyle(fontSize: 11, color: p.muted),
                              ),
                            if (_availabilityLoading) ...[
                              const SizedBox(height: 8),
                              const StockChipSkeleton(),
                            ] else if (stock != null) ...[
                              const SizedBox(height: 8),
                              StockChip(availability: stock),
                              if (stock.updatedAgo != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    'updated ${stock.updatedAgo}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: p.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: p.primaryText,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: !selected
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(height: 1, color: p.border),
                          if (address.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 8, 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 16,
                                    color: p.muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      address,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.foreground,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (number != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    label: 'Copy number $number',
                                    excludeSemantics: true,
                                    child: InkWell(
                                      onTap: () => _copyNumber(number),
                                      borderRadius: BorderRadius.circular(8),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 48,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.phone_outlined,
                                              size: 16,
                                              color: p.muted,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                number,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: p.foreground,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.copy_rounded,
                                              size: 14,
                                              color: p.muted,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Call ${f.name}',
                                  onPressed: () => _call(number),
                                  icon: Icon(
                                    Icons.call_rounded,
                                    color: p.primaryText,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(HospitalRequestOptions options) {
    final p = context.palette;
    final facility = _facility;
    final stock = facility == null ? null : _stockOf(facility);
    final component = _componentOption;
    final photo = _photo;
    return Container(
      key: const ValueKey('review-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        facility?.name ?? 'No hospital chosen yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: facility == null ? p.muted : p.foreground,
                        ),
                      ),
                      if (facility != null && facility.locationLine.isNotEmpty)
                        Text(
                          facility.locationLine,
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                      if (stock != null) ...[
                        const SizedBox(height: 6),
                        StockChip(availability: stock),
                      ],
                    ],
                  ),
                ),
              ),
              _editLink('hospital', onTap: _showHospitalList),
            ],
          ),
          Divider(height: 20, color: p.surfaceAlt),
          Row(
            children: [
              BloodDropBadge(bloodType: _bloodType, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      component?.label ?? '—',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.foreground,
                      ),
                    ),
                    Text(
                      '$_units ${_units == 1 ? 'unit' : 'units'} of '
                      '${_bloodType ?? '—'}',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
              _editLink('blood', step: 1),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              UrgencyChip(urgency: _urgency),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _neededBy == null ? '' : 'Needed by ${_neededByShort()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.foreground,
                  ),
                ),
              ),
              _editLink('urgency and date', step: 1),
            ],
          ),
          Divider(height: 20, color: p.surfaceAlt),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 14, color: p.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'PRIVATE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: p.muted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              _editLink('patient', step: 0),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                _reviewRow(
                  'Patient',
                  _patientNameCtrl.text.trim().isEmpty
                      ? '—'
                      : _patientNameCtrl.text.trim(),
                ),
                _reviewRow('Relationship', _relationshipLabel()),
                _reviewRow(
                  'Contact',
                  _contactCtrl.text.trim().isEmpty
                      ? '—'
                      : _contactCtrl.text.trim(),
                ),
                if (_hospitalRefCtrl.text.trim().isNotEmpty)
                  _reviewRow('Hospital ref.', _hospitalRefCtrl.text.trim()),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'Form photo',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                      const SizedBox(width: 8),
                      const Spacer(),
                      if (photo != null) ...[
                        _thumbnail(photo.bytes, 28),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        flex: 4,
                        child: Text(
                          photo != null ? 'Form photo attached' : 'Not added',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Edit": back to the step (or place) that holds [what], in a 48 px
  /// target.
  Widget _editLink(String what, {int? step, VoidCallback? onTap}) => Semantics(
    button: true,
    label: 'Edit $what',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap ?? () => _goToStep(step!),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'Edit',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.palette.primaryText,
          ),
        ),
      ),
    ),
  );

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.foreground,
            ),
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
  bool shouldRepaint(covariant _MiniDropPainter oldDelegate) =>
      oldDelegate.color != color;
}
