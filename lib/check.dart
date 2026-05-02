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
  List<String>? extraData; // ✅ NEW
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
      setState(() {
        isLoading = false;
      });
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          "followup_answer": _followUpControllers[i].text
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data["message"] ?? "Submitted"),
          backgroundColor: Colors.green,
        ),
      );
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
    final answeredCount = questions.where((q) => q.answer != null).length;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // HEADER (UNCHANGED)
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

          // PROGRESS BAR (UNCHANGED)
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
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                  ),
                ),
              ],
            ),
          ),

          // QUESTIONS
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) =>
                  setState(() => _currentPage = index),
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
                            Text(
                              q.question,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            // ✅ DYNAMIC LIST (NO UI BREAK)
                            if (q.extraData != null &&
                                q.extraData!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFE5E7EB)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "List:",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...q.extraData!.map((item) => Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 2),
                                          child: Text("• $item",
                                              style: const TextStyle(
                                                  fontSize: 12)),
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
                                    selectedColor:
                                        const Color(0xFF16A34A),
                                    selectedBg:
                                        const Color(0xFFF0FDF4),
                                    selectedBorder:
                                        const Color(0xFFBBF7D0),
                                    onTap: () {
                                      setState(() {
                                        q.answer = 'yes';
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _answerButton(
                                    label: "No",
                                    icon: Icons.cancel_rounded,
                                    selected: q.answer == 'no',
                                    selectedColor:
                                        const Color(0xFFDC2626),
                                    selectedBg:
                                        const Color(0xFFFFF1F1),
                                    selectedBorder:
                                        const Color(0xFFFECACA),
                                    onTap: () {
                                      setState(() {
                                        q.answer = 'no';
                                        q.followUp = null;
                                        _followUpControllers[index]
                                            .clear();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (q.answer == q.followUpTrigger)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextField(
                            controller: _followUpControllers[index],
                            onChanged: (val) => q.followUp = val,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: q.followUpPrompt,
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // BUTTONS (UNCHANGED)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _goPrev,
                      child: const Text("Previous"),
                    ),
                  ),
                if (_currentPage > 0)
                  const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _goNext,
                    child:
                        Text(_isLastPage ? "Submit" : "Next"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white,
          border: Border.all(
            color: selected ? selectedBorder : Colors.grey,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(label)),
      ),
    );
  }
}