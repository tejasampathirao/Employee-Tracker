import 'package:flutter/material.dart';
import '../screens/home.dart';
import '../database/db_helper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  static const String id = 'register_screen';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  
  String _selectedRole = 'Employee';
  bool _isLoading = false;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1.0);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final String name = _nameController.text.trim();
      final String empId = _idController.text.trim();

      final bool success = await DatabaseHelper.instance.registerUserWithNameIdRole(name, empId, _selectedRole);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registered successfully! Welcome aboard.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pushNamedAndRemoveUntil(context, HomePage.id, (route) => false);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee ID already exists. Please log in.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during registration: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green[900]!.withValues(alpha: 0.05),
              Colors.white,
              Colors.blue[50]!.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
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
                    icon: Icon(Icons.arrow_back_ios_new, color: theme.colorScheme.primary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Create Account',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                  const Text('Sign up to start tracking your work.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 40),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: <Widget>[
                        _buildTextField(
                          controller: _nameController,
                          hint: 'Full Name',
                          icon: Icons.person_outline,
                          validator: (v) => v!.isEmpty ? 'Enter your name' : null,
                        ),
                        const SizedBox(height: 20.0),
                        _buildTextField(
                          controller: _idController,
                          hint: 'Employee ID (e.g., AMP-001)',
                          icon: Icons.badge_outlined,
                          type: TextInputType.text,
                          validator: (v) => v!.isEmpty ? 'Enter your ID' : null,
                        ),
                        const SizedBox(height: 20.0),
                        _buildRoleDropdown(),
                        const SizedBox(height: 40.0),
                        _buildRegisterButton(),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? type,
    String? Function(String?)? validator
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedRole,
        decoration: InputDecoration(
          icon: Icon(Icons.admin_panel_settings_outlined, color: theme.colorScheme.primary),
          border: InputBorder.none,
        ),
        items: ['Employee', 'Admin', 'Trainee'].map((role) {
          return DropdownMenuItem(value: role, child: Text(role));
        }).toList(),
        onChanged: (v) {
          if (v != null) setState(() => _selectedRole = v);
        },
      ),
    );
  }

  Widget _buildRegisterButton() {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xff21b409), Color(0xff1565C0)]),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _isLoading
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('REGISTER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
      ),
    );
  }
}
