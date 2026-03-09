import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';

class EmployeeExpenseDetailScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const EmployeeExpenseDetailScreen({
    super.key, 
    required this.employeeId, 
    required this.employeeName
  });

  @override
  State<EmployeeExpenseDetailScreen> createState() => _EmployeeExpenseDetailScreenState();
}

class _EmployeeExpenseDetailScreenState extends State<EmployeeExpenseDetailScreen> {
  // Category Selections
  bool _hasFood = false;
  bool _hasFuel = false;
  bool _hasTravel = false;

  // Controllers
  final _foodDesc = TextEditingController();
  final _foodAmt = TextEditingController();
  final _fuelDesc = TextEditingController();
  final _fuelAmt = TextEditingController();
  final _travelDesc = TextEditingController();
  final _travelAmt = TextEditingController();

  bool _isLoading = false;

  Future<void> _saveExpenses() async {
    setState(() => _isLoading = true);
    final today = DateTime.now().toIso8601String();

    try {
      if (_hasFood) {
        await DatabaseHelper.instance.insertEmployeeExpense({
          'employee_id': widget.employeeId,
          'date': today,
          'expense_category': 'Food',
          'description': _foodDesc.text,
          'amount': double.tryParse(_foodAmt.text) ?? 0.0,
        });
      }

      if (_hasFuel) {
        await DatabaseHelper.instance.insertEmployeeExpense({
          'employee_id': widget.employeeId,
          'date': today,
          'expense_category': 'Fuel',
          'description': _fuelDesc.text,
          'amount': double.tryParse(_fuelAmt.text) ?? 0.0,
        });
      }

      if (_hasTravel) {
        await DatabaseHelper.instance.insertEmployeeExpense({
          'employee_id': widget.employeeId,
          'date': today,
          'expense_category': 'Travel',
          'description': _travelDesc.text,
          'amount': double.tryParse(_travelAmt.text) ?? 0.0,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expenses saved successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expenses: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadReport() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() => _isLoading = true);
      try {
        final startDate = DateFormat('yyyy-MM-dd').format(picked.start);
        final endDate = DateFormat('yyyy-MM-dd').format(picked.end);

        final expenses = await DatabaseHelper.instance.getExpensesByEmployeeAndDateRange(
          widget.employeeId, startDate, endDate
        );

        if (expenses.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No expenses found for this range.')),
            );
          }
          return;
        }

        // Generate Excel
        var excel = Excel.createExcel();
        Sheet sheet = excel['Expenses'];
        
        sheet.appendRow([
          TextCellValue('Date'), 
          TextCellValue('Category'), 
          TextCellValue('Description'), 
          TextCellValue('Amount (₹)')
        ]);

        for (var ex in expenses) {
          sheet.appendRow([
            TextCellValue(ex['date'].toString().split('T')[0]),
            TextCellValue(ex['expense_category']),
            TextCellValue(ex['description']),
            DoubleCellValue(ex['amount']),
          ]);
        }

        final directory = await getApplicationDocumentsDirectory();
        final fileName = "Expenses_${widget.employeeId}_${startDate}_to_${endDate}.xlsx";
        final path = p.join(directory.path, fileName);
        final file = File(path);
        
        final bytes = excel.save();
        if (bytes != null) {
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Report saved to: $path'), duration: const Duration(seconds: 5)),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Expenses: ${widget.employeeName}'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _downloadReport,
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Download Report',
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildExpenseSection('Food Expenses', _hasFood, (val) => setState(() => _hasFood = val!), _foodDesc, _foodAmt),
                const SizedBox(height: 20),
                _buildExpenseSection('Fuel Expenses', _hasFuel, (val) => setState(() => _hasFuel = val!), _fuelDesc, _fuelAmt),
                const SizedBox(height: 20),
                _buildExpenseSection('Travel Expenses', _hasTravel, (val) => setState(() => _hasTravel = val!), _travelDesc, _travelAmt),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: _saveExpenses,
                    icon: const Icon(Icons.save),
                    label: const Text('SAVE EXPENSES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildExpenseSection(String title, bool isVisible, ValueChanged<bool?> onChanged, TextEditingController desc, TextEditingController amt) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Switch(value: isVisible, onChanged: onChanged),
              ],
            ),
            if (isVisible) ...[
              const Divider(height: 30),
              TextField(
                controller: desc,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amt,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
