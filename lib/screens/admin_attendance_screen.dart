import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _loadShiftTimes();
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

    final ampmMatch = RegExp(r'^([0-9]{1,2})(?::([0-5]\d))?\s*(AM|PM)$').firstMatch(trimmed);
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

  Future<void> _loadShiftTimes() async {
    final fromTime = await DatabaseHelper.instance.getShiftFromTime();
    final toTime = await DatabaseHelper.instance.getShiftToTime();
    setState(() {
      _shiftStart = _parseShiftTime(fromTime);
      _shiftEnd = _parseShiftTime(toTime);
    });
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
      await DatabaseHelper.instance.setShiftTimes(fromTime, toTime);
      MqttHandler().publishShiftUpdate(fromTime, toTime);

      // Show confirmation snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift timings broadcasted to all employees.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildShiftTimeSlot(BuildContext context, String label, TimeOfDay time, VoidCallback onTap) {
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
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimeOfDay(time),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        final lateDuration = checkIn.difference(shiftStart);
        final h = lateDuration.inHours;
        final m = lateDuration.inMinutes % 60;

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
  Future<String> calculateOTSlot(String? checkInStr, String? checkOutStr) async {
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
    return Column(
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
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
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
        ),
      ],
    );
  }

  Widget _buildMonthlySummaries() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getAllEmployees(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return _buildEmptyState('No employees registered.');

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
                      if (!summarySnapshot.hasData)
                        return const LinearProgressIndicator();
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
                      final data = await DatabaseHelper.instance.getAttendanceByEmployee(empId);
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
