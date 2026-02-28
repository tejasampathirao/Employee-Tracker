import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AppLogger {
  static final ValueNotifier<List<String>> logs = ValueNotifier([]);

  static void log(String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final logEntry = "[$timestamp] $message";

    // Update ValueNotifier (triggering UI updates)
    final currentLogs = List<String>.from(logs.value);
    currentLogs.insert(0, logEntry);

    // Keep it reasonable (optional: limit to last 500 logs)
    if (currentLogs.length > 500) {
      currentLogs.removeLast();
    }
    
    logs.value = currentLogs;

    // Still show in VS Code console
    debugPrint(logEntry);
  }

  static void clear() {
    logs.value = [];
  }
}
