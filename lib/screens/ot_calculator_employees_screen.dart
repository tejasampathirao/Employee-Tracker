import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../services/mqtt_handler.dart';

class OTCalculatorEmployeesScreen extends StatefulWidget {
  const OTCalculatorEmployeesScreen({super.key});
  static const String id = 'ot_calculator_employees_screen';

  @override
  State<OTCalculatorEmployeesScreen> createState() => _OTCalculatorEmployeesScreenState();
}

class _OTCalculatorEmployeesScreenState extends State<OTCalculatorEmployeesScreen> {
  final TextEditingController _otRateController = TextEditingController(text: '0');
  final TextEditingController _fixedSalaryController = TextEditingController(text: '0');

  String _otPayoutPeriod = 'Weekly';
  double _otHourlyRate = 0;
  int _otWeeklyMins = 0;
  int _otMonthlyMins = 0;
  bool _isOtLoading = false;
  String? _otEmployeeId;
  String? _otEmployeeName;
  double _baseSalary = 0.0;
  double _adjustedFixedSalary = 0.0;
  int _presentDays = 0;
  int _payableDays = 0;
  int _absentDays = 0;
  double _deduction = 0.0;
  double _approvedExpenses = 0.0;
  double _totalMonthlyPayout = 0.0;
  Timer? _prefsSaveTimer;

  @override
  void dispose() {
    _prefsSaveTimer?.cancel();
    _otRateController.dispose();
    _fixedSalaryController.dispose();
    super.dispose();
  }

  void _schedulePayrollPrefsSave() {
    _prefsSaveTimer?.cancel();
    _prefsSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_otEmployeeId == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ot_rate_${_otEmployeeId}', _otHourlyRate);
      await prefs.setDouble('fixed_salary_${_otEmployeeId}', _baseSalary);
    });
  }

  Future<void> _loadOtStats(String empId, String empName) async {
    setState(() {
      _isOtLoading = true;
      _otEmployeeId = empId;
      _otEmployeeName = empName;
    });

    final now = DateTime.now();
    final monthYear = DateFormat('yyyy-MM').format(now);
    
    // Fetch stats from DB
    final approvedExpenses = await DatabaseHelper.instance.getActualMonthlyExpenseTotal(empId, monthYear);
    final stats = await DatabaseHelper.instance.getEmployeeOTStats(empId);
    final baseSalaryFromDb = await DatabaseHelper.instance.getEmployeeSalary(empId);
    
    // Load from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedRate = prefs.getDouble('ot_rate_$empId') ?? 0.0;
    final savedBaseSalary = prefs.getDouble('fixed_salary_$empId') ?? 0.0;
    
    final presentDays = await DatabaseHelper.instance.getPresentDaysCount(empId, now.month, now.year);
    final sundaysPassed = DatabaseHelper.instance.getSundaysPassed(now);
    final payableDays = presentDays + sundaysPassed;
    final absentDays = now.day - payableDays;

    if (mounted) {
      setState(() {
        _otWeeklyMins = stats['weeklyOTMinutes'] ?? 0;
        _otMonthlyMins = stats['monthlyOTMinutes'] ?? 0;
        
        _baseSalary = savedBaseSalary > 0 ? savedBaseSalary : (baseSalaryFromDb > 0 ? baseSalaryFromDb : 0.0);
        _approvedExpenses = approvedExpenses;
        _presentDays = presentDays;
        _payableDays = payableDays;
        _absentDays = absentDays >= 0 ? absentDays : 0;
        
        _otHourlyRate = savedRate;
        _otRateController.text = _otHourlyRate.toString();
        _fixedSalaryController.text = _baseSalary.toString();
        
        _recalculateTotalPayout();
        _isOtLoading = false;
      });
    }
  }

  void _recalculateTotalPayout() {
    final monthlyOTHours = _otMonthlyMins / 60.0;
    _deduction = (_baseSalary / 30.0) * _absentDays;
    _adjustedFixedSalary = _baseSalary - _deduction;
    _totalMonthlyPayout = _adjustedFixedSalary + (monthlyOTHours * _otHourlyRate) + _approvedExpenses;
  }

  String _formatMins(int totalMins) {
    int h = totalMins ~/ 60;
    int m = totalMins % 60;
    return '${h}h ${m}m';
  }

  double _getCalculatedHours() {
    int mins = _otPayoutPeriod == 'Weekly' ? _otWeeklyMins : _otMonthlyMins;
    return mins / 60.0;
  }

  void _publishOtPayout() {
    if (_otEmployeeId == null) return;

    final otHours = _otMonthlyMins / 60.0;
    final otEarnings = otHours * _otHourlyRate;
    
    final Map<String, dynamic> dynamicPayload = {
      "type": "salary_payout",
      "emp_id": _otEmployeeId,
      "emp_name": _otEmployeeName,
      "month": DateFormat('MMMM yyyy').format(DateTime.now()),
      "base_fixed_salary": double.tryParse(_fixedSalaryController.text) ?? 0.0,
      "adjusted_fixed_salary": _adjustedFixedSalary,
      "absent_days": _absentDays,
      "actual_expenses": _approvedExpenses,
      "ot_earnings": otEarnings,
      "total_monthly_payout": _totalMonthlyPayout,
      "timestamp": DateTime.now().toIso8601String(),
    };

    try {
      MqttHandler().publish(
        MqttHandler().topicOTPayout,
        jsonEncode(dynamicPayload),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Salary Payout Published for $_otEmployeeName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Publish Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error publishing payout'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('OT Calculator Employees'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select Employee to Calculate',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.getAllEmployees(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No employees found.'));
                }

                final employees = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final emp = employees[index];
                    final name = emp['name'] ?? 'Unknown';
                    final empId = emp['emp_id'] ?? 'N/A';
                    final isSelected = _otEmployeeId == empId;
                    return Card(
                      elevation: isSelected ? 4 : 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: isSelected ? const BorderSide(color: Colors.deepOrange, width: 2) : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepOrange[100],
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'E',
                            style: const TextStyle(color: Colors.deepOrange),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('ID: $empId'),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.deepOrange) : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _loadOtStats(empId, name),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            if (_otEmployeeId != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payroll Summary: ${_otEmployeeName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange),
                    ),
                    const Divider(height: 24),
                    if (_isOtLoading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard('Weekly OT', _formatMins(_otWeeklyMins), Colors.orange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard('Monthly OT', _formatMins(_otMonthlyMins), Colors.deepOrange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _otRateController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'OT Rate (₹/hr)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixText: '₹ ',
                              ),
                              onChanged: (val) {
                                final rate = double.tryParse(val) ?? 0;
                                setState(() {
                                  _otHourlyRate = rate;
                                  _recalculateTotalPayout();
                                });
                                _schedulePayrollPrefsSave();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _otPayoutPeriod,
                              decoration: InputDecoration(
                                labelText: 'View Period',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: ['Weekly', 'Monthly']
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _otPayoutPeriod = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _fixedSalaryController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Base Fixed Salary (₹)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixText: '₹ ',
                        ),
                        onChanged: (val) {
                          final salary = double.tryParse(val) ?? 0;
                          setState(() {
                            _baseSalary = salary;
                            _recalculateTotalPayout();
                          });
                          _schedulePayrollPrefsSave();
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildCalculationRow('Adjusted Fixed Salary', '₹ ${_adjustedFixedSalary.toStringAsFixed(2)}', subtitle: '(Payable: $_payableDays | Absent: $_absentDays)'),
                      _buildCalculationRow('Approved Expenses', '₹ ${_approvedExpenses.toStringAsFixed(0)}'),
                      _buildCalculationRow('OT Earnings', '₹ ${((_otMonthlyMins / 60.0) * _otHourlyRate).toStringAsFixed(0)}', subtitle: '(${(_otMonthlyMins / 60.0).toStringAsFixed(1)} hours)'),
                      const Divider(height: 32),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange[50],
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.deepOrange[100]!),
                        ),
                        child: Column(
                          children: [
                            const Text('Total Monthly Payout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            Text(
                              '₹ ${_totalMonthlyPayout.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: _totalMonthlyPayout > 0 ? _publishOtPayout : null,
                          icon: const Icon(Icons.publish),
                          label: const Text('PUBLISH OT PAYOUT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(String label, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
