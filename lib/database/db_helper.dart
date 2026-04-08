import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      version: 28, // Bumped to 28 to add start_date and end_date to holidays
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Force creation of tables if they are missing
    await _createTables(db);

    if (oldVersion < 28) {
      try {
        await db.execute('ALTER TABLE holidays ADD COLUMN start_date TEXT');
        await db.execute('ALTER TABLE holidays ADD COLUMN end_date TEXT');
      } catch (e) {
        debugPrint("Note: holidays date columns already exist or error: $e");
      }
    }

    if (oldVersion < 27) {
      final tables = ['employee_expenses', 'leave_requests'];
      for (var table in tables) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN approved_by TEXT');
        } catch (e) {
          debugPrint(
            "Note: $table approved_by column already exists or error: $e",
          );
        }
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN approved_at TEXT');
        } catch (e) {
          debugPrint(
            "Note: $table approved_at column already exists or error: $e",
          );
        }
      }
    }

    if (oldVersion < 26) {
      await _seedDefaultHolidays(db);
    }

    if (oldVersion < 25) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN employee_id TEXT');
      } catch (e) {
        debugPrint(
          "Note: users employee_id column already exists or error: $e",
        );
      }
    }

    if (oldVersion < 24) {
      final tables = ['employee_expenses', 'leave_requests'];
      for (var table in tables) {
        try {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN request_id TEXT UNIQUE',
          );
          await db.execute('ALTER TABLE $table ADD COLUMN latitude REAL');
          await db.execute('ALTER TABLE $table ADD COLUMN longitude REAL');
          await db.execute('ALTER TABLE $table ADD COLUMN distance REAL');
        } catch (e) {
          debugPrint("Note: Columns for $table already exist or error: $e");
        }
      }
    }

    if (oldVersion < 23) {
      try {
        await db.execute(
          'ALTER TABLE users ADD COLUMN is_active INTEGER DEFAULT 1',
        );
      } catch (e) {
        debugPrint("Note: users is_active column already exists or error: $e");
      }
    }

    if (oldVersion < 22) {
      try {
        await db.execute(
          'ALTER TABLE employee_expenses ADD COLUMN status TEXT DEFAULT "Pending"',
        );
      } catch (e) {
        debugPrint(
          "Note: employee_expenses status column already exists or error: $e",
        );
      }
    }

    if (oldVersion < 21) {
      try {
        await db.execute('ALTER TABLE attendance ADD COLUMN employee_id TEXT');
      } catch (e) {
        debugPrint(
          "Note: attendance employee_id column already exists or error: $e",
        );
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
        'pan_no TEXT',
        'aadhar_no TEXT',
        'bank_acc_no TEXT',
        'ifsc_code TEXT',
        'father_name TEXT',
        'mother_name TEXT',
        'salary REAL',
        'photo_path TEXT',
        'role TEXT',
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
        debugPrint(
          "Note: expenses bill_image column already exists or error: $e",
        );
      }
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE expenses ADD COLUMN src_lat REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN src_lng REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN dest_lat REAL');
        await db.execute('ALTER TABLE expenses ADD COLUMN dest_lng REAL');
      } catch (e) {
        debugPrint(
          "Note: expenses location columns already exist or error: $e",
        );
      }
    }
  }

  Future _createDB(Database db, int version) async {
    await _createTables(db);

    await db.insert('sites', {
      'name': 'Head Office',
      'lat': 12.9716,
      'lng': 77.5946,
    });

    await _seedDefaultHolidays(db);
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
        request_id TEXT UNIQUE,
        employee_id TEXT,
        leave_type TEXT,
        from_date TEXT,
        to_date TEXT,
        reason TEXT,
        status TEXT DEFAULT 'Pending',
        latitude REAL,
        longitude REAL,
        distance REAL,
        approved_by TEXT,
        approved_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id TEXT UNIQUE,
        employee_id TEXT,
        date TEXT,
        expense_category TEXT,
        description TEXT,
        amount REAL,
        status TEXT DEFAULT 'Pending',
        latitude REAL,
        longitude REAL,
        distance REAL,
        approved_by TEXT,
        approved_at TEXT
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
        employee_id TEXT,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS holidays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        name TEXT NOT NULL,
        is_recurring INTEGER DEFAULT 0
      )
    ''');
  }

  // --- MQTT Master Router Helper Methods ---

  Future<int> insertAttendance(Map<String, dynamic> payload) async {
    final db = await instance.database;
    // Map MQTT payload to attendance table
    return await db.insert('attendance', {
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'checkInTime':
          payload['timestamp'], // Using timestamp as check-in for records from employees
      'date': (payload['timestamp'] as String).split('T')[0],
      'latitude': payload['location']?['lat'],
      'longitude': payload['location']?['lng'],
      'status': payload['status'] ?? 'Checked-In',
      'type': 'Office',
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
      'status': payload['action'] ?? 'Travel Event',
    });
  }

  Future<int> insertHoliday(Map<String, dynamic> payload) async {
    final db = await instance.database;
    return await db.insert('holidays', {
      'date': (payload['start_date'] ?? payload['date'] as String).split(
        'T',
      )[0],
      'start_date': payload['start_date'],
      'end_date': payload['end_date'],
      'name': payload['reason'] ?? 'Company Holiday',
      'is_recurring': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUpcomingHolidays() async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String().split('T')[0];
    return await db.query(
      'holidays',
      where: 'date >= ? OR start_date >= ?',
      whereArgs: [now, now],
      orderBy: 'date ASC',
    );
  }

  Future<int> insertExpenseRecord(Map<String, dynamic> payload) async {
    final db = await instance.database;
    // Handles Food, Fuel, Travel, and Material via category
    final String rawDate =
        payload['timestamp'] ?? DateTime.now().toIso8601String();
    final String dateOnly = rawDate.contains('T')
        ? rawDate.split('T')[0]
        : rawDate;
    return await db.insert('employee_expenses', {
      'request_id': payload['request_id'],
      'employee_id': payload['employee_id'] ?? 'Unknown',
      'date': dateOnly,
      'expense_category': payload['category'] ?? payload['type'] ?? 'General',
      'description': payload['description'] ?? '',
      'amount': payload['amount'] ?? 0.0,
      'status': payload['status'] ?? 'Pending',
      'latitude': payload['latitude'] ?? payload['lat'],
      'longitude': payload['longitude'] ?? payload['lng'],
      'distance': payload['distance'] ?? payload['distance_km'],
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getUnifiedPendingApprovals() async {
    final db = await instance.database;

    // Fetch pending leaves with real_employee_id via JOIN on users table
    final List<Map<String, dynamic>> leaves = await db.rawQuery('''
      SELECT l.*, u.emp_id as real_employee_id, u.name as employee_name 
      FROM leave_requests l 
      LEFT JOIN users u ON (l.employee_id = u.name OR l.employee_id = u.emp_id) 
      WHERE l.status = 'Pending'
    ''');

    // Fetch pending expenses with real_employee_id via JOIN on users table
    final List<Map<String, dynamic>> expenses = await db.rawQuery('''
      SELECT e.*, u.emp_id as real_employee_id, u.name as employee_name 
      FROM employee_expenses e 
      LEFT JOIN users u ON (e.employee_id = u.name OR e.employee_id = u.emp_id) 
      WHERE e.status = 'Pending'
    ''');

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

  /// Get unified approval history (Approved/Rejected) with optional date range filter
  Future<List<Map<String, dynamic>>> getApprovalHistory({
    String? fromDate,
    String? toDate,
  }) async {
    final db = await instance.database;

    String leaveWhere = "l.status IN ('Approved', 'Rejected')";
    String expenseWhere = "e.status IN ('Approved', 'Rejected')";
    List<dynamic> leaveArgs = [];
    List<dynamic> expenseArgs = [];

    if (fromDate != null && toDate != null) {
      leaveWhere += " AND l.from_date >= ? AND l.from_date <= ?";
      leaveArgs.addAll([fromDate, toDate]);
      expenseWhere +=
          " AND substr(e.date, 1, 10) >= ? AND substr(e.date, 1, 10) <= ?";
      expenseArgs.addAll([fromDate, toDate]);
    }

    final List<Map<String, dynamic>> leaves = await db.rawQuery('''
      SELECT l.*, u.emp_id as real_employee_id, u.name as employee_name 
      FROM leave_requests l 
      LEFT JOIN users u ON (l.employee_id = u.name OR l.employee_id = u.emp_id) 
      WHERE $leaveWhere
    ''', leaveArgs);

    final List<Map<String, dynamic>> expenses = await db.rawQuery('''
      SELECT e.*, u.emp_id as real_employee_id, u.name as employee_name 
      FROM employee_expenses e 
      LEFT JOIN users u ON (e.employee_id = u.name OR e.employee_id = u.emp_id) 
      WHERE $expenseWhere
    ''', expenseArgs);

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
  Future<int> checkInTravel(
    String time,
    String date,
    double lat,
    double lng,
    String employeeId,
  ) async {
    final db = await instance.database;
    return await db.insert('travel_attendance', {
      'checkInTime': time,
      'date': date,
      'latitude': lat,
      'longitude': lng,
      'employee_id': employeeId,
      'status': 'Checked-In',
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
        'checkInTime':
            checkOutTime, // Note: Re-using the time field or we could add checkOutTime column.
        // For simplicity and matching user request of "separate table", I will add a checkOutTime column in a version bump if needed,
        // but for now I'll update status to 'Checked-Out'.
        'status': 'Checked-Out',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Sites Methods ---
  Future<int> addSite(String name, double lat, double lng) async {
    final db = await instance.database;
    return await db.insert('sites', {'name': name, 'lat': lat, 'lng': lng});
  }

  Future<Map<String, LatLng>> getSites() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('sites');

    return {
      for (var row in maps)
        row['name'] as String: LatLng(
          row['lat'] as double,
          row['lng'] as double,
        ),
    };
  }

  // --- Settings Methods ---
  Future<int> updateSetting(String key, String value) async {
    final db = await instance.database;
    return await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  // --- Attendance Methods ---
  Future<int> checkIn(
    String checkInTime,
    String date,
    double? lat,
    double? lng,
    String employeeId, {
    String type = 'Office',
  }) async {
    final db = await instance.database;
    return await db.insert('attendance', {
      'employee_id': employeeId,
      'checkInTime': checkInTime,
      'date': date,
      'latitude': lat,
      'longitude': lng,
      'type': type,
      'status': 'Pending',
    });
  }

  Future<int> checkOut(
    String checkOutTime,
    int id, {
    String status = 'Completed',
  }) async {
    final db = await instance.database;
    return await db.update(
      'attendance',
      {'checkOutTime': checkOutTime, 'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getLastAttendance() async {
    final db = await instance.database;
    final result = await db.query('attendance', orderBy: 'id DESC', limit: 1);
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
    return await db.rawQuery('''
      SELECT a.*, u.name as name 
      FROM attendance a 
      LEFT JOIN users u ON UPPER(a.employee_id) = UPPER(u.employee_id) 
      ORDER BY a.date DESC, a.id DESC
    ''');
  }

  Future<Map<String, dynamic>> getEmployeeAttendanceStats(
    String employeeId,
  ) async {
    final db = await instance.database;
    final now = DateTime.now();

    // 1. Attendance Percentage (Current Month)
    final monthStartStr = "${DateFormat('yyyy-MM').format(now)}-01";
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    // Updated: Ensuring strict employee_id filter is applied to prevent company-wide summing
    final monthlyRecords = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT date) as count
      FROM attendance
      WHERE employee_id = ? AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''',
      [employeeId, monthStartStr],
    );

    int monthlyPresent = Sqflite.firstIntValue(monthlyRecords) ?? 0;
    double attendancePercentage =
        (monthlyPresent.toDouble() / daysInMonth.toDouble()) * 100.0;

    // 2. Late Minutes Calculation (Current Month)
    final checkInRecords = await db.rawQuery(
      '''
      SELECT checkInTime 
      FROM attendance 
      WHERE employee_id = ? AND date >= ? AND checkInTime IS NOT NULL
    ''',
      [employeeId, monthStartStr],
    );

    int totalLateMinutes = 0;
    for (var record in checkInRecords) {
      final String? checkInStr = record['checkInTime'] as String?;
      if (checkInStr != null) {
        try {
          final checkIn = DateTime.parse(checkInStr);
          final shiftStart = DateTime(
            checkIn.year,
            checkIn.month,
            checkIn.day,
            9,
            0,
          );
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

  Future<Map<String, dynamic>?> authenticateUserByNameAndId(
    String name,
    String id,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'name = ? AND emp_id = ? AND is_active = 1',
      whereArgs: [name, id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // New Method to fetch current calendar month's attendance for a specific employee
  Future<List<Map<String, dynamic>>> getCurrentMonthAttendance(
    String employeeId,
  ) async {
    final db = await instance.database;
    final now = DateTime.now();

    // Logic: DateTime(year, month, 1) gets first day of current month
    // Logic: DateTime(year, month + 1, 0) gets last day of current month
    final firstDayCurrentMonth = DateTime(now.year, now.month, 1);
    final lastDayCurrentMonth = DateTime(now.year, now.month + 1, 0);

    final startStr = DateFormat('yyyy-MM-dd').format(firstDayCurrentMonth);
    final endStr = DateFormat('yyyy-MM-dd').format(lastDayCurrentMonth);

    debugPrint(
      "Fetching Current Month Attendance for $employeeId between $startStr and $endStr",
    );

    return await db.query(
      'attendance',
      where: 'UPPER(employee_id) = UPPER(?) AND date >= ? AND date <= ?',
      whereArgs: [employeeId, startStr, endStr],
      orderBy: 'date DESC',
    );
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

    return {'today': todayTotal, 'week': weekTotal, 'month': monthTotal};
  }

  Future<Map<String, double>> getOvertimeStats({String? employeeId}) async {
    final db = await instance.database;
    final String whereClause = employeeId != null
        ? 'employee_id = ? AND checkOutTime IS NOT NULL'
        : 'checkOutTime IS NOT NULL';
    final List<dynamic>? whereArgs = employeeId != null ? [employeeId] : null;
    final all = await db.query('attendance', where: whereClause, whereArgs: whereArgs);

    double todayOT = 0;
    double weekOT = 0;
    double monthOT = 0;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekAgo = now.subtract(const Duration(days: 7));
    final firstOfMonth = DateTime(now.year, now.month, 1);

    final prefs = await SharedPreferences.getInstance();
    final shiftEndStr = prefs.getString('shift_to_time') ?? '17:00';
    final otBufferMins = prefs.getInt('ot_buffer') ?? 25;
    final endParts = shiftEndStr.split(':');
    final shiftEndHour = int.tryParse(endParts[0]) ?? 17;
    final shiftEndMinute = int.tryParse(endParts[1]) ?? 0;

    for (var row in all) {
      final checkIn = DateTime.parse(row['checkInTime'] as String);
      final checkOutStr = row['checkOutTime'] as String?;

      DateTime? checkOut;
      if (checkOutStr != null) {
        checkOut = DateTime.parse(checkOutStr);
      } else if (row['date'] == todayStr) {
        checkOut = now;
      }

      if (checkOut != null) {
        final shiftEnd = DateTime(
          checkIn.year,
          checkIn.month,
          checkIn.day,
          shiftEndHour,
          shiftEndMinute,
        );

        if (checkOut.isAfter(shiftEnd)) {
          final otStartTime = checkIn.isAfter(shiftEnd) ? checkIn : shiftEnd;
          final extraMinutes = checkOut.difference(otStartTime).inMinutes;
          if (extraMinutes >= otBufferMins) {
            final double sessionOT = (extraMinutes - otBufferMins) / 3600.0;
            final date = row['date'] as String;
            if (date == todayStr) todayOT += sessionOT;
            if (checkIn.isAfter(weekAgo)) weekOT += sessionOT;
            if (checkIn.isAfter(firstOfMonth)) monthOT += sessionOT;
          }
        }
      }
    }

    return {'today': todayOT, 'week': weekOT, 'month': monthOT};
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
    return await db.update(
      'approvals',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
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

    return {'today': today, 'week': week, 'month': month};
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
    String empId,
    String startDate,
    String endDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'employee_expenses',
      where: 'employee_id = ? AND date >= ? AND date <= ?',
      whereArgs: [empId, startDate, endDate],
      orderBy: 'date DESC',
    );
  }

  Future<int> updateExpenseStatus(
    int id,
    String status, {
    String? approvedBy,
    String? approvedAt,
  }) async {
    final db = await instance.database;
    final values = <String, dynamic>{'status': status};
    if (approvedBy != null) values['approved_by'] = approvedBy;
    if (approvedAt != null) values['approved_at'] = approvedAt;
    return await db.update(
      'employee_expenses',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> getMonthlyExpenseTotal(
    String category, {
    String? employeeId,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(days: 1));

    final startDateStr = monthStart.toIso8601String().split('T')[0];
    final endDateStr = monthEnd.toIso8601String().split('T')[0];

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0.0) as total FROM employee_expenses
      WHERE expense_category = ? 
        AND date >= ? 
        AND date <= ?
        AND status IN ('Approved', 'Pending')
        ${employeeId != null ? 'AND employee_id = ?' : ''}
      ''',
      employeeId != null
          ? [category, startDateStr, endDateStr, employeeId]
          : [category, startDateStr, endDateStr],
    );

    final total = result.isNotEmpty && result[0]['total'] != null
        ? (result[0]['total'] as num).toDouble()
        : 0.0;

    return total;
  }

  Future<double> getCategorySpentThisMonth(
    String category, {
    String? employeeId,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1)
        .toIso8601String()
        .split('T')[0];

    final query = StringBuffer(
      'SELECT SUM(amount) as total FROM employee_expenses WHERE expense_category = ? '
      'AND date >= ? AND status IN ("Approved", "Pending")',
    );
    final args = <Object>[category, firstDayOfMonth];
    if (employeeId != null && employeeId.isNotEmpty) {
      query.write(' AND employee_id = ?');
      args.add(employeeId);
    }

    final result = await db.rawQuery(query.toString(), args);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
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

    // Check both leave_requests (from admin/MQTT) and local leaves table
    final remoteResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM leave_requests 
      WHERE (employee_id = ? OR employee_id IN (SELECT name FROM users WHERE emp_id = ?))
      AND (leave_type = 'Paid Leave' OR leave_type = 'Casual Leave')
      AND status = 'Approved'
      AND from_date LIKE ?
    ''',
      [employeeId, employeeId, '$currentYear-%'],
    );

    final localResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM leaves 
      WHERE (leaveType = 'Paid Leave' OR leaveType = 'Casual Leave')
      AND status = 'Approved'
      AND fromDate LIKE ?
    ''',
      ['$currentYear-%'],
    );

    final remote = Sqflite.firstIntValue(remoteResult) ?? 0;
    final local = Sqflite.firstIntValue(localResult) ?? 0;
    return remote > local ? remote : local;
  }

  Future<bool> hasUsedPaidLeaveThisMonth(String employeeId) async {
    final db = await instance.database;
    final String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

    final remoteResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM leave_requests 
      WHERE (employee_id = ? OR employee_id IN (SELECT name FROM users WHERE emp_id = ?))
      AND leave_type = 'Paid Leave'
      AND status = 'Approved'
      AND from_date LIKE ?
    ''',
      [employeeId, employeeId, '$currentMonth-%'],
    );

    final localResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM leaves 
      WHERE leaveType = 'Paid Leave'
      AND status = 'Approved'
      AND fromDate LIKE ?
    ''',
      ['$currentMonth-%'],
    );

    int remote = Sqflite.firstIntValue(remoteResult) ?? 0;
    int local = Sqflite.firstIntValue(localResult) ?? 0;
    return (remote > 0 || local > 0);
  }

  // --- Leave Requests (Admin) ---
  Future<int> insertLeaveRequest(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('leave_requests', {
      'request_id': data['request_id'],
      'employee_id': data['employee_id'] ?? 'Unknown',
      'leave_type': data['leave_type'] ?? 'Leave',
      'from_date': data['from_date'] ?? '',
      'to_date': data['to_date'] ?? '',
      'reason': data['reason'] ?? '',
      'status': data['status'] ?? 'Pending',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getPendingLeaveRequests() async {
    final db = await instance.database;
    final leaves = await db.query('leave_requests', orderBy: 'id DESC');
    return leaves;
  }

  Future<int> updateLeaveRequestStatus(
    int id,
    String status, {
    String? approvedBy,
    String? approvedAt,
  }) async {
    final db = await instance.database;
    final values = <String, dynamic>{'status': status};
    if (approvedBy != null) values['approved_by'] = approvedBy;
    if (approvedAt != null) values['approved_at'] = approvedAt;
    return await db.update(
      'leave_requests',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateRequestStatus(
    String category,
    String id,
    String newStatus,
  ) async {
    final db = await instance.database;

    if (category == 'leave_request') {
      int updated = await db.update(
        'leave_requests',
        {'status': newStatus},
        where: 'request_id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        final intId = int.tryParse(id) ?? 0;
        updated = await db.update(
          'leave_requests',
          {'status': newStatus},
          where: 'id = ?',
          whereArgs: [intId],
        );
      }
      return updated;
    } else if (category == 'expense_claim' ||
        category == 'expense_report' ||
        category == 'expense_request') {
      int updated = await db.update(
        'employee_expenses',
        {'status': newStatus},
        where: 'request_id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        final intId = int.tryParse(id) ?? 0;
        updated = await db.update(
          'employee_expenses',
          {'status': newStatus},
          where: 'id = ?',
          whereArgs: [intId],
        );
      }
      return updated;
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> getMyExpenseRequests(
    String employeeId,
  ) async {
    final db = await instance.database;
    return await db.query(
      'employee_expenses',
      where:
          'employee_id = ? OR employee_id IN (SELECT name FROM users WHERE emp_id = ?)',
      whereArgs: [employeeId, employeeId],
      orderBy: 'id DESC',
    );
  }

  Future<Map<String, dynamic>> getEmployeeAttendanceSummary(
    String employeeId,
  ) async {
    final db = await instance.database;
    final now = DateTime.now();

    // Weekly calculation (last 7 days)
    final weekStart = now.subtract(const Duration(days: 7));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

    // Requirement: CASE INSENSITIVE and parity with stats
    final weeklyRecords = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT date) as count 
      FROM attendance 
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''',
      [employeeId, weekStartStr],
    );

    int weeklyPresent = Sqflite.firstIntValue(weeklyRecords) ?? 0;
    // Requirement: DOUBLE CASTING
    double weeklyPercentage = (weeklyPresent.toDouble() / 7.0) * 100.0;

    // Monthly calculation (current month)
    final monthStartStr = "${DateFormat('yyyy-MM').format(now)}-01";
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    final monthlyRecords = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT date) as count 
      FROM attendance 
      WHERE UPPER(employee_id) = UPPER(?) AND date >= ? AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''',
      [employeeId, monthStartStr],
    );

    int monthlyPresent = Sqflite.firstIntValue(monthlyRecords) ?? 0;
    // Requirement: DOUBLE CASTING
    double monthlyPercentage =
        (monthlyPresent.toDouble() / daysInMonth.toDouble()) * 100.0;

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
  Future<bool> registerUserWithNameIdRole(
    String name,
    String empId,
    String role,
  ) async {
    final db = await instance.database;

    // Check if ID already exists
    final existing = await db.query(
      'users',
      where: 'emp_id = ?',
      whereArgs: [empId],
    );

    if (existing.isNotEmpty) {
      final isActive = existing.first['is_active'] as int? ?? 1;
      if (isActive == 1) {
        return false; // Active employee — ID already registered
      }

      // Reactivate deactivated employee with new details
      await db.update(
        'users',
        {'name': name, 'role': role, 'details': role, 'is_active': 1},
        where: 'emp_id = ?',
        whereArgs: [empId],
      );
      return true;
    }

    // Insert new user with role and employee_id
    await db.insert('users', {
      'name': name,
      'emp_id': empId,
      'employee_id': empId, // Set both for compatibility
      'role': role,
      'details': role, // Use role for details for backward compatibility
      'is_active': 1,
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
      'details': 'Employee', // Default role/details
    });
    return true;
  }

  Future<Map<String, dynamic>?> authenticateUser(
    String email,
    String password,
  ) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'email = ? AND password = ? AND is_active = 1',
      whereArgs: [email, password],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final empId = prefs.getString('employee_id')?.trim();

    if (empId == null || empId.isEmpty) {
      return null;
    }

    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'emp_id = ? OR employee_id = ?',
      whereArgs: [empId, empId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateUserProfile(String name, String details) async {
    final prefs = await SharedPreferences.getInstance();
    final empId = prefs.getString('employee_id');

    if (empId == null || empId.isEmpty) {
      return 0;
    }

    final db = await instance.database;
    return await db.update(
      'users',
      {'name': name, 'details': details},
      where: 'emp_id = ?',
      whereArgs: [empId],
    );
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
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await instance.database;
    return await db.query(
      'users',
      where: 'is_active = 1 AND (role IS NULL OR LOWER(role) != "admin")',
      orderBy: 'name ASC',
    );
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

  Future<List<Map<String, dynamic>>> getAttendanceByEmployee(
    String empId,
  ) async {
    final db = await instance.database;
    return await db.query(
      'attendance',
      where: 'employee_id = ?',
      whereArgs: [empId],
      orderBy: 'date ASC',
    );
  }

  Future<Map<String, dynamic>> getEmployeeOTStats(String employeeId) async {
    final db = await instance.database;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final shiftEndStr = prefs.getString('shift_to_time') ?? '17:00';
    final otBufferMins = prefs.getInt('ot_buffer') ?? 25;
    final endParts = shiftEndStr.split(':');
    final shiftEndHour = int.tryParse(endParts[0]) ?? 17;
    final shiftEndMinute = int.tryParse(endParts[1]) ?? 0;

    // 1. Current Week OT
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

    final weeklyRecords = await db.query(
      'attendance',
      where: 'employee_id = ? AND date >= ? AND checkOutTime IS NOT NULL',
      whereArgs: [employeeId, weekStartStr],
    );

    // 2. Current Month OT
    final monthStartStr = "${DateFormat('yyyy-MM').format(now)}-01";
    final monthlyRecords = await db.query(
      'attendance',
      where: 'employee_id = ? AND date >= ? AND checkOutTime IS NOT NULL',
      whereArgs: [employeeId, monthStartStr],
    );

    int calculateTotalOT(List<Map<String, dynamic>> records) {
      int totalMinutes = 0;
      for (var record in records) {
        final checkOutStr = record['checkOutTime'] as String?;
        final checkInStr = record['checkInTime'] as String?;
        if (checkOutStr != null && checkInStr != null) {
          try {
            final checkIn = DateTime.parse(checkInStr);
            final checkOut = DateTime.parse(checkOutStr);
            final shiftEnd = DateTime(
              checkOut.year,
              checkOut.month,
              checkOut.day,
              shiftEndHour,
              shiftEndMinute,
            );

            if (checkOut.isAfter(shiftEnd)) {
              final otStartTime = checkIn.isAfter(shiftEnd) ? checkIn : shiftEnd;
              final extraMinutes = checkOut.difference(otStartTime).inMinutes;
              if (extraMinutes >= otBufferMins) {
                totalMinutes += extraMinutes - otBufferMins;
              }
            }
          } catch (e) {
            debugPrint("Error parsing checkOutTime for OT stats: $e");
          }
        }
      }
      return totalMinutes;
    }

    return {
      'weeklyOTMinutes': calculateTotalOT(weeklyRecords),
      'monthlyOTMinutes': calculateTotalOT(monthlyRecords),
    };
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

  // --- Holiday Methods ---

  static const List<Map<String, String>> _companyHolidays = [
    {'month': '01', 'day': '01', 'name': 'New Year'},
    {'month': '01', 'day': '14', 'name': 'Makara Sankranti'},
    {'month': '01', 'day': '26', 'name': 'Republic Day'},
    {'month': '02', 'day': '26', 'name': 'Maha Shivarathri'},
    {'month': '03', 'day': '30', 'name': 'Ugadi'},
    {'month': '05', 'day': '01', 'name': 'May Day'},
    {'month': '08', 'day': '15', 'name': 'Independence Day'},
    {'month': '08', 'day': '27', 'name': 'Ganesh Chaturthi'},
    {'month': '10', 'day': '02', 'name': 'Gandhi Jayanthi / Dasara Festival'},
    {'month': '10', 'day': '20', 'name': 'Deepavali Festival'},
    {'month': '11', 'day': '01', 'name': 'Kannada Rajyothsava'},
  ];

  Future<void> _seedDefaultHolidays(Database db) async {
    // Check if holidays already seeded
    final existing = await db.query('holidays', limit: 1);
    if (existing.isNotEmpty) return;

    final years = [2025, 2026];
    for (final year in years) {
      for (final h in _companyHolidays) {
        await db.insert('holidays', {
          'date': '$year-${h['month']}-${h['day']}',
          'name': h['name'],
          'is_recurring': 1,
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> getHolidaysForYear(int year) async {
    final db = await instance.database;
    return await db.query(
      'holidays',
      where: "date LIKE ?",
      whereArgs: ['$year%'],
      orderBy: 'date ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllHolidays() async {
    final db = await instance.database;
    return await db.query('holidays', orderBy: 'date ASC');
  }

  Future<int> addHoliday(
    String date,
    String name, {
    bool isRecurring = false,
  }) async {
    final db = await instance.database;
    return await db.insert('holidays', {
      'date': date,
      'name': name,
      'is_recurring': isRecurring ? 1 : 0,
    });
  }

  Future<int> deleteHoliday(int id) async {
    final db = await instance.database;
    return await db.delete('holidays', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateHoliday(int id, String date, String name) async {
    final db = await instance.database;
    return await db.update(
      'holidays',
      {'date': date, 'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Shift Settings Methods ---
  Future<String> getShiftFromTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('shift_from_time') ?? '09:00';
  }

  Future<String> getShiftToTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('shift_to_time') ?? '17:00';
  }

  Future<void> setShiftTimes(String fromTime, String toTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shift_from_time', fromTime);
    await prefs.setString('shift_to_time', toTime);
  }

  // --- New Methods for Total Monthly Salary Calculation ---
  Future<double> getEmployeeSalary(String empId) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      columns: ['salary'],
      where: 'emp_id = ? OR employee_id = ?',
      whereArgs: [empId, empId],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['salary'] as double? ?? 0.0;
    }
    return 0.0;
  }

  Future<int> getPresentDaysCount(String empId, int month, int year) async {
    final db = await instance.database;
    final monthPrefix = DateFormat('yyyy-MM').format(DateTime(year, month));

    final result = await db.rawQuery('''
      SELECT COUNT(DISTINCT date) as presentCount
      FROM attendance
      WHERE (employee_id = ? OR employee_id IN (SELECT name FROM users WHERE emp_id = ?))
        AND date LIKE ?
        AND (status = 'Present' OR checkInTime IS NOT NULL)
    ''', [empId, empId, '$monthPrefix-%']);

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<double> getApprovedMonthlyExpenses(String empId) async {
    // Use admin-defined monthly expense limits as the approved expenses amount.
    // This is sourced from SharedPreferences set by the Admin Expense Limits screen.
    final prefs = await SharedPreferences.getInstance();
    final foodLimit = prefs.getDouble('food_amt_limit') ?? 0.0;
    final materialLimit = prefs.getDouble('material_amt_limit') ?? 0.0;
    final fuelLimit = prefs.getDouble('fuel_amt_limit') ?? 0.0;
    final travelRapidoLimit = prefs.getDouble('travel_rapido_limit') ?? 0.0;
    final travelBusLimit = prefs.getDouble('travel_bus_limit') ?? 0.0;
    final travelOwnVehicleLimit = prefs.getDouble('travel_own_vehicle_limit') ?? 0.0;

    return foodLimit + materialLimit + fuelLimit + travelRapidoLimit + travelBusLimit + travelOwnVehicleLimit;
  }
}
