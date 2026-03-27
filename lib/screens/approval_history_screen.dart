import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';

class ApprovalHistoryScreen extends StatefulWidget {
  const ApprovalHistoryScreen({super.key});
  static const String id = 'approval_history_screen';

  @override
  State<ApprovalHistoryScreen> createState() => _ApprovalHistoryScreenState();
}

class _ApprovalHistoryScreenState extends State<ApprovalHistoryScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    String? from;
    String? to;
    if (_fromDate != null && _toDate != null) {
      from = DateFormat('yyyy-MM-dd').format(_fromDate!);
      to = DateFormat('yyyy-MM-dd').format(_toDate!);
    }

    final results = await DatabaseHelper.instance.getApprovalHistory(
      fromDate: from,
      toDate: to,
    );

    setState(() {
      _history = results;
      _isLoading = false;
    });
  }

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Approval History'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Date range filter bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(context, true),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _fromDate != null
                              ? dateFormat.format(_fromDate!)
                              : 'From Date',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(context, false),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _toDate != null
                              ? dateFormat.format(_toDate!)
                              : 'To Date',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_fromDate != null && _toDate != null)
                            ? _loadHistory
                            : null,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Search'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _clearFilter,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No approval history found.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: ListView.builder(
                      itemCount: _history.length,
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return _buildHistoryCard(item);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final isLeave = item['approval_type'] == 'leave';
    final status = item['status'] ?? 'Unknown';
    final isApproved = status == 'Approved';

    String empName = item['employee_name'] ?? item['employee_id'] ?? 'Unknown';
    String empId = item['real_employee_id'] ?? item['employee_id'] ?? '';
    String displayTitle = (empId.isNotEmpty && empName != empId)
        ? '$empName ($empId)'
        : empName;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    displayTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isApproved ? Colors.green[50] : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isApproved ? Colors.green[800] : Colors.red[800],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isLeave ? Colors.purple[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isLeave
                        ? (item['leave_type'] ?? 'Leave')
                        : (item['expense_category'] ?? 'Expense'),
                    style: TextStyle(
                      color: isLeave ? Colors.purple[800] : Colors.blue[800],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  isLeave
                      ? '${item['from_date'] ?? ''} → ${item['to_date'] ?? ''}'
                      : (item['date'] ??
                            item['timestamp']?.toString().split('T')[0] ??
                            ''),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            const Divider(height: 16),
            if (isLeave) ...[
              Text(
                'Reason: ${item['reason'] ?? 'N/A'}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ] else ...[
              Row(
                children: [
                  Text(
                    '₹${item['amount'] ?? '0'}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['description'] ?? 'No description',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (item['approved_by'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    item['status'] == 'Approved' ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: item['status'] == 'Approved' ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${item['status']} by ${item['approved_by']}${item['approved_at'] != null ? ' on ${item['approved_at'].toString().split('T')[0]}' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
            if (item['distance'] != null && (item['distance'] as num) > 0) ...[
              const SizedBox(height: 6),
              Text(
                '🚗 Distance: ${item['distance']?.toStringAsFixed(2)} km',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
