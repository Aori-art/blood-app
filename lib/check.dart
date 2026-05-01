import 'package:flutter/material.dart';

class Question {
  String id;
  String question;
  String? answer;
  String? followUp;

  Question({
    required this.id,
    required this.question,
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
  List<Question> questions = [
    Question(id: '1', question: 'Are you currently feeling healthy and well?'),
    Question(id: '2', question: 'Have you donated blood in the last 8 weeks?'),
    Question(id: '3', question: 'Are you taking any medications?'),
    Question(id: '4', question: 'Have you had dental work in the last 24 hours?'),
    Question(id: '5', question: 'Have you traveled recently?'),
    Question(id: '6', question: 'Have you had tattoos/piercings recently?'),
    Question(id: '7', question: 'Do you have chronic illness?'),
    Question(id: '8', question: 'Have you had fever recently?'),
    Question(id: '9', question: 'Are you pregnant/recently pregnant?'),
    Question(id: '10', question: 'Have you consumed alcohol recently?'),
  ];

  void submit() {
    bool allAnswered = questions.every((q) => q.answer != null);

    if (!allAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please answer all questions")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Submitted successfully")),
    );
  }

  Widget buildQuestionCard(Question q, int index) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${index + 1}. ${q.question}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Row(
                  children: [
                    Radio(
                      value: 'yes',
                      groupValue: q.answer,
                      activeColor: Colors.green.shade700,
                      onChanged: (val) {
                        setState(() {
                          q.answer = val.toString();
                          if (q.answer == 'no') q.followUp = null;
                        });
                      },
                    ),
                    const Text(
                      "Yes",
                      style: TextStyle(color: Color(0xFF2E7D32)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Radio(
                      value: 'no',
                      groupValue: q.answer,
                      activeColor: Colors.red.shade700,
                      onChanged: (val) {
                        setState(() {
                          q.answer = val.toString();
                        });
                      },
                    ),
                    const Text(
                      "No",
                      style: TextStyle(color: Color(0xFFC62828)),
                    ),
                  ],
                ),
              ],
            ),

            if (q.answer == 'yes')
              Column(
                children: [
                  const Divider(),
                  TextField(
                    onChanged: (val) => q.followUp = val,
                    decoration: const InputDecoration(
                      hintText: "Provide more details...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // 🔥 HEADER
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
                      fontWeight: FontWeight.bold),
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
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: questions.length,
                      itemBuilder: (context, index) =>
                          buildQuestionCard(questions[index], index),
                    ),
                  ),

                  const SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF750000),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Submit Eligibility Check"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}