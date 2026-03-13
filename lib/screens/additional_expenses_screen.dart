import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/mqtt_handler.dart';
import '../database/db_helper.dart';
import '../utils/app_logger.dart';

class AdditionalExpensesScreen extends StatefulWidget {
  const AdditionalExpensesScreen({super.key});
  static const String id = 'additional_expenses_screen';

  @override
  State<AdditionalExpensesScreen> createState() => _AdditionalExpensesScreenState();
}

class _AdditionalExpensesScreenState extends State<AdditionalExpensesScreen> {
  // 1. State Management Variables
  bool hasFood = false;
  bool hasFuel = false;
  bool hasTravel = false;

  final TextEditingController foodDesc = TextEditingController();
  final TextEditingController foodAmount = TextEditingController();
  final TextEditingController fuelDesc = TextEditingController();
  final TextEditingController fuelAmount = TextEditingController();

  String? selectedTravelMode;
  bool _isSubmitting = false;

  @override
  void dispose() {
    foodDesc.dispose();
    foodAmount.dispose();
    fuelDesc.dispose();
    fuelAmount.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_isSubmitting) return;
    
    if (!hasFood && !hasFuel && !hasTravel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable at least one expense type.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = await DatabaseHelper.instance.getUser();
      final String employeeId = user != null ? (user['emp_id'] ?? 'Unknown') : 'Unknown';

      // 4. Submission Logic & MQTT Payload
      final Map<String, dynamic> payload = {
        "type": "additional_expense",
        "employee_id": employeeId,
        "timestamp": DateTime.now().toIso8601String(),
      };

      if (hasFood) {
        payload["food_desc"] = foodDesc.text;
        payload["food_amt"] = double.tryParse(foodAmount.text) ?? 0.0;
      }

      if (hasFuel) {
        payload["fuel_desc"] = fuelDesc.text;
        payload["fuel_amt"] = double.tryParse(fuelAmount.text) ?? 0.0;
      }

      if (hasTravel) {
        payload["travel_mode"] = selectedTravelMode;
      }

      final String jsonString = jsonEncode(payload);
      
      // Publish to MQTT topic: employee/tracker/expenses
      MqttHandler().publish('employee/tracker/expenses', jsonString);
      AppLogger.log('MQTT: Published additional expenses: $jsonString');

      // Also save locally for history (using the common expenses table)
      if (hasFood) {
        await DatabaseHelper.instance.insertExpense({
          'type': 'Food',
          'category': 'Additional',
          'description': foodDesc.text,
          'amount': double.tryParse(foodAmount.text) ?? 0.0,
          'date': DateTime.now().toIso8601String(),
          'status': 'Pending'
        });
      }
      
      if (hasFuel) {
        await DatabaseHelper.instance.insertExpense({
          'type': 'Fuel',
          'category': 'Additional',
          'description': fuelDesc.text,
          'amount': double.tryParse(fuelAmount.text) ?? 0.0,
          'date': DateTime.now().toIso8601String(),
          'status': 'Pending'
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses submitted successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      AppLogger.log('Error submitting expenses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Additional Expenses'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      // 1. Fix Layout (Overflow Error)
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Food Expenses Section
            _buildSection(
              title: "Food Expenses",
              icon: Icons.restaurant,
              isActive: hasFood,
              onToggle: (val) => setState(() => hasFood = val),
              child: Column(
                children: [
                  TextField(
                    controller: foodDesc,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Lunch with client',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: foodAmount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Fuel Expenses Section
            _buildSection(
              title: "Fuel Expenses",
              icon: Icons.local_gas_station,
              isActive: hasFuel,
              onToggle: (val) => setState(() => hasFuel = val),
              child: Column(
                children: [
                  TextField(
                    controller: fuelDesc,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Bike petrol',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fuelAmount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹)',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Travel Expenses Section
            _buildSection(
              title: "Travel Expenses",
              icon: Icons.directions_bus,
              isActive: hasTravel,
              onToggle: (val) => setState(() => hasTravel = val),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Travel Mode:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: selectedTravelMode,
                    onChanged: (val) => setState(() => selectedTravelMode = val),
                    child: Column(
                      children: [
                        _buildRadioTile("Rapido"),
                        _buildRadioTile("Bus"),
                        _buildRadioTile("Two Wheeler"),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            if (_isSubmitting)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Save Changes', 
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile(String mode) {
    return RadioListTile<String>(
      title: Text(mode),
      value: mode,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required bool isActive,
    required Function(bool) onToggle,
    required Widget child,
  }) {
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
                Row(
                  children: [
                    Icon(icon, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Switch(
                  value: isActive, 
                  onChanged: onToggle,
                  activeThumbColor: Colors.blueAccent,
                ),
              ],
            ),
            if (isActive) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Divider(),
              ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}
