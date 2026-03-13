import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../database/db_helper.dart';
import '../services/mqtt_handler.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});
  static const String id = 'admin_approvals_screen';

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  StreamSubscription? _mqttSubscription;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() async {
    await MqttHandler().connect();
    _setupMqttListener();
  }

  void _setupMqttListener() {
    _mqttSubscription = MqttHandler().updates?.listen((messages) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    super.dispose();
  }

  Future<void> _updateStatus(Map<String, dynamic> item, String status) async {
    final id = item['id'];
    final type = item['approval_type'];
    final employeeId = item['employee_id'];

    if (type == 'leave') {
      await DatabaseHelper.instance.updateLeaveRequestStatus(id, status);
    } else {
      await DatabaseHelper.instance.updateExpenseStatus(id, status);
    }

    // Closed-Loop: Notify the Employee via MQTT
    final String category = type == 'leave' ? 'leave_request' : (item['type'] ?? 'expense_claim');
    final Map<String, dynamic> statusPayload = {
      "type": "status_update",
      "category": category,
      "id": id.toString(),
      "status": status
    };
    
    MqttHandler().publish('employee/tracker/status/$employeeId', jsonEncode(statusPayload));

    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type == 'leave' ? 'Leave' : 'Expense'} $status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Admin Approvals'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper.instance.getUnifiedPendingApprovals(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No pending approvals found.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final requests = snapshot.data!;

            return ListView.builder(
              itemCount: requests.length,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final request = requests[index];
                final isLeave = request['approval_type'] == 'leave';

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              request['employee_id'] ?? 'Unknown Employee',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isLeave ? Colors.purple[50] : Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isLeave ? (request['leave_type'] ?? 'Leave') : (request['expense_category'] ?? 'Expense'),
                                style: TextStyle(
                                  color: isLeave ? Colors.purple[800] : Colors.green[800],
                                  fontSize: 12, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isLeave) ...[
                          Row(
                            children: [
                              const Icon(Icons.date_range, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                "${request['from_date']} to ${request['to_date']}",
                                style: TextStyle(color: Colors.grey[800]),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              const Icon(Icons.payments_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text(
                                "Amount: ₹${request['amount']}",
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'Description / Reason:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          isLeave ? (request['reason'] ?? 'No reason') : (request['description'] ?? 'No description'),
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => _updateStatus(request, 'Rejected'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () => _updateStatus(request, 'Approved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
