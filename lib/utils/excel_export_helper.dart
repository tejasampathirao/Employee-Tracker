import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';

class ExcelExportHelper {
  static Future<String> exportDataToExcel() async {
    final excel = Excel.createExcel();
    
    // Remove default sheet
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // 1. Attendance Sheet
    Sheet attendanceSheet = excel['Attendance'];
    final attendanceData = await DatabaseHelper.instance.getAllEmployeeAttendance();
    attendanceSheet.appendRow([
      TextCellValue('Employee ID'), 
      TextCellValue('Date'), 
      TextCellValue('Check-In'), 
      TextCellValue('Check-Out'), 
      TextCellValue('Status')
    ]);
    for (var row in attendanceData) {
      attendanceSheet.appendRow([
        TextCellValue(row['id'].toString()), // Assuming record id or user id
        TextCellValue(row['date'] ?? ''),
        TextCellValue(row['checkInTime'] ?? ''),
        TextCellValue(row['checkOutTime'] ?? ''),
        TextCellValue(row['status'] ?? ''),
      ]);
    }

    // 2. Locations Sheet
    Sheet locationSheet = excel['Locations'];
    final locationData = await DatabaseHelper.instance.getAllLiveLocations();
    locationSheet.appendRow([
      TextCellValue('Employee ID'), 
      TextCellValue('Timestamp'), 
      TextCellValue('Latitude'), 
      TextCellValue('Longitude'), 
      TextCellValue('Speed')
    ]);
    for (var row in locationData) {
      locationSheet.appendRow([
        TextCellValue(row['employee_id'] ?? ''),
        TextCellValue(row['timestamp'] ?? ''),
        DoubleCellValue(row['latitude'] ?? 0.0),
        DoubleCellValue(row['longitude'] ?? 0.0),
        DoubleCellValue(row['speed'] ?? 0.0),
      ]);
    }

    // 3. Expenses Sheet
    Sheet expenseSheet = excel['Expenses'];
    final expenseData = await DatabaseHelper.instance.getAllEmployeeExpenses();
    expenseSheet.appendRow([
      TextCellValue('Employee ID'), 
      TextCellValue('Date'), 
      TextCellValue('Category'), 
      TextCellValue('Description'), 
      TextCellValue('Amount')
    ]);
    for (var row in expenseData) {
      expenseSheet.appendRow([
        TextCellValue(row['employee_id'] ?? ''),
        TextCellValue(row['date'] ?? ''),
        TextCellValue(row['expense_category'] ?? ''),
        TextCellValue(row['description'] ?? ''),
        DoubleCellValue(row['amount'] ?? 0.0),
      ]);
    }

    // Save the file
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, "Admin_HR_Report.xlsx");
    final file = File(path);
    
    final bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }

    // Trigger System Share Sheet
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'Admin HR Report',
      text: 'Please find the generated HR and Tracking report attached.',
    );

    return path;
  }

  static Future<String> appendToExcel({
    required String sheetName,
    required List<String> headers,
    required List<dynamic> rowData,
  }) async {
    const String fileName = "HR_Service_Logs.xlsx";
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, fileName);
    final file = File(path);

    Excel excel;
    if (await file.exists()) {
      var bytes = file.readAsBytesSync();
      excel = Excel.decodeBytes(bytes);
    } else {
      excel = Excel.createExcel();
      // Remove default sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    }

    Sheet sheet = excel[sheetName];

    // Add headers if sheet is new
    if (sheet.maxRows == 0) {
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
    }

    // Append the row data
    sheet.appendRow(rowData.map((e) {
      if (e is double) return DoubleCellValue(e);
      if (e is int) return IntCellValue(e);
      if (e is bool) return BoolCellValue(e);
      return TextCellValue(e?.toString() ?? "");
    }).toList());

    var fileBytes = excel.save();
    if (fileBytes != null) {
      await file.writeAsBytes(fileBytes);
    }

    return path;
  }
}
