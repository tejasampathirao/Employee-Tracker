import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class AdminLeaveScreen extends StatefulWidget {
  const AdminLeaveScreen({super.key});
  static const String id = 'admin_leave_screen';

  @override
  State<AdminLeaveScreen> createState() => _AdminLeaveScreenState();
}

class _AdminLeaveScreenState extends State<AdminLeaveScreen> {
  Future<void> _updateStatus(int id, String status) async {
    await DatabaseHelper.instance.updateLeaveRequestStatus(id, status);
    setState(() {}); // Refresh list
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request $status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Leave Approvals'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getPendingLeaveRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No pending leave requests.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data!;

          return ListView.builder(
            itemCount: requests.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final request = requests[index];
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
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              request['leave_type'] ?? 'Leave',
                              style: TextStyle(color: Colors.blue[800], fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
                      const Text(
                        'Reason:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        request['reason'] ?? 'No reason provided',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _updateStatus(request['id'], 'Rejected'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _updateStatus(request['id'], 'Approved'),
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
    );
  }
}
