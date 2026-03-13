import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'admin_attendance_screen.dart';
import 'employee_list_screen.dart';
import 'admin_approvals_screen.dart';
import 'admin_location_screen.dart';
import 'admin_expenses_list_screen.dart';
import 'login_screen.dart';
import '../utils/excel_export_helper.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  static const String id = 'admin_dashboard';

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 

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
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.admin_panel_settings, size: 35, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome, Admin!',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Manage your workforce efficiently',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
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
              children: [
                _buildServiceCard(
                  context,
                  'Attendance',
                  Icons.timer_outlined,
                  Colors.orange,
                  () => Navigator.pushNamed(context, AdminAttendanceScreen.id),
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
                  'Expenses Service',
                  Icons.payments_outlined,
                  Colors.green,
                  () => Navigator.pushNamed(context, AdminExpensesListScreen.id),
                ),
                _buildServiceCard(
                  context,
                  'Location Logs',
                  Icons.location_on_outlined,
                  Colors.red,
                  () => Navigator.pushNamed(context, AdminLocationScreen.id),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  bool confirm = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Wipe Data?'),
                      content: const Text('This will delete all attendance records from the database.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('WIPE', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ) ?? false;
                  
                  if (confirm) {
                    await DatabaseHelper.instance.clearAttendanceTable();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance table cleared!')));
                    }
                  }
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                label: const Text('Wipe Attendance Data (Temporary)', style: TextStyle(color: Colors.red)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            final path = await ExcelExportHelper.exportDataToExcel();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel Report Generated! Saved at: $path'),
                  duration: const Duration(seconds: 10),
                  action: SnackBarAction(label: 'OK', onPressed: () {}),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: Colors.red),
              );
            }
          }
        },
        label: const Text('Export Excel Report'),
        icon: const Icon(Icons.description_outlined),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildServiceCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
