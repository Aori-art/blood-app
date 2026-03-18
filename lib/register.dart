import 'package:flutter/material.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: const [
          Step1(),
        ],
      ),
    );
  }
}

class Step1 extends StatelessWidget {
  const Step1({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 393,
      height: 852,
      decoration: const BoxDecoration(
        color: Color(0xFFAE0000),
      ),
      child: Stack(
        children: [
          // White container
          Positioned(
            top: 220,
            left: 0,
            child: Container(
              width: 393,
              height: 650,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),

          // Title
          const Positioned(
            top: 150,
            left: 60,
            child: Text(
              'Step 1 of 3: Personal Information',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),

          const Positioned(
            top: 74,
            left: 140,
            child: Text(
              'eDonate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Full Name
          const Positioned(
            top: 260,
            left: 20,
            child: Text('Full Name'),
          ),

          Positioned(
            top: 280,
            left: 20,
            child: SizedBox(
              width: 350,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Juan Dela Cruz',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // Email
          const Positioned(
            top: 340,
            left: 20,
            child: Text('Email Address'),
          ),

          Positioned(
            top: 360,
            left: 20,
            child: SizedBox(
              width: 350,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'your.email@gmail.com',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // Phone
          const Positioned(
            top: 420,
            left: 20,
            child: Text('Phone Number'),
          ),

          Positioned(
            top: 440,
            left: 20,
            child: SizedBox(
              width: 350,
              child: TextField(
                decoration: InputDecoration(
                  hintText: '0912 345 6789',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // DOB
          const Positioned(
            top: 500,
            left: 20,
            child: Text('Date of Birth'),
          ),

          Positioned(
            top: 520,
            left: 20,
            child: SizedBox(
              width: 350,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'dd/mm/yyyy',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // Gender
          const Positioned(
            top: 580,
            left: 20,
            child: Text('Gender'),
          ),

          Positioned(
            top: 600,
            left: 20,
            child: SizedBox(
              width: 350,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Male / Female',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // Next Button
          Positioned(
            top: 680,
            left: 100,
            child: SizedBox(
              width: 200,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF850000),
                ),
                onPressed: () {
                  // TODO: Go to Step 2
                },
                child: const Text("Next"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}