import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'book.dart';
import 'config.dart';

class Question {
  String id;
  String question;
  String followUpPrompt;
  String followUpTrigger;
  List<String>? extraData;
  String? answer;
  String? followUp;

  Question({
    required this.id,
    required this.question,
    required this.followUpPrompt,
    required this.followUpTrigger,
    this.extraData,
    this.answer,
    this.followUp,
  });
}

class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _started = false;

  late List<TextEditingController> _followUpControllers;

  List<Question> questions = [];
  bool isLoading = true;

  String? _eligibilityStatus;
  bool _checkingEligibility = true;

  late AnimationController _approvedAnimController;
  late Animation<double> _approvedFadeAnim;
  late Animation<double> _approvedScaleAnim;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _approvedAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _approvedFadeAnim = CurvedAnimation(
      parent: _approvedAnimController,
      curve: Curves.easeOut,
    );
    _approvedScaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _approvedAnimController,
        curve: Curves.easeOutBack,
      ),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchEligibilityStatus();
    fetchQuestions();
  }

  Future<void> _fetchEligibilityStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final donorId = prefs.getString('donorId');

      if (donorId == null || donorId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _eligibilityStatus = null;
          _checkingEligibility = false;
        });
        return;
      }

      final url = Uri.parse(
        "${AppConfig.baseUrl}/get_eligibility_status.php?donor_id=$donorId",
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final raw = data['status'];
        final String? status =
            (raw != null && raw.toString().trim().isNotEmpty)
                ? raw.toString().trim()
                : null;

        setState(() {
          _eligibilityStatus = status;
          _checkingEligibility = false;
        });

        if (status == 'approved') {
          _approvedAnimController.forward();
        }
      } else {
        setState(() {
          _eligibilityStatus = null;
          _checkingEligibility = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eligibilityStatus = null;
        _checkingEligibility = false;
      });
    }
  }

  Future<void> fetchQuestions() async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_screening_questions.php"),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (data["status"] == "success") {
        List<Question> loaded = [];

        for (var q in data["questions"]) {
          loaded.add(
            Question(
              id: q["question_id"].toString(),
              question: q["question_text"],
              followUpPrompt: q["followup_prompt"],
              followUpTrigger: q["followup_trigger"],
              extraData: q["extra_data"] != null
                  ? List<String>.from(q["extra_data"])
                  : null,
            ),
          );
        }

        setState(() {
          questions = loaded;
          _followUpControllers = List.generate(
            questions.length,
            (_) => TextEditingController(),
          );
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _approvedAnimController.dispose();
    _pulseController.dispose();

    if (questions.isNotEmpty) {
      for (final c in _followUpControllers) {
        c.dispose();
      }
    }

    super.dispose();
  }

  bool get _isLastPage => _currentPage == questions.length - 1;

  bool get _currentAnswered =>
      questions.isNotEmpty && questions[_currentPage].answer != null;

  bool get _showPendingOverlay =>
      !_checkingEligibility && _eligibilityStatus == 'pending';

  bool get _showApprovedOverlay =>
      !_checkingEligibility && _eligibilityStatus == 'approved';

  void _showSnackError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _goNext() {
    final q = questions[_currentPage];

    if (!_currentAnswered) {
      _showSnackError("Please answer this question to continue.");
      return;
    }

    if (q.answer == q.followUpTrigger &&
        _followUpControllers[_currentPage].text.trim().isEmpty) {
      _showSnackError("Please fill in the follow-up answer to continue.");
      return;
    }

    if (_isLastPage) {
      _submit();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goPrev() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _checkingEligibility = true;
      isLoading = true;
      _started = false;
      _currentPage = 0;
      questions = [];
      _eligibilityStatus = null;
      _approvedAnimController.reset();
    });

    await Future.wait([
      _fetchEligibilityStatus(),
      fetchQuestions(),
    ]);
  }

  Future<bool> _showSubmitConfirmation() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF1F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Color(0xFFDC2626),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Submit Your Answers?",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "Please make sure all your answers are accurate and honest. You won't be able to edit them after submission.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                ),
                child: const Text("Go Back"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                ),
                child: const Text(
                  "Yes, Submit",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _submit() async {
    final confirmed = await _showSubmitConfirmation();
    if (!confirmed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final donorIdString = prefs.getString('donorId');

      if (donorIdString == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("User not logged in"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final donorId = int.tryParse(donorIdString);

      if (donorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid user session"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      List<Map<String, dynamic>> answers = [];

      for (int i = 0; i < questions.length; i++) {
        answers.add({
          "question_id": questions[i].id,
          "answer": questions[i].answer,
          "followup_answer": _followUpControllers[i].text,
        });
      }

      final response = await http.post(
        Uri.parse("${AppConfig.baseUrl}/submit_screening.php"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "donor_id": donorId,
          "answers": answers,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data["message"] ?? "Submitted"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Submission failed"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    if (isLoading || _checkingEligibility) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFDC2626),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: screenHeight * 0.06,
                  bottom: screenHeight * 0.03,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF750000),
                      Color(0xFFFF4E4E),
                    ],
                  ),
                ),
                child: const Column(
                  children: [
                    Text(
                      "Eligibility Check",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Answer all questions honestly",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _started
                      ? _buildQuestionnaire(key: const ValueKey('quiz'))
                      : _buildIntroScreen(key: const ValueKey('intro')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntroScreen({Key? key}) {
    return RefreshIndicator(
      color: const Color(0xFFDC2626),
      onRefresh: _refresh,
      child: SingleChildScrollView(
        key: key,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFF1F1),
                    Color(0xFFFFE4E4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFDC2626).withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFDC2626),
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Blood Donor\nEligibility Screening",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "A quick health check before your donation",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _infoCard(
              icon: Icons.quiz_outlined,
              iconColor: const Color(0xFF2563EB),
              iconBg: const Color(0xFFEFF6FF),
              title: "${questions.length} Questions",
              subtitle: "Simple yes/no questions about your health",
            ),
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF16A34A),
              iconBg: const Color(0xFFF0FDF4),
              title: "Takes ~3 minutes",
              subtitle: "Answer at your own pace, one question at a time",
            ),
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.lock_outline_rounded,
              iconColor: const Color(0xFF9333EA),
              iconBg: const Color(0xFFFAF5FF),
              title: "Private & Confidential",
              subtitle: "Your answers are securely recorded for medical use only",
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Color(0xFFD97706),
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Please answer all questions honestly. Your responses help ensure the safety of both donors and recipients.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _started = true),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text(
                  "Start Eligibility Check",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You can go back and change answers before submitting.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionnaire({Key? key}) {
    final answeredCount = questions.where((q) => q.answer != null).length;

    return Column(
      key: key,
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
                    "Question ${_currentPage + 1} of ${questions.length}",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "$answeredCount/${questions.length} answered",
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
                  value: (_currentPage + 1) / questions.length,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final q = questions[index];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1.5,
                        ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Question ${index + 1}",
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
                          if (q.extraData != null && q.extraData!.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "List:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...q.extraData!.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        "• $item",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _answerButton(
                                  label: "Yes",
                                  icon: Icons.check_circle_rounded,
                                  selected: q.answer == 'yes',
                                  selectedColor: const Color(0xFF16A34A),
                                  selectedBg: const Color(0xFFF0FDF4),
                                  selectedBorder: const Color(0xFFBBF7D0),
                                  onTap: () => setState(() => q.answer = 'yes'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _answerButton(
                                  label: "No",
                                  icon: Icons.cancel_rounded,
                                  selected: q.answer == 'no',
                                  selectedColor: const Color(0xFFDC2626),
                                  selectedBg: const Color(0xFFFFF1F1),
                                  selectedBorder: const Color(0xFFFECACA),
                                  onTap: () {
                                    setState(() {
                                      q.answer = 'no';
                                      q.followUp = null;
                                      _followUpControllers[index].clear();
                                    });
                                  },
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
                      child: q.answer == q.followUpTrigger
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFBBF7D0),
                                    width: 1.5,
                                  ),
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
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.chat_bubble_outline,
                                          color: Color(0xFF16A34A),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          "Follow-up Question",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF1F1),
                                            borderRadius:
                                                BorderRadius.circular(99),
                                            border: Border.all(
                                              color: const Color(0xFFFECACA),
                                            ),
                                          ),
                                          child: const Text(
                                            "Required",
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
                                    Text(
                                      q.followUpPrompt,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _followUpControllers[index],
                                      onChanged: (val) => q.followUp = val,
                                      maxLines: 3,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: "Type your answer here...",
                                        hintStyle: const TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 13,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF9FAFB),
                                        contentPadding:
                                            const EdgeInsets.all(14),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFD1D5DB),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFD1D5DB),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF16A34A),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              if (_currentPage == 0)
                Expanded(
                  flex: 1,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _started = false),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text("Intro"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (_currentPage > 0)
                Expanded(
                  flex: 1,
                  child: OutlinedButton.icon(
                    onPressed: _goPrev,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text("Back"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _goNext,
                  icon: Icon(
                    _isLastPage
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(_isLastPage ? "Submit" : "Next"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentAnswered
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFF87171),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _answerButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required Color selectedBg,
    required Color selectedBorder,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBg : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? selectedBorder : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? selectedColor : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? selectedColor : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedOverlay extends StatelessWidget {
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;
  final Animation<double> pulseAnimation;
  final Future<void> Function() onRefresh;
  final VoidCallback onBookAppointment;

  const _ApprovedOverlay({
    required this.fadeAnimation,
    required this.scaleAnimation,
    required this.pulseAnimation,
    required this.onRefresh,
    required this.onBookAppointment,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnimation,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFECFDF5),
              Color(0xFFF0FDF4),
              Color(0xFFDCFCE7),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFF16A34A),
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.80,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),
                      ScaleTransition(
                        scale: scaleAnimation,
                        child: ScaleTransition(
                          scale: pulseAnimation,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      const Color(0xFF16A34A).withOpacity(0.10),
                                ),
                              ),
                              Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      const Color(0xFF16A34A).withOpacity(0.16),
                                ),
                              ),
                              Container(
                                width: 86,
                                height: 86,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF22C55E),
                                      Color(0xFF16A34A),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF16A34A)
                                          .withOpacity(0.40),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.verified_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF16A34A).withOpacity(0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              "APPROVED",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "You're Eligible\nto Donate!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF14532D),
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Your screening has been reviewed and approved.\nYou can now book a blood donation appointment.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF166534),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.bloodtype_rounded,
                              iconColor: const Color(0xFFDC2626),
                              iconBg: const Color(0xFFFFF1F1),
                              value: "1 Life",
                              label: "per donation",
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statCard(
                              icon: Icons.people_alt_rounded,
                              iconColor: const Color(0xFF2563EB),
                              iconBg: const Color(0xFFEFF6FF),
                              value: "3 People",
                              label: "can be helped",
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statCard(
                              icon: Icons.timer_rounded,
                              iconColor: const Color(0xFF9333EA),
                              iconBg: const Color(0xFFFAF5FF),
                              value: "~1 Hour",
                              label: "total time",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFBBF7D0),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF16A34A).withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.checklist_rounded,
                                  color: Color(0xFF16A34A),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "What to expect at your appointment",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14532D),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _expectStep(
                              Icons.assignment_ind_outlined,
                              "Registration & ID verification",
                            ),
                            const SizedBox(height: 8),
                            _expectStep(
                              Icons.monitor_heart_outlined,
                              "Quick mini-physical (BP, hemoglobin)",
                            ),
                            const SizedBox(height: 8),
                            _expectStep(
                              Icons.water_drop_outlined,
                              "Blood draw — takes about 8–10 minutes",
                            ),
                            const SizedBox(height: 8),
                            _expectStep(
                              Icons.local_cafe_outlined,
                              "Rest & refreshments before you go",
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: onBookAppointment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            shadowColor:
                                const Color(0xFF16A34A).withOpacity(0.40),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 20),
                              SizedBox(width: 10),
                              Text(
                                "Book an Appointment",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Color(0xFF16A34A),
                            ),
                            SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                "Approval is valid for your next scheduled donation session.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF166534),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1FAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xFF14532D),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expectStep(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: const Color(0xFF16A34A),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF374151),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingOverlay extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _PendingOverlay({
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(0.97),
      child: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFFF59E0B),
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFFBEB),
                        border: Border.all(
                          color: const Color(0xFFFDE68A),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFF59E0B).withOpacity(0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        size: 46,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Screening Under Review",
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Your previous eligibility screening is currently being reviewed. You may view the screening form below, but please wait for your results before submitting again.",
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: Color(0xFFD97706),
                          ),
                          SizedBox(width: 7),
                          Text(
                            "Status: Pending Review",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFD97706),
                                size: 17,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "What happens next?",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _nextStep(
                            "1",
                            "Our team reviews your screening answers.",
                          ),
                          const SizedBox(height: 6),
                          _nextStep(
                            "2",
                            "You'll be notified once a decision is made.",
                          ),
                          const SizedBox(height: 6),
                          _nextStep(
                            "3",
                            "If approved, you can book a donation appointment.",
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      "Swipe down to refresh your screening status.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD97706),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Please check back later. You will be notified once a decision has been made.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        height: 1.5,
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

  Widget _nextStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFF59E0B),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF92400E),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}