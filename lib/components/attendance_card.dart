import 'package:flutter/material.dart';
import 'dart:async';
import '../database/db_helper.dart';
import 'package:intl/intl.dart';
import '../network/mqtt.dart';
import '../network/location_service.dart';
import 'package:geolocator/geolocator.dart';
import '../constants.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class AttendanceCard extends StatefulWidget {
  final MQTTClientWrapper mqttClient;
  final VoidCallback? onActionComplete;
  const AttendanceCard({super.key, required this.mqttClient, this.onActionComplete});

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  Timer? _timer;
  Duration _duration = Duration.zero;
  int? _currentAttendanceId;
  double? _checkInLat;
  double? _checkInLng;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadLastAttendance();
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
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

  Future<void> _loadLastAttendance() async {
    final lastAttendance = await DatabaseHelper.instance.getLastAttendance();
    if (lastAttendance != null && lastAttendance['checkOutTime'] == null) {
      setState(() {
        _isCheckedIn = true;
        _currentAttendanceId = lastAttendance['id'];
        _checkInTime = DateTime.parse(lastAttendance['checkInTime']);
        _startTimer();
      });
      // Resume location tracking if already checked in
      LocationService().startTracking(widget.mqttClient, onExitedOffice: _autoCheckOut);
    }
  }

  void _autoCheckOut() {
    if (_isCheckedIn && mounted) {
      _handleCheckInOut(isAuto: true);
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
    final now = DateTime.now();
    final timeString = now.toIso8601String();
    final dateString = DateFormat('yyyy-MM-dd').format(now);

    try {
      if (!_isCheckedIn) {
        // Check In - Get current position first
        Position? position;
        bool isAtOffice = false;
        
        try {
          final hasPermission = await LocationService().handleLocationPermission();
          if (hasPermission) {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.best,
                timeLimit: Duration(seconds: 15),
              ),
            );
            
            // Load office coordinates and radius from settings
            double officeLat = kOfficeLatitude;
            double officeLng = kOfficeLongitude;
            double radius = kGeofenceRadiusMeter;

            final savedLat = await DatabaseHelper.instance.getSetting('office_latitude');
            final savedLng = await DatabaseHelper.instance.getSetting('office_longitude');
            final savedRadius = await DatabaseHelper.instance.getSetting('geofence_radius');

            if (savedLat != null && savedLng != null) {
              officeLat = double.tryParse(savedLat) ?? kOfficeLatitude;
              officeLng = double.tryParse(savedLng) ?? kOfficeLongitude;
            }
            if (savedRadius != null) {
              radius = double.tryParse(savedRadius) ?? kGeofenceRadiusMeter;
            }

            double distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              officeLat,
              officeLng,
            );
            
            isAtOffice = distance <= radius;
          }
        } catch (e) {
          // Fallback handled below
        }

        if (isAtOffice) {
          final id = await DatabaseHelper.instance.checkIn(
            timeString, 
            dateString, 
            position?.latitude, 
            position?.longitude,
            type: 'Office'
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Checked in at Office. Attendance marked.'),
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
          if (widget.onActionComplete != null) widget.onActionComplete!();
          LocationService().startTracking(widget.mqttClient, onExitedOffice: _autoCheckOut);
        } else {
          // Non-office check-in: Start Time Log (recorded in attendance table now)
          final id = await DatabaseHelper.instance.checkIn(
            timeString, 
            dateString, 
            position?.latitude, 
            position?.longitude,
            type: 'Away'
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Not at office. Starting Time Log for: ${position != null ? '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}' : 'Unknown location'}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          
          setState(() {
            _isCheckedIn = true;
            _checkInTime = now;
            _currentAttendanceId = id;
            _duration = Duration.zero;
            _checkInLat = position?.latitude;
            _checkInLng = position?.longitude;
          });
          _startTimer();
          if (widget.onActionComplete != null) widget.onActionComplete!();
          // Still track for range updates
          LocationService().startTracking(widget.mqttClient, centerLat: position?.latitude, centerLng: position?.longitude, onExitedOffice: _autoCheckOut);
        }
      } else {
        // Check Out
        if (_currentAttendanceId != null) {
          String finalStatus = 'Completed';
          
          // VERIFY LOCATION ON CHECKOUT if type was Away
          // Note: We need to know if it was Away. For simplicity, check _checkInLat
          if (_checkInLat != null) {
            try {
              final currentPos = await Geolocator.getCurrentPosition();
              double distance = Geolocator.distanceBetween(
                _checkInLat!, _checkInLng!, currentPos.latitude, currentPos.longitude
              );
              
              double radius = kGeofenceRadiusMeter;
              final savedRadius = await DatabaseHelper.instance.getSetting('geofence_radius');
              if (savedRadius != null) radius = double.tryParse(savedRadius) ?? kGeofenceRadiusMeter;
              
              if (distance > radius) finalStatus = 'Failed';
            } catch (e) {
              // Location check failed, assume Completed or keep as is
            }
          }

          await DatabaseHelper.instance.checkOut(timeString, _currentAttendanceId!, status: finalStatus);
          
          if (finalStatus == 'Completed') {
            await _scheduleNextShiftAlarm();
          }

          _timer?.cancel();
          LocationService().stopTracking();
          setState(() {
            _isCheckedIn = false;
            _checkInTime = null;
            _currentAttendanceId = null;
            _duration = Duration.zero;
            _checkInLat = null;
            _checkInLng = null;
          });
          if (widget.onActionComplete != null) widget.onActionComplete!();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(finalStatus == 'Failed' 
                  ? 'Checked out: Log marked as FAILED (Location mismatch)' 
                  : (isAuto ? 'Auto-checked out (Location Range Exceeded)' : 'Checked out successfully!')),
                backgroundColor: finalStatus == 'Failed' ? Colors.red : (isAuto ? Colors.orange : Colors.blue),
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
    LocationService().stopTracking();
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
