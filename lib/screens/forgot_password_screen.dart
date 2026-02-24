import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../database/db_helper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  static const String id = 'forgot_password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _currentStep = 1;
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _generatedCode;

  Future<void> sendOtpEmail(String recipientEmail, String otpCode) async {
    // REPLACE THESE WITH YOUR ACTUAL GMAIL AND APP PASSWORD
    String username = 'YOUR_GMAIL_ADDRESS@gmail.com';
    String password = 'YOUR_GOOGLE_APP_PASSWORD'; 

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'Employee Tracker Support')
      ..recipients.add(recipientEmail)
      ..subject = 'Your Verification Code'
      ..html = '''
        <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px; max-width: 500px;">
          <h2 style="color: #1565C0; margin-bottom: 20px;">Verification Code</h2>
          <p style="font-size: 16px; color: #333;">Your Employee Tracker verification code is:</p>
          <div style="font-size: 32px; font-weight: bold; color: #1565C0; background-color: #f5f5f5; padding: 15px; text-align: center; border-radius: 8px; margin: 20px 0; letter-spacing: 5px;">
            $otpCode
          </div>
          <p style="font-size: 14px; color: #666;">Enter this code in the app to continue with your password reset.</p>
          <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
          <p style="font-size: 12px; color: #888;">If you did not request this, please ignore this email.</p>
        </div>
      ''';

    try {
      await send(message, smtpServer);
    } catch (e) {
      debugPrint('Error sending email: $e');
      rethrow;
    }
  }

  void _sendEmailCode() async {
    // Generates a 6-digit code
    _generatedCode = (100000 + (900000 * (DateTime.now().millisecond / 1000)).floor()).toString();
    
    // Show loading feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending verification code...'), duration: Duration(seconds: 2)),
    );

    try {
      await sendOtpEmail(_emailController.text, _generatedCode!);
      
      if (mounted) {
        setState(() => _currentStep = 2);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent to email')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send email. Check your SMTP settings.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Reset Password', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: 40),
              _buildStepContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _indicatorCircle(1, "Email"),
        _indicatorLine(1),
        _indicatorCircle(2, "Code"),
        _indicatorLine(2),
        _indicatorCircle(3, "Reset"),
      ],
    );
  }

  Widget _indicatorCircle(int step, String label) {
    bool isActive = _currentStep >= step;
    return Column(
      children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: isActive ? Colors.blue[800] : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              "$step",
              style: TextStyle(color: isActive ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.blue[800] : Colors.grey[600])),
      ],
    );
  }

  Widget _indicatorLine(int afterStep) {
    bool isActive = _currentStep > afterStep;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.only(left: 8, right: 8, bottom: 15),
      color: isActive ? Colors.blue[800] : Colors.grey[200],
    );
  }

  Widget _buildStepContent() {
    if (_currentStep == 1) {
      return _buildEmailStep();
    } else if (_currentStep == 2) {
      return _buildCodeStep();
    } else {
      return _buildResetStep();
    }
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Registered Email', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Enter the email address associated with your account.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _styledTextField(
          controller: _emailController,
          hint: 'Enter your email',
          icon: Icons.email_outlined,
          type: TextInputType.emailAddress,
        ),
        const SizedBox(height: 40),
        _actionButton('SEND CODE', _sendEmailCode),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verification Code', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('We\'ve sent a 6-digit code to ${_emailController.text}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _styledTextField(
          controller: _codeController,
          hint: '6-Digit Code',
          icon: Icons.security_outlined,
          type: TextInputType.number,
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: _sendEmailCode,
          child: const Text('Resend Code', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 40),
        _actionButton('VERIFY CODE', () {
          if (_codeController.text == _generatedCode) {
            setState(() => _currentStep = 3);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid verification code')));
          }
        }),
      ],
    );
  }

  Widget _buildResetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Set New Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Your identity has been verified. Choose a strong new password.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        _styledTextField(
          controller: _passwordController,
          hint: 'New Password',
          icon: Icons.lock_outline,
          isPassword: true,
        ),
        const SizedBox(height: 20),
        _styledTextField(
          controller: _confirmPasswordController,
          hint: 'Confirm Password',
          icon: Icons.lock_reset_outlined,
          isPassword: true,
        ),
        const SizedBox(height: 40),
        _actionButton('UPDATE PASSWORD', () async {
          if (_passwordController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password cannot be empty')));
            return;
          }
          if (_passwordController.text == _confirmPasswordController.text) {
            await DatabaseHelper.instance.updatePassword(_passwordController.text);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password updated successfully! Log in now.')),
              );
              Navigator.pop(context);
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
          }
        }),
      ],
    );
  }

  Widget _styledTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? type
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.blue[800]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[800],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
