import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLogger {
  static final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>([]);
  static final StreamController<void> holidayUpdateStream = StreamController<void>.broadcast();

  static void log(String message) {
    if (kDebugMode) {
      final String timestamp = DateTime.now().toIso8601String().substring(11, 19);
      final String logEntry = "[$timestamp] $message";
      
      print("[EmployeeTracker] $logEntry");

      // Update the logs list for the UI
      final List<String> currentLogs = List.from(logs.value);
      currentLogs.insert(0, logEntry); // Newest on top
      if (currentLogs.length > 500) currentLogs.removeLast(); // Keep reasonable
      logs.value = currentLogs;
    }
  }

  static void clear() {
    logs.value = [];
  }

  static void triggerHolidayRefresh() {
    holidayUpdateStream.add(null);
  }
}
