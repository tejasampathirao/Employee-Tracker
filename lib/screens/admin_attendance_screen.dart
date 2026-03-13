import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../components/overtime_calculator_card.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  static const String id = 'admin_attendance_screen';

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  bool _isMonthlyView = false;

  // Late Calculation Logic
  // Standard shift starts at 9:00 AM.
  String calculateLateStatus(String? checkInStr) {
    if (checkInStr == null) return "";
    
    try {
      final checkIn = DateTime.parse(checkInStr);
      // Create a DateTime object for 9:00 AM on the same day as check-in
      final shiftStart = DateTime(checkIn.year, checkIn.month, checkIn.day, 9, 0);
      
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

  // Overtime (OT) Calculation Logic
  // Define a standard shift as 9 hours.
  String calculateOTSlot(String? checkInStr, String? checkOutStr) {
    if (checkInStr == null || checkOutStr == null) return "0h OT";
    
    try {
      final checkIn = DateTime.parse(checkInStr);
      final checkOut = DateTime.parse(checkOutStr);
      final duration = checkOut.difference(checkIn);
      
      final totalMinutes = duration.inMinutes;
      final standardShiftMinutes = 9 * 60; // 9 hours
      
      if (totalMinutes > standardShiftMinutes) {
        final otMinutes = totalMinutes - standardShiftMinutes;
        final h = otMinutes ~/ 60;
        final m = otMinutes % 60;
        
        String otStr = "";
        if (h > 0) otStr += "${h}h ";
        if (m > 0) otStr += "${m}m ";
        return "${otStr.trim()} OT";
      }
    } catch (e) {
      debugPrint("Error calculating OT: $e");
    }
    return "0h OT";
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
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text('Stats: $employeeName')),
          ],
        ),
        content: FutureBuilder<Map<String, dynamic>>(
          future: DatabaseHelper.instance.getEmployeeAttendanceStats(employeeId),
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
                  Colors.green
                ),
                const SizedBox(height: 12),
                _buildStatTile(
                  "Total Late Minutes", 
                  "${stats['lateMinutes']} mins", 
                  Icons.access_time_filled, 
                  Colors.red
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

  Widget _buildStatTile(String label, String value, IconData icon, Color color) {
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
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
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
        title: const Text('Admin Attendance & OT'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isMonthlyView ? Icons.calendar_view_day : Icons.analytics_outlined),
            onPressed: () => setState(() => _isMonthlyView = !_isMonthlyView),
            tooltip: _isMonthlyView ? "Switch to Daily Logs" : "Switch to Monthly Summary",
          ),
        ],
      ),
      body: _isMonthlyView ? _buildMonthlySummaries() : _buildDailyLogs(),
    );
  }

  Widget _buildDailyLogs() {
    return FutureBuilder<List<Map<String, dynamic>>>(
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
          itemCount: records.length + 1,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: OvertimeCalculatorCard(),
              );
            }
            
            final record = records[index - 1];
            final checkIn = record['checkInTime'] as String?;
            final checkOut = record['checkOutTime'] as String?;
            final date = record['date'] as String? ?? "N/A";
            final employeeId = record['employee_id'] ?? 'N/A';
            final employeeName = record['name'] ?? 'Unknown Employee';
            final otSlot = calculateOTSlot(checkIn, checkOut);
            final lateStatus = calculateLateStatus(checkIn);
            final isPending = checkOut == null;

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showAttendanceStatsDialog(context, employeeId, employeeName),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                "$employeeName ($employeeId)",
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 16),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1))),
                            child: Text(date, style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600, fontSize: 13)),
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
                                    _buildInfoItem(context, Icons.login_rounded, "Check-in", formatTime(checkIn), Colors.green),
                                    if (lateStatus.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(lateStatus, style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                              Container(width: 1, height: 40, color: Colors.grey[200]),
                              Expanded(child: _buildInfoItem(context, Icons.logout_rounded, "Check-out", formatTime(checkOut), isPending ? Colors.grey : Colors.red)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: otSlot == "0h OT" ? Colors.grey[50] : Colors.orange[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: otSlot == "0h OT" ? Colors.grey[200]! : Colors.orange[100]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.timer_outlined, size: 18, color: otSlot == "0h OT" ? Colors.grey[600] : Colors.orange[800]),
                                const SizedBox(width: 8),
                                Text("OT Slot: ", style: TextStyle(color: otSlot == "0h OT" ? Colors.grey[600] : Colors.orange[800], fontWeight: FontWeight.w500)),
                                Text(isPending ? "Shift Active" : otSlot, style: TextStyle(color: isPending ? Colors.blue[800] : (otSlot == "0h OT" ? Colors.grey[800] : Colors.orange[900]), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
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
    );
  }

  Widget _buildMonthlySummaries() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getAllEmployees(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState('No employees registered.');

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ExpansionTile(
                leading: CircleAvatar(child: Text(empName[0])),
                title: Text(empName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("ID: $empId"),
                children: [
                  FutureBuilder<Map<String, dynamic>>(
                    future: DatabaseHelper.instance.getEmployeeAttendanceSummary(empId),
                    builder: (context, summarySnapshot) {
                      if (!summarySnapshot.hasData) return const LinearProgressIndicator();
                      final summary = summarySnapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildSummaryRow("Weekly Attendance", "${summary['weekly']}%", Colors.blue),
                            const Divider(),
                            _buildSummaryRow("Monthly Attendance", "${summary['monthly']}%", Colors.green),
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
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
      ],
    );
  }
}
