import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

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
      version: 8, // Bumped version to 8
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE attendance ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE attendance ADD COLUMN longitude REAL');
    }
    if (oldVersion < 3) {
      // Create new tables for existing users upgrading to version 3
      await db.execute('''
        CREATE TABLE IF NOT EXISTS approvals (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          type TEXT,
          status TEXT,
          requester TEXT,
          timestamp TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS timelogs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT,
          task TEXT,
          hours REAL,
          description TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT
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
          status TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE attendance ADD COLUMN type TEXT DEFAULT "Office"');
      await db.execute('ALTER TABLE attendance ADD COLUMN status TEXT DEFAULT "Completed"');
    }
    if (oldVersion < 6) {
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
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY,
          name TEXT,
          details TEXT,
          phone TEXT,
          password TEXT,
          email TEXT
        )
      ''');
      await db.insert('users', {
        'id': 1,
        'name': 'Srinivas Reddy',
        'details': 'Chief Financial Officer',
        'phone': '9876543210',
        'password': 'password123',
        'email': 'srinivas@example.com'
      });
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN email TEXT');
        await db.update('users', {'email': 'srinivas@example.com'}, where: 'id = ?', whereArgs: [1]);
      } catch (e) {
        // ignore
      }
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
      CREATE TABLE approvals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        type TEXT,
        status TEXT,
        requester TEXT,
        timestamp TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE timelogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        task TEXT,
        hours REAL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        category TEXT,
        amount REAL,
        description TEXT,
        date TEXT,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE leaves (
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
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT,
        details TEXT,
        phone TEXT,
        password TEXT,
        email TEXT
      )
    ''');
    
    await db.insert('users', {
      'id': 1,
      'name': 'Srinivas Reddy',
      'details': 'Chief Financial Officer',
      'phone': '9876543210',
      'password': 'password123',
      'email': 'srinivas@example.com'
    });
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
  Future<int> checkIn(String checkInTime, String date, double? lat, double? lng, {String type = 'Office'}) async {
    final db = await instance.database;
    return await db.insert('attendance', {
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

  // --- Leaves Methods ---
  Future<int> insertLeave(Map<String, dynamic> leave) async {
    final db = await instance.database;
    return await db.insert('leaves', leave);
  }

  Future<List<Map<String, dynamic>>> getAllLeaves() async {
    final db = await instance.database;
    return await db.query('leaves', orderBy: 'id DESC');
  }

  // --- User Methods ---
  Future<Map<String, dynamic>?> getUser() async {
    final db = await instance.database;
    final result = await db.query('users', where: 'id = ?', whereArgs: [1]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateUserProfile(String name, String details) async {
    final db = await instance.database;
    return await db.update('users', {'name': name, 'details': details}, where: 'id = ?', whereArgs: [1]);
  }

  Future<int> updatePassword(String newPassword) async {
    final db = await instance.database;
    return await db.update('users', {'password': newPassword}, where: 'id = ?', whereArgs: [1]);
  }

  Future<void> seedData() async {
    try {
      // Dummy data removed as requested
    } catch (e) {
      // Log the error but don't crash the app
      debugPrint("Error seeding data: $e");
    }
  }
}