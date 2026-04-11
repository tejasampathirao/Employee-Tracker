import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../services/mqtt_handler.dart';
import 'admin_attendance_screen.dart';
import 'ot_calculator_employees_screen.dart';
import 'employee_list_screen.dart';
import 'admin_approvals_screen.dart';
import 'approval_history_screen.dart';
import 'admin_location_screen.dart';
import 'admin_leave_management_screen.dart';
import 'admin_expense_limits_screen.dart';
import 'login_screen.dart';
import '../utils/excel_export_helper.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  static const String id = 'admin_dashboard';

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    _initMqtt();
  }

  void _initMqtt() async {
    await MqttHandler().connect();
  }

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    final preservedKeys = [
      'fuel_km_limit',
      'fuel_amt_limit',
      'food_type_limit',
      'food_amt_limit',
      'material_type_limit',
      'material_amt_limit',
      'travel_rapido_limit',
      'travel_bus_limit',
      'travel_own_vehicle_limit',
    ];

    final preservedValues = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (preservedKeys.contains(key) ||
          key.startsWith('ot_rate_') ||
          key.startsWith('fixed_salary_')) {
        preservedValues[key] = prefs.get(key);
      }
    }

    await prefs.clear();

    for (final entry in preservedValues.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        LoginScreen.id,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _handleLogout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),
            const Text(
              'Management Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
              children: [
                _buildServiceCard(
                  context,
                  'Working Time Slot',
                  Icons.timer_outlined,
                  Colors.orange,
                  () => Navigator.pushNamed(context, AdminAttendanceScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'OT Calculator',
                  Icons.calculate,
                  Colors.deepOrange,
                  () =>
                      Navigator.pushNamed(context, OTCalculatorEmployeesScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Employee Details',
                  Icons.badge_outlined,
                  Colors.blue,
                  () => Navigator.pushNamed(context, EmployeeListScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Admin Approvals',
                  Icons.mark_email_read_outlined,
                  Colors.purple,
                  () => Navigator.pushNamed(context, AdminApprovalsScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Approval History',
                  Icons.history,
                  Colors.teal,
                  () => Navigator.pushNamed(context, ApprovalHistoryScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Location Logs',
                  Icons.location_on_outlined,
                  Colors.red,
                  () => Navigator.pushNamed(context, AdminLocationScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Leave Management',
                  Icons.edit_calendar,
                  Colors.teal,
                  () => Navigator.pushNamed(
                    context,
                    AdminLeaveManagementScreen.id,
                  ),
                ),
                _buildServiceCard(
                  context,
                  'Expense Limits',
                  Icons.money_off,
                  Colors.redAccent,
                  () =>
                      Navigator.pushNamed(context, AdminExpenseLimitsScreen.id),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final path = await ExcelExportHelper.exportDataToExcel();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Excel Report Generated! Saved at: $path'),
                          duration: const Duration(seconds: 10),
                          action: SnackBarAction(label: 'OK', onPressed: () {}),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to generate report: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('Export Excel Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: const StadiumBorder(),
                  elevation: 4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  bool confirm =
                      await showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Wipe Data?'),
                          content: const Text(
                            'This will delete all attendance records from the database.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'WIPE',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ) ??
                      false;

                  if (confirm) {
                    await DatabaseHelper.instance.clearAttendanceTable();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Attendance table cleared!'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.red,
                  size: 20,
                ),
                label: const Text(
                  'Wipe Attendance Data (Temporary)',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Logout from Admin'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseHelper.instance.getUser(),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final name = userData?['name'] ?? 'Admin';
        final role = userData?['role'] ?? 'System Administrator';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';
        final theme = Theme.of(context);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        role,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        overflow: TextOverflow.ellipsis,
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
  }

  Widget _buildServiceCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
