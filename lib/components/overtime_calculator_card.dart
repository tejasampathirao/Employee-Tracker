import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class OvertimeCalculatorCard extends StatefulWidget {
  const OvertimeCalculatorCard({super.key});

  @override
  State<OvertimeCalculatorCard> createState() => _OvertimeCalculatorCardState();
}

class _OvertimeCalculatorCardState extends State<OvertimeCalculatorCard> {
  Map<String, double> _otStats = {'today': 0.0, 'week': 0.0, 'month': 0.0};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOTStats();
  }

  Future<void> _loadOTStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final empId = prefs.getString('employee_id')?.trim();
      if (empId == null || empId.isEmpty) {
        if (mounted) {
          setState(() {
            _otStats = {'today': 0.0, 'week': 0.0, 'month': 0.0};
            _isLoading = false;
          });
        }
        return;
      }

      final monthlyOT = await DatabaseHelper.instance.getMonthlyOT(empId);
      if (mounted) {
        setState(() {
          _otStats = {'today': 0.0, 'week': 0.0, 'month': monthlyOT};
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading OT stats: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _otStats = {'today': 0.0, 'week': 0.0, 'month': 0.0};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overtime (OT) Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                _buildOTRow('Current Month OT', _otStats['month']!),
                const SizedBox(height: 8),
                Text(
                  'Calculated using admin-defined shift end and OT buffer settings.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildOTRow(String label, double hours) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text('${hours.toStringAsFixed(1)} hrs', style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
