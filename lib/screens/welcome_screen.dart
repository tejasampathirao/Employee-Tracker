import 'package:flutter/material.dart';
import '../components/rounded_button.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  static const String id = 'welcome_screen';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(flex: 2),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'EMPLOYEE ',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.blue[900],
                            letterSpacing: 0.5,
                          ),
                        ),
                        TextSpan(
                          text: 'TRACKER',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            color: Colors.green[700],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Professional HR Management Solution',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 14),
                ),
              ),
              const Spacer(flex: 1),
              const SizedBox(height: 48.0),
              RoundedButton(
                title: 'Log In',
                colour: Colors.blue[800]!,
                onPressed: () {
                  Navigator.pushNamed(context, LoginScreen.id);
                },
              ),
              const SizedBox(height: 12),
              RoundedButton(
                title: 'Register',
                colour: const Color(0xff21b409),
                onPressed: () {
                  Navigator.pushNamed(context, RegisterScreen.id);
                },
              ),
              const Spacer(flex: 2),
              const Center(
                child: Text(
                  'Employee Tracker',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
