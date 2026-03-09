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
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getAllEmployeeAttendance(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No attendance records found.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
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
              final otSlot = calculateOTSlot(checkIn, checkOut);
              final lateStatus = calculateLateStatus(checkIn);
              
              final isPending = checkOut == null;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                color: Colors.white,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.05),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                "Emp ID: #${record['id']}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
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
                                        padding: const EdgeInsets.only(top: 4),
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
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: otSlot == "0h OT" ? Colors.grey[50] : Colors.orange[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: otSlot == "0h OT" ? Colors.grey[200]! : Colors.orange[100]!,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 18,
                                  color: otSlot == "0h OT" ? Colors.grey[600] : Colors.orange[800],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "OT Slot: ",
                                  style: TextStyle(
                                    color: otSlot == "0h OT" ? Colors.grey[600] : Colors.orange[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  isPending ? "Shift Active" : otSlot,
                                  style: TextStyle(
                                    color: isPending 
                                        ? Colors.blue[800] 
                                        : (otSlot == "0h OT" ? Colors.grey[800] : Colors.orange[900]),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
