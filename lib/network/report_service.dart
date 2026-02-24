import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ReportService {
  // 1. Get the local path for saving files
  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // 2. Reference to the report file
  static Future<File> _getLocalFile(String fileName) async {
    final path = await _localPath;
    return File('$path/$fileName');
  }

  // 3. Append new Expenses to the CSV report
  static Future<void> appendExpenseToReport(Map<String, dynamic> expense) async {
    final file = await _getLocalFile('expense_report.csv');
    bool exists = await file.exists();

    // Create header if file is new
    if (!exists) {
      await file.writeAsString('ID,Type,Category,Amount,Description,Date,Status\n');
    }

    // Prepare row data
    String row = '${expense['id'] ?? 'N/A'},${expense['type']},${expense['category']},${expense['amount']},"${expense['description']}",${expense['date']},${expense['status']}\n';

    // CRUCIAL: Append to existing file rather than overwriting
    await file.writeAsString(row, mode: FileMode.append);
  }

  // 4. Append new Leave to the CSV report
  static Future<void> appendLeaveToReport(Map<String, dynamic> leave) async {
    final file = await _getLocalFile('leave_report.csv');
    bool exists = await file.exists();

    // Create header if file is new
    if (!exists) {
      await file.writeAsString('ID,Type,From,To,Reason,Status,AppliedDate\n');
    }

    // Prepare row data
    String row = '${leave['id'] ?? 'N/A'},${leave['leaveType']},${leave['fromDate']},${leave['toDate']},"${leave['reason']}",${leave['status']},${leave['appliedDate']}\n';

    // Append to file
    await file.writeAsString(row, mode: FileMode.append);
  }
}
