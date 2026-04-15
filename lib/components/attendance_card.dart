import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/background_geofence_service.dart';
import '../services/overtime_calculator_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AttendanceCard extends StatefulWidget {
  final VoidCallback? onActionComplete;
  const AttendanceCard({super.key, this.onActionComplete});

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard>
    with WidgetsBindingObserver {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  Timer? _timer;
  Duration _duration = Duration.zero;
  int? _currentAttendanceId;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  late MqttHandler mqttService;

  // Dynamic shift times
  int _shiftStartHour = 9;
  int _shiftStartMinute = 0;
  int _shiftEndHour = 17;
  int _shiftEndMinute = 0;

  // Geofencing and History logic
  StreamSubscription<Position>? _positionStream;
  Timer? _exitDebounceTimer;

  // Dual Zone Geofencing
  bool _isSiteMode = false;
  LatLng? _activeSiteLocation;
  int _consecutiveExitPulses = 0;
  static const double kOfficeRadius = 100.0;
  static const double kSiteTriggerDistance = 6000.0; // 6 km
  static const double kSiteRadius = 100.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _loadShiftTimes();
    _loadLastAttendance();
    _setupMqtt();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check attendance state when app returns to foreground
    // (handles case where auto-checkout happened in background)
    if (state == AppLifecycleState.resumed) {
      _loadLastAttendance();
    }
  }

  void _startGeofenceMonitoring() {
    _positionStream?.cancel();

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Monitoring your attendance location",
          notificationTitle: "Attendance Active",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _exitDebounceTimer?.cancel();
    _exitDebounceTimer = null;
    _consecutiveExitPulses = 0;

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) async {
        if (!_isCheckedIn) return;

        if (position.accuracy > 50) {
          AppLogger.log("GPS Jump detected (Accuracy: ${position.accuracy}m). Ignoring pulse.");
          return;
        }

        double distance;
        double radius;
        String mode;

        // 1. Determine Mode & Radius
        double distanceToOffice = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          kOfficeLatitude,
          kOfficeLongitude,
        );

        if (_isSiteMode && _activeSiteLocation != null) {
          distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            _activeSiteLocation!.latitude,
            _activeSiteLocation!.longitude,
          );
          radius = kSiteRadius;
          mode = "Site";
        } else {
          distance = distanceToOffice;
          radius = kOfficeRadius;
          mode = "Office";

          // Trigger Site Mode if > 6km from office
          if (distanceToOffice > kSiteTriggerDistance && !_isSiteMode) {
            AppLogger.log("GEOFENCE: Distance > 6km. Switching to Site Mode.");
            setState(() {
              _isSiteMode = true;
            });
          }
        }

        AppLogger.log("GEOFENCE: Mode: $mode | Distance: ${distance.toStringAsFixed(0)}m | Radius: ${radius}m");

        // 2. Handle Geofence Logic with Stability Check (3 Pulses)
        if (distance > radius) {
          _consecutiveExitPulses++;
          AppLogger.log("GEOFENCE: Outside radius. Pulse count: $_consecutiveExitPulses/3");

          if (_consecutiveExitPulses >= 3) {
            AppLogger.log("GEOFENCE: Stability check failed. Triggering Auto-Checkout.");
            await _performAutoCheckout("Left $mode area (Stability Check)");
          } else {
            // MQTT Heartbeat: Outside but not yet stable checkout
            _publishGeofenceHeartbeat(position, mode, "Exited", radius);
          }
        } else {
          _consecutiveExitPulses = 0; // Reset on return
          _publishGeofenceHeartbeat(position, mode, "Inside", radius);
        }
      },
    );
  }

  void _publishGeofenceHeartbeat(Position pos, String mode, String status, double radius) async {
    final prefs = await SharedPreferences.getInstance();
    final empId = prefs.getString('employee_id') ?? 'Unknown';

    mqttService.publishGeofenceAttendance(
      status: "Heartbeat",
      lat: pos.latitude,
      lng: pos.longitude,
      employeeId: empId,
      locationMode: mode,
      geofenceStatus: status,
      activeSiteCoords: _activeSiteLocation != null
          ? {"lat": _activeSiteLocation!.latitude, "lng": _activeSiteLocation!.longitude}
          : null,
    );
  }

  /// Background-safe auto-checkout — works even when the app is not in foreground
  Future<void> _performAutoCheckout(String reason) async {
    AppLogger.log("AUTO-CHECKOUT: Triggered. Reason: $reason");
    if (_currentAttendanceId == null || _checkInTime == null) return;

    _positionStream?.cancel();

    final now = DateTime.now();
    final timeString = now.toIso8601String();

    // 1. Calculate Overtime using Service (Simultaneous Running)
    final allRecords = await DatabaseHelper.instance.getAllAttendance();
    final otResult = await OvertimeCalculatorService().calculateDailyOT(
      _checkInTime!.toIso8601String(),
      timeString,
      allRecords,
    );

    int calculatedOT = otResult.dailyOTMinutes + otResult.doubleTimeMinutes;

    Duration worked = now.difference(_checkInTime!);
    String finalStatus = worked.inHours >= 9 ? 'Present' : 'Incomplete';

    // 2. Save and Stop OT
    await DatabaseHelper.instance.updateCheckOut(
      timeString,
      _currentAttendanceId!,
      status: finalStatus,
      otMinutes: calculatedOT,
    );

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final prefs = await SharedPreferences.getInstance();
      final empId = prefs.getString('employee_id') ?? 'Unknown';

      // 3. MQTT Payload with Geofence Details
      mqttService.publishGeofenceAttendance(
        status: finalStatus,
        lat: position.latitude,
        lng: position.longitude,
        employeeId: empId,
        locationMode: _isSiteMode ? "Site" : "Office",
        geofenceStatus: "Exited",
        activeSiteCoords: _activeSiteLocation != null
            ? {"lat": _activeSiteLocation!.latitude, "lng": _activeSiteLocation!.longitude}
            : null,
        empstatus: 'checkout',
        otMinutes: calculatedOT,
      );
    } catch (e) {
      AppLogger.log("AUTO-CHECKOUT: Failed to publish MQTT: $e");
    }

    _cancelShiftEndReminder();
    BackgroundGeofenceService.stopMonitoring();
    _timer?.cancel();

    // Reset Site Mode state
    _isSiteMode = false;
    _activeSiteLocation = null;
    _consecutiveExitPulses = 0;

    // Show notification
    await flutterLocalNotificationsPlugin.show(
      2,
      'Auto Checkout 📍',
      'You left the $reason radius. Status: $finalStatus',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'auto_checkout',
          'Auto Checkout',
          channelDescription: 'Notifications for automatic checkout',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _currentAttendanceId = null;
        _duration = Duration.zero;
        _isSiteMode = false;
        _activeSiteLocation = null;
      });
    }

    if (widget.onActionComplete != null) widget.onActionComplete!();
    AppLogger.log("AUTO-CHECKOUT: Completed. Status: $finalStatus, OT: $calculatedOT mins");
  }

  Future<void> _triggerExitNotification() async {
    AppLogger.log('GEOFENCE: Triggering exit notification after debounce timer');
    await flutterLocalNotificationsPlugin.show(
      3,
      'Location Update',
      'You seem to have left the office. Would you like to Check Out?',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'exit_notification',
          'Exit Notification',
          channelDescription:
              'Notification for geofence exit verification',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  void _setupMqtt() async {
    mqttService = MqttHandler();
    await mqttService.connect();
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // REQUIREMENT: Request Runtime Permissions for Notifications (Android 13+)
    // and Exact Alarms (Android 12+)
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

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
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day + 1,
      _shiftStartHour,
      _shiftStartMinute,
    ); // Next shift start

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Upcoming Shift',
      'Your next shift starts at $_shiftStartHour:${_shiftStartMinute.toString().padLeft(2, '0')}. Get ready!',
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

  // Requirement 2: Schedule Reminder for shift end
  Future<void> _scheduleShiftEndReminder() async {
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      _shiftEndHour,
      _shiftEndMinute,
    );

    // If it's already past shift end, don't schedule for today
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
      final checkInTime = DateTime.parse(lastAttendance['checkInTime']);
      final now = DateTime.now();

      // SAME DAY RULE: If check-in is NOT from today, it's a stale session
      if (checkInTime.day != now.day ||
          checkInTime.month != now.month ||
          checkInTime.year != now.year) {
        AppLogger.log(
          "STALE SESSION: Auto-resetting UI for previous day's check-in: ${lastAttendance['checkInTime']}",
        );

        // Reset state variables for UI
        setState(() {
          _isCheckedIn = false;
          _checkInTime = null;
          _currentAttendanceId = null;
          _duration = Duration.zero;
        });
        return;
      }

      setState(() {
        _isCheckedIn = true;
        _currentAttendanceId = lastAttendance['id'];
        _checkInTime = checkInTime;
        _startTimer();
      });
      _startGeofenceMonitoring(); // Resume foreground stream

      // Resume background foreground service
      final prefs = await SharedPreferences.getInstance();
      final empId = prefs.getString('employee_id') ?? 'Unknown';
      BackgroundGeofenceService.startMonitoring(
        attendanceId: _currentAttendanceId!,
        employeeId: empId,
      );

      // Listen for auto-checkout events from the background service
      FlutterBackgroundService().on('auto_checkout_done').listen((_) {
        _loadLastAttendance();
      });
    }
  }

  Future<void> _loadShiftTimes() async {
    final fromTime = await DatabaseHelper.instance.getShiftFromTime();
    final toTime = await DatabaseHelper.instance.getShiftToTime();
    final fromParts = fromTime.split(':');
    final toParts = toTime.split(':');
    setState(() {
      _shiftStartHour = int.parse(fromParts[0]);
      _shiftStartMinute = int.parse(fromParts[1]);
      _shiftEndHour = int.parse(toParts[0]);
      _shiftEndMinute = int.parse(toParts[1]);
    });
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
    final hasPermission = await LocationService().handleLocationPermission(
      context,
    );
    if (!hasPermission) return;

    final now = DateTime.now();
    final timeString = now.toIso8601String();
    final dateString = DateFormat('yyyy-MM-dd').format(now);

    try {
      if (!_isCheckedIn) {
        // Requirement 1: Dynamic Mode Selection & Validation
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );

        double distanceToOffice = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          kOfficeLatitude,
          kOfficeLongitude,
        );

        String currentMode = "Office";
        if (distanceToOffice > kSiteTriggerDistance) {
          currentMode = "Site";
        }

        AppLogger.log("CHECK-IN: Mode detected: $currentMode | Distance to office: ${distanceToOffice.toStringAsFixed(0)}m");

        // GEOFENCE ENFORCEMENT
        if (currentMode == "Office" && distanceToOffice > kOfficeRadius) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Check-in failed: You are not at the office (Distance: ${distanceToOffice.toStringAsFixed(0)}m)'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        // Proceed with check-in
        final prefs = await SharedPreferences.getInstance();
        final empId = prefs.getString('employee_id') ?? 'Unknown';

        // If Site Mode, save the active site location
        if (currentMode == "Site") {
          _activeSiteLocation = LatLng(position.latitude, position.longitude);
          _isSiteMode = true;
          AppLogger.log("CHECK-IN: Active site coordinates saved: $_activeSiteLocation");
        }

        final id = await DatabaseHelper.instance.checkIn(
          timeString,
          dateString,
          position.latitude,
          position.longitude,
          empId,
          type: currentMode,
        );

        // Publish to MQTT with Geofence details
        mqttService.publishGeofenceAttendance(
          status: "Checked In",
          lat: position.latitude,
          lng: position.longitude,
          employeeId: empId,
          locationMode: currentMode,
          geofenceStatus: "Inside",
          activeSiteCoords: _activeSiteLocation != null
              ? {"lat": _activeSiteLocation!.latitude, "lng": _activeSiteLocation!.longitude}
              : null,
        );

        // Publish to Admin Attendance topic for live sync
        mqttService.publishAdminAttendance(
          employeeId: empId,
          checkInTime: timeString,
          lat: position.latitude,
          lng: position.longitude,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Checked in at $currentMode.'),
              backgroundColor: Colors.green,
            ),
          );
        }

        setState(() {
          _isCheckedIn = true;
          _checkInTime = now;
          _currentAttendanceId = id;
          _duration = Duration.zero;
        });
        _startTimer();
        _startGeofenceMonitoring(); // Start geofencing stream immediately
        BackgroundGeofenceService.startMonitoring(
          attendanceId: id,
          employeeId: empId,
        ); // Background foreground service

        // Requirement 2: Schedule shift end reminder on Check-In
        _scheduleShiftEndReminder();

        if (widget.onActionComplete != null) widget.onActionComplete!();
      } else {
        // Prevent manual checkout before shift end time
        if (!isAuto) {
          final shiftEnd = DateTime(
            now.year,
            now.month,
            now.day,
            _shiftEndHour,
            _shiftEndMinute,
          );
          if (now.isBefore(shiftEnd)) {
            if (mounted) {
              final remaining = shiftEnd.difference(now);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Cannot check out before shift end ($_shiftEndHour:${_shiftEndMinute.toString().padLeft(2, '0')}). Remaining: ${_formatDuration(remaining)}',
                  ),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
        }

        // Minimum Duration for "Present" Status
        if (_currentAttendanceId != null && _checkInTime != null) {
          const String reason = 'Manual checkout by employee';
          AppLogger.log(
            "CHECKOUT ATTEMPT: Reason - $reason | Time - ${DateTime.now()}",
          );
          _positionStream
              ?.cancel(); // STOP monitoring immediately on manual checkout
          _exitDebounceTimer?.cancel();
          _exitDebounceTimer = null;
          BackgroundGeofenceService.stopMonitoring(); // Stop background service

          Duration worked = now.difference(_checkInTime!);
          // DATABASE LOGIC: Explicitly save strings
          String finalStatus = worked.inHours >= 9 ? 'Present' : 'Incomplete';

          final prefs = await SharedPreferences.getInstance();
          final shiftEndTimeStr = prefs.getString('shift_to_time') ?? '17:00';
          final otBuffer = prefs.getInt('ot_buffer') ?? 30;

          final endParts = shiftEndTimeStr.split(':');
          final shiftEndHour = int.tryParse(endParts[0]) ?? 17;
          final shiftEndMinute = int.tryParse(endParts[1]) ?? 0;
          final shiftEndTime = DateTime(
            now.year,
            now.month,
            now.day,
            shiftEndHour,
            shiftEndMinute,
          );

          int calculatedOT = 0;
          if (now.isAfter(shiftEndTime)) {
            final minutesPastShift = now.difference(shiftEndTime).inMinutes;
            if (minutesPastShift >= otBuffer) {
              calculatedOT = minutesPastShift;
            }
          }

          await DatabaseHelper.instance.updateCheckOut(
            timeString,
            _currentAttendanceId!,
            status: finalStatus,
            otMinutes: calculatedOT,
          );

          // Get current position for MQTT
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

          final empId = prefs.getString('employee_id') ?? 'Unknown';

          // Publish to MQTT with Geofence details
          mqttService.publishGeofenceAttendance(
            status: finalStatus,
            lat: position.latitude,
            lng: position.longitude,
            employeeId: empId,
            locationMode: _isSiteMode ? "Site" : "Office",
            geofenceStatus: "Exited",
            activeSiteCoords: _activeSiteLocation != null
                ? {"lat": _activeSiteLocation!.latitude, "lng": _activeSiteLocation!.longitude}
                : null,
            empstatus: 'checkout',
            otMinutes: calculatedOT,
          );

          // Requirement 3: Cancel shift end reminder on Check-Out
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
                content: Text(
                  finalStatus == 'Present'
                      ? 'Shift Completed: Present'
                      : 'Checked out: Shift Incomplete (< 9hrs)',
                ),
                backgroundColor: finalStatus == 'Present'
                    ? Colors.blue
                    : Colors.orange,
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _positionStream?.cancel();
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
                return Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                );
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
                  side: BorderSide(
                    color: _isCheckedIn ? Colors.red : Colors.green,
                  ),
                ),
                child: Text(
                  _isCheckedIn ? 'Check-out' : 'Check-in',
                  style: TextStyle(
                    color: _isCheckedIn ? Colors.red : Colors.green,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
