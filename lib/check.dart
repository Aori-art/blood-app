import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'book.dart';
import 'config.dart';
import 'shared_design.dart' show HeaderIconButton;
import 'home.dart' show FloatingNavMetrics;
import 'streak/streak_screen.dart';
import 'app_palette.dart';

class Question {
  Question({
    required this.id,
    required this.question,
    required this.followUpPrompt,
    required this.followUpTrigger,
    this.followUpConfig,
    this.extraData,
    this.answer,
    this.followUpAnswer,
  });
  final String id, question, followUpPrompt, followUpTrigger;
  final Map<String, dynamic>? followUpConfig;
  final List<String>? extraData;
  String? answer;
  dynamic followUpAnswer;
}

class FollowUpResponse {
  String text = '';
  String? choice, secondaryAnswer;
  DateTime? date;
  dynamic payload(String type) {
    switch (type) {
      case 'date':
        return date == null ? null : {'date': dateValue(date!)};
      case 'choice':
        return choice == null ? null : {'choice': choice};
      case 'choice_date':
        return choice == null || date == null
            ? null
            : {'choice': choice, 'date': dateValue(date!)};
      case 'yes_no_date':
        return secondaryAnswer == null
            ? null
            : secondaryAnswer == 'no'
            ? {'answer': 'no'}
            : date == null
            ? null
            : {'answer': 'yes', 'date': dateValue(date!)};
      default:
        return text.trim().isEmpty ? null : text.trim();
    }
  }

  static String dateValue(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});
  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen>
    with TickerProviderStateMixin {
  final _scroll = ScrollController();
  int _dir = 1; // 1 = moving forward, -1 = back (for the slide)
  final Map<String, FollowUpResponse> _responses = {};
  final Map<String, TextEditingController> _textControllers = {};
  late final AnimationController _resultAnimation;
  List<Question> _questions = [];
  int _page = 0;
  bool _started = false, _loading = true, _checking = true, _submitting = false;
  String _status = 'not_checked';
  String? _reason, _recommendation, _nextDate;
  String? _retakeDate;
  int _retakeDaysRemaining = 0;
  bool _canBook = false, _canRetake = false;

  // Retaking: the old result is still on the server, so a refresh must not
  // bring it back while the donor is answering again.
  bool _retaking = false;
  String? _retakeBase;

  // Educational materials (link and title come from the server).
  String? _matUrl, _matTitle;
  bool _matRequired = false, _matViewed = false;
  bool _matLoaded = false, _matFailed = false;
  bool _matRecording = false, _matRetrying = false;
  final _matKey = GlobalKey();
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _resultAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _shake.dispose();
    _resultAnimation.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _json(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  /// Reloads the screening status, the questions and the materials state
  /// together. [silent] (pull-to-refresh) never shows the full-screen loader,
  /// so the indicator and the scroll position survive; only the first load
  /// shows it.
  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _checking = true;
      });
    }
    await Future.wait([_fetchStatus(), _fetchQuestions(), _fetchMaterials()]);
  }

  Future<String?> _donorId() async {
    final id = (await SharedPreferences.getInstance()).getString('donorId');
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _fetchStatus() async {
    try {
      final id = await _donorId();
      if (id == null) {
        if (mounted) setState(() => _checking = false);
        return;
      }
      final r = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_eligibility_status.php?donor_id=$id',
            ),
          )
          .timeout(const Duration(seconds: 12));
      final d = _json(r.body);
      if (!mounted) return;
      if (r.statusCode == 200 && d != null) {
        // Someone retaking the check still has their old result on the
        // server: that must not pull them out of the retake.
        if (_retaking && _statusOf(d) == _retakeBase) {
          setState(() => _checking = false);
          return;
        }
        final wasResult = _result;
        setState(() {
          _applyStatus(d);
          _checking = false;
        });
        if (_result && !wasResult) _resultAnimation.forward(from: 0);
      } else {
        setState(() => _checking = false);
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _fetchQuestions() async {
    try {
      final r = await http
          .get(Uri.parse('${AppConfig.baseUrl}/get_screening_questions.php'))
          .timeout(const Duration(seconds: 12));
      final d = _json(r.body);
      if (!mounted) return;
      if (r.statusCode == 200 &&
          d?['status'] == 'success' &&
          d?['questions'] is List) {
        final qs = (d!['questions'] as List).whereType<Map>().map((raw) {
          final q = Map<String, dynamic>.from(raw);
          return Question(
            id: q['question_id'].toString(),
            question: q['question_text']?.toString() ?? '',
            followUpPrompt: q['followup_prompt']?.toString() ?? '',
            followUpTrigger:
                q['followup_trigger']?.toString().toLowerCase() ?? '',
            followUpConfig: q['followup_config'] is Map
                ? Map<String, dynamic>.from(q['followup_config'])
                : null,
            extraData: q['extra_data'] is List
                ? List<String>.from(q['extra_data'])
                : null,
          );
        }).toList();
        _applyQuestions(qs);
      } else {
        _error(
          d?['message']?.toString() ?? 'Unable to load screening questions.',
        );
      }
    } catch (_) {
      if (mounted) {
        _error('Unable to load screening questions. Please try again.');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String _signature(List<Question> qs) =>
      qs.map((q) => '${q.id}|${q.question}|${q.followUpTrigger}').join('\n');

  /// Swaps in a freshly loaded question list without losing the donor's
  /// progress: answers (and their follow-up responses) are carried over by
  /// question id, answers of removed questions are dropped, new questions
  /// start unanswered, and the current question is kept (or [_page] clamped).
  void _applyQuestions(List<Question> qs) {
    final old = {for (final q in _questions) q.id: q};
    final before = _signature(_questions);
    final current = _questions.isNotEmpty && _page < _questions.length
        ? _questions[_page].id
        : null;
    for (final q in qs) {
      final o = old[q.id];
      if (o == null) continue;
      q.answer = o.answer;
      q.followUpAnswer = o.followUpAnswer;
      if (!_triggered(q)) {
        q.followUpAnswer = null;
        _responses.remove(q.id);
        _textControllers.remove(q.id)?.dispose();
      }
    }
    final ids = qs.map((q) => q.id).toSet();
    for (final id in _responses.keys.where((k) => !ids.contains(k)).toList()) {
      _responses.remove(id);
      _textControllers.remove(id)?.dispose();
    }
    final changed = before.isNotEmpty && before != _signature(qs);
    setState(() {
      _questions = qs;
      if (qs.isEmpty) {
        _page = 0;
        _started = false;
      } else {
        final i = current == null ? -1 : qs.indexWhere((q) => q.id == current);
        _page = i >= 0 ? i : _page.clamp(0, qs.length - 1);
      }
    });
    if (changed) {
      _snack('Questions updated', AppColors.info, Icons.refresh_rounded);
    }
  }

  // ── Educational materials ─────────────────────────────────────────────────

  /// The donor may start only once the current material was opened (or when
  /// none is required). While the state is unknown, they may not.
  bool get _canStart =>
      _questions.isNotEmpty && _matLoaded && (!_matRequired || _matViewed);

  Future<void> _fetchMaterials() async {
    try {
      final id = await _donorId();
      if (id == null) {
        if (mounted && !_matLoaded) setState(() => _matFailed = true);
        return;
      }
      final r = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/get_screening_materials.php?donor_id=$id',
            ),
          )
          .timeout(const Duration(seconds: 12));
      final d = _json(r.body);
      if (!mounted) return;
      final m = d?['materials'];
      if (r.statusCode == 200 && d?['status'] == 'success' && m is Map) {
        setState(() {
          _matUrl = m['url']?.toString();
          _matTitle = m['title']?.toString();
          _matRequired =
              m['required'] == true || m['required'].toString() == '1';
          _matViewed = m['viewed'] == true || m['viewed'].toString() == '1';
          _matLoaded = true;
          _matFailed = false;
        });
      } else if (!_matLoaded) {
        setState(() => _matFailed = true);
      }
    } catch (_) {
      if (mounted && !_matLoaded) setState(() => _matFailed = true);
    }
  }

  Future<void> _retryMaterials() async {
    setState(() => _matRetrying = true);
    await _fetchMaterials();
    if (mounted) setState(() => _matRetrying = false);
  }

  Future<void> _openMaterials() async {
    if (_matRecording) return;
    HapticFeedback.lightImpact();
    final url = _matUrl;
    var opened = false;
    try {
      if (url != null && url.isNotEmpty) {
        opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      _error("Couldn't open the materials. Please try again.");
      return;
    }
    if (!mounted) return;
    setState(() => _matRecording = true);
    var saved = false;
    try {
      final id = await _donorId();
      if (id != null) {
        final r = await http
            .post(
              Uri.parse('${AppConfig.baseUrl}/record_material_view.php'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'donor_id': int.tryParse(id) ?? id}),
            )
            .timeout(const Duration(seconds: 12));
        final d = _json(r.body);
        saved =
            r.statusCode >= 200 &&
            r.statusCode < 300 &&
            d?['status'] == 'success' &&
            d?['viewed'] == true;
      }
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() {
      _matRecording = false;
      if (saved) _matViewed = true;
    });
    if (!saved) {
      _error(
        "We couldn't save that you opened the materials. Please try again.",
      );
    }
  }

  /// A tap on the start button while the materials are still required.
  void _startBlocked() {
    if (_questions.isEmpty) return;
    final ctx = _matKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
    if (!_reduceMotion) _shake.forward(from: 0);
    HapticFeedback.lightImpact();
    _error('Please open the educational materials first.');
  }

  /// Leaves the questionnaire for the first page, keeping every answer.
  void _backToFirstPage() {
    if (!_started) return;
    setState(() => _started = false);
  }

  /// The status in a status/submit response; pending and for_review are one
  /// state to the donor: "Under Review".
  String _statusOf(Map<String, dynamic> d) {
    final raw = d['eligibility'] ?? d['status'];
    final s = raw?.toString().trim().toLowerCase();
    var status = s == null || s.isEmpty || s == 'success' ? 'not_checked' : s;
    if (status == 'pending') status = 'for_review';
    if (status == 'not_checked' && d['needs_review'] == true) {
      status = 'for_review';
    }
    return status;
  }

  void _applyStatus(Map<String, dynamic> d) {
    _status = _statusOf(d);
    _reason = d['result_reason']?.toString();
    _recommendation = d['recommendation_message']?.toString();
    _nextDate = d['next_eligible_date']?.toString();
    final retakeDate = d['retake_available_date']?.toString();
    _retakeDate = retakeDate?.isEmpty == true ? null : retakeDate;
    _retakeDaysRemaining = (d['retake_days_remaining'] as num?)?.toInt() ?? 0;
    _canBook = d['can_book'] == true || d['can_book'].toString() == '1';
    _canRetake = d['can_retake'] == true || d['can_retake'].toString() == '1';
  }

  String _retakeWhen(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  bool get _result => const {
    'eligible',
    'not_eligible',
    'temporary_deferred',
    'pending',
    'for_review',
  }.contains(_status);
  bool _triggered(Question q) => q.answer == q.followUpTrigger;
  String _type(Question q) =>
      q.followUpConfig?['input_type']?.toString() ?? 'text';
  FollowUpResponse _response(Question q) =>
      _responses.putIfAbsent(q.id, FollowUpResponse.new);
  bool _required(Question q) => q.followUpConfig?['required'] == true;
  bool _valid(Question q) {
    if (!_triggered(q) || !_required(q)) return true;
    final r = _responses[q.id];
    switch (_type(q)) {
      case 'date':
        return r?.date != null;
      case 'choice':
        return r?.choice != null;
      case 'choice_date':
        return r?.choice != null && r?.date != null;
      case 'yes_no_date':
        return r?.secondaryAnswer != null &&
            (r?.secondaryAnswer == 'no' || r?.date != null);
      default:
        return r?.text.trim().isNotEmpty == true;
    }
  }

  void _answer(Question q, String answer) {
    setState(() {
      q.answer = answer;
      if (!_triggered(q)) {
        q.followUpAnswer = null;
        _responses.remove(q.id);
        _textControllers.remove(q.id)?.dispose();
      }
    });
  }

  void _next() {
    final q = _questions[_page];
    if (q.answer == null) {
      return _error('Please answer this question to continue.');
    }
    if (!_valid(q)) {
      return _error(
        'Please complete the required follow-up before continuing.',
      );
    }
    if (_page == _questions.length - 1) {
      _submit();
    } else {
      _goTo(_page + 1);
    }
  }

  Future<void> _pickDate(Question q) async {
    final r = _response(q);
    final d = await showDatePicker(
      context: context,
      initialDate: r.date ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) setState(() => r.date = d);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit your answers?'),
        content: const Text(
          'Your answers are checked right away. If some need a closer look, '
          'our team will review them and let you know.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = int.tryParse(
      (await SharedPreferences.getInstance()).getString('donorId') ?? '',
    );
    if (id == null) {
      return _error('Your session is invalid. Please sign in again.');
    }
    setState(() => _submitting = true);
    try {
      final answers = _questions.map((q) {
        final f = _triggered(q) ? _responses[q.id]?.payload(_type(q)) : null;
        q.followUpAnswer = f;
        return {
          'question_id': int.tryParse(q.id) ?? q.id,
          'answer': q.answer,
          'followup_answer': f,
        };
      }).toList();
      final r = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/submit_screening.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'donor_id': id, 'answers': answers}),
          )
          .timeout(const Duration(seconds: 15));
      final d = _json(r.body);
      if (!mounted) return;
      if (r.statusCode >= 200 &&
          r.statusCode < 300 &&
          d?['status'] == 'success') {
        final result = d!;
        _retaking = false;
        setState(() {
          _applyStatus(result);
          _started = false;
        });
        _resultAnimation.forward(from: 0);
        _success(
          result['message']?.toString() ?? 'Screening evaluated successfully.',
        );
        await _fetchStatus();
      } else if (d?['code'] == 'MATERIALS_NOT_VIEWED') {
        // The opened-materials window ran out (or the link changed): back to
        // the first page, answers kept, and ask again.
        _error(
          d?['message']?.toString() ??
              'Please open the educational materials first.',
        );
        setState(() {
          _started = false;
          _matViewed = false;
        });
        await _fetchMaterials();
      } else if (d?['code'] == 'RETAKE_NOT_AVAILABLE') {
        _error(d?['message']?.toString() ?? "You can't retake the check yet.");
        setState(() => _started = false);
        await _fetchStatus();
      } else {
        _error(d?['message']?.toString() ?? 'Unable to submit screening.');
      }
    } catch (_) {
      if (mounted) {
        _error(
          'Submission failed. Please check your connection and try again.',
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _retake() {
    _retaking = true;
    _retakeBase = _status;
    for (final q in _questions) {
      q.answer = null;
      q.followUpAnswer = null;
    }
    for (final c in _textControllers.values) {
      c.dispose();
    }
    setState(() {
      _responses.clear();
      _textControllers.clear();
      _page = 0;
      _dir = -1;
      _status = 'not_checked';
      _started = true;
    });
  }

  void _error(String text) =>
      _snack(text, AppColors.primary, Icons.warning_amber_rounded);
  void _success(String text) =>
      _snack(text, AppColors.success, Icons.check_circle_outline);
  void _snack(String text, Color color, IconData icon) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreakScreen(id: 'check', child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    if (_loading || _checking) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: Center(
          child: CircularProgressIndicator(color: context.palette.primaryText),
        ),
      );
    }
    final inQuestions = _started && !_result;
    // The tabs stay mounted: only the visible one may take the system back.
    final backIsOurs = inQuestions && StreakTabScope.isActive(context);
    return PopScope(
      canPop: !backIsOurs,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backIsOurs) _backToFirstPage();
      },
      child: Scaffold(
        backgroundColor: context.palette.background,
        // Bottom inset is handled by the floating nav's clearance, not here.
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    22,
                    22,
                    22,
                    inQuestions ? 20 : 22,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: inQuestions ? 48 : 0,
                              ),
                              child: const Column(
                                children: [
                                  Text(
                                    'Eligibility Check',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.onPrimary,
                                      fontSize: 21,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Answer all questions honestly',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (inQuestions)
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: HeaderIconButton(
                                    icon: Icons.arrow_back_rounded,
                                    tooltip: 'Back',
                                    onTap: _backToFirstPage,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (inQuestions) ...[
                        const SizedBox(height: 16),
                        _progressBlock(),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _result
                    ? _resultView()
                    : _started
                    ? _questionnaire()
                    : _intro(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The first page. It is laid out to fit one screen on a normal phone (the
  /// start button sits at the bottom of the available space); on very small
  /// screens or with large text it scrolls. Pull-to-refresh always works.
  Widget _intro() {
    final canStart = _canStart;
    final answered = _questions.any((q) => q.answer != null);
    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      color: context.palette.primaryText,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  FloatingNavMetrics.bottomPadding(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _introCard(),
                    const SizedBox(height: 12),
                    _miniCards(),
                    if (!_matLoaded || _matRequired) ...[
                      const SizedBox(height: 12),
                      _materialsCard(),
                    ],
                    const SizedBox(height: 12),
                    _noticeBox(),
                    const Spacer(),
                    const SizedBox(height: 12),
                    _startButton(canStart, answered),
                    const SizedBox(height: 8),
                    Text(
                      canStart || _questions.isEmpty
                          ? 'You can go back and change answers before submitting.'
                          : 'Open the educational materials first to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _introCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.palette.accentBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.primaryBorder),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: context.palette.surface,
          child: Icon(
            Icons.favorite_rounded,
            color: context.palette.primaryText,
            size: 26,
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Blood Donor Eligibility Screening',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.palette.foreground,
                  height: 1.25,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'A quick health check before your donation',
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _miniCards() => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _miniCard(
            Icons.quiz_outlined,
            context.palette.info,
            context.palette.infoBg,
            '${_questions.length} Questions',
            'About your health',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniCard(
            Icons.timer_outlined,
            context.palette.success,
            context.palette.successBg,
            '~3 minutes',
            'At your own pace',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniCard(
            Icons.lock_outline_rounded,
            context.palette.purple,
            context.palette.purpleBg,
            'Private',
            'Medical use only',
          ),
        ),
      ],
    ),
  );

  Widget _miniCard(
    IconData icon,
    Color color,
    Color background,
    String title,
    String subtitle,
  ) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(12),
      boxShadow: context.palette.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: context.palette.foreground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 10.5,
            color: context.palette.muted,
            height: 1.3,
          ),
        ),
      ],
    ),
  );

  /// The educational materials the donor must open before starting. The link
  /// and its title come from the server, never from the app.
  Widget _materialsCard() {
    final viewed = _matViewed;
    final unknown = !_matLoaded; // still loading, or the request failed
    final title = unknown
        ? 'Educational materials'
        : (_matTitle?.isNotEmpty == true
              ? _matTitle!
              : 'Educational materials');
    final subtitle = unknown
        ? (_matFailed
              ? "We couldn't load the materials."
              : 'Checking the materials...')
        : viewed
        ? 'Opened. You can start the check.'
        : 'Required before you start';

    final card = AnimatedContainer(
      key: _matKey,
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: viewed
              ? context.palette.successBorder
              : context.palette.border,
        ),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: viewed ? AppColors.success : context.palette.accentBg,
                ),
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: _reduceMotion ? 0 : 300),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: child,
                  ),
                  child: Icon(
                    viewed ? Icons.check_rounded : Icons.menu_book_rounded,
                    key: ValueKey(viewed),
                    size: 22,
                    color: viewed ? Colors.white : context.palette.primaryText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.palette.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: viewed
                            ? context.palette.success
                            : context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_matFailed && !_matLoaded)
            SizedBox(
              height: 44,
              child: TextButton.icon(
                onPressed: _matRetrying ? null : _retryMaterials,
                icon: _matRetrying
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.palette.primaryText,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            )
          else
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: unknown ? null : _openMaterials,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.primaryText,
                  side: BorderSide(
                    color: context.palette.primaryText,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _matRecording
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.palette.primaryText,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            viewed ? 'Open Again' : 'Open Materials',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.open_in_new_rounded, size: 18),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
    // A short shake when the donor tries to start without opening them.
    return AnimatedBuilder(
      animation: _shake,
      child: card,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          math.sin(_shake.value * math.pi * 6) * 6 * (1 - _shake.value),
          0,
        ),
        child: child,
      ),
    );
  }

  Widget _startButton(bool canStart, bool resume) {
    final label = resume
        ? 'Resume Eligibility Check'
        : 'Start Eligibility Check';
    return SizedBox(
      height: 52,
      child: Semantics(
        button: true,
        enabled: canStart,
        label: label,
        excludeSemantics: true,
        onTap: canStart ? () => setState(() => _started = true) : _startBlocked,
        child: ElevatedButton.icon(
          // Always tappable: a tap while locked explains what is missing.
          onPressed: canStart
              ? () => setState(() => _started = true)
              : _startBlocked,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: canStart
                ? AppColors.primary
                : context.palette.border,
            foregroundColor: canStart ? Colors.white : context.palette.hint,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noticeBox() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.palette.warningBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.palette.warningBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: context.palette.warning, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Please answer honestly. Your answers keep donors and patients safe.',
            style: TextStyle(
              fontSize: 12,
              color: context.palette.warningText,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// Moves to question [i], remembering which way we went so the card slides
  /// in from the right (Next) or the left (Back).
  void _goTo(int i) {
    if (i < 0 || i >= _questions.length || i == _page) return;
    setState(() {
      _dir = i > _page ? 1 : -1;
      _page = i;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ── Progress (inside the header) ──────────────────────────────────────────
  Widget _progressBlock() {
    final total = _questions.length;
    final answered = _questions.where((q) => q.answer != null).length;
    final reduce = _reduceMotion;
    return Semantics(
      label: 'Question ${_page + 1} of $total, $answered answered',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question ${_page + 1} of $total',
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$answered/$total answered',
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(end: (_page + 1) / total),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: reduce
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Question area + actions ───────────────────────────────────────────────
  Widget _questionnaire() {
    final reduce = _reduceMotion;
    final q = _questions[_page];
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: context.palette.primaryText,
            onRefresh: () => _refresh(silent: true),
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: AnimatedSize(
                alignment: Alignment.topCenter,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: reduce ? 120 : 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // Leaving cards do not take part in the height.
                      for (final p in previous)
                        Positioned(top: 0, left: 0, right: 0, child: p),
                      ?current,
                    ],
                  ),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == ValueKey<int>(_page);
                    Widget out = FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                    if (!reduce && incoming) {
                      out = AnimatedBuilder(
                        animation: animation,
                        builder: (_, c) => Transform.translate(
                          offset: Offset((1 - animation.value) * 24 * _dir, 0),
                          child: c,
                        ),
                        child: out,
                      );
                    }
                    return out;
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_page),
                    child: _question(q),
                  ),
                ),
              ),
            ),
          ),
        ),
        // No background: the gray page shows through. The bottom padding keeps
        // the buttons clear of the floating nav.
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            FloatingNavMetrics.bottomPadding(context) - 24,
          ),
          child: _actionRow(q),
        ),
      ],
    );
  }

  Widget _actionRow(Question q) {
    final last = _page == _questions.length - 1;
    final reduce = _reduceMotion;
    final showBack = _page > 0;
    final slide = Duration(milliseconds: reduce ? 120 : 260);
    final enabled = q.answer != null && !_submitting;
    return LayoutBuilder(
      builder: (context, c) {
        final backW = (c.maxWidth - 12) * 2 / 5;
        return Row(
          children: [
            // Back takes 2 parts and Next 3 from question 2 on; it slides in.
            AnimatedContainer(
              duration: slide,
              curve: Curves.easeOutCubic,
              width: showBack ? backW + 12 : 0,
              height: 52,
              child: ExcludeSemantics(
                excluding: !showBack,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: backW + 12,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: backW,
                        child: _PressBuilder(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _goTo(_page - 1);
                          },
                          builder: (context, pressed) => AnimatedScale(
                            scale: pressed && !reduce ? 0.97 : 1,
                            duration: const Duration(milliseconds: 160),
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: context.palette.primaryText,
                                  width: 1.5,
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_back_rounded,
                                      size: 18,
                                      color: context.palette.primaryText,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Back',
                                      style: TextStyle(
                                        color: context.palette.primaryText,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _PressBuilder(
                // A tap on a disabled Next still explains what is missing.
                onTap: _submitting
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _next();
                      },
                builder: (context, pressed) => AnimatedScale(
                  scale: pressed && !reduce ? 0.98 : 1,
                  duration: const Duration(milliseconds: 160),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: enabled
                            ? AppColors.primaryGradient
                            : [context.palette.border, context.palette.border],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: enabled
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : const [],
                    ),
                    child: Semantics(
                      button: true,
                      enabled: enabled,
                      label: last
                          ? (_submitting ? 'Submitting' : 'Submit')
                          : 'Next',
                      excludeSemantics: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                color: enabled
                                    ? AppColors.onPrimary
                                    : context.palette.hint,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              child: Text(
                                last
                                    ? (_submitting ? 'Submitting...' : 'Submit')
                                    : 'Next',
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              transform: Matrix4.translationValues(
                                pressed && enabled && !reduce ? 3 : 0,
                                0,
                                0,
                              ),
                              child: TweenAnimationBuilder<Color?>(
                                tween: ColorTween(
                                  end: enabled
                                      ? AppColors.onPrimary
                                      : context.palette.hint,
                                ),
                                duration: const Duration(milliseconds: 200),
                                builder: (_, color, _) => Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── The question card ─────────────────────────────────────────────────────
  Widget _question(Question q) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.palette.border),
          boxShadow: context.palette.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.palette.accentBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Question ${_page + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.primaryText,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              q.question,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.palette.foreground,
                height: 1.35,
              ),
            ),
            if (q.extraData?.isNotEmpty == true) _extraList(q.extraData!),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _answerButton(
                    'Yes',
                    true,
                    q.answer == 'yes',
                    () => _answer(q, 'yes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _answerButton(
                    'No',
                    false,
                    q.answer == 'no',
                    () => _answer(q, 'no'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: _triggered(q)
            ? Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _followUpShell(q, _followUp(q)),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
  Widget _extraList(List<String> data) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.palette.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'List:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...data.map(
          (value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $value', style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    ),
  );

  /// A Yes / No choice (also used by the follow-up questions).
  Widget _answerButton(
    String label,
    bool yes,
    bool selected,
    VoidCallback onTap,
  ) {
    final icon = selected
        ? (yes ? Icons.check_circle_rounded : Icons.cancel_rounded)
        : (yes ? Icons.check_circle_outline_rounded : Icons.cancel_outlined);
    final reduce = _reduceMotion;
    void tap() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: tap,
      child: _PressBuilder(
        onTap: tap,
        builder: (context, pressed) => AnimatedScale(
          scale: pressed && !reduce ? 0.97 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: selected
                    ? AppColors.primaryGradient
                    : [context.palette.surfaceAlt, context.palette.surfaceAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: selected ? Colors.transparent : context.palette.border,
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    end: selected ? AppColors.onPrimary : context.palette.muted,
                  ),
                  duration: const Duration(milliseconds: 180),
                  builder: (_, color, _) => Icon(icon, size: 22, color: color),
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.onPrimary
                        : context.palette.foreground,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _followUp(Question q) {
    final c = q.followUpConfig, r = _response(q), type = _type(q);
    final title = q.followUpPrompt.isNotEmpty
        ? q.followUpPrompt
        : c?['question']?.toString() ?? 'Please provide more details.';
    final options = (c?['options'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    Widget date(String label) => InkWell(
      onTap: () => _pickDate(q),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: context.palette.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.date == null ? label : FollowUpResponse.dateValue(r.date!),
                style: TextStyle(
                  fontSize: 14,
                  color: r.date == null
                      ? context.palette.muted
                      : context.palette.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Widget choice() => DropdownButtonFormField<String>(
      initialValue: r.choice,
      isExpanded: true,
      menuMaxHeight: 280,
      decoration: InputDecoration(
        labelText: c?['choice_label']?.toString() ?? 'Select an option',
        filled: true,
        fillColor: context.palette.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.palette.success, width: 1.5),
        ),
      ),
      selectedItemBuilder: (context) => options
          .map(
            (option) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                option['label']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      items: options
          .map(
            (o) => DropdownMenuItem(
              value: o['value']?.toString(),
              child: Text(
                o['label']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => r.choice = v),
    );
    if (type == 'text') {
      final controller = _textControllers.putIfAbsent(q.id, () {
        final x = TextEditingController(text: r.text);
        x.addListener(() => r.text = x.text);
        return x;
      });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  c?['placeholder']?.toString() ?? 'Type your answer here...',
              hintStyle: TextStyle(color: context.palette.muted, fontSize: 13),
              filled: true,
              fillColor: context.palette.surfaceAlt,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: context.palette.success,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (type == 'date') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          date(c?['date_label']?.toString() ?? 'Select date'),
        ],
      );
    }
    if (type == 'choice') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          choice(),
        ],
      );
    }
    if (type == 'choice_date') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          choice(),
          const SizedBox(height: 12),
          date(c?['date_label']?.toString() ?? 'Select date'),
        ],
      );
    }
    if (type == 'yes_no_date') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c?['question']?.toString() ?? title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _answerButton(
                  'Yes',
                  true,
                  r.secondaryAnswer == 'yes',
                  () => setState(() => r.secondaryAnswer = 'yes'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _answerButton(
                  'No',
                  false,
                  r.secondaryAnswer == 'no',
                  () => setState(() {
                    r.secondaryAnswer = 'no';
                    r.date = null;
                  }),
                ),
              ),
            ],
          ),
          if (r.secondaryAnswer == 'yes')
            date(c?['date_label']?.toString() ?? 'Select date'),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _followUpShell(Question q, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.palette.successBorder, width: 1.5),
      boxShadow: context.palette.shadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: context.palette.success,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Follow-up Question',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: context.palette.success,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_required(q))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.palette.accentBg,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: context.palette.primaryBorder),
                ),
                child: Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: context.palette.primaryText,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  /// "What happens next" while the screening is under review: a vertical
  /// three-step stepper joined by a line.
  Widget _reviewSteps() {
    Widget step({
      required Widget marker,
      required String title,
      String? subtitle,
      required String state,
      required Color lineColor,
      bool last = false,
    }) {
      return Semantics(
        label: '$title, $state',
        excludeSemantics: true,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(child: marker),
                    ),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: lineColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: state == 'upcoming'
                              ? context.palette.muted
                              : context.palette.foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
        boxShadow: context.palette.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happens next',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.palette.foreground,
            ),
          ),
          const SizedBox(height: 16),
          step(
            marker: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            title: 'Answers submitted',
            state: 'done',
            lineColor: context.palette.success,
          ),
          step(
            marker: _PulsingDot(
              color: context.palette.warning,
              animate: !MediaQuery.disableAnimationsOf(context),
            ),
            title: 'Team review',
            state: 'current',
            lineColor: context.palette.border,
          ),
          step(
            marker: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.surfaceAlt,
                border: Border.all(color: context.palette.hint, width: 2),
              ),
            ),
            title: 'You get the result',
            subtitle: "We'll notify you in the app",
            state: 'upcoming',
            lineColor: context.palette.border,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _resultView() {
    final eligible = _status == 'eligible',
        deferred = _status == 'temporary_deferred',
        review = _status == 'for_review' || _status == 'pending';
    final showRetakeCountdown =
        !eligible && !_canRetake && !review && _retakeDate != null;
    final color = eligible
        ? context.palette.success
        : deferred || review
        ? context.palette.warning
        : context.palette.primaryText;
    final title = eligible
        ? "You're Eligible to Donate!"
        : deferred
        ? 'Temporarily Deferred'
        : review
        ? 'Under Review'
        : "You're Not Eligible Right Now";
    final icon = eligible
        ? Icons.verified_rounded
        : deferred
        ? Icons.schedule_rounded
        : review
        ? Icons.fact_check_rounded
        : Icons.block_rounded;
    final fallback = eligible
        ? 'Your automated eligibility screening indicates that you may proceed to schedule a blood donation appointment. Final donor clearance will still take place at the donation center.'
        : deferred
        ? 'Your eligibility has been temporarily deferred.'
        : review
        ? 'Some of your answers need a closer look. Our team will review your '
              'screening and notify you of the result.'
        : 'You are not eligible to book at this time.';
    final bottomPad = FloatingNavMetrics.bottomPadding(context);
    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad),
        children: [
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _resultAnimation,
              curve: Curves.easeOutBack,
            ),
            child: FadeTransition(
              opacity: _resultAnimation,
              child: Column(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                color.withValues(alpha: .22),
                                color.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: color.withValues(alpha: .12),
                          child: Icon(icon, size: 54, color: color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: .18)),
                      boxShadow: context.palette.shadow,
                    ),
                    child: Column(
                      children: [
                        if (!review && _reason?.isNotEmpty == true)
                          Text(
                            _reason!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        if (!review && _reason?.isNotEmpty == true)
                          const SizedBox(height: 8),
                        Text(
                          _recommendation?.isNotEmpty == true
                              ? _recommendation!
                              : fallback,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.palette.muted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (review) ...[const SizedBox(height: 16), _reviewSteps()],
                  if (!review &&
                      _nextDate?.isNotEmpty == true &&
                      !(showRetakeCountdown && _nextDate == _retakeDate))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Next Eligible Date: ${_formatDate(_nextDate!)}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  if (eligible && _canBook)
                    Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: .35),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const BookScreen(showBackButton: true),
                              ),
                            ),
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                        ),
                        label: const Text(
                          'Book an Appointment',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  if (!eligible && !review && _canRetake)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _retake,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Take Eligibility Check Again'),
                      ),
                    ),
                  if (showRetakeCountdown) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withValues(alpha: .18)),
                        boxShadow: context.palette.shadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: .12),
                                ),
                                child: Icon(
                                  Icons.event_repeat_rounded,
                                  size: 20,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Retake Available',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: context.palette.foreground,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _formatDate(_retakeDate!),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: context.palette.foreground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You can take the check again '
                            '${_retakeWhen(_retakeDaysRemaining)}.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            deferred
                                ? 'You can take the check again once your deferral period ends.'
                                : 'This short waiting period lets your health settle before '
                                      "you're screened again.",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.palette.border,
                          foregroundColor: context.palette.muted,
                          disabledBackgroundColor: context.palette.border,
                          disabledForegroundColor: context.palette.muted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.lock_clock_rounded, size: 18),
                        label: Text(
                          'Available ${_retakeWhen(_retakeDaysRemaining)}',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      !eligible &&
                              !review &&
                              !_canRetake &&
                              _retakeDaysRemaining == 0
                          ? 'Check again'
                          : 'Refresh status',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Reports whether a finger is down, so a button can react while pressed.
class _PressBuilder extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool pressed) builder;

  const _PressBuilder({required this.onTap, required this.builder});

  @override
  State<_PressBuilder> createState() => _PressBuilderState();
}

class _PressBuilderState extends State<_PressBuilder> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    child: widget.builder(context, _pressed),
  );
}

/// The "current step" dot: a solid dot with a soft halo that pulses. With
/// [animate] off (reduced motion) the halo stays still.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool animate;

  const _PulsingDot({required this.color, required this.animate});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 + 14 * t,
                height: 14 + 14 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - t) + 0.06),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
