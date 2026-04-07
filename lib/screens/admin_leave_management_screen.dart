import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mqtt_handler.dart';
import '../database/db_helper.dart';

class AdminLeaveManagementScreen extends StatefulWidget {
  const AdminLeaveManagementScreen({super.key});
  static const String id = 'admin_leave_management_screen';

  @override
  State<AdminLeaveManagementScreen> createState() =>
      _AdminLeaveManagementScreenState();
}

class _AdminLeaveManagementScreenState
    extends State<AdminLeaveManagementScreen> {
  final TextEditingController _reasonController = TextEditingController();
  DateTimeRange? _selectedRange;
  bool _isPublishing = false;

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime(2100),
      initialDateRange: _selectedRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.teal[700]!,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedRange = picked;
      });
    }
  }

  Future<void> _announceHoliday() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday reason')),
      );
      return;
    }

    if (_selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date range')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('employee_id') ?? 'Admin';

      MqttHandler().publishHoliday(
        _selectedRange!.start,
        _selectedRange!.end,
        reason,
        adminId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Holiday announced and broadcasted!'),
            backgroundColor: Colors.teal,
          ),
        );
        _reasonController.clear();
        setState(() {
            _selectedRange = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to announce holiday: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Leave & Holiday Management'),
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Declare Company Holiday',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Announce holidays to all employees via MQTT broadcast.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            // Date Selection Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: const Icon(Icons.calendar_month, color: Colors.teal),
                title: const Text('Selected Date Range'),
                subtitle: Text(
                  _selectedRange == null
                      ? 'No range selected'
                      : '${DateFormat('MMM d').format(_selectedRange!.start)} - ${DateFormat('MMM d, yyyy').format(_selectedRange!.end)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _selectDateRange(context),
                  child: const Text('SELECT'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Reason Field
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Holiday Reason / Name',
                hintText: 'e.g. Independence Day, Annual Peak...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                prefixIcon: const Icon(Icons.edit_note, color: Colors.teal),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 32),
            // Announce Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isPublishing ? null : _announceHoliday,
                icon: _isPublishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.campaign),
                label: const Text(
                  'ANNOUNCE HOLIDAY',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              'Upcoming Holidays (Local DB)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.getUpcomingHolidays(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final holidays = snapshot.data ?? [];
                if (holidays.isEmpty) {
                  return const Text('No upcoming holidays found.');
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: holidays.length > 8 ? 8 : holidays.length,
                  itemBuilder: (context, index) {
                    final h = holidays[index];
                    String dateDisplay = h['date'];
                    if (h['start_date'] != null && h['end_date'] != null) {
                        try {
                            final start = DateTime.parse(h['start_date']);
                            final end = DateTime.parse(h['end_date']);
                            dateDisplay = '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}';
                        } catch(_) {}
                    }
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_available, color: Colors.teal, size: 20),
                      title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(dateDisplay),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }
}
