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

  final TextEditingController _otRateController = TextEditingController(
    text: '0',
  );
  final TextEditingController _checkinBufferController = TextEditingController(
    text: '10',
  );
  final TextEditingController _checkoutBufferController = TextEditingController(
    text: '5',
  );
  final TextEditingController _otBufferController = TextEditingController(
    text: '25',
  );

  String _otPayoutPeriod = 'Weekly';
  double _otHourlyRate = 0;
  int _otWeeklyMins = 0;
  int _otMonthlyMins = 0;
  bool _isOtLoading = false;
  int _checkinBufferMins = 10;
  int _checkoutBufferMins = 5;
  int _otBufferMins = 25;
  String? _otEmployeeId;
  String? _otEmployeeName;

  @override
  void initState() {
    super.initState();
    _loadShiftSettings();
  }

  @override
  void dispose() {
    _otRateController.dispose();
    _checkinBufferController.dispose();
    _checkoutBufferController.dispose();
    _otBufferController.dispose();
    super.dispose();
  }

  TimeOfDay _parseShiftTime(String timeStr) {
    final trimmed = timeStr.trim().toUpperCase();
    final hmMatch = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(trimmed);
    if (hmMatch != null) {
      return TimeOfDay(
        hour: int.parse(hmMatch.group(1)!),
        minute: int.parse(hmMatch.group(2)!),
      );
    }

    final ampmMatch = RegExp(
      r'^([0-9]{1,2})(?::([0-5]\d))?\s*(AM|PM)$',
    ).firstMatch(trimmed);
    if (ampmMatch != null) {
      var hour = int.parse(ampmMatch.group(1)!);
      final minute = int.tryParse(ampmMatch.group(2) ?? '0') ?? 0;
      final period = ampmMatch.group(3);
      if (period == 'AM') {
        if (hour == 12) hour = 0;
      } else if (period == 'PM') {
        if (hour != 12) hour += 12;
      }
      return TimeOfDay(hour: hour, minute: minute);
    }

    try {
      final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
      final parsed = DateFormat.jm().parse(normalized);
      return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
    } catch (_) {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 9,
          minute: int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        );
      }
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  Future<void> _loadShiftSettings() async {
    final fromTime = await DatabaseHelper.instance.getShiftFromTime();
    final toTime = await DatabaseHelper.instance.getShiftToTime();
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _shiftStart = _parseShiftTime(fromTime);
      _shiftEnd = _parseShiftTime(toTime);
      _checkinBufferMins = prefs.getInt('checkin_buffer') ?? 10;
      _checkoutBufferMins = prefs.getInt('checkout_buffer') ?? 5;
      _otBufferMins = prefs.getInt('ot_buffer') ?? 25;
      _checkinBufferController.text = _checkinBufferMins.toString();
      _checkoutBufferController.text = _checkoutBufferMins.toString();
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
    await prefs.setInt('checkout_buffer', _checkoutBufferMins);
    await prefs.setInt('ot_buffer', _otBufferMins);

    MqttHandler().publishShiftUpdate(
      safeFromTime,
      safeToTime,
      _checkinBufferMins,
      _otBufferMins,
    );
  }

  Future<void> _loadOtStats(String empId, String empName) async {
    setState(() {
      _isOtLoading = true;
      _otEmployeeId = empId;
      _otEmployeeName = empName;
    });

    final stats = await DatabaseHelper.instance.getEmployeeOTStats(empId);
    if (mounted) {
      setState(() {
        _otWeeklyMins = stats['weeklyOTMinutes'] ?? 0;
        _otMonthlyMins = stats['monthlyOTMinutes'] ?? 0;
        _isOtLoading = false;
      });
    }
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
    final otHours = _getCalculatedHours();
    final totalPayout = otHours * _otHourlyRate;

    if (_otEmployeeId == null || _otEmployeeName == null) {
      return;
    }

    MqttHandler().publishOTPayout(
      _otEmployeeId!,
      _otPayoutPeriod,
      otHours,
      _otHourlyRate,
      totalPayout,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'OT Payout of ₹${totalPayout.toStringAsFixed(2)} published for $_otEmployeeName',
        ),
        backgroundColor: Colors.green,
      ),
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          timePickerTheme: TimePickerThemeData(
            dialHandColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _shiftStart = picked;
        } else {
          _shiftEnd = picked;
        }
      });

      final fromTime = _formatTimeForStorage(_shiftStart);
      final toTime = _formatTimeForStorage(_shiftEnd);
      await _saveShiftSettings(fromTime: fromTime, toTime: toTime);
    }
  }

  Widget _buildShiftTimeSlot(
    BuildContext context,
    String label,
    TimeOfDay time,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimeOfDay(time),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.access_time, size: 18, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Late Calculation Logic
  String calculateLateStatus(String? checkInStr) {
    if (checkInStr == null) return "";

    try {
      final checkIn = DateTime.parse(checkInStr);
      // Use the current shift start time set by admin
      final shiftStart = DateTime(
        checkIn.year,
        checkIn.month,
        checkIn.day,
        _shiftStart.hour,
        _shiftStart.minute,
      );

      if (checkIn.isAfter(shiftStart)) {
        final lateDuration = checkIn.difference(shiftStart).inMinutes;
        final lateAfterBuffer = lateDuration - _checkinBufferMins;
        if (lateAfterBuffer <= 0) return "";

        final h = lateAfterBuffer ~/ 60;
        final m = lateAfterBuffer % 60;

        if (h > 0) {
          return "$h hr $m mins late";
        } else {
          return "$m mins late";
        }
      }
    } catch (e) {
      debugPrint("Error calculating late status: $e");
    }
    return "";
  }

  // OT calculation is now delegated entirely to OvertimeCalculatorService.
  // This method is kept as a thin wrapper so all existing call sites
  // in _buildDailyLogs() continue to work without any change.
  Future<String> calculateOTSlot(
    String? checkInStr,
    String? checkOutStr,
  ) async {
    final result = await OvertimeCalculatorService().calculateDailyOT(
      checkInStr,
      checkOutStr,
      const [], // 7th-consecutive-day check not needed for per-card daily display
    );
    return result.dailyOTFormatted;
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

  void _showAttendanceStatsDialog(
    BuildContext context,
    String employeeId,
    String employeeName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text('Stats: $employeeName ($employeeId)')),
          ],
        ),
        content: FutureBuilder<Map<String, dynamic>>(
          future: DatabaseHelper.instance.getEmployeeAttendanceStats(
            employeeId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Text("Error loading stats.");
            }

            final stats = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatTile(
                  "Monthly Attendance",
                  "${stats['percentage']}%",
                  Icons.calendar_month,
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildStatTile(
                  "Total Late Minutes",
                  "${stats['lateMinutes']} mins",
                  Icons.access_time_filled,
                  Colors.red,
                ),
                const SizedBox(height: 8),
                Text(
                  "Calculated for current month",
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Working Time Slot'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isMonthlyView
                  ? Icons.calendar_view_day
                  : Icons.analytics_outlined,
            ),
            onPressed: () => setState(() => _isMonthlyView = !_isMonthlyView),
            tooltip: _isMonthlyView
                ? "Switch to Daily Logs"
                : "Switch to Monthly Summary",
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _buildShiftTimeSlot(
                  context,
                  'From time slot',
                  _shiftStart,
                  () => _pickShiftTime(context, true),
                ),
                const SizedBox(width: 12),
                _buildShiftTimeSlot(
                  context,
                  'To time slot',
                  _shiftEnd,
                  () => _pickShiftTime(context, false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _checkinBufferController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.access_time, size: 20),
                          labelText: 'Check-in',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                        ),
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null) {
                            setState(() => _checkinBufferMins = parsed);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _otBufferController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.add_alarm, size: 20),
                          labelText: 'OT Buf',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                        ),
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null) {
                            setState(() => _otBufferMins = parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.sync, size: 22),
                label: const Text(
                  'Update Shift Rules',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final checkin =
                      int.tryParse(_checkinBufferController.text) ?? 0;
                  final ot = int.tryParse(_otBufferController.text) ?? 0;
                  setState(() {
                    _checkinBufferMins = checkin;
                    _otBufferMins = ot;
                  });
                  MqttHandler().publishShiftUpdate(
                    _formatTimeForStorage(_shiftStart),
                    _formatTimeForStorage(_shiftEnd),
                    checkin,
                    ot,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Shift rules updated and broadcasted successfully!',
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue[800],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Shift Timings: ${_formatTimeOfDay(_shiftStart)} to ${_formatTimeOfDay(_shiftEnd)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.getAllEmployeeAttendance(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState('No daily records found.');
              }

              final records = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final checkIn = record['checkInTime'] as String?;
                  final checkOut = record['checkOutTime'] as String?;
                  final date = record['date'] as String? ?? "N/A";
                  final employeeId = record['employee_id'] ?? 'Unknown';
                  final employeeName = record['name'] ?? 'Unknown Employee';
                  final lateStatus = calculateLateStatus(checkIn);
                  final isPending = checkOut == null;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showAttendanceStatsDialog(
                        context,
                        employeeId,
                        employeeName,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.05),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.badge_outlined,
                                        size: 20,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "$employeeName ($employeeId)",
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Text(
                                    date,
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          _buildInfoItem(
                                            context,
                                            Icons.login_rounded,
                                            "Check-in",
                                            formatTime(checkIn),
                                            Colors.green,
                                          ),
                                          if (lateStatus.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                lateStatus,
                                                style: const TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.grey[200],
                                    ),
                                    Expanded(
                                      child: _buildInfoItem(
                                        context,
                                        Icons.logout_rounded,
                                        "Check-out",
                                        formatTime(checkOut),
                                        isPending ? Colors.grey : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 50),
          const Divider(height: 50, thickness: 2, color: Color(0xFFE0E0E0)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ExpansionTile(
              title: const Text(
                'Manage Overtime Payouts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: DatabaseHelper.instance.getAllEmployees(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: Text('No employees found.')),
                            );
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
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.deepOrange[100],
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'E',
                                      style: const TextStyle(
                                        color: Colors.deepOrange,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text('ID: $empId'),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () => _loadOtStats(empId, name),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_otEmployeeId != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Employee: ${_otEmployeeName ?? 'Unknown'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_isOtLoading)
                                const Center(child: CircularProgressIndicator())
                              else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildStatCard(
                                        'Weekly OT',
                                        _formatMins(_otWeeklyMins),
                                        Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard(
                                        'Monthly OT',
                                        _formatMins(_otMonthlyMins),
                                        Colors.deepOrange,
                                      ),
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
                                          labelText: 'Rate per Hour (₹)',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          prefixText: '₹ ',
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _otHourlyRate =
                                                double.tryParse(val) ?? 0;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _otPayoutPeriod,
                                        decoration: InputDecoration(
                                          labelText: 'Period',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        items: ['Weekly', 'Monthly']
                                            .map(
                                              (period) => DropdownMenuItem(
                                                value: period,
                                                child: Text(period),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(
                                              () => _otPayoutPeriod = val,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange[50],
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: Colors.deepOrange[100]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Amount to Payout',
                                            style: TextStyle(
                                              color: Colors.deepOrange[800],
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '₹ ${(_getCalculatedHours() * _otHourlyRate).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepOrange,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${_getCalculatedHours().toStringAsFixed(1)} Hours',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                    onPressed:
                                        _getCalculatedHours() * _otHourlyRate >
                                            0
                                        ? _publishOtPayout
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepOrange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    child: const Text(
                                      'PUBLISH OT PAYOUT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
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
              ],
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
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
          const SizedBox(height: 8),
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
    );
  }

  Widget _buildMonthlySummaries() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getAllEmployees(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState('No employees registered.');
        }

        final employees = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: employees.length,
          itemBuilder: (context, index) {
            final emp = employees[index];
            final empId = emp['emp_id'] ?? 'N/A';
            final empName = emp['name'] ?? 'Unknown';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ExpansionTile(
                leading: CircleAvatar(child: Text(empName[0])),
                title: Text(
                  empName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("ID: $empId"),
                children: [
                  // EXISTING — do not touch this FutureBuilder
                  FutureBuilder<Map<String, dynamic>>(
                    future: DatabaseHelper.instance
                        .getEmployeeAttendanceSummary(empId),
                    builder: (context, summarySnapshot) {
                      if (!summarySnapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final summary = summarySnapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildSummaryRow(
                              "Weekly Attendance",
                              "${summary['weekly']}%",
                              Colors.blue,
                            ),
                            const Divider(),
                            _buildSummaryRow(
                              "Monthly Attendance",
                              "${summary['monthly']}%",
                              Colors.green,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // NEW — OT summary rows, powered by OvertimeCalculatorService
                  FutureBuilder<Map<String, dynamic>>(
                    future: () async {
                      final data = await DatabaseHelper.instance
                          .getAttendanceByEmployee(empId);
                      final svc = OvertimeCalculatorService();
                      final weekly = await svc.getWeeklyOTSummary(data);
                      final monthly = await svc.getMonthlyOTSummary(data);
                      return {'weekly': weekly, 'monthly': monthly};
                    }(),
                    builder: (context, otSnap) {
                      if (!otSnap.hasData) return const SizedBox.shrink();
                      final weekly = otSnap.data!['weekly'];
                      final monthly = otSnap.data!['monthly'];
                      final svc = OvertimeCalculatorService();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            const Divider(),
                            _buildSummaryRow(
                              "Weekly OT",
                              weekly['weeklyOTFormatted'] as String,
                              Colors.orange,
                            ),
                            const Divider(),
                            _buildSummaryRow(
                              "Monthly OT",
                              monthly['weeklyOTFormatted'] as String,
                              Colors.deepOrange,
                            ),
                            const Divider(),
                            _buildSummaryRow(
                              "Double Time",
                              svc.formatOT(monthly['doubleTimeMinutes'] as int),
                              Colors.red,
                            ),
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
        Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
