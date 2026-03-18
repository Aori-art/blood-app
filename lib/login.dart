import 'package:flutter/material.dart';
import 'register.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: const [
          Iphone161(),
        ],
      ),
    );
  }
}

class Iphone161 extends StatelessWidget {
  const Iphone161({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 393,
      height: 852,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(0.50, 0.09),
          end: Alignment(0.50, 0.34),
          colors: [Color(0xFF750000), Color(0xFFDA2D2D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 294,
            child: Container(
              width: 393,
              height: 709,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),

          // Title
          const Positioned(
            left: 17,
            top: 319,
            child: Text(
              'Welcome Back',
              style: TextStyle(
                color: Color(0xFF750000),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const Positioned(
            left: 17,
            top: 346,
            child: Text(
              'Sign in to continue saving lives',
              style: TextStyle(
                color: Color(0xFF666464),
                fontSize: 14,
              ),
            ),
          ),

          // Email label
          const Positioned(
            left: 17,
            top: 397,
            child: Text(
              'Email Address',
              style: TextStyle(fontSize: 10),
            ),
          ),

          // Email field (FIXED → real TextField)
          Positioned(
            left: 17,
            top: 414,
            child: SizedBox(
              width: 357,
              height: 40,
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

          // Password label
          const Positioned(
            left: 17,
            top: 460,
            child: Text(
              'Password',
              style: TextStyle(fontSize: 10),
            ),
          ),

          // Password field (FIXED → real TextField)
          Positioned(
            left: 17,
            top: 480,
            child: SizedBox(
              width: 357,
              height: 40,
              child: TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  filled: true,
                  fillColor: const Color(0xFFD9D9D9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),

          // Login Button (FIXED → clickable)
          Positioned(
            left: 100,
            top: 550,
            child: SizedBox(
              width: 200,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF850000),
                ),
                onPressed: () {
                  // TODO: Navigate to home screen
                },
                child: const Text("Sign In"),
              ),
            ),
          ),

          // Footer text
          const Positioned(
            left: 80,
            top: 620,
            child: Text(
              'New to eDonate?',
              style: TextStyle(fontSize: 12),
            ),
          ),

          Positioned(
           left: 200,
           top: 620,
           child: GestureDetector(
           onTap: () {
           Navigator.push(
            context,
          MaterialPageRoute(
              builder: (context) => const RegisterScreen(),
              ),
            );
          },
          child: const Text(
            'Create an Account',
              style: TextStyle(
              color: Color(0xFF850000),
              fontWeight: FontWeight.bold,
              ),
          ),
        ),
      ),

          // App title
          const Positioned(
            left: 120,
            top: 85,
            child: Text(
              'eDonate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const Positioned(
            left: 120,
            top: 125,
            child: Text(
              'Blood Donation App',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}