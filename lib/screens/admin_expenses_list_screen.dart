import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'employee_expense_detail_screen.dart';

class AdminExpensesListScreen extends StatefulWidget {
  const AdminExpensesListScreen({super.key});
  static const String id = 'admin_expenses_list_screen';

  @override
  State<AdminExpensesListScreen> createState() => _AdminExpensesListScreenState();
}

class _AdminExpensesListScreenState extends State<AdminExpensesListScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses Management'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getAllEmployees(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No employees found.'));
          }

          final employees = snapshot.data!;

          return ListView.builder(
            itemCount: employees.length,
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemBuilder: (context, index) {
              final employee = employees[index];
              final String name = employee['name'] ?? 'Unknown';
              final String empId = employee['emp_id'] ?? employee['id'].toString();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      name[0].toUpperCase(),
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: $empId'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EmployeeExpenseDetailScreen(
                          employeeId: empId,
                          employeeName: name,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
