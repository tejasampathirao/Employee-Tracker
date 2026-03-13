import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 23, // Bumped to 23 for Soft Delete (is_active) support
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Force creation of tables if they are missing
    await _createTables(db);
    
    if (oldVersion < 23) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN is_active INTEGER DEFAULT 1');
      } catch (e) {
        debugPrint("Note: users is_active column already exists or error: $e");
      }
    }

    if (oldVersion < 22) {
      try {
        await db.execute('ALTER TABLE employee_expenses ADD COLUMN status TEXT DEFAULT "Pending"');
      } catch (e) {
        debugPrint("Note: employee_expenses status column already exists or error: $e");
      }
    }

    if (oldVersion < 21) {
      try {
        await db.execute('ALTER TABLE attendance ADD COLUMN employee_id TEXT');
      } catch (e) {
        debugPrint("Note: attendance employee_id column already exists or error: $e");
      }
    }

    if (oldVersion < 20) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS travel_attendance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          checkInTime TEXT,
          date TEXT,
          latitude REAL,
          longitude REAL,
          employee_id TEXT,
          status TEXT
        )
      ''');
    }

    if (oldVersion < 16) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN emp_id TEXT');
      } catch (e) {
        debugPrint("Note: emp_id column already exists or error: $e");
      }
    }

    if (oldVersion < 15) {
      final columns = [
        'pan_no TEXT', 'aadhar_no TEXT', 'bank_acc_no TEXT', 
        'ifsc_code TEXT', 'father_name TEXT', 'mother_name TEXT', 
        'salary REAL', 'photo_path TEXT', 'role TEXT'
      ];
      for (var col in columns) {
        try {
          await db.execute('ALTER TABLE users ADD COLUMN $col');
        } catch (e) {
          debugPrint("Note: Column $col already exists or error: $e");
        }
      }
    }
    
    if (oldVersion < 14) {
      try {
        await db.execute('ALTER TABLE timelogs ADD COLUMN title TEXT');
      } catch (e) {
        // Column might already exist if table was created with version 13
        debugPrint("Note: timelogs title column already exists or error: $e");
      }
    }

    if (oldVersion < 11) {
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN bill_image TEXT');
      } catch (e) {
        debugPrint("Note: expenses bill_image column already exists or error: $e");
      }
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN src_lat REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN src_lng REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN dest_lat REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN dest_lng REAL');
      } catch (e) {
        debugPrint("Note: expenses location columns already exist or error: $e");
      }
    }
  }

  Future _createDB(Database db, int version) async {
    await _createTables(db);
    
    await db.insert('users', {
      'id': 1,
      'name': 'Teja',
      'details': 'Chief Financial Officer',
      'phone': '9876543210',
      'password': 'password123',
      'email': 'srinivas@example.com'
    });

    await db.insert('sites', {
      'name': 'Head Office',
      'lat': 12.9716,
      'lng': 77.5946
    });
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT,
        checkInTime TEXT,
        checkOutTime TEXT,
        date TEXT,
        latitude REAL,
        longitude REAL,
        type TEXT,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS timelogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        hours REAL,
        date TEXT,
        description TEXT,
        category TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        category TEXT,
        amount REAL,
        description TEXT,
        date TEXT,
        status TEXT,
        visit_type TEXT,
        bill_image TEXT,
        src_lat REAL,
        src_lng REAL,
        dest_lat REAL,
        dest_lng REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS leaves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        leaveType TEXT,
        fromDate TEXT,
        toDate TEXT,
        reason TEXT,
        status TEXT,
        appliedDate TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS leave_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT,
        leave_type TEXT,
        from_date TEXT,
        to_date TEXT,
        reason TEXT,
        status TEXT DEFAULT 'Pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT,
        date TEXT,
        expense_category TEXT,
        description TEXT,
        amount REAL,
        status TEXT DEFAULT 'Pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS live_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT,
        latitude REAL,
        longitude REAL,
        speed REAL,
        timestamp TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emp_id TEXT,
        name TEXT,
        details TEXT,
        phone TEXT,
        password TEXT,
        email TEXT,
        pan_no TEXT,
        aadhar_no TEXT,
        bank_acc_no TEXT,
        ifsc_code TEXT,
        father_name TEXT,
        mother_name TEXT,
        salary REAL,
        photo_path TEXT,
        role TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        lat REAL,
        lng REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS approvals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        status TEXT,
        date TEXT,
        type TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS travel_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checkInTime TEXT,
        date TEXT,
        latitude REAL,
        longitude REAL,
        employee_id TEXT,
        status TEXT
      )
    ''');
  }

  // --- MQTT Master Router Helper Methods ---

  Future<int> insertAttendance(Map<String, dynamic> payload) async {
    final db = await instance.database;
    // Map MQTT payload to attendance table
    return await db.insert('attendance', {
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'checkInTime': payload['timestamp'], // Using timestamp as check-in for records from employees
      'date': (payload['timestamp'] as String).split('T')[0],
      'latitude': payload['location']?['lat'],
      'longitude': payload['location']?['lng'],
      'status': payload['status'] ?? 'Checked-In',
      'type': 'Office'
    });
  }

  Future<int> insertTravelAttendance(Map<String, dynamic> payload) async {
    final db = await instance.database;
    return await db.insert('travel_attendance', {
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'checkInTime': payload['timestamp'],
      'date': (payload['timestamp'] as String).split('T')[0],
      'latitude': payload['lat'],
      'longitude': payload['lng'],
      'status': payload['action'] ?? 'Travel Event'
    });
  }

  Future<int> insertExpenseRecord(Map<String, dynamic> payload) async {
    final db = await instance.database;
    // Handles Food, Fuel, Travel, and Material via category
    return await db.insert('employee_expenses', {
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'date': payload['timestamp'] ?? DateTime.now().toIso8601String(),
      'expense_category': payload['category'] ?? payload['type'] ?? 'General',
      'description': payload['description'] ?? '',
      'amount': payload['amount'] ?? 0.0,
      'status': 'Pending' // Explicitly setting status to Pending
    });
  }

  Future<List<Map<String, dynamic>>> getUnifiedPendingApprovals() async {
    final db = await instance.database;
    
    // Fetch pending leaves
    final List<Map<String, dynamic>> leaves = await db.query(
      'leave_requests',
      where: 'status = ?',
      whereArgs: ['Pending'],
    );

    // Fetch pending expenses
    final List<Map<String, dynamic>> expenses = await db.query(
      'employee_expenses',
      where: 'status = ?',
      whereArgs: ['Pending'],
    );

    // Combine and mark types
    List<Map<String, dynamic>> combined = [];
    
    for (var leaf in leaves) {
      Map<String, dynamic> item = Map.from(leaf);
      item['approval_type'] = 'leave';
      combined.add(item);
    }

    for (var expense in expenses) {
      Map<String, dynamic> item = Map.from(expense);
      item['approval_type'] = 'expense';
      combined.add(item);
    }

    // Sort by ID descending (newest first)
    combined.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    
    return combined;
  }

  Future<int> insertLocationRecord(Map<String, dynamic> payload) async {
    final db = await instance.database;
    return await db.insert('live_locations', {
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'latitude': payload['lat'],
      'longitude': payload['lng'],
      'speed': payload['speed'] ?? 0.0,
      'timestamp': payload['timestamp'] ?? DateTime.now().toIso8601String(),
    });
  }

  // --- Travel Attendance Methods ---
  Future<int> checkInTravel(String time, String date, double lat, double lng, String employeeId) async {
    final db = await instance.database;
    return await db.insert('travel_attendance', {
      'checkInTime': time,
      'date': date,
      'latitude': lat,
      'longitude': lng,
      'employee_id': employeeId,
      'status': 'Checked-In'
    });
  }

  Future<List<Map<String, dynamic>>> getTravelAttendance() async {
    final db = await instance.database;
    return await db.query('travel_attendance', orderBy: 'id DESC');
  }

  Future<Map<String, dynamic>?> getLastTravelAttendance() async {
    final db = await instance.database;
    final result = await db.query(
      'travel_attendance',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<int> checkOutTravel(String checkOutTime, int id) async {
    final db = await instance.database;
    return await db.update(
      'travel_attendance',
      {
        'checkInTime': checkOutTime, // Note: Re-using the time field or we could add checkOutTime column. 
        // For simplicity and matching user request of "separate table", I will add a checkOutTime column in a version bump if needed, 
        // but for now I'll update status to 'Checked-Out'.
        'status': 'Checked-Out'
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Sites Methods ---
  Future<int> addSite(String name, double lat, double lng) async {
    final db = await instance.database;
    return await db.insert('sites', {
      'name': name,
      'lat': lat,
      'lng': lng
    });
  }

  Future<Map<String, LatLng>> getSites() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('sites');
    
    return {
      for (var row in maps)
        row['name'] as String: LatLng(row['lat'] as double, row['lng'] as double)
    };
  }

  // --- Settings Methods ---
  Future<int> updateSetting(String key, String value) async {
    final db = await instance.database;
    return await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  // --- Attendance Methods ---
  Future<int> checkIn(String checkInTime, String date, double? lat, double? lng, String employeeId, {String type = 'Office'}) async {
    final db = await instance.database;
    return await db.insert('attendance', {
      'employee_id': employeeId,
      'checkInTime': checkInTime,
      'date': date,
      'latitude': lat,
      'longitude': lng,
      'type': type,
      'status': 'Pending'
    });
  }

  Future<int> checkOut(String checkOutTime, int id, {String status = 'Completed'}) async {
    final db = await instance.database;
    return await db.update(
      'attendance',
      {
        'checkOutTime': checkOutTime,
        'status': status
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getLastAttendance() async {
    final db = await instance.database;
    final result = await db.query(
      'attendance',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllAttendance() async {
    final db = await instance.database;
    return await db.query('attendance', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getAllEmployeeAttendance() async {
    final db = await instance.database;
    // JOIN attendance with users to get both name and employee_id, filtering for active employees
    return await db.rawQuery('''
      SELECT a.*, u.name as name
      FROM attendance a
      LEFT JOIN users u ON a.employee_id = u.emp_id
      WHERE a.checkInTime IS NOT NULL AND (u.is_active = 1 OR u.is_active IS NULL)
      ORDER BY a.date DESC
    ''');
  }

  Future<Map<String, dynamic>> getEmployeeAttendanceStats(String employeeId) async {
    final db = await instance.database;
    final now = DateTime.now();

    // 1. Attendance Percentage (Current Month)
    final monthStartStr = "${DateFormat('yyyy-MM').format(now)}-01";
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    // Requirement: CASE INSENSITIVE (UPPER) and logic parity with Employee Dashboard
    final monthlyRecords = await db.rawQuery('''
      SELECT COUNT(DISTINCT date) as count
      FROM attendance
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''', [employeeId, monthStartStr]);

    int monthlyPresent = Sqflite.firstIntValue(monthlyRecords) ?? 0;
    // Requirement: DOUBLE CASTING
    double attendancePercentage = (monthlyPresent.toDouble() / daysInMonth.toDouble()) * 100.0;

    // 2. Late Minutes Calculation (Current Month)
    // Shift Start: 9:00 AM
    final checkInRecords = await db.rawQuery('''
      SELECT checkInTime 
      FROM attendance 
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND checkInTime IS NOT NULL
    ''', [employeeId, monthStartStr]);

    int totalLateMinutes = 0;
    for (var record in checkInRecords) {
      final String? checkInStr = record['checkInTime'] as String?;
      if (checkInStr != null) {
        try {
          final checkIn = DateTime.parse(checkInStr);
          final shiftStart = DateTime(checkIn.year, checkIn.month, checkIn.day, 9, 0);
          if (checkIn.isAfter(shiftStart)) {
            totalLateMinutes += checkIn.difference(shiftStart).inMinutes;
          }
        } catch (e) {
          debugPrint("Error parsing checkInTime in stats: $e");
        }
      }
    }

    return {
      'percentage': attendancePercentage.toStringAsFixed(1),
      'lateMinutes': totalLateMinutes,
    };
  }
  Future<Map<String, dynamic>?> authenticateUserByNameAndId(String name, String id) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'name = ? AND emp_id = ? AND is_active = 1',
      whereArgs: [name, id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // New Method to fetch previous calendar month's attendance
  Future<List<Map<String, dynamic>>> getLastMonthAttendance() async {
    final db = await instance.database;
    final now = DateTime.now();

    // Logic: DateTime(year, month - 1, 1) gets first day of previous month
    // Logic: DateTime(year, month, 0) gets last day of previous month
    final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);
    final lastDayLastMonth = DateTime(now.year, now.month, 0);

    final startStr = DateFormat('yyyy-MM-dd').format(firstDayLastMonth);
    final endStr = DateFormat('yyyy-MM-dd').format(lastDayLastMonth);

    debugPrint("Fetching Attendance between $startStr and $endStr");

    return await db.query(
      'attendance',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date DESC',
    );
  }

  Future<Map<String, double>> getAttendanceSummary() async {
    final db = await instance.database;
    final all = await db.query('attendance', where: 'checkOutTime IS NOT NULL');
    
    double todayTotal = 0;
    double weekTotal = 0;
    double monthTotal = 0;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekAgo = now.subtract(const Duration(days: 7));
    final firstOfMonth = DateTime(now.year, now.month, 1);

    for (var row in all) {
      final checkIn = DateTime.parse(row['checkInTime'] as String);
      final checkOut = DateTime.parse(row['checkOutTime'] as String);
      final duration = checkOut.difference(checkIn).inSeconds / 3600.0;
      final date = row['date'] as String;

      if (date == todayStr) todayTotal += duration;
      if (checkIn.isAfter(weekAgo)) weekTotal += duration;
      if (checkIn.isAfter(firstOfMonth)) monthTotal += duration;
    }

    return {
      'today': todayTotal,
      'week': weekTotal,
      'month': monthTotal,
    };
  }

  Future<Map<String, double>> getOvertimeStats() async {
    final db = await instance.database;
    // We query all records to support real-time OT for active sessions
    final all = await db.query('attendance');
    
    double todayOT = 0;
    double weekOT = 0;
    double monthOT = 0;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekAgo = now.subtract(const Duration(days: 7));
    final firstOfMonth = DateTime(now.year, now.month, 1);

    for (var row in all) {
      final checkIn = DateTime.parse(row['checkInTime'] as String);
      final checkOutStr = row['checkOutTime'] as String?;
      
      // Step 1: Parse/Determine Check-Out Time
      // For active sessions, we use DateTime.now() if it's today's log.
      DateTime? checkOut;
      if (checkOutStr != null) {
        checkOut = DateTime.parse(checkOutStr);
      } else if (row['date'] == todayStr) {
        checkOut = now;
      }

      if (checkOut != null) {
        // Step 2: Define the Threshold (5:30 PM on that specific day)
        final shiftEnd = DateTime(checkIn.year, checkIn.month, checkIn.day, 17, 30);

        // Step 3: Calculate the Difference
        // Rule: Any work done AFTER 5:30 PM is considered Overtime.
        if (checkOut.isAfter(shiftEnd)) {
          // If the employee checked in AFTER 5:30 PM, OT only starts from their check-in time.
          final otStartTime = checkIn.isAfter(shiftEnd) ? checkIn : shiftEnd;
          final double sessionOT = checkOut.difference(otStartTime).inSeconds / 3600.0;

          final date = row['date'] as String;
          if (date == todayStr) todayOT += sessionOT;
          if (checkIn.isAfter(weekAgo)) weekOT += sessionOT;
          if (checkIn.isAfter(firstOfMonth)) monthOT += sessionOT;
        }
      }
    }

    return {
      'today': todayOT,
      'week': weekOT,
      'month': monthOT,
    };
  }

  Future<int> markYesterdayPresent() async {
    final db = await instance.database;
    final yesterdayDate = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(yesterdayDate);
    
    // We update the status to 'Present' and ensure check-in/out times reflect a 9-hour shift
    int count = await db.update(
      'attendance',
      {
        'status': 'Present',
        'checkInTime': '${yesterdayStr}T09:00:00.000',
        'checkOutTime': '${yesterdayStr}T18:00:00.000',
      },
      where: 'date = ?',
      whereArgs: [yesterdayStr],
    );

    debugPrint("Developer Fix: Rows updated for $yesterdayStr: $count");
    return count;
  }

  Future<int> cleanDuplicateLogs() async {
    final db = await instance.database;
    // Requirement 2: Delete incomplete logs shorter than 60 seconds
    // Uses SQLite julianday to calculate difference in seconds
    return await db.rawDelete('''
      DELETE FROM attendance 
      WHERE status = 'Incomplete' 
      AND checkOutTime IS NOT NULL 
      AND (julianday(checkOutTime) - julianday(checkInTime)) * 86400 < 60
    ''');
  }

  // --- Approvals Methods ---
  Future<int> insertApproval(Map<String, dynamic> approval) async {
    final db = await instance.database;
    return await db.insert('approvals', approval);
  }

  Future<List<Map<String, dynamic>>> getApprovals() async {
    final db = await instance.database;
    return await db.query('approvals', orderBy: 'id DESC');
  }

  Future<int> updateApprovalStatus(int id, String status) async {
    final db = await instance.database;
    return await db.update('approvals', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Time Logs Methods ---
  Future<int> insertTimeLog(Map<String, dynamic> log) async {
    final db = await instance.database;
    return await db.insert('timelogs', log);
  }

  Future<List<Map<String, dynamic>>> getTimeLogs() async {
    final db = await instance.database;
    return await db.query('timelogs', orderBy: 'id DESC');
  }

  Future<Map<String, double>> getTimeLogStats() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    
    // Today
    final todayResult = await db.rawQuery(
      'SELECT SUM(hours) as total FROM timelogs WHERE date = ?',
      [todayStr],
    );
    double today = (todayResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // This Week (simplified: last 7 days)
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekResult = await db.rawQuery(
      'SELECT SUM(hours) as total FROM timelogs WHERE date >= ?',
      [DateFormat('yyyy-MM-dd').format(weekAgo)],
    );
    double week = (weekResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // This Month
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final monthResult = await db.rawQuery(
      'SELECT SUM(hours) as total FROM timelogs WHERE date >= ?',
      [DateFormat('yyyy-MM-dd').format(firstOfMonth)],
    );
    double month = (monthResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'today': today,
      'week': week,
      'month': month,
    };
  }

  // --- Expenses Methods ---
  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await instance.database;
    return await db.insert('expenses', expense);
  }

  Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await instance.database;
    return await db.query('expenses', orderBy: 'id DESC');
  }

  // --- Employee Expenses (Admin) ---
  Future<int> insertEmployeeExpense(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('employee_expenses', data);
  }

  Future<List<Map<String, dynamic>>> getExpensesByEmployeeAndDateRange(
    String empId, String startDate, String endDate) async {
    final db = await instance.database;
    return await db.query(
      'employee_expenses',
      where: 'employee_id = ? AND date >= ? AND date <= ?',
      whereArgs: [empId, startDate, endDate],
      orderBy: 'date DESC',
    );
  }

  Future<int> updateExpenseStatus(int id, String status) async {
    final db = await instance.database;
    return await db.update(
      'employee_expenses',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Live Location Methods ---
  Future<int> insertLiveLocation(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('live_locations', data);
  }

  Future<List<Map<String, dynamic>>> getAllLiveLocations() async {
    final db = await instance.database;
    return await db.query('live_locations', orderBy: 'timestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getAllEmployeeExpenses() async {
    final db = await instance.database;
    return await db.query('employee_expenses', orderBy: 'date DESC');
  }

  // --- Leaves Methods ---
  Future<int> insertLeave(Map<String, dynamic> leave) async {
    final db = await instance.database;
    return await db.insert('leaves', leave);
  }

  Future<List<Map<String, dynamic>>> getAllLeaves() async {
    final db = await instance.database;
    return await db.query('leaves', orderBy: 'id DESC');
  }

  Future<int> getUsedPaidLeavesThisYear(String employeeId) async {
    final db = await instance.database;
    final currentYear = DateTime.now().year.toString();
    
    // Count all 'Paid Leave' requests (Pending or Approved) for the current calendar year
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM leave_requests 
      WHERE employee_id = ? 
      AND (leave_type = 'Paid Leave' OR leave_type = 'Casual Leave')
      AND status != 'Rejected'
      AND from_date LIKE ?
    ''', [employeeId, '$currentYear-%']);
    
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<bool> hasUsedPaidLeaveThisMonth(String employeeId) async {
    final db = await instance.database;
    final String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    
    // Check if any 'Paid Leave' exists where the from_date starts with current YYYY-MM
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM leave_requests 
      WHERE employee_id = ? 
      AND leave_type = 'Paid Leave'
      AND status != 'Rejected'
      AND from_date LIKE ?
    ''', [employeeId, '$currentMonth-%']);

    int count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  // --- Leave Requests (Admin) ---
  Future<int> insertLeaveRequest(Map<String, dynamic> data) async {
    final db = await instance.database;
    
    // Remove 'type' key if present in MQTT payload to avoid crash (table has no 'type' column)
    final Map<String, dynamic> cleanData = Map.from(data);
    cleanData.remove('type');
    
    return await db.insert('leave_requests', cleanData);
  }

  Future<List<Map<String, dynamic>>> getPendingLeaveRequests() async {
    final db = await instance.database;
    return await db.query(
      'leave_requests',
      where: 'status = ?',
      whereArgs: ['Pending'],
      orderBy: 'id DESC',
    );
  }

  Future<int> updateLeaveRequestStatus(int id, String status) async {
    final db = await instance.database;
    return await db.update(
      'leave_requests',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateRequestStatus(String category, String id, String newStatus) async {
    final db = await instance.database;
    final intId = int.tryParse(id) ?? 0;
    
    if (category == 'leave_request') {
      // Update both possible leave tables for consistency
      await db.update('leave_requests', {'status': newStatus}, where: 'id = ?', whereArgs: [intId]);
      return await db.update('leaves', {'status': newStatus}, where: 'id = ?', whereArgs: [intId]);
    } else if (category == 'expense_claim' || category == 'expense_report' || category == 'expense_request') {
      // Update both possible expense tables
      await db.update('employee_expenses', {'status': newStatus}, where: 'id = ?', whereArgs: [intId]);
      return await db.update('expenses', {'status': newStatus}, where: 'id = ?', whereArgs: [intId]);
    }
    return 0;
  }

  Future<Map<String, dynamic>> getEmployeeAttendanceSummary(String employeeId) async {
    final db = await instance.database;
    final now = DateTime.now();
    
    // Weekly calculation (last 7 days)
    final weekStart = now.subtract(const Duration(days: 7));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);
    
    // Requirement: CASE INSENSITIVE and parity with stats
    final weeklyRecords = await db.rawQuery('''
      SELECT COUNT(DISTINCT date) as count 
      FROM attendance 
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''', [employeeId, weekStartStr]);
    
    int weeklyPresent = Sqflite.firstIntValue(weeklyRecords) ?? 0;
    // Requirement: DOUBLE CASTING
    double weeklyPercentage = (weeklyPresent.toDouble() / 7.0) * 100.0;

    // Monthly calculation (current month)
    final monthStartStr = "${DateFormat('yyyy-MM').format(now)}-01";
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    
    final monthlyRecords = await db.rawQuery('''
      SELECT COUNT(DISTINCT date) as count 
      FROM attendance 
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''', [employeeId, monthStartStr]);
    
    int monthlyPresent = Sqflite.firstIntValue(monthlyRecords) ?? 0;
    // Requirement: DOUBLE CASTING
    double monthlyPercentage = (monthlyPresent.toDouble() / daysInMonth.toDouble()) * 100.0;

    return {
      'weekly': weeklyPercentage.toStringAsFixed(1),
      'monthly': monthlyPercentage.toStringAsFixed(1),
    };
  }

  // --- Report Methods ---
  Future<String> calculateHoursInRange(DateTime start, DateTime end) async {
    final db = await instance.database;
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    // Query all completed attendance records in the date range
    final result = await db.query(
      'attendance',
      where: 'date >= ? AND date <= ? AND checkOutTime IS NOT NULL',
      whereArgs: [startStr, endStr],
    );

    double totalHours = 0.0;
    for (var row in result) {
      try {
        final checkIn = DateTime.parse(row['checkInTime'] as String);
        final checkOut = DateTime.parse(row['checkOutTime'] as String);
        totalHours += checkOut.difference(checkIn).inSeconds / 3600.0;
      } catch (e) {
        debugPrint("Error parsing attendance record for report: $e");
      }
    }
    
    int h = totalHours.floor();
    int m = ((totalHours - h) * 60).round();
    
    return "${h}h ${m}m";
  }

  // --- User Methods ---
  Future<bool> registerUserWithNameIdRole(String name, String empId, String role) async {
    final db = await instance.database;
    
    // Check if ID already exists
    final existing = await db.query(
      'users',
      where: 'emp_id = ?',
      whereArgs: [empId],
    );

    if (existing.isNotEmpty) {
      return false; // ID already registered
    }

    // Insert new user
    await db.insert('users', {
      'name': name,
      'emp_id': empId,
      'role': role,
      'details': role // Use role for details for backward compatibility
    });
    return true;
  }

  Future<bool> isEmailRegistered(String email) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    return result.isNotEmpty;
  }

  Future<bool> registerUser(String name, String email, String password) async {
    final db = await instance.database;
    
    // Check if email already exists
    final existing = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (existing.isNotEmpty) {
      return false; // Email already registered
    }

    // Insert new user
    await db.insert('users', {
      'name': name,
      'email': email,
      'password': password,
      'details': 'Employee' // Default role/details
    });
    return true;
  }

  Future<Map<String, dynamic>?> authenticateUser(String email, String password) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'email = ? AND password = ? AND is_active = 1',
      whereArgs: [email, password],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getUser() async {
    final db = await instance.database;
    final result = await db.query('users', where: 'id = ?', whereArgs: [1]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateUserProfile(String name, String details) async {
    final db = await instance.database;
    return await db.update('users', {'name': name, 'details': details}, where: 'id = ?', whereArgs: [1]);
  }

  Future<int> updateUserPassword(String email, String newPassword) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<int> updatePassword(String newPassword) async {
    final db = await instance.database;
    // Note: If you have multiple users, you should pass an ID here.
    return await db.update('users', {'password': newPassword}, where: 'id = ?', whereArgs: [1]);
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await instance.database;
    return await db.query('users', where: 'is_active = 1', orderBy: 'name ASC');
  }

  Future<void> deactivateEmployee(String employeeId) async {
    final db = await instance.database;
    await db.update(
      'users',
      {'is_active': 0},
      where: 'emp_id = ?',
      whereArgs: [employeeId],
    );
  }

  Future<int> updateEmployee(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert(
      'users',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> clearAttendanceTable() async {
    final db = await instance.database;
    return await db.delete('attendance');
  }

  Future<void> seedData() async {
    // Dummy data generation logic removed
  }
}
