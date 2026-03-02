import 'package:flutter/material.dart';
import 'dart:async';
import '../database/db_helper.dart';
import 'package:intl/intl.dart';
import '../services/mqtt_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../constants.dart';
import '../network/location_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../utils/app_logger.dart';

class AttendanceCard extends StatefulWidget {
  final VoidCallback? onActionComplete;
  const AttendanceCard({super.key, this.onActionComplete});

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  Timer? _timer;
  Duration _duration = Duration.zero;
  int? _currentAttendanceId;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  late MqttHandler mqttService;

  // Geofencing and History logic
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadLastAttendance();
    _setupMqtt();

    // Requirement 2: Setup live geofence listener
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (_isCheckedIn) {
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          kOfficeLatitude,
          kOfficeLongitude,
        );
        
        AppLogger.log("GEOFENCE: Distance to office: ${distance.toStringAsFixed(0)}m");

        // Requirement 2: IF distance > 100m AND checked-in, trigger auto-checkout
        if (distance > 100) {
          AppLogger.log("GEOFENCE: Auto-checkout triggered (out of bounds)");
          _handleCheckInOut(isAuto: true);
        }
      }
    });
  }

  void _setupMqtt() async {
    mqttService = MqttHandler();
    await mqttService.connect();
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // REQUIREMENT: Request Runtime Permissions for Notifications (Android 13+) 
    // and Exact Alarms (Android 12+)
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // Request notification permission
      await androidImplementation.requestNotificationsPermission();
      // Request exact alarm permission
      await androidImplementation.requestExactAlarmsPermission();
      AppLogger.log("NOTIFICATIONS: Runtime permissions requested.");
    }
  }

  Future<void> _scheduleNextShiftAlarm() async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day + 1, 9, 0); // 9:00 AM tomorrow

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Upcoming Shift',
      'Your next shift starts at 9:00 AM. Get ready!',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'shift_alarm',
          'Shift Alarms',
          channelDescription: 'Alarms for upcoming shifts',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // Requirement 2: Schedule Reminder for 5:30 PM
  Future<void> _scheduleShiftEndReminder() async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, 17, 30); // 5:30 PM Today

    // If it's already past 5:30 PM, don't schedule for today
    if (now.isAfter(scheduledDate)) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      1, // Unique ID for shift end
      'Shift Ended 🕠',
      'Don\'t forget to mark your attendance checkout!',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'shift_end_reminder',
          'Shift End Reminders',
          channelDescription: 'Reminders to check out at end of shift',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // Requirement 3: Cancel Logic
  Future<void> _cancelShiftEndReminder() async {
    await flutterLocalNotificationsPlugin.cancel(1);
  }

  Future<void> _loadLastAttendance() async {
    final lastAttendance = await DatabaseHelper.instance.getLastAttendance();
    
    // Load local history list
    await DatabaseHelper.instance.getAllAttendance();

    if (lastAttendance != null && lastAttendance['checkOutTime'] == null) {
      setState(() {
        _isCheckedIn = true;
        _currentAttendanceId = lastAttendance['id'];
        _checkInTime = DateTime.parse(lastAttendance['checkInTime']);
        _startTimer();
      });
      // Resume location tracking if already checked in
      // Note: We might need to handle the MQTT client migration here too
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        setState(() {
          _duration = DateTime.now().difference(_checkInTime!);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)} : $twoDigitMinutes : $twoDigitSeconds";
  }

  Future<void> _handleCheckInOut({bool isAuto = false}) async {
    // FIX 1: Location Runtime Permissions Check
    final hasPermission = await LocationService().handleLocationPermission(context);
    if (!hasPermission) return;

    final now = DateTime.now();
    final timeString = now.toIso8601String();
    final dateString = DateFormat('yyyy-MM-dd').format(now);

    try {
      if (!_isCheckedIn) {
        // Requirement 1: Strict Location Validation
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );

        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          kOfficeLatitude,
          kOfficeLongitude,
        );
        
        AppLogger.log("CHECK-IN: Distance to office: ${distance.toStringAsFixed(0)}m");

        // STRICT GEOFENCE ENFORCEMENT
        if (distance > 100) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Check-in failed: You are not at the office location. (Distance: ${distance.toStringAsFixed(0)}m)'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return; // STOP execution here: No timer, No MQTT
        }

        // Proceed with check-in only if within 100m
        final id = await DatabaseHelper.instance.checkIn(
          timeString, 
          dateString, 
          position.latitude, 
          position.longitude,
          type: 'Office'
        );
        
        // Publish to MQTT using standardized function
        mqttService.publishAttendance(
          "Checked In",
          position.latitude,
          position.longitude,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Checked in at Office.'), backgroundColor: Colors.green),
          );
        }
        
        setState(() {
          _isCheckedIn = true;
          _checkInTime = now;
          _currentAttendanceId = id;
          _duration = Duration.zero;
        });
        _startTimer();
        
        // Requirement 2: Schedule 5:30 PM reminder on Check-In
        _scheduleShiftEndReminder();

        if (widget.onActionComplete != null) widget.onActionComplete!();

      } else {
        // Requirement 2: Minimum Duration for "Present" Status
        if (_currentAttendanceId != null && _checkInTime != null) {
          Duration worked = now.difference(_checkInTime!);
          // DATABASE LOGIC: Explicitly save strings
          String finalStatus = worked.inHours >= 9 ? 'Present' : 'Incomplete';
          
          await DatabaseHelper.instance.checkOut(timeString, _currentAttendanceId!, status: finalStatus);
          
          // Get current position for MQTT
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );

          // Publish to MQTT using standardized function
          mqttService.publishAttendance(
            finalStatus,
            position.latitude,
            position.longitude,
          );

          // Requirement 3: Cancel 5:30 PM reminder on Check-Out
          _cancelShiftEndReminder();

          if (finalStatus == 'Present') {
            await _scheduleNextShiftAlarm();
          }

          _timer?.cancel();
          
          setState(() {
            _isCheckedIn = false;
            _checkInTime = null;
            _currentAttendanceId = null;
            _duration = Duration.zero;
          });
          
          if (widget.onActionComplete != null) widget.onActionComplete!();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(finalStatus == 'Present' 
                  ? 'Shift Completed: Present' 
                  : 'Checked out: Shift Incomplete (< 9hrs)'),
                backgroundColor: finalStatus == 'Present' ? Colors.blue : Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel(); // Requirement 2: Prevent memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(radius: 45, child: Icon(Icons.person, size: 45)),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>?>(
              future: DatabaseHelper.instance.getUser(),
              builder: (context, snapshot) {
                final name = snapshot.data?['name'] ?? 'Employee Name';
                return Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
              },
            ),
            const Divider(height: 30),
            Text(
              _isCheckedIn ? 'Checked-in' : 'Yet to check-in',
              style: TextStyle(
                color: _isCheckedIn ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_duration),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _handleCheckInOut,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _isCheckedIn ? Colors.red : Colors.green),
                ),
                child: Text(
                  _isCheckedIn ? 'Check-out' : 'Check-in',
                  style: TextStyle(color: _isCheckedIn ? Colors.red : Colors.green),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
