import 'package:flutter/material.dart';
import '../screens/home.dart';
import '../screens/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  static const String id = 'login_screen';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _keyL = GlobalKey();
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Stack allows drawing behind the system bars if needed, but we use Container with gradient
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[900]!.withOpacity(0.05),
              Colors.white,
              Colors.green[50]!.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          // SafeArea ensures content doesn't overlap with system UI buttons/notch
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 800),
            opacity: _opacity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 20),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.blue, size: 20),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  const Text(
                    'Log in to your workspace to continue.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 50),
                  Form(
                    key: _keyL,
                    child: Column(
                      children: <Widget>[
                        _buildStyledTextField(
                          hint: 'Email Address',
                          icon: Icons.alternate_email,
                          type: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20.0),
                        _buildStyledTextField(
                          hint: 'Password',
                          icon: Icons.lock_open_rounded,
                          isPassword: true,
                        ),
                        const SizedBox(height: 15),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()));
                            },
                            child: const Text('Forgot Password?', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 40.0),
                        Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [Colors.blue[800]!, const Color(0xff21b409)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue[800]!.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamedAndRemoveUntil(context, HomePage.id, (route) => false);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text(
                              'LOG IN',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR', style: TextStyle(color: Colors.grey)),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Center(
                          child: Wrap(
                            spacing: 20,
                            children: [
                              _buildSocialButton(Icons.fingerprint, Colors.blue),
                              _buildSocialButton(Icons.face_unlock_rounded, Colors.green),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledTextField({required String hint, required IconData icon, bool isPassword = false, TextInputType? type}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        obscureText: isPassword,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          prefixIcon: Icon(icon, color: Colors.blue[900], size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildSocialButton(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

