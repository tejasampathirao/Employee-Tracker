import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const String id = 'welcome_screen';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 40),
              // Top Logo Section
              Column(
                children: [
                  Image.asset(
                    'images/app_logo.png',
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Column(
                      children: [
                        const Icon(Icons.business, size: 80, color: Colors.blue),
                        const SizedBox(height: 10),
                        Text(
                          'AMPEREPLUS',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                        const Text(
                          'Engineering & Services',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Middle Buttons Section
              Column(
                children: [
                  _buildButton(
                    context,
                    label: 'Log In',
                    color: const Color(0xff1565C0), // Professional Blue
                    onPressed: () => Navigator.pushNamed(context, LoginScreen.id),
                  ),
                  const SizedBox(height: 20),
                  _buildButton(
                    context,
                    label: 'Register',
                    color: const Color(0xff2E7D32), // Professional Green
                    onPressed: () => Navigator.pushNamed(context, RegisterScreen.id),
                  ),
                ],
              ),

              // Bottom Footer
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Text(
                  '© 2026 AmperePlus Engineering. All Rights Reserved.',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
