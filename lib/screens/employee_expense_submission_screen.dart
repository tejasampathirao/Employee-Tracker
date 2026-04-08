import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mqtt_handler.dart';
import '../database/db_helper.dart';

class EmployeeExpenseSubmissionScreen extends StatefulWidget {
  const EmployeeExpenseSubmissionScreen({super.key});
  static const String id = 'employee_expense_submission';

  @override
  State<EmployeeExpenseSubmissionScreen> createState() =>
      _EmployeeExpenseSubmissionScreenState();
}

class _EmployeeExpenseSubmissionScreenState
    extends State<EmployeeExpenseSubmissionScreen>
    with WidgetsBindingObserver {
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
  bool _isLoadingBalances = true;
  Map<String, double> _remainingBalances = {
    'Food': 0.0,
    'Fuel': 0.0,
    'Material': 0.0,
    'Travel': 0.0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshRemainingBalances();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRemainingBalances();
    }
  }

  Future<void> _refreshRemainingBalances() async {
    setState(() {
      _isLoadingBalances = true;
    });
    final balances = await _loadRemainingBalances();
    if (!mounted) return;
    setState(() {
      _remainingBalances = balances;
      _isLoadingBalances = false;
    });
  }

  Future<Map<String, double>> _loadRemainingBalances() async {
    final prefs = await SharedPreferences.getInstance();
    final foodLimit = prefs.getDouble('food_amt_limit') ?? 0.0;
    final fuelLimit = prefs.getDouble('fuel_amt_limit') ?? 0.0;
    final materialLimit = prefs.getDouble('material_amt_limit') ?? 0.0;
    final travelLimit = (prefs.getDouble('travel_rapido_limit') ?? 0.0) +
        (prefs.getDouble('travel_bus_limit') ?? 0.0) +
        (prefs.getDouble('travel_own_vehicle_limit') ?? 0.0);

    final user = await DatabaseHelper.instance.getUser();
    final String? employeeId = prefs.getString('employee_id')?.trim() ??
        user?['employee_id']?.toString() ??
        user?['emp_id']?.toString();

    final spentFood = await DatabaseHelper.instance.getCategorySpentThisMonth(
      'Food',
      employeeId: employeeId,
    );
    final spentFuel = await DatabaseHelper.instance.getCategorySpentThisMonth(
      'Fuel',
      employeeId: employeeId,
    );
    final spentMaterial = await DatabaseHelper.instance.getCategorySpentThisMonth(
      'Material',
      employeeId: employeeId,
    );
    final spentTravel = await DatabaseHelper.instance.getCategorySpentThisMonth(
      'Travel',
      employeeId: employeeId,
    );

    return {
      'Food': (foodLimit - spentFood).clamp(0.0, double.infinity),
      'Fuel': (fuelLimit - spentFuel).clamp(0.0, double.infinity),
      'Material': (materialLimit - spentMaterial).clamp(0.0, double.infinity),
      'Travel': (travelLimit - spentTravel).clamp(0.0, double.infinity),
    };
  }

  double _parseAmount(TextEditingController controller) {
    return double.tryParse(controller.text) ?? 0.0;
  }

  bool _validateRemainingBalance(String category, double enteredAmount) {
    final remaining = _remainingBalances[category] ?? 0.0;
    if (enteredAmount > remaining) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limit Exceeded for $category: Remaining ₹${remaining.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _submitExpenses() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final user = await DatabaseHelper.instance.getUser();
      final String employeeId = prefs.getString('employee_id')?.trim() ??
          user?['employee_id']?.toString() ??
          user?['emp_id']?.toString() ??
          'Unknown';

      final Map<String, dynamic> expenses = {};
      final foodAmount = _parseAmount(_foodAmt);
      final fuelAmount = _parseAmount(_fuelAmt);
      final travelAmount = _parseAmount(_travelAmt);
      final materialAmount = _parseAmount(_materialAmt);

      if (_hasFood) {
        if (!_validateRemainingBalance('Food', foodAmount)) {
          setState(() => _isSubmitting = false);
          return;
        }
        expenses['food_amount'] = foodAmount;
        expenses['food_desc'] = _foodDesc.text;
      }

      if (_hasFuel) {
        if (!_validateRemainingBalance('Fuel', fuelAmount)) {
          setState(() => _isSubmitting = false);
          return;
        }
        expenses['fuel_amount'] = fuelAmount;
        expenses['fuel_desc'] = _fuelDesc.text;
      }

      if (_hasTravel) {
        if (!_validateRemainingBalance('Travel', travelAmount)) {
          setState(() => _isSubmitting = false);
          return;
        }
        expenses['travel_amount'] = travelAmount;
        expenses['travel_desc'] = _travelDesc.text;
      }

      if (_hasMaterial) {
        if (!_validateRemainingBalance('Material', materialAmount)) {
          setState(() => _isSubmitting = false);
          return;
        }
        expenses['material_amount'] = materialAmount;
        expenses['material_desc'] = _materialDesc.text;
      }

      if (expenses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select at least one expense category.'),
              backgroundColor: Colors.orange,
            ),
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

      // Refresh balances after submit so the screen reflects the new state.
      final updatedBalances = await _loadRemainingBalances();
      if (mounted) {
        setState(() {
          _remainingBalances = updatedBalances;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expenses submitted for Admin approval'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting expenses: $e'),
            backgroundColor: Colors.red,
          ),
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
      body: _isLoadingBalances
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildExpenseSection(
                    'Food Expenses',
                    _hasFood,
                    (val) => setState(() => _hasFood = val!),
                    _foodDesc,
                    _foodAmt,
                    'Food',
                  ),
                  const SizedBox(height: 20),
                  _buildExpenseSection(
                    'Fuel Expenses',
                    _hasFuel,
                    (val) => setState(() => _hasFuel = val!),
                    _fuelDesc,
                    _fuelAmt,
                    'Fuel',
                  ),
                  const SizedBox(height: 20),
                  _buildExpenseSection(
                    'Travel Expenses',
                    _hasTravel,
                    (val) => setState(() => _hasTravel = val!),
                    _travelDesc,
                    _travelAmt,
                    'Travel',
                  ),
                  const SizedBox(height: 20),
                  _buildExpenseSection(
                    'Material Expenses',
                    _hasMaterial,
                    (val) => setState(() => _hasMaterial = val!),
                    _materialDesc,
                    _materialAmt,
                    'Material',
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitExpenses,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        disabledBackgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send),
                                SizedBox(width: 8),
                                Text(
                                  'SUBMIT FOR APPROVAL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildExpenseSection(
    String title,
    bool isVisible,
    ValueChanged<bool?> onChanged,
    TextEditingController desc,
    TextEditingController amt,
    String categoryKey,
  ) {
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: isVisible,
                  onChanged: onChanged,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            if (isVisible) ...[
              const Divider(height: 30),
              TextField(
                controller: desc,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Enter $title details',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amt,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Remaining: ₹${_remainingBalances[categoryKey]?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
