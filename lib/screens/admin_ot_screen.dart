import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/mqtt_handler.dart';

class AdminOTScreen extends StatefulWidget {
  const AdminOTScreen({super.key});
  static const String id = 'admin_ot_screen';

  @override
  State<AdminOTScreen> createState() => _AdminOTScreenState();
}

class _AdminOTScreenState extends State<AdminOTScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OT Time Slot Service'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final emp = employees[index];
              final name = emp['name'] ?? 'Unknown';
              final empId = emp['emp_id'] ?? 'N/A';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepOrange[100],
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('ID: $empId'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showOTCalculator(context, empId, name),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showOTCalculator(BuildContext context, String empId, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => OTCalculatorSheet(empId: empId, empName: name),
    );
  }
}

class OTCalculatorSheet extends StatefulWidget {
  final String empId;
  final String empName;

  const OTCalculatorSheet({
    super.key,
    required this.empId,
    required this.empName,
  });

  @override
  State<OTCalculatorSheet> createState() => _OTCalculatorSheetState();
}

class _OTCalculatorSheetState extends State<OTCalculatorSheet> {
  final TextEditingController _rateController = TextEditingController(
    text: '0',
  );
  String _payoutPeriod = 'Weekly';
  double _hourlyRate = 0;
  int _weeklyMins = 0;
  int _monthlyMins = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await DatabaseHelper.instance.getEmployeeOTStats(
      widget.empId,
    );
    if (mounted) {
      setState(() {
        _weeklyMins = stats['weeklyOTMinutes'] ?? 0;
        _monthlyMins = stats['monthlyOTMinutes'] ?? 0;
        _isLoading = false;
      });
    }
  }

  String _formatMins(int totalMins) {
    int h = totalMins ~/ 60;
    int m = totalMins % 60;
    return '${h}h ${m}m';
  }

  double _getCalculatedHours() {
    int mins = _payoutPeriod == 'Weekly' ? _weeklyMins : _monthlyMins;
    return mins / 60.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    double otHours = _getCalculatedHours();
    double totalPayout = otHours * _hourlyRate;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'OT Calculator: ${widget.empName}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatCard(
                'Weekly OT',
                _formatMins(_weeklyMins),
                Colors.orange,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Monthly OT',
                _formatMins(_monthlyMins),
                Colors.deepOrange,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Payout Configuration',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rateController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Rate per Hour (₹)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixText: '₹ ',
                  ),
                  onChanged: (val) {
                    setState(() {
                      _hourlyRate = double.tryParse(val) ?? 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _payoutPeriod,
                  decoration: InputDecoration(
                    labelText: 'Period',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: ['Weekly', 'Monthly'].map((p) {
                    return DropdownMenuItem(value: p, child: Text(p));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _payoutPeriod = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepOrange[50],
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.deepOrange[100]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Amount to Payout',
                      style: TextStyle(
                        color: Colors.deepOrange[800],
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '₹ ${totalPayout.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${otHours.toStringAsFixed(1)} Hours',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: totalPayout > 0 ? _publishPayout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'PUBLISH OT PAYOUT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _publishPayout() {
    final otHours = _getCalculatedHours();
    final totalPayout = otHours * _hourlyRate;

    MqttHandler().publishOTPayout(
      widget.empId,
      _payoutPeriod,
      otHours,
      _hourlyRate,
      totalPayout,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'OT Payout of ₹${totalPayout.toStringAsFixed(2)} published for ${widget.empName}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }
}
