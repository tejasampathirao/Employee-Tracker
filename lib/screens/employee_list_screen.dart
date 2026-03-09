import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'employee_edit_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});
  static const String id = 'employee_list_screen';

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Details'),
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
            itemBuilder: (context, index) {
              final employee = employees[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Text(
                    employee['name']?[0]?.toUpperCase() ?? 'E',
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  employee['name'] ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('ID: ${employee['emp_id'] ?? employee['id']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmployeeEditScreen(employee: employee),
                    ),
                  );
                  setState(() {}); // Refresh list after returning
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, EmployeeEditScreen.id);
          setState(() {}); // Refresh list
        },
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
