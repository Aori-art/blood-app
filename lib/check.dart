import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

class _CheckScreenState extends State<CheckScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _started = false;

  late List<TextEditingController> _followUpControllers;

  List<Question> questions = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchQuestions();
  }

  Future<void> fetchQuestions() async {
    try {
      final response = await http.get(
        Uri.parse("${AppConfig.baseUrl}/get_screening_questions.php"),
      );

      final data = jsonDecode(response.body);

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
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  void _goNext() {
    if (!_currentAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text("Please answer this question to continue."),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
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

  Future<void> _submit() async {
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
        body: jsonEncode({"donor_id": donorId, "answers": answers}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data["message"] ?? "Submitted"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );

      // Return to intro screen after submit
      setState(() {
        _started = false;
        _currentPage = 0;
        for (var q in questions) {
          q.answer = null;
          q.followUp = null;
        }
        for (var c in _followUpControllers) {
          c.clear();
        }
        _pageController.jumpToPage(0);
      });
    } catch (e) {
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

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // HEADER — unchanged
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenHeight * 0.06,
              bottom: screenHeight * 0.03,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF750000), Color(0xFFFF4E4E)],
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
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
    );
  }

  // ── INTRO SCREEN ──────────────────────────────────────────────
  Widget _buildIntroScreen({Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Column(
        children: [
          // Hero illustration area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF1F1), Color(0xFFFFE4E4)],
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
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Info cards
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

          // Disclaimer box
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
                Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
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

          // Start button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _started = true),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text(
                "Start Eligibility Check",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
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
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── QUESTIONNAIRE ─────────────────────────────────────────────
  Widget _buildQuestionnaire({Key? key}) {
    final answeredCount = questions.where((q) => q.answer != null).length;

    return Column(
      key: key,
      children: [
        // PROGRESS BAR
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
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
        ),

        // PAGE VIEW
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

                    // Question card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFE5E7EB), width: 1.5),
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
                                horizontal: 10, vertical: 4),
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
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("List:",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const SizedBox(height: 8),
                                  ...q.extraData!.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Text("• $item",
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      )),
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

                    // Follow-up card
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
                                      width: 1.5),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 6,
                                        offset: Offset(0, 3)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline,
                                            color: Color(0xFF16A34A), size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          "Follow-up Question",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF16A34A),
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
                                            fontSize: 13),
                                        filled: true,
                                        fillColor: const Color(0xFFF9FAFB),
                                        contentPadding: const EdgeInsets.all(14),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFD1D5DB)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFD1D5DB)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: Color(0xFF16A34A),
                                              width: 1.5),
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

        // BOTTOM NAV BUTTONS
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              // Back to intro on first page
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
                          borderRadius: BorderRadius.circular(12)),
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
                          borderRadius: BorderRadius.circular(12)),
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
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
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
            Icon(icon,
                size: 20,
                color: selected ? selectedColor : const Color(0xFF9CA3AF)),
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