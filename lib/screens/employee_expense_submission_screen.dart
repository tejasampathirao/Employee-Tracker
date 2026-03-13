import 'package:flutter/material.dart';
import '../services/mqtt_handler.dart';
import '../database/db_helper.dart';

class EmployeeExpenseSubmissionScreen extends StatefulWidget {
  const EmployeeExpenseSubmissionScreen({super.key});
  static const String id = 'employee_expense_submission';

  @override
  State<EmployeeExpenseSubmissionScreen> createState() => _EmployeeExpenseSubmissionScreenState();
}

class _EmployeeExpenseSubmissionScreenState extends State<EmployeeExpenseSubmissionScreen> {
  // Category Selections
  bool _hasFood = false;
  bool _hasFuel = false;
  bool _hasTravel = false;
  bool _hasMaterial = false;

  // Controllers
  final _foodDesc = TextEditingController();
  final _foodAmt = TextEditingController();
  final _fuelDesc = TextEditingController();
  final _fuelAmt = TextEditingController();
  final _travelDesc = TextEditingController();
  final _travelAmt = TextEditingController();
  final _materialDesc = TextEditingController();
  final _materialAmt = TextEditingController();

  bool _isSubmitting = false;

  Future<void> _submitExpenses() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final user = await DatabaseHelper.instance.getUser();
      final String employeeId = user?['name'] ?? 'Unknown';

      final Map<String, dynamic> expenses = {};

      if (_hasFood) {
        expenses['food_amount'] = double.tryParse(_foodAmt.text) ?? 0.0;
        expenses['food_desc'] = _foodDesc.text;
      }

      if (_hasFuel) {
        expenses['fuel_amount'] = double.tryParse(_fuelAmt.text) ?? 0.0;
        expenses['fuel_desc'] = _fuelDesc.text;
      }

      if (_hasTravel) {
        expenses['travel_amount'] = double.tryParse(_travelAmt.text) ?? 0.0;
        expenses['travel_desc'] = _travelDesc.text;
      }

      if (_hasMaterial) {
        expenses['material_amount'] = double.tryParse(_materialAmt.text) ?? 0.0;
        expenses['material_desc'] = _materialDesc.text;
      }

      if (expenses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select at least one expense category.'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // MQTT Publish
      MqttHandler().publishExpenseReport(
        employeeId: employeeId,
        expenses: expenses,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses submitted for Admin approval'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting expenses: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Daily Expenses'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildExpenseSection('Food Expenses', _hasFood, (val) => setState(() => _hasFood = val!), _foodDesc, _foodAmt),
            const SizedBox(height: 20),
            _buildExpenseSection('Fuel Expenses', _hasFuel, (val) => setState(() => _hasFuel = val!), _fuelDesc, _fuelAmt),
            const SizedBox(height: 20),
            _buildExpenseSection('Travel Expenses', _hasTravel, (val) => setState(() => _hasTravel = val!), _travelDesc, _travelAmt),
            const SizedBox(height: 20),
            _buildExpenseSection('Material Expenses', _hasMaterial, (val) => setState(() => _hasMaterial = val!), _materialDesc, _materialAmt),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitExpenses,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  disabledBackgroundColor: theme.colorScheme.primary.withOpacity(0.6),
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send),
                        SizedBox(width: 8),
                        Text('SUBMIT FOR APPROVAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseSection(String title, bool isVisible, ValueChanged<bool?> onChanged, TextEditingController desc, TextEditingController amt) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Switch(value: isVisible, onChanged: onChanged, activeThumbColor: Theme.of(context).colorScheme.primary),
              ],
            ),
            if (isVisible) ...[
              const Divider(height: 30),
              TextField(
                controller: desc,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Enter $title details',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amt,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
