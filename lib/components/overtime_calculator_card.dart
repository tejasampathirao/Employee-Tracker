import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class OvertimeCalculatorCard extends StatefulWidget {
  const OvertimeCalculatorCard({super.key});

  @override
  State<OvertimeCalculatorCard> createState() => _OvertimeCalculatorCardState();
}

class _OvertimeCalculatorCardState extends State<OvertimeCalculatorCard> {
  double _hourlyRate = 0.0;
  Map<String, double> _otStats = {'today': 0.0, 'week': 0.0, 'month': 0.0};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOTStats();
  }

  Future<void> _loadOTStats() async {
    try {
      final stats = await DatabaseHelper.instance.getOvertimeStats();
      if (mounted) {
        setState(() {
          _otStats = stats;
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
            'Overtime (OT) Calculator',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Enter Hourly OT Rate (₹)',
              prefixText: '₹ ',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _hourlyRate = double.tryParse(value) ?? 0.0;
              });
            },
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                _buildOTRow('Today', _otStats['today']!),
                const Divider(height: 20),
                _buildOTRow('This Week', _otStats['week']!),
                const Divider(height: 20),
                _buildOTRow('This Month', _otStats['month']!),
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
        Text('${hours.toStringAsFixed(1)} hrs', style: const TextStyle(color: Colors.blueGrey)),
        Text(
          '₹ ${(hours * _hourlyRate).toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16),
        ),
      ],
    );
  }
}
