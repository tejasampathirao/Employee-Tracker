import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mqtt_handler.dart';

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
  
  // Step 1: State Variables
  DateTime? _selectedDate;
  final List<Map<String, dynamic>> _sessionHolidays = [];
  bool _isPublishing = false;

  // Step 2: The Date Picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
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
        _selectedDate = picked;
      });
    }
  }

  // Step 3: The Announce Logic
  Future<void> _announceHoliday() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a holiday reason')),
      );
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final adminId = prefs.getString('employee_id') ?? 'Admin';
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      // Create the MQTT payload
      final payload = {
        "holiday_name": reason,
        "formatted_date": formattedDate,
        "admin_id": adminId,
      };

      // Call mqttService.publishHoliday(payload)
      MqttHandler().publishHoliday(payload);

      // Add the new holiday to _sessionHolidays and call setState()
      setState(() {
        _sessionHolidays.add({
          "name": reason,
          "date": formattedDate,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Holiday announced and broadcasted!'),
            backgroundColor: Colors.teal,
          ),
        );
        _reasonController.clear();
        setState(() {
          _selectedDate = null;
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
                title: const Text('Selected Date'),
                subtitle: Text(
                  _selectedDate == null
                      ? 'No date selected'
                      : DateFormat('MMM d, yyyy').format(_selectedDate!),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () => _selectDate(context),
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
              'Announced Holidays (Live)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Step 4: The Bottom List
            if (_sessionHolidays.isEmpty)
              const Text('No holidays announced in this session.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _sessionHolidays.length,
                itemBuilder: (context, index) {
                  final h = _sessionHolidays[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.event_available,
                        color: Colors.teal, size: 20),
                    title: Text(h['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(h['date']),
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
