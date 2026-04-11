import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../services/overtime_calculator_service.dart';
import '../services/mqtt_handler.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  static const String id = 'admin_attendance_screen';

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  bool _isMonthlyView = false;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);

  final TextEditingController _checkinBufferController = TextEditingController(text: '10');
  final TextEditingController _otBufferController = TextEditingController(text: '30');

  int _checkinBufferMins = 10;
  int _otBufferMins = 30;

  @override
  void initState() {
    super.initState();
    _loadShiftSettings();
  }

  @override
  void dispose() {
    _checkinBufferController.dispose();
    _otBufferController.dispose();
    super.dispose();
  }

  TimeOfDay _parseShiftTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    } catch (_) {}
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _loadShiftSettings() async {
    final fromTime = await DatabaseHelper.instance.getShiftFromTime();
    final toTime = await DatabaseHelper.instance.getShiftToTime();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _shiftStart = _parseShiftTime(fromTime);
      _shiftEnd = _parseShiftTime(toTime);
      _checkinBufferMins = prefs.getInt('checkin_buffer') ?? 10;
      _otBufferMins = prefs.getInt('ot_buffer') ?? 30;
      _checkinBufferController.text = _checkinBufferMins.toString();
      _otBufferController.text = _otBufferMins.toString();
    });
  }

  Future<void> _saveShiftSettings({String? fromTime, String? toTime}) async {
    final safeFromTime = fromTime ?? _formatTimeForStorage(_shiftStart);
    final safeToTime = toTime ?? _formatTimeForStorage(_shiftEnd);
    await DatabaseHelper.instance.setShiftTimes(safeFromTime, safeToTime);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shift_from_time', safeFromTime);
    await prefs.setString('shift_to_time', safeToTime);
    await prefs.setInt('checkin_buffer', _checkinBufferMins);
    await prefs.setInt('ot_buffer', _otBufferMins);

    MqttHandler().publishShiftUpdate(
      safeFromTime,
      safeToTime,
      _checkinBufferMins,
      _otBufferMins,
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return time.format(context);
  }

  String _formatTimeForStorage(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickShiftTime(BuildContext context, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _shiftStart : _shiftEnd,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _shiftStart = picked;
        } else {
          _shiftEnd = picked;
        }
      });
      await _saveShiftSettings();
    }
  }

  String calculateLateStatus(String? checkInStr) {
    if (checkInStr == null) return "";
    try {
      final checkIn = DateTime.parse(checkInStr);
      final shiftStart = DateTime(checkIn.year, checkIn.month, checkIn.day, _shiftStart.hour, _shiftStart.minute);
      if (checkIn.isAfter(shiftStart)) {
        final lateDuration = checkIn.difference(shiftStart).inMinutes;
        final lateAfterBuffer = lateDuration - _checkinBufferMins;
        if (lateAfterBuffer <= 0) return "";
        final h = lateAfterBuffer ~/ 60;
        final m = lateAfterBuffer % 60;
        return h > 0 ? "$h hr $m mins late" : "$m mins late";
      }
    } catch (e) {}
    return "";
  }

  String formatTime(String? timeStr) {
    if (timeStr == null) return "N/A";
    try {
      final dt = DateTime.parse(timeStr);
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return "N/A";
    }
  }

  void _showAttendanceStatsDialog(BuildContext context, String employeeId, String employeeName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Stats: $employeeName'),
        content: FutureBuilder<Map<String, dynamic>>(
          future: DatabaseHelper.instance.getEmployeeAttendanceStats(employeeId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final stats = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatTile("Monthly Attendance", "${stats['percentage']}%", Icons.calendar_month, Colors.green),
                const SizedBox(height: 12),
                _buildStatTile("Total Late Minutes", "${stats['lateMinutes']} mins", Icons.access_time_filled, Colors.red),
              ],
            );
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Working Time Slot'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isMonthlyView ? Icons.calendar_view_day : Icons.analytics_outlined),
            onPressed: () => setState(() => _isMonthlyView = !_isMonthlyView),
          ),
        ],
      ),
      body: _isMonthlyView ? _buildMonthlySummaries() : _buildDailyLogs(),
    );
  }

  Widget _buildDailyLogs() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildShiftTimeSlot('From Slot', _shiftStart, () => _pickShiftTime(context, true)),
                const SizedBox(width: 12),
                _buildShiftTimeSlot('To Slot', _shiftEnd, () => _pickShiftTime(context, false)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _checkinBufferController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Check-in Buffer (mins)', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => _checkinBufferMins = int.tryParse(v) ?? 10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _otBufferController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'OT Buffer (mins)', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => _otBufferMins = int.tryParse(v) ?? 30),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _saveShiftSettings(),
                icon: const Icon(Icons.sync),
                label: const Text('Update Shift Rules'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              ),
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.getAllEmployeeAttendance(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final records = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final r = records[index];
                  final lateStatus = calculateLateStatus(r['checkInTime']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      onTap: () => _showAttendanceStatsDialog(context, r['employee_id'], r['name'] ?? 'Unknown'),
                      title: Text("${r['name']} (${r['employee_id']})", style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Date: ${r['date']} | In: ${formatTime(r['checkInTime'])} | Out: ${formatTime(r['checkOutTime'])}"),
                          if (lateStatus.isNotEmpty) Text(lateStatus, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummaries() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getAllEmployees(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final employees = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: employees.length,
          itemBuilder: (context, index) {
            final emp = employees[index];
            final empId = emp['emp_id'] ?? 'N/A';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Text(emp['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("ID: $empId"),
                children: [
                  FutureBuilder<Map<String, dynamic>>(
                    future: DatabaseHelper.instance.getEmployeeAttendanceSummary(empId),
                    builder: (context, snap) {
                      if (!snap.hasData) return const LinearProgressIndicator();
                      final s = snap.data!;
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSummaryRow("Weekly Attendance", "${s['weekly']}%", Colors.blue),
                            const Divider(),
                            _buildSummaryRow("Monthly Attendance", "${s['monthly']}%", Colors.green),
                          ],
                        ),
                      );
                    },
                  ),
                  FutureBuilder<Map<String, dynamic>>(
                    future: () async {
                      final data = await DatabaseHelper.instance.getAttendanceByEmployee(empId);
                      final svc = OvertimeCalculatorService();
                      return {'weekly': await svc.getWeeklyOTSummary(data), 'monthly': await svc.getMonthlyOTSummary(data)};
                    }(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final w = snap.data!['weekly'];
                      final m = snap.data!['monthly'];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            const Divider(),
                            _buildSummaryRow("Weekly OT", w['weeklyOTFormatted'], Colors.orange),
                            const Divider(),
                            _buildSummaryRow("Monthly OT", m['weeklyOTFormatted'], Colors.deepOrange),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildShiftTimeSlot(String label, TimeOfDay time, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(_formatTimeOfDay(time), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
