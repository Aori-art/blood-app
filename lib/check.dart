import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'book.dart';
import 'config.dart';

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
  final _pages = PageController();
  final Map<String, FollowUpResponse> _responses = {};
  final Map<String, TextEditingController> _textControllers = {};
  late final AnimationController _resultAnimation;
  List<Question> _questions = [];
  int _page = 0;
  bool _started = false, _loading = true, _checking = true, _submitting = false;
  String _status = 'not_checked';
  String? _reason, _recommendation, _nextDate;
  bool _canBook = false, _canRetake = true;

  @override
  void initState() {
    super.initState();
    _resultAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _refresh();
  }

  @override
  void dispose() {
    _pages.dispose();
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

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _checking = true;
      });
    }
    await Future.wait([_fetchStatus(), _fetchQuestions()]);
  }

  Future<void> _fetchStatus() async {
    try {
      final id = (await SharedPreferences.getInstance()).getString('donorId');
      if (id == null || id.isEmpty) {
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
        setState(() {
          _applyStatus(d);
          _checking = false;
        });
        if (_result) _resultAnimation.forward(from: 0);
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
        setState(() => _questions = qs);
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

  void _applyStatus(Map<String, dynamic> d) {
    final raw = d['eligibility'] ?? d['status'];
    final s = raw?.toString().trim().toLowerCase();
    _status = s == null || s.isEmpty || s == 'success' ? 'not_checked' : s;
    _reason = d['result_reason']?.toString();
    _recommendation = d['recommendation_message']?.toString();
    _nextDate = d['next_eligible_date']?.toString();
    _canBook = d['can_book'] == true || d['can_book'].toString() == '1';
    _canRetake = d['can_retake'] == true || d['can_retake'].toString() == '1';
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
      _pages.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
          'The donation service will evaluate your eligibility immediately.',
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
        setState(() {
          _applyStatus(result);
          _started = false;
        });
        _resultAnimation.forward(from: 0);
        _success(
          result['message']?.toString() ?? 'Screening evaluated successfully.',
        );
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
      _status = 'not_checked';
      _started = true;
    });
    _pages.jumpToPage(0);
  }

  void _error(String text) =>
      _snack(text, const Color(0xFFDC2626), Icons.warning_amber_rounded);
  void _success(String text) =>
      _snack(text, const Color(0xFF16A34A), Icons.check_circle_outline);
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
  Widget build(BuildContext context) {
    if (_loading || _checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFDC2626)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
                ),
              ),
              child: const Column(
                children: [
                  Text(
                    'Eligibility Check',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Answer all questions honestly',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
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
    );
  }

  Widget _intro() => RefreshIndicator(
    onRefresh: _refresh,
    color: const Color(0xFFDC2626),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF1F1), Color(0xFFFFE4E4)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Column(
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFDC2626),
                  size: 52,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Blood Donor\nEligibility Screening',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                  height: 1.3,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'A quick health check before your donation',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _infoCard(
          Icons.quiz_outlined,
          const Color(0xFF2563EB),
          const Color(0xFFEFF6FF),
          '${_questions.length} Questions',
          'Simple questions about your health',
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.timer_outlined,
          const Color(0xFF16A34A),
          const Color(0xFFF0FDF4),
          'Takes ~3 minutes',
          'Answer at your own pace, one question at a time',
        ),
        const SizedBox(height: 12),
        _infoCard(
          Icons.lock_outline_rounded,
          const Color(0xFF9333EA),
          const Color(0xFFFAF5FF),
          'Private & Confidential',
          'Your answers are securely recorded for medical use only',
        ),
        const SizedBox(height: 24),
        _noticeBox(),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _questions.isEmpty
                ? null
                : () => setState(() => _started = true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Start Eligibility Check',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can go back and change answers before submitting.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
  Widget _infoCard(
    IconData icon,
    Color color,
    Color background,
    String title,
    String subtitle,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: background,
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _noticeBox() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Please answer all questions honestly. Your responses help ensure the safety of both donors and recipients.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF92400E),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _questionnaire() => Column(
    children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question ${_page + 1} of ${_questions.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_questions.where((q) => q.answer != null).length}/${_questions.length} answered',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (_page + 1) / _questions.length,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFDC2626)),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: PageView.builder(
          controller: _pages,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _questions.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _question(_questions[i]),
        ),
      ),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Row(
          children: [
            if (_page > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pages.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back'),
                ),
              ),
            if (_page > 0) const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  _page == _questions.length - 1
                      ? Icons.check_circle_outline
                      : Icons.arrow_forward,
                  size: 18,
                ),
                label: Text(
                  _page == _questions.length - 1
                      ? (_submitting ? 'Submitting...' : 'Submit')
                      : 'Next',
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _question(Question q) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Question ${_page + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              q.question,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                height: 1.4,
              ),
            ),
            if (q.extraData?.isNotEmpty == true) _extraList(q.extraData!),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _answerButton(
                    'Yes',
                    Icons.check_circle_rounded,
                    q.answer == 'yes',
                    const Color(0xFF16A34A),
                    const Color(0xFFF0FDF4),
                    const Color(0xFFBBF7D0),
                    () => _answer(q, 'yes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _answerButton(
                    'No',
                    Icons.cancel_rounded,
                    q.answer == 'no',
                    const Color(0xFFDC2626),
                    const Color(0xFFFFF1F1),
                    const Color(0xFFFECACA),
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
      const SizedBox(height: 32),
    ],
  );
  Widget _extraList(List<String> data) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
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
  Widget _answerButton(
    String label,
    IconData icon,
    bool selected,
    Color color,
    Color background,
    Color border,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? background : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? border : const Color(0xFFE5E7EB),
          width: selected ? 2 : 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected ? color : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected ? color : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    ),
  );
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
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.date == null ? label : FollowUpResponse.dateValue(r.date!),
                style: TextStyle(
                  fontSize: 14,
                  color: r.date == null
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF111827),
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
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
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
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 13,
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFF16A34A),
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
                  Icons.check_circle_rounded,
                  r.secondaryAnswer == 'yes',
                  const Color(0xFF16A34A),
                  const Color(0xFFF0FDF4),
                  const Color(0xFFBBF7D0),
                  () => setState(() => r.secondaryAnswer = 'yes'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _answerButton(
                  'No',
                  Icons.cancel_rounded,
                  r.secondaryAnswer == 'no',
                  const Color(0xFFDC2626),
                  const Color(0xFFFFF1F1),
                  const Color(0xFFFECACA),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: Color(0xFF16A34A),
              size: 18,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Follow-up Question',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_required(q))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Text(
                  'Required',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
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

  Widget _resultView() {
    final eligible = _status == 'eligible',
        deferred = _status == 'temporary_deferred',
        legacy = _status == 'pending' || _status == 'for_review';
    final color = eligible
        ? const Color(0xFF16A34A)
        : deferred || legacy
        ? const Color(0xFFF59E0B)
        : const Color(0xFFDC2626);
    final title = eligible
        ? "You're Eligible to Donate!"
        : deferred
        ? 'Temporarily Deferred'
        : legacy
        ? 'Previous Screening Under Review'
        : "You're Not Eligible Right Now";
    final icon = eligible
        ? Icons.verified_rounded
        : deferred
        ? Icons.schedule_rounded
        : legacy
        ? Icons.hourglass_top_rounded
        : Icons.block_rounded;
    final fallback = eligible
        ? 'Your automated eligibility screening indicates that you may proceed to schedule a blood donation appointment. Final donor clearance will still take place at the donation center.'
        : deferred
        ? 'Your eligibility has been temporarily deferred.'
        : legacy
        ? 'A previous screening still requires review.'
        : 'You are not eligible to book at this time.';
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FadeTransition(
            opacity: _resultAnimation,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(icon, size: 54, color: color),
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
                const SizedBox(height: 14),
                if (_reason?.isNotEmpty == true)
                  Text(
                    _reason!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 8),
                Text(
                  _recommendation?.isNotEmpty == true
                      ? _recommendation!
                      : fallback,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280), height: 1.5),
                ),
                if (_nextDate?.isNotEmpty == true)
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BookScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Book an Appointment'),
                    ),
                  ),
                if (!eligible && _canRetake)
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
                TextButton(
                  onPressed: _refresh,
                  child: const Text('Refresh status'),
                ),
              ],
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
