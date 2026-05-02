import 'package:flutter/material.dart';

class Question {
  String id;
  String question;
  String followUpPrompt;
  String? answer;
  String? followUp;

  Question({
    required this.id,
    required this.question,
    this.followUpPrompt = "Please provide more details...",
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

  List<Question> questions = [
    Question(
      id: '1',
      question: 'Are you currently feeling healthy and well?',
      followUpPrompt: 'What symptoms are you experiencing?',
    ),
    Question(
      id: '2',
      question: 'Have you donated blood in the last 8 weeks?',
      followUpPrompt: 'When was your last donation?',
    ),
    Question(
      id: '3',
      question: 'Are you taking any medications?',
      followUpPrompt: 'Please list the medications you are currently taking.',
    ),
    Question(
      id: '4',
      question: 'Have you had dental work in the last 24 hours?',
      followUpPrompt: 'What type of dental procedure did you have?',
    ),
    Question(
      id: '5',
      question: 'Have you traveled recently?',
      followUpPrompt: 'Where did you travel and when did you return?',
    ),
    Question(
      id: '6',
      question: 'Have you had tattoos or piercings recently?',
      followUpPrompt: 'When did you get your tattoo or piercing?',
    ),
    Question(
      id: '7',
      question: 'Do you have any chronic illness?',
      followUpPrompt: 'Please describe your condition.',
    ),
    Question(
      id: '8',
      question: 'Have you had a fever recently?',
      followUpPrompt: 'When did the fever occur and how high was it?',
    ),
    Question(
      id: '9',
      question: 'Are you pregnant or recently pregnant?',
      followUpPrompt: 'Please provide details (e.g., weeks pregnant or postpartum).',
    ),
    Question(
      id: '10',
      question: 'Have you consumed alcohol in the last 24 hours?',
      followUpPrompt: 'How much alcohol did you consume?',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _followUpControllers = List.generate(
      questions.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _followUpControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isLastPage => _currentPage == questions.length - 1;
  bool get _currentAnswered => questions[_currentPage].answer != null;

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

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text("Eligibility check submitted successfully!"),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final answeredCount = questions.where((q) => q.answer != null).length;

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

          // PROGRESS BAR + COUNTER
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
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
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

                      // QUESTION CARD
                      Container(
                        width: double.infinity,
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
                            // Question number chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

                            const SizedBox(height: 20),

                            // YES / NO buttons
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

                      // FOLLOW-UP CARD (animated)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: q.answer == 'yes'
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
                                            fontSize: 13,
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF9FAFB),
                                          contentPadding: const EdgeInsets.all(14),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFD1D5DB)),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFD1D5DB)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF16A34A), width: 1.5),
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
                if (_currentPage > 0)
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: _goPrev,
                      icon: const Icon(Icons.arrow_back, size: 18),
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
                if (_currentPage > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _goNext,
                    icon: Icon(
                      _isLastPage ? Icons.check_circle_outline : Icons.arrow_forward,
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